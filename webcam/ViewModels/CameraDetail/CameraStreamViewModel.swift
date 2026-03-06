import Foundation
import UIKit
import Combine
import os

@MainActor
final class CameraStreamViewModel: ObservableObject {

    @Published private(set) var isLoading = false
    @Published private(set) var streamURL: URL?
    @Published private(set) var format: String?
    @Published private(set) var isArchive = false
    @Published private(set) var mode: String = "live"
    @Published private(set) var currentArchiveTs: Int?

    @Published var errorMessage: String?

    private(set) var cameraID: Int?
    private let api = APIService.shared

    private var openTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?

    private var lastRequestedArchiveTs: Int?
    private var lastRequestedMode: String?

    private let debounceNs: UInt64 = 450_000_000
    private let minArchiveDeltaSec: Int = 2

    private let busyBaseDelayNs: UInt64 = 300_000_000
    private let busyMaxDelayNs: UInt64 = 2_000_000_000
    private let maxRetriesOnBusy: Int = 3
    
    private var lastArchiveSpeed: Double?

    var streamKey: String { "\(mode)|\(streamURL?.absoluteString ?? "nil")" }

    // Logs
    private let log = OSLog(subsystem: "com.webcam.camera", category: "stream")

    func setCamera(id: Int) {
        self.cameraID = id
    }

