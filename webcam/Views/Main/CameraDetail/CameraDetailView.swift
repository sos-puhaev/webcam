import SwiftUI
import AVKit
import AudioToolbox

struct CameraDetailView: View {
    let camera: Camera
    @ObservedObject var viewModel: CameraListViewModel

    @StateObject private var streamVM = CameraStreamViewModel()
    @StateObject private var ptzVM = CameraPTZViewModel()
    @StateObject private var archiveVM = CameraArchiveViewModel()
    @StateObject private var ui = CameraDetailState()

    @ObservedObject private var detailPlayer = DetailPlayerStore.shared

    @State private var showEdit = false
    @State private var showFullscreen = false
    @State private var lastAppliedStreamKey: String? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var sceneRecoverTask: Task<Void, Never>?

    @StateObject private var deviceOrientation = DeviceOrientationObserver()

    @State private var archiveFollowTask: Task<Void, Never>?
    @State private var isPTZExpanded = false

    // Tuning
    private let debounceNanoseconds: UInt64 = 450_000_000
    private let minSeekDeltaSeconds: Double = 2.0
    private let minRequestDeltaSeconds: Int = 2
    private let goLiveThreshold: Double = 5

    private var sliderMax: Double { max(1, archiveVM.maxBackSeconds) }
    private var backSeconds: Double { sliderMax - ui.positionSeconds }

    private func playPTZToggleSound(expanded: Bool) {
        let openSound: SystemSoundID = 1157
        let closeSound: SystemSoundID = 1519
        AudioServicesPlaySystemSound(expanded ? openSound : closeSound)
    }

    var body: some View {
        content
            .navigationTitle("Детали камеры")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .onAppear(perform: onAppearSetup)
            .onDisappear(perform: onDisappearCleanup)

            .onChange(of: streamVM.streamKey, perform: handleStreamKeyChange)

            .onChange(of: archiveVM.maxBackSeconds) { _ in
                rebuildMarkersNow()

                let maxV = max(1, sliderMax)

                ui.previewPositionSeconds = min(max(ui.previewPositionSeconds, 0), maxV)
                ui.positionSeconds = min(max(ui.positionSeconds, 0), maxV)

                if streamVM.mode == "live" && !ui.isScrubbing {
                    ui.previewPositionSeconds = maxV
                    ui.positionSeconds = maxV
                    ui.lastOpenedPositionSeconds = maxV
                    ui.lastRequestedFromTs = nil
                }

                if streamVM.mode == "archive" && ui.isPlaying && !ui.isScrubbing {
                    rebaseArchiveFollowNow()
                    startArchiveTimelineFollow()
                }
            }

            .onChange(of: archiveVM.serverTime) { _ in
                rebuildMarkersNow()
            }

            .onChange(of: detailPlayer.showError, perform: handlePlayerShowError)
            .onChange(of: ui.showVideoError, perform: handleVideoErrorSheet)
            .onChange(of: ui.isPlaying, perform: handlePlayingChange)
            .onChange(of: scenePhase, perform: handleScenePhase)

            .onAppear { startArchiveTimelineFollow() }
            .onDisappear { archiveFollowTask?.cancel() }

            .onChange(of: streamVM.mode) { _ in startArchiveTimelineFollow() }
            .onChange(of: ui.isPlaying) { _ in startArchiveTimelineFollow() }
            .onChange(of: ui.isScrubbing) { _ in startArchiveTimelineFollow() }

            .onChange(of: archiveVM.shouldShowPTZControls) { canShow in
                if !canShow, isPTZExpanded {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                        isPTZExpanded = false
                    }
                }
            }

            .onChange(of: deviceOrientation.isLandscape) { isLand in
                if isLand && showFullscreen == false {
                    openFullscreen(auto: true)
                }
                if !isLand && showFullscreen == true {
                    closeFullscreen()
                }
            }

            .sheet(isPresented: $showEdit) { editSheet }

