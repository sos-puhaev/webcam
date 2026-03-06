import Foundation
import AVFoundation
import Combine
import os

@MainActor
final class DetailPlayerStore: ObservableObject {
    static let shared = DetailPlayerStore()

    // MARK: - Player
    let player: AVPlayer = {
        let p = AVPlayer()
        p.automaticallyWaitsToMinimizeStalling = true
        return p
    }()

    // MARK: - Published state
    @Published private(set) var currentURL: URL?
    @Published private(set) var isLoading: Bool = true

    // ✅ для UI
    @Published private(set) var hasFirstFrame: Bool = false
    @Published private(set) var isRebuffering: Bool = false

    @Published private(set) var showError: Bool = false
    @Published private(set) var errorMessage: String = ""

    // MARK: - Observers
    private var timeControlObs: NSKeyValueObservation?
    private var statusObs: NSKeyValueObservation?
    private var failedToken: NSObjectProtocol?
    private var stalledToken: NSObjectProtocol?

    // MARK: - Metrics / Logging
    private let log = OSLog(subsystem: "com.yourapp.camera", category: "player")
    private var startClock: ContinuousClock.Instant?
    private var firstFrameLogged = false
    private var periodicTimeObserver: Any?

    // MARK: - Watchdog (anti infinite loading)
    private var loadingWatchdogTask: Task<Void, Never>?
    private let loadingTimeoutSec: UInt64 = 15

    // MARK: - Auto retry on transient network errors (LIVE only)
    private var lastSetIsLive: Bool = true
    private var autoRetryTask: Task<Void, Never>?
    private var autoRetryCount: Int = 0
    private let autoRetryMax: Int = 3

    // MARK: - Attempt / Anti false reconnect
    private var attemptID: UUID = UUID()
    private var didTriggerLongWaitReconnect: Bool = false

    // MARK: - Extra diagnostics flags
    private var didLogInitialStateForAttempt: Bool = false

    private init() {
        isLoading = (player.timeControlStatus == .waitingToPlayAtSpecifiedRate)

        timeControlObs = player.observe(\.timeControlStatus, options: [.new]) { [weak self] p, _ in
            guard let self else { return }

            switch p.timeControlStatus {
            case .waitingToPlayAtSpecifiedRate:
                self.isLoading = true
                self.isRebuffering = self.hasFirstFrame

                if self.didLogInitialStateForAttempt == false {
                    self.didLogInitialStateForAttempt = true
                    self.dumpState(tag: "timeControl=waiting (first)", includeItemLogs: false)
                }

                if let start = self.startClock {
                    let ms = Self.ms(since: start)
                    os_log("⏳ waitingToPlay (%.1fms)", log: self.log, type: .info, ms)

                    // ✅ long-wait reconnect только для ТЕКУЩЕЙ попытки и только 1 раз
                    if self.lastSetIsLive,
                       self.hasFirstFrame == false,
                       self.didTriggerLongWaitReconnect == false,
                       ms > 10_000 {
                        self.didTriggerLongWaitReconnect = true
                        os_log("🛠 long waiting (>10s) -> reconnect item", log: self.log, type: .error)
                        self.reconnectItemForCurrentAttempt(autoplay: true)
                    }
                }

            case .playing:
                self.isLoading = false
                self.isRebuffering = false
                self.loadingWatchdogTask?.cancel()

                self.clearError()
                self.showError = false

                if let start = self.startClock {
                    os_log("🎬 timeControlStatus=playing in %.1fms", log: self.log, type: .info, Self.ms(since: start))
                }
                self.startFirstFrameProbeIfNeeded()

            case .paused:
                self.isRebuffering = false
                break

            @unknown default:
                break
            }
        }
    }