    func openLiveDebounced(force: Bool = false) {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: debounceNs)
            if Task.isCancelled { return }
            await self.openLive(force: force)
        }
        print("DEBOUNCE LIVE scheduled")

    }

    func openArchiveDebounced(fromTs ts: Int, speed: Double?) {
        lastArchiveSpeed = speed
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: debounceNs)
            if Task.isCancelled { return }
            await self.openArchive(fromTs: ts, speed: speed)
        }
        print("DEBOUNCE ARCHIVE scheduled ts=\(ts) speed=\(speed?.description ?? "nil")")
    }

    func openLive(force: Bool = false) async {
        if !force, lastRequestedMode == "live", streamURL != nil, errorMessage == nil { return }
        lastRequestedMode = "live"

        // cached live
        if !force, let cameraID, let cached = CameraStreamPrefetch.shared.takeLive(cameraId: cameraID) {
            os_log("⚡️ cached live URL (cam=%d)", log: log, type: .info, cameraID)
            setIfChanged(&errorMessage, nil)
            currentArchiveTs = nil
            if mode != "live" { mode = "live" }
            if isArchive != false { isArchive = false }
            if streamURL != cached { streamURL = cached }

            // обновим в фоне свежим url
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.openLive(force: true)
            }
            return
        }

        lastRequestedArchiveTs = nil
        openTask?.cancel()

        openTask = Task { [weak self] in
            guard let self, let cameraID else { return }
            if Task.isCancelled { return }

            if force { setIfChanged(&self.errorMessage, nil) }
            self.currentArchiveTs = nil

            let req = CameraStreamRequest(mode: "live", platform: "ios", from: nil, tz: nil, speed: nil)
            await self.fetchStream(cameraID: cameraID, request: req, retriesLeft: self.maxRetriesOnBusy)
        }
    }

    func openArchive(fromTs ts: Int, speed: Double?) async {
        lastArchiveSpeed = speed
        if let last = lastRequestedArchiveTs, abs(last - ts) < minArchiveDeltaSec { return }
        lastRequestedArchiveTs = ts
        lastRequestedMode = "archive"

        openTask?.cancel()

        openTask = Task { [weak self] in
            guard let self, let cameraID else { return }
            if Task.isCancelled { return }

            self.currentArchiveTs = ts
            let tz = TimeZone.current.secondsFromGMT()
            let req = CameraStreamRequest(mode: "archive", platform: "ios", from: ts, tz: tz, speed: speed)
            await self.fetchStream(cameraID: cameraID, request: req, retriesLeft: self.maxRetriesOnBusy)
        }
    }

    func reconnectStream(force: Bool = true) {
        Task { @MainActor in
            if mode == "live" {
                await openLive(force: force)
            } else if let ts = currentArchiveTs {
                await openArchive(fromTs: ts, speed: lastArchiveSpeed)
            } else {
                await openLive(force: force)
            }
        }
    }

    // MARK: - Private

    private func fetchStream(cameraID: Int, request: CameraStreamRequest, retriesLeft: Int) async {
        setIfChanged(&isLoading, true)
        setIfChanged(&errorMessage, nil)
        defer { setIfChanged(&isLoading, false) }

        let signpostID = OSSignpostID(log: log)
        let start = ContinuousClock.now

        os_signpost(.begin, log: log, name: "FetchStream", signpostID: signpostID,
                    "cam=%d mode=%{public}s from=%{public}s retries=%d",
                    cameraID, request.mode, request.from.map(String.init) ?? "nil", retriesLeft)

        defer {
            let ms = Self.durationMs(from: start, to: .now)
            os_signpost(.end, log: log, name: "FetchStream", signpostID: signpostID, "duration=%.1fms", ms)
        }

        do {
            let body = try JSONEncoder().encode(request)

            os_log("➡️ stream req cam=%d body=%{public}s", log: log, type: .info,
                   cameraID, String(data: body, encoding: .utf8) ?? "<non-utf8>")

            let response: CameraStreamResponse = try await api.request(
                endpoint: Constants.API.Camera.stream(cameraID: cameraID),
                method: "POST",
                body: body
            )

            if request.mode == "archive", let ts = request.from {
                // пользователь уже ушёл в live или поменял ts — этот archive-ответ устарел
                if lastRequestedMode != "archive" {
                    os_log("🧯 ignore stale ARCHIVE resp (user switched mode) cam=%d", log: log, type: .info, cameraID)
                    return
                }
                if lastRequestedArchiveTs != ts {
                    os_log("🧯 ignore stale ARCHIVE resp (ts changed) cam=%d respTs=%d lastTs=%{public}s",
                           log: log, type: .info, cameraID, ts, lastRequestedArchiveTs.map(String.init) ?? "nil")
                    return
                }
            } else {
                // live-ответ не применяем, если пользователь уже в archive
                if lastRequestedMode != "live" {
                    os_log("🧯 ignore stale LIVE resp (user switched to archive) cam=%d", log: log, type: .info, cameraID)
                    return
                }
            }

            // ✅ ТОЛЬКО ТЕПЕРЬ ПИШЕМ В STATE
            format = response.format
            isArchive = response.archive
            mode = response.mode ?? request.mode

            os_log("⬅️ stream resp cam=%d mode=%{public}s archive=%d format=%{public}s url=%{public}s availableFrom=%{public}s",
                   log: log, type: .info,
                   cameraID,
                   (response.mode ?? request.mode),
                   response.archive ? 1 : 0,
                   response.format ?? "nil",
                   response.url ?? "nil",
                   response.availableFrom ?? "nil")

            if let urlString = response.url, let url = URL(string: urlString) {
                if streamURL != url { streamURL = url }
            } else {
                streamURL = nil
                if let af = response.availableFrom {
                    setIfChanged(&errorMessage, "Архив доступен с: \(af)")
                } else {
                    setIfChanged(&errorMessage, "Архив недоступен для выбранного времени")
                }
            }

        } catch is CancellationError {
            os_log("↩️ cancelled cam=%d mode=%{public}s", log: log, type: .info, cameraID, request.mode)
            return
        } catch {
            if retriesLeft > 0, isBusyError(error) {
                let attempt = (maxRetriesOnBusy - retriesLeft)
                let base = min(busyBaseDelayNs * UInt64(1 << attempt), busyMaxDelayNs)
                let jitter = UInt64.random(in: 0...120_000_000)
                let delay = base + jitter

                os_log("⏳ busy retry cam=%d mode=%{public}s left=%d delay=%.0fms",
                       log: log, type: .info,
                       cameraID, request.mode, retriesLeft, Double(delay) / 1_000_000)

                try? await Task.sleep(nanoseconds: delay)
                if Task.isCancelled { return }

                // актуальность (у тебя уже правильно)
                if request.mode == "archive", let ts = request.from {
                    if lastRequestedMode != "archive" { return }
                    if lastRequestedArchiveTs != ts { return }
                } else {
                    if lastRequestedMode != "live" { return }
                }

                await fetchStream(cameraID: cameraID, request: request, retriesLeft: retriesLeft - 1)
                return
            }

            streamURL = nil
            setIfChanged(&errorMessage, error.localizedDescription)

            let ns = error as NSError
            os_log("❌ stream error cam=%d mode=%{public}s err=%{public}s domain=%{public}s code=%d userInfo=%{public}s",
                   log: log, type: .error,
                   cameraID, request.mode,
                   String(reflecting: error),
                   ns.domain, ns.code,
                   String(describing: ns.userInfo))
        }
    }


    private func isBusyError(_ error: Error) -> Bool {
        if case NetworkError.serverError(let statusCode, _) = error { return statusCode == 429 }
        let t = String(reflecting: error).lowercased()
        return t.contains("429") || t.contains("too many requests") || t.contains("busy") || t.contains("rate limit")
    }

    private static func durationMs(from start: ContinuousClock.Instant, to end: ContinuousClock.Instant) -> Double {
        let d = start.duration(to: end)
        let seconds = Double(d.components.seconds)
        let attos = Double(d.components.attoseconds)
        return seconds * 1000.0 + attos / 1e15
    }

    private func setIfChanged<T: Equatable>(_ target: inout T, _ value: T) {
        if target != value { target = value }
    }
    
    func cancelDebounce() {
        debounceTask?.cancel()
        debounceTask = nil
    }
}