            .fullScreenCover(isPresented: $showFullscreen) {
                CameraFullscreenView(
                    streamVM: streamVM,
                    archiveVM: archiveVM,
                    playerStore: detailPlayer,
                    ui: ui,
                    sliderMax: sliderMax,
                    majorTickEvery: majorTickEvery,
                    minorTickEvery: minorTickEvery,
                    currentDateText: currentDateText,
                    previewDateText: previewDateText,
                    labelForValue: labelForTimelineValue,
                    compactLabelForValue: labelForTimelineValueCompact,
                    onScrubEnded: onScrubEnded,
                    onGoLive: goLive,
                    onDismiss: { closeFullscreen() },
                    scrubberHeight: 78
                )
            }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button { showEdit = true } label: {
                Image(systemName: "gearshape")
            }
        }
    }

    var liveOnlySection: some View {
        CameraLiveOnlySection(
            message: archiveVM.archiveStatusText ?? "Архив недоступен"
        )
    }

    private func onAppearSetup() {
        lastAppliedStreamKey = nil

        streamVM.setCamera(id: camera.id)
        archiveVM.setCamera(id: camera.id)
        ptzVM.setCamera(id: camera.id)

        let maxV = max(1, sliderMax)
        ui.positionSeconds = maxV
        ui.previewPositionSeconds = maxV
        ui.lastOpenedPositionSeconds = maxV

        if let url = CameraStreamPrefetch.shared.takeLive(cameraId: camera.id) {
            Task { @MainActor in
                detailPlayer.set(url: url, isLive: true, autoplay: ui.isPlaying, force: false)
                lastAppliedStreamKey = "live|\(url.absoluteString)"
            }
        }

        Task { @MainActor in
            await streamVM.openLive(force: true)
            await archiveVM.loadAll()
            rebuildMarkersNow()

            if archiveVM.isPTZ {
                await ptzVM.loadCapabilities()
            }
        }
    }

    private func onDisappearCleanup() {
        ui.isPlaying = false
        lastAppliedStreamKey = nil
        isPTZExpanded = false

        ptzVM.stopMove(for: "up")
        ptzVM.stopMove(for: "down")
        ptzVM.stopMove(for: "left")
        ptzVM.stopMove(for: "right")
        ptzVM.stopMove(for: "zoom_in")
        ptzVM.stopMove(for: "zoom_out")

        Task { @MainActor in
            detailPlayer.pause()
            detailPlayer.reset()
        }

        ui.debounceTask?.cancel()
        sceneRecoverTask?.cancel()
    }

    private func recoverOnActive() {
        sceneRecoverTask?.cancel()
        sceneRecoverTask = Task { @MainActor in
            detailPlayer.reconnect(autoplay: ui.isPlaying)

            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if Task.isCancelled { return }

            let stillBad =
                detailPlayer.hasFirstFrame == false ||
                detailPlayer.player.timeControlStatus == .waitingToPlayAtSpecifiedRate

            if stillBad {
                await streamVM.openLive(force: true)
            }

            Task { @MainActor in
                await archiveVM.loadArchiveRange()

                if archiveVM.shouldShowArchiveControls {
                    await archiveVM.loadArchiveEvents(limit: 120)
                } else {
                    archiveVM.clearArchiveEvents()
                }
            }

            Task { @MainActor in
                if archiveVM.isPTZ {
                    await ptzVM.loadCapabilities()
                }
            }
        }
    }

    private func labelForTimelineValueCompact(_ v: Double) -> String {
        if abs(v - sliderMax) < 0.5 { return "LIVE" }

        let st = Double(archiveVM.serverTime ?? Int(Date().timeIntervalSince1970))
        let back = sliderMax - v
        let ts = st - back

        return CameraTimeFormatter.timeOnlyWithSeconds(
            Date(timeIntervalSince1970: ts)
        )
    }

    private func labelForTimelineValue(_ v: Double) -> String {
        if abs(v - sliderMax) < 0.5 { return "LIVE" }

        let st = Double(archiveVM.serverTime ?? Int(Date().timeIntervalSince1970))
        let back = sliderMax - v
        let ts = st - back

        return CameraTimeFormatter.dateTimeWithDayIfNeededWithSeconds(
            Date(timeIntervalSince1970: ts)
        )
    }

    private var previewDateText: String {
        let st = Double(archiveVM.serverTime ?? Int(Date().timeIntervalSince1970))
        let back = sliderMax - ui.previewPositionSeconds
        let ts = st - back

        return CameraTimeFormatter.dateTimeWithDayIfNeededWithSeconds(
            Date(timeIntervalSince1970: ts)
        )
    }

    private var currentDateText: String {
        let st = Double(archiveVM.serverTime ?? Int(Date().timeIntervalSince1970))
        let back = sliderMax - ui.positionSeconds
        let ts = st - back

        return CameraTimeFormatter.dateTimeWithDayIfNeededWithSeconds(
            Date(timeIntervalSince1970: ts)
        )
    }

    private var majorTickEvery: Double {
        let hours = sliderMax / 3600
        if hours <= 1 { return 600 }
        if hours <= 6 { return 3600 }
        return 7200
    }

    private var minorTickEvery: Double {
        let hours = sliderMax / 3600
        if hours <= 1 { return 300 }
        return 600
    }

    private func openFullscreen(auto: Bool = false) {
        guard archiveVM.playerStatusText == nil else { return }
        guard showFullscreen == false else { return }
        guard showEdit == false else { return }

        OrientationLock.lockAndRotate(.landscape, to: .landscapeRight)
        showFullscreen = true
    }

    private func closeFullscreen() {
        guard showFullscreen else { return }

        showFullscreen = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            OrientationLock.lockAndRotate(.portrait, to: .portrait)
        }
    }

    private func rebaseArchiveFollowNow() {
        guard streamVM.mode == "archive" else { return }
        guard let stInt = archiveVM.serverTime else { return }

        let playerSec = detailPlayer.player.currentTime().seconds
        guard playerSec.isFinite else { return }

        let speed = ui.archiveSpeed ?? ui.archiveBaseSpeed
        let maxV = max(1, sliderMax)
        let back = maxV - ui.positionSeconds

        let st = Double(stInt)
        let currentTs = st - back

        ui.archiveBaseFromTs = Int(currentTs.rounded(.down))
        ui.archiveBasePlayerSeconds = playerSec
        ui.archiveBaseSpeed = speed
    }
}

