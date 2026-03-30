import Foundation
import os
import Combine

@MainActor
final class CameraArchiveViewModel: ObservableObject {

    @Published private(set) var availableFrom: Date?
    @Published private(set) var availableFromTs: Int?
    @Published private(set) var serverTime: Int?
    @Published private(set) var maxBackSeconds: Double = 0
    @Published private(set) var archiveEvents: [ArchiveEvent] = []
    @Published private(set) var eventsRevision: Int = 0
    
    @Published private(set) var isCameraActive: Bool = true
    @Published private(set) var isCameraOnline: Bool = true
    @Published private(set) var isPTZ: Bool = false
    @Published private(set) var isRecordingEnabled: Bool = false
    @Published private(set) var hasArchive: Bool = false
    @Published private(set) var archiveMessage: String?
    @Published private(set) var cameraName: String?

    @Published var errorMessage: String?

    private(set) var cameraID: Int?
    private let api = APIService.shared
    private let iso = ISO8601DateFormatter()

    private let log = OSLog(subsystem: "com.webcam.camera", category: "archive")
    
    var shouldShowPTZControls: Bool {
        isCameraActive && isCameraOnline && isPTZ
    }

    var shouldShowArchiveControls: Bool {
        isRecordingEnabled && hasArchive && maxBackSeconds > 0
    }

    var shouldShowLiveOnly: Bool {
        !shouldShowArchiveControls
    }

    var playerStatusText: String? {
        if !isCameraActive {
            return "Камера не активна"
        }
        if !isCameraOnline {
            return "Камера офлайн"
        }
        return nil
    }

    var archiveStatusText: String? {
        if !isRecordingEnabled {
            return "Архив недоступен: запись не ведётся"
        }
        if !hasArchive {
            return archiveMessage ?? "Архив недоступен"
        }
        return nil
    }
    
    func setCamera(id: Int) {
        self.cameraID = id
    }

    func loadAll() async {
        await loadArchiveRange()

        guard isRecordingEnabled, hasArchive else {
            archiveEvents = []
            eventsRevision &+= 1
            return
        }

        await loadArchiveEvents(limit: 120)
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.loadArchiveEventsFullIfNeeded()
        }
    }

    func loadArchiveRange() async {
        guard let cameraID else { return }
        let tz = TimeZone.current.secondsFromGMT()

        os_log("➡️ archive-range cam=%d tz=%d", log: log, type: .info, cameraID, tz)

        do {
            let resp: ArchiveRangeResponse = try await api.request(
                endpoint: Constants.API.Camera.archiveRange(cameraID: cameraID, tz: tz),
                method: "GET"
            )

            serverTime = resp.serverTime
            isRecordingEnabled = resp.recordingEnabled
            hasArchive = resp.hasArchive
            archiveMessage = resp.message
            cameraName = resp.camera?.name

            isCameraActive = resp.camera?.isActive ?? true
            isPTZ = resp.camera?.ptz ?? false

            if let range = resp.range {
                availableFromTs = range.fromTs
                maxBackSeconds = max(0, Double(range.toTs - range.fromTs))

                if let from = range.from {
                    availableFrom = iso.date(from: from)
                } else {
                    availableFrom = Date(timeIntervalSince1970: TimeInterval(range.fromTs))
                }

                serverTime = max(resp.serverTime, range.toTs)

                os_log("✅ archive-range cam=%d server=%d fromTs=%d toTs=%d maxBack=%.0f rec=%{public}s hasArchive=%{public}s active=%{public}s ptz=%{public}s",
                       log: log, type: .info,
                       cameraID,
                       resp.serverTime,
                       range.fromTs,
                       range.toTs,
                       maxBackSeconds,
                       String(resp.recordingEnabled),
                       String(resp.hasArchive),
                       String(isCameraActive),
                       String(isPTZ))
            } else {
                availableFromTs = nil
                availableFrom = nil
                maxBackSeconds = 0

                os_log("✅ archive-range cam=%d no range rec=%{public}s hasArchive=%{public}s message=%{public}s",
                       log: log, type: .info,
                       cameraID,
                       String(resp.recordingEnabled),
                       String(resp.hasArchive),
                       resp.message ?? "-")
            }

        } catch {
            os_log("❌ archive-range cam=%d err=%{public}s", log: log, type: .error, cameraID, String(reflecting: error))
            maxBackSeconds = 0
            archiveMessage = "Не удалось загрузить архив"
        }
    }

    func loadArchiveEvents(limit: Int = 120, types: [Int] = []) async {
        guard let cameraID else { return }
        let tz = TimeZone.current.secondsFromGMT()

        os_log("➡️ archive-events cam=%d tz=%d limit=%d types=%{public}s",
               log: log, type: .info,
               cameraID, tz, limit, String(describing: types))

        do {
            let resp: ArchiveEventsResponse = try await api.request(
                endpoint: Constants.API.Camera.archiveEvents(cameraID: cameraID, tz: tz, limit: limit, types: types),
                method: "GET",
                timeoutOverride: 30
            )

            archiveEvents = resp.events
            eventsRevision &+= 1   // ✅ ДОБАВЬ ВОТ ТУТ

            if let old = serverTime { serverTime = max(old, resp.archive_to_ts) }
            else { serverTime = resp.archive_to_ts }

            maxBackSeconds = max(maxBackSeconds, Double(resp.archive_to_ts - resp.archive_from_ts))

            os_log("✅ archive-events cam=%d count=%d from=%d to=%d",
                   log: log, type: .info,
                   cameraID, resp.events.count, resp.archive_from_ts, resp.archive_to_ts)

        } catch {
            let ns = error as NSError
            os_log("⚠️ archive-events failed cam=%d err=%{public}s domain=%{public}s code=%d",
                   log: log, type: .error,
                   cameraID, String(reflecting: error), ns.domain, ns.code)
        }
    }


    private func loadArchiveEventsFullIfNeeded() async {
        if archiveEvents.count >= 250 { return }
        await loadArchiveEvents(limit: 300, types: [])
    }
    
    func clearArchiveEvents() {
        archiveEvents = []
        eventsRevision &+= 1
    }
}