    deinit {
        // cancel tasks (можно и так)
        loadingWatchdogTask?.cancel()
        autoRetryTask?.cancel()

        if let failedToken { NotificationCenter.default.removeObserver(failedToken) }
        if let stalledToken { NotificationCenter.default.removeObserver(stalledToken) }

        timeControlObs?.invalidate()
        statusObs?.invalidate()

        // ✅ main-actor cleanup из deinit
        let token = periodicTimeObserver
        periodicTimeObserver = nil
        if let token {
            Task { @MainActor [player] in
                player.removeTimeObserver(token)
            }
        }
    }

    // MARK: - Public helpers

    func clearError() {
        showError = false
        errorMessage = ""
    }

    func reset() {
        stopFirstFrameProbe()
        loadingWatchdogTask?.cancel()
        autoRetryTask?.cancel()
        autoRetryCount = 0

        statusObs?.invalidate()
        statusObs = nil

        if let failedToken { NotificationCenter.default.removeObserver(failedToken) }
        failedToken = nil

        if let stalledToken { NotificationCenter.default.removeObserver(stalledToken) }
        stalledToken = nil

        currentURL = nil
        clearError()
        isLoading = true
        hasFirstFrame = false
        isRebuffering = false

        startClock = nil
        firstFrameLogged = false
        didTriggerLongWaitReconnect = false
        didLogInitialStateForAttempt = false
        attemptID = UUID()

        player.replaceCurrentItem(with: nil)
    }

    /// ✅ ручной реконнект (пересоздать item). URL тот же.
    func reconnect(autoplay: Bool = true) {
        os_log("🔁 manual reconnect()", log: log, type: .info)
        didTriggerLongWaitReconnect = true // чтобы long-wait не дернулся следом
        reconnectItemForCurrentAttempt(autoplay: autoplay)
    }

    // MARK: - Core set

    func set(url: URL, isLive: Bool, autoplay: Bool, force: Bool = false) {

        // ✅ если item уже nil (после reset), нельзя early-return
        if !force, currentURL == url, player.currentItem != nil {
            if autoplay { player.play() }
            return
        }

        lastSetIsLive = isLive
        autoRetryTask?.cancel()
        autoRetryCount = 0

        // ✅ новая попытка
        attemptID = UUID()
        didTriggerLongWaitReconnect = false
        didLogInitialStateForAttempt = false

        // старт метрик
        startClock = ContinuousClock.now
        firstFrameLogged = false
        hasFirstFrame = false
        isRebuffering = false
        stopFirstFrameProbe()
        loadingWatchdogTask?.cancel()

        os_log("🔗 set(url) isLive=%{public}s autoplay=%{public}s force=%{public}s url=%{public}s",
               log: log, type: .info,
               isLive ? "true" : "false",
               autoplay ? "true" : "false",
               force ? "true" : "false",
               url.absoluteString)

        currentURL = url
        clearError()
        isLoading = true

        let item = makeItem(url: url, isLive: isLive)

        attachObservers(to: item, autoplay: autoplay, attempt: attemptID)

        player.replaceCurrentItem(with: item)

        // ✅ моментальный снимок состояния (иногда уже тут видно ATS/URL=nil и т.п.)
        dumpState(tag: "after replaceCurrentItem", includeItemLogs: false)

        startFirstFrameProbeIfNeeded()
        startLoadingWatchdogIfNeeded(attempt: attemptID)
        dumpStateSoon(tag: "after replaceCurrentItem +700ms", attempt: attemptID)
    }

    func play() { player.play() }
    func pause() { player.pause() }

    // MARK: - Build / Attach

    private func makeItem(url: URL, isLive: Bool) -> AVPlayerItem {
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = isLive ? 3.0 : 1.0
        item.preferredPeakBitRate = 0
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true

        if isLive, #available(iOS 13.0, *) {
            item.configuredTimeOffsetFromLive = CMTime(seconds: 2.0, preferredTimescale: 600)
        }