private extension CameraDetailView {
    var content: some View {
        ScrollView {
            VStack(spacing: 16) {
                playerSection

                if archiveVM.shouldShowPTZControls && ptzVM.isAvailable && isPTZExpanded {
                    CameraPTZSection(vm: ptzVM)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .move(edge: .top).combined(with: .opacity)
                            )
                        )
                }

                if archiveVM.shouldShowArchiveControls {
                    dvrSection
                } else {
                    liveOnlySection
                }

                infoSection
                Spacer(minLength: 24)
            }
            .padding(.vertical)
        }
    }

    var playerSection: some View {
        VStack(spacing: 0) {
            CameraPlayerSection(
                streamVM: streamVM,
                playerStore: detailPlayer,
                ui: ui,
                archiveVM: archiveVM,
                backSeconds: backSeconds,
                goLiveThreshold: goLiveThreshold,
                onGoLive: goLive,
                onFullscreen: { openFullscreen() }
            )

            if archiveVM.shouldShowPTZControls && ptzVM.isAvailable {
                PTZDrawerHandle(
                    isExpanded: isPTZExpanded,
                    action: {
                        let newValue = !isPTZExpanded
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                            isPTZExpanded = newValue
                        }
                        playPTZToggleSound(expanded: newValue)
                    }
                )
                .padding(.horizontal)
                .padding(.top, -6)
            }
        }
    }

    var dvrSection: some View {
        CameraDVRSection(
            streamVM: streamVM,
            archiveVM: archiveVM,
            ui: ui,
            sliderMax: sliderMax,
            majorTickEvery: majorTickEvery,
            minorTickEvery: minorTickEvery,
            onScrubEnded: onScrubEnded,
            currentDateText: currentDateText,
            previewDateText: previewDateText,
            labelForValue: labelForTimelineValue,
            compactLabelForValue: labelForTimelineValueCompact,
            compactControls: false,
            scrubberHeight: 110
        )
    }

    var infoSection: some View {
        CameraInfoSection(camera: camera, streamVM: streamVM, archiveVM: archiveVM)
    }

    var editSheet: some View {
        EditCameraView(
            camera: camera,
            onSave: { _, _ in viewModel.loadCameras() },
            onDelete: {
                viewModel.loadCameras()
                dismiss()
            }
        )
    }

    func goLive() {
        guard archiveVM.isCameraActive, archiveVM.isCameraOnline else { return }

        CameraDetailLifecycle.goLive(
            ui: ui,
            sliderMax: sliderMax,
            streamVM: streamVM
        )
    }

    func onScrubEnded() {
        guard archiveVM.shouldShowArchiveControls else { return }

        CameraDetailLifecycle.scheduleOpenForPreviewPosition(
            ui: ui,
            debounceNanoseconds: debounceNanoseconds
        ) { pos in
            await CameraDetailLifecycle.openByPositionSeconds(
                position: pos,
                ui: ui,
                streamVM: streamVM,
                archiveVM: archiveVM,
                sliderMax: sliderMax,
                minSeekDeltaSeconds: minSeekDeltaSeconds,
                minRequestDeltaSeconds: minRequestDeltaSeconds,
                goLiveThreshold: goLiveThreshold,
                speed: ui.archiveSpeed
            )
        }
    }

    func rebuildMarkersNow() {
        CameraDetailLifecycle.rebuildMarkers(
            ui: ui,
            archiveVM: archiveVM,
            sliderMax: sliderMax
        )
    }

    func handleStreamKeyChange(_ key: String) {
        guard lastAppliedStreamKey != key else { return }
        lastAppliedStreamKey = key

        guard let url = streamVM.streamURL else { return }
        let isLive = (streamVM.mode == "live")

        Task { @MainActor in
            detailPlayer.set(url: url, isLive: isLive, autoplay: ui.isPlaying, force: !isLive)

            if isLive {
                ui.archiveBaseFromTs = nil
                ui.archiveBasePlayerSeconds = 0
                ui.archiveBaseSpeed = 1
            } else {
                if let ts = streamVM.currentArchiveTs {
                    ui.archiveBaseFromTs = ts
                }

                ui.archiveBaseSpeed = ui.archiveSpeed ?? 1

                let ps = detailPlayer.player.currentTime().seconds
                ui.archiveBasePlayerSeconds = ps.isFinite ? ps : 0
            }

            startArchiveTimelineFollow()
        }
    }

    func handlePlayerShowError(_ isErr: Bool) {
        guard isErr else { return }
        ui.showVideoError = true
        ui.videoErrorMessage = detailPlayer.errorMessage
    }

    func handleVideoErrorSheet(_ isShown: Bool) {
        if !isShown {
            Task { @MainActor in
                detailPlayer.clearError()
            }
        }
    }

    func handlePlayingChange(_ playing: Bool) {
        playing ? detailPlayer.player.play() : detailPlayer.player.pause()
    }

    func handleScenePhase(_ phase: ScenePhase) {
        guard phase == .active else { return }
        recoverOnActive()
    }

    private func startArchiveTimelineFollow() {
        archiveFollowTask?.cancel()

        guard archiveVM.shouldShowArchiveControls,
              streamVM.mode == "archive",
              ui.isPlaying,
              ui.isScrubbing == false,
              let _ = ui.archiveBaseFromTs else { return }

        archiveFollowTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                if Task.isCancelled { return }

                guard streamVM.mode == "archive",
                      ui.isPlaying,
                      ui.isScrubbing == false,
                      let baseTs = ui.archiveBaseFromTs else { continue }

                let playerSec = detailPlayer.player.currentTime().seconds
                guard playerSec.isFinite else { continue }

                let deltaPlayer = playerSec - ui.archiveBasePlayerSeconds
                guard deltaPlayer.isFinite else { continue }

                let speed = ui.archiveSpeed ?? ui.archiveBaseSpeed
                let deltaArchive = deltaPlayer * speed

                let currentTs = Double(baseTs) + deltaArchive
                let st = Double(archiveVM.serverTime ?? Int(Date().timeIntervalSince1970))
                let maxV = max(1, sliderMax)

                let back = st - currentTs
                let newPos = max(0, min(maxV, maxV - back))

                ui.positionSeconds = newPos
                ui.previewPositionSeconds = newPos
            }
        }
    }
}
