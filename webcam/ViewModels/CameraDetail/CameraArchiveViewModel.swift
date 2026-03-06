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

    @Published var errorMessage: String?

    private(set) var cameraID: Int?
    private let api = APIService.shared
    private let iso = ISO8601DateFormatter()

    private let log = OSLog(subsystem: "com.webcam.camera", category: "archive")

    func setCamera(id: Int) {
        self.cameraID = id
    }

    func loadAll() async {
        await loadArchiveRange()
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
            availableFromTs = resp.availableFromTs
            maxBackSeconds = max(0, Double(resp.serverTime - resp.availableFromTs))
            availableFrom = iso.date(from: resp.availableFrom)

            os_log("✅ archive-range cam=%d server=%d fromTs=%d maxBack=%.0f",
                   log: log, type: .info,
                   cameraID, resp.serverTime, resp.availableFromTs, maxBackSeconds)

        } catch {
            os_log("❌ archive-range cam=%d err=%{public}s", log: log, type: .error, cameraID, String(reflecting: error))
            maxBackSeconds = max(maxBackSeconds, 600)
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
}