        return item
    }

    private func attachObservers(to item: AVPlayerItem, autoplay: Bool, attempt: UUID) {
        statusObs?.invalidate()

        statusObs = item.observe(\.status, options: [.new]) { [weak self] it, _ in
            guard let self else { return }
            guard attempt == self.attemptID else { return }

            switch it.status {
            case .readyToPlay:
                if let start = self.startClock {
                    os_log("🎞 item readyToPlay in %.1fms", log: self.log, type: .info, Self.ms(since: start))
                }
                if autoplay { self.player.play() }

                self.startFirstFrameProbeIfNeeded()
                self.startLoadingWatchdogIfNeeded(attempt: attempt)
                self.dumpStateSoon(tag: "after readyToPlay +700ms", attempt: attempt)

            case .failed:
                self.loadingWatchdogTask?.cancel()
                self.isLoading = false
                self.isRebuffering = false
                self.showError = true
                self.errorMessage = it.error?.localizedDescription ?? "Ошибка воспроизведения"

                if let start = self.startClock {
                    os_log("❌ item failed in %.1fms: %{public}s",
                           log: self.log, type: .error,
                           Self.ms(since: start),
                           self.errorMessage)
                }

                // ✅ Тут важнейшее: подробные errorLog/accessLog + underlying error
                self.dumpState(tag: "failed", includeItemLogs: true)
                self.dumpLogs(item: it, tag: "failed")
                self.maybeAutoRetryAfterItemFailure()

            default:
                break
            }
        }

        if let failedToken { NotificationCenter.default.removeObserver(failedToken) }
        failedToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            guard attempt == self.attemptID else { return }

            self.loadingWatchdogTask?.cancel()
            self.isLoading = false
            self.isRebuffering = false
            self.showError = true
            self.errorMessage = "Ошибка воспроизведения"

            if let start = self.startClock {
                os_log("❌ failedToPlayToEndTime in %.1fms", log: self.log, type: .error, Self.ms(since: start))
            }

            self.dumpState(tag: "failedToPlayToEndTime", includeItemLogs: true)
            self.dumpLogs(item: item, tag: "failedToPlayToEndTime")
            self.maybeAutoRetryAfterItemFailure()
        }

        if let stalledToken { NotificationCenter.default.removeObserver(stalledToken) }
        stalledToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            guard attempt == self.attemptID else { return }

            let t = self.player.currentTime().seconds
            os_log("🧊 Playback stalled at t=%.2fs", log: self.log, type: .error, t)
            self.isRebuffering = self.hasFirstFrame

            self.dumpState(tag: "stalled", includeItemLogs: true)
            self.dumpLogs(item: item, tag: "stalled")
        }
    }

    // MARK: - Reconnect item (same URL, same attempt)

    private func reconnectItemForCurrentAttempt(autoplay: Bool) {
        guard let url = currentURL else { return }

        stopFirstFrameProbe()
        firstFrameLogged = false
        hasFirstFrame = false
        isRebuffering = false
        isLoading = true

        let item = makeItem(url: url, isLive: lastSetIsLive)
        attachObservers(to: item, autoplay: autoplay, attempt: attemptID)

        player.replaceCurrentItem(with: item)
        if autoplay { player.play() }

        dumpState(tag: "after reconnect replaceCurrentItem", includeItemLogs: false)

        startFirstFrameProbeIfNeeded()
        startLoadingWatchdogIfNeeded(attempt: attemptID)
        dumpStateSoon(tag: "after reconnect +700ms", attempt: attemptID)
    }

    // MARK: - Auto retry (LIVE only)

    private func maybeAutoRetryAfterItemFailure() {
        guard lastSetIsLive else { return }
        guard autoRetryCount < autoRetryMax else { return }
        guard let url = currentURL else { return }

        let ns = (player.currentItem?.error as NSError?) ?? NSError(domain: "unknown", code: -1)

        let isTransient =
            ns.domain == NSURLErrorDomain &&
            (ns.code == NSURLErrorNetworkConnectionLost ||
             ns.code == NSURLErrorTimedOut ||
             ns.code == NSURLErrorNotConnectedToInternet ||
             ns.code == NSURLErrorResourceUnavailable)

        guard isTransient else {
            os_log("🧱 no autoRetry: non-transient %{public}s %d", log: log, type: .info, ns.domain, ns.code)
            return
        }

        autoRetryCount += 1
        let delayNs: UInt64
        switch autoRetryCount {
        case 1: delayNs = 450_000_000
        case 2: delayNs = 950_000_000
        default: delayNs = 1_600_000_000
        }

        os_log("🔁 autoRetry #%d in %.0fms (reason=%{public}s %d)",
               log: log, type: .info,
               autoRetryCount, Double(delayNs)/1_000_000, ns.domain, ns.code)

        autoRetryTask?.cancel()
        autoRetryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: delayNs)
            if Task.isCancelled { return }

            // ✅ новая попытка (новый attemptID)
            self.set(url: url, isLive: true, autoplay: true, force: true)
        }
    }

    // MARK: - "First frame" probe

    private func startFirstFrameProbeIfNeeded() {
        guard periodicTimeObserver == nil else { return }
        guard firstFrameLogged == false else { return }
        guard startClock != nil else { return }

        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        periodicTimeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.tryLogFirstFrame()
        }
    }

    private func stopFirstFrameProbe() {
        if let token = periodicTimeObserver {
            player.removeTimeObserver(token)
            periodicTimeObserver = nil
        }
    }

    private func tryLogFirstFrame() {
        guard firstFrameLogged == false else { return }
        guard let start = startClock else { return }
        guard player.timeControlStatus == .playing else { return }
        guard let item = player.currentItem else { return }
        guard item.status == .readyToPlay else { return }

        let t = player.currentTime().seconds
        let size = item.presentationSize

        guard t.isFinite, t > 0.05 else { return }
        guard size.width > 0, size.height > 0 else { return }

        firstFrameLogged = true
        hasFirstFrame = true
        isRebuffering = false

        clearError()
        showError = false

        os_log("🖼 first frame in %.1fms (t=%.2fs size=%.0fx%.0f)",
               log: log, type: .info,
               Self.ms(since: start), t, size.width, size.height)

        stopFirstFrameProbe()
        loadingWatchdogTask?.cancel()
    }

    // MARK: - Watchdog

    private func startLoadingWatchdogIfNeeded(attempt: UUID) {
        loadingWatchdogTask?.cancel()

        loadingWatchdogTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.loadingTimeoutSec * 1_000_000_000)
            if Task.isCancelled { return }
            guard attempt == self.attemptID else { return }

            guard let item = self.player.currentItem else { return }

            if self.hasFirstFrame == false &&
                self.player.timeControlStatus == .waitingToPlayAtSpecifiedRate &&
                item.isPlaybackLikelyToKeepUp == false {

                self.isLoading = false
                self.isRebuffering = false
                self.showError = true
                self.errorMessage = "Видео не загрузилось за \(self.loadingTimeoutSec)с"

                os_log("⏱️ Watchdog fired (no first frame).", log: self.log, type: .error)
                self.dumpState(tag: "watchdog", includeItemLogs: true)
                self.dumpLogs(item: item, tag: "watchdog")
            }
        }
    }

    // MARK: - Debug dumps

    private func dumpStateSoon(tag: String, attempt: UUID) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard attempt == self.attemptID else { return }
            self.dumpState(tag: tag, includeItemLogs: false)
        }
    }

    private func dumpState(tag: String, includeItemLogs: Bool) {
        guard let item = player.currentItem else {
            os_log("🔎 dumpState(%{public}s): no currentItem", log: log, type: .info, tag)
            return
        }

        let tc = player.timeControlStatus
        let t = player.currentTime().seconds
        let dur = item.duration.seconds
        let size = item.presentationSize

        os_log("""
        🔎 %{public}s
        url=%{public}s
        item.status=%d
        tc=%d
        t=%.2f dur=%.2f size=%.0fx%.0f
        empty=%{public}s keepUp=%{public}s full=%{public}s
        """,
        log: log, type: .info,
        tag,
        (currentURL?.absoluteString ?? "nil"),
        item.status.rawValue,
        tc.rawValue,
        t,
        dur.isFinite ? dur : -1,
        size.width, size.height,
        item.isPlaybackBufferEmpty ? "true" : "false",
        item.isPlaybackLikelyToKeepUp ? "true" : "false",
        item.isPlaybackBufferFull ? "true" : "false")

        if includeItemLogs {
            dumpLogs(item: item, tag: tag)
        }
    }

    /// ✅ Главный диагностический дамп:
    /// - NSError + underlying
    /// - errorLog events (uri/status/comment)
    /// - accessLog events (uri/bitrates/segments)
    private func dumpLogs(item: AVPlayerItem, tag: String) {

        // 1) NSError + underlying
        if let err = item.error as NSError? {
            os_log("📛 %{public}s item.error domain=%{public}s code=%d localized=%{public}s",
                   log: log, type: .error,
                   tag,
                   err.domain, err.code,
                   err.localizedDescription)

            os_log("📛 %{public}s item.error userInfo=%{public}s",
                   log: log, type: .error,
                   tag,
                   String(describing: err.userInfo))

            if let underlying = err.userInfo[NSUnderlyingErrorKey] as? NSError {
                os_log("📛 %{public}s underlying domain=%{public}s code=%d localized=%{public}s",
                       log: log, type: .error,
                       tag,
                       underlying.domain, underlying.code,
                       underlying.localizedDescription)
            }
        } else {
            os_log("📛 %{public}s item.error = nil", log: log, type: .info, tag)
        }

        // 2) Error log events (самое важное для HLS)
        if let e = item.errorLog() {
            os_log("📛 %{public}s errorLog events=%d", log: log, type: .error, tag, e.events.count)

            for (idx, ev) in e.events.enumerated() {
                os_log("""
                📛 HLS ERROR #%d:
                uri=%{public}s
                server=%{public}s
                status=%d
                domain=%{public}s
                comment=%{public}s
                """,
                log: log,
                type: .error,
                idx,
                ev.uri ?? "nil",
                ev.serverAddress ?? "nil",
                ev.errorStatusCode,
                ev.errorDomain ?? "nil",
                ev.errorComment ?? "nil")
            }
        } else {
            os_log("📛 %{public}s errorLog = nil", log: log, type: .info, tag)
        }

        // 3) Access log events (полезно для понимания загрузки/битрейта/сегментов)
        if let a = item.accessLog() {
            os_log("📶 %{public}s accessLog events=%d", log: log, type: .info, tag, a.events.count)

            let tail = a.events.suffix(3)
            for ev in tail {
                os_log("""
                📶 ACCESS:
                uri=%{public}s
                indicatedBitrate=%.0f
                observedBitrate=%.0f
                durationWatched=%.2f
                mediaRequests=%d
                stalls=%d
                bytes=%lld
                transferDuration=%.2f
                startupTime=%.2f
                """,
                log: log,
                type: .info,
                ev.uri ?? "nil",
                ev.indicatedBitrate,
                ev.observedBitrate,
                ev.durationWatched,
                ev.numberOfMediaRequests,
                ev.numberOfStalls,
                ev.numberOfBytesTransferred,
                ev.transferDuration,
                ev.startupTime)
            }
        } else {
            os_log("📶 %{public}s accessLog = nil", log: log, type: .info, tag)
        }
    }

    // MARK: - Helpers

    private static func ms(since start: ContinuousClock.Instant) -> Double {
        let d = start.duration(to: .now)
        let seconds = Double(d.components.seconds)
        let attos = Double(d.components.attoseconds)
        return seconds * 1000.0 + attos / 1e15
    }
}
