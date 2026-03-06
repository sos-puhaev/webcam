import Foundation

@MainActor
enum CameraDetailLifecycle {

    static func rebuildMarkers(
        ui: CameraDetailState,
        archiveVM: CameraArchiveViewModel,
        sliderMax: Double
    ) {
        let st = archiveVM.serverTime ?? Int(Date().timeIntervalSince1970)
        let maxV = max(1, sliderMax)

        ui.cachedMarkers = archiveVM.archiveEvents.compactMap { e in
            let back = Double(st - e.ts)
            let v = maxV - back
            guard v >= 0, v <= maxV else { return nil }

            return TimelineScrubber.TimelineMarker(
                id: e.id,
                value: v,
                duration: Double(e.duration),
                kind: .motion
            )
        }
    }

    static func scheduleOpenForPreviewPosition(
        ui: CameraDetailState,
        debounceNanoseconds: UInt64,
        openByPosition: @escaping (Double) async -> Void
    ) {
        ui.debounceTask?.cancel()
        let target = ui.previewPositionSeconds

        ui.debounceTask = Task { [target] in
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            if Task.isCancelled { return }

            await openByPosition(target)

            await MainActor.run {
                ui.positionSeconds = target
                ui.lastOpenedPositionSeconds = target
            }
        }
    }

    static func openByPositionSeconds(
        position: Double,
        ui: CameraDetailState,
        streamVM: CameraStreamViewModel,
        archiveVM: CameraArchiveViewModel,
        sliderMax: Double,
        minSeekDeltaSeconds: Double,
        minRequestDeltaSeconds: Int,
        goLiveThreshold: Double,
        speed: Double?
    ) async {
        if let last = ui.lastOpenedPositionSeconds,
           abs(position - last) < minSeekDeltaSeconds {
            return
        }

        let maxV = max(1, sliderMax)
        let back = maxV - position

        // ✅ если близко к LIVE — уходим в live и сбрасываем базу архива
        if back < goLiveThreshold {
            ui.archiveBaseFromTs = nil
            ui.archiveBasePlayerSeconds = 0

            await streamVM.openLive()
            ui.lastRequestedFromTs = nil
            return
        }

        let st = archiveVM.serverTime ?? Int(Date().timeIntervalSince1970)
        var fromTs = st - Int(back.rounded())

        // ✅ clamp: не уходим раньше начала архива
        if let minTs = archiveVM.availableFromTs {
            fromTs = max(fromTs, minTs)
        }

        // ✅ анти-спам запросов
        if let last = ui.lastRequestedFromTs, abs(fromTs - last) < minRequestDeltaSeconds {
            return
        }

        ui.lastRequestedFromTs = fromTs

        // ✅ база для “едущей шкалы”
        ui.archiveBaseFromTs = fromTs
        // archiveBasePlayerSeconds выставляется в CameraDetailView (после detailPlayer.set)

        streamVM.openArchiveDebounced(fromTs: fromTs, speed: speed)
    }

    static func goLive(
        ui: CameraDetailState,
        sliderMax: Double,
        streamVM: CameraStreamViewModel
    ) {
        ui.debounceTask?.cancel()
        ui.debounceTask = nil

        streamVM.cancelDebounce()

        let maxV = max(1, sliderMax)
        ui.previewPositionSeconds = maxV
        ui.positionSeconds = maxV
        ui.lastRequestedFromTs = nil
        ui.lastOpenedPositionSeconds = nil

        // ✅ сброс базы архива
        ui.archiveBaseFromTs = nil
        ui.archiveBasePlayerSeconds = 0

        streamVM.openLiveDebounced(force: true)
    }

    static func forceOpenArchiveNow(
        ui: CameraDetailState,
        streamVM: CameraStreamViewModel,
        archiveVM: CameraArchiveViewModel,
        sliderMax: Double,
        speed: Double?
    ) {
        // 1) отменяем дебаунс скраба, иначе он может переоткрыть старым speed позже
        ui.debounceTask?.cancel()
        ui.debounceTask = nil

        // 2) чтобы openByPositionSeconds не раннеретёрнил по minSeekDelta
        ui.lastOpenedPositionSeconds = nil

        // 3) нужен ts, который сейчас выбран
        let maxV = max(1, sliderMax)
        let back = maxV - ui.previewPositionSeconds
        let st = archiveVM.serverTime ?? Int(Date().timeIntervalSince1970)
        var fromTs = st - Int(back.rounded())

        if let minTs = archiveVM.availableFromTs {
            fromTs = max(fromTs, minTs)
        }

        ui.lastRequestedFromTs = fromTs

        // ✅ база для “едущей шкалы”
        ui.archiveBaseFromTs = fromTs
        // archiveBasePlayerSeconds выставляется в CameraDetailView (после detailPlayer.set)

        // 4) сразу открыть архив с новой скоростью (без ожидания debounce)
        Task { @MainActor in
            await streamVM.openArchive(fromTs: fromTs, speed: speed)
        }
    }
}
