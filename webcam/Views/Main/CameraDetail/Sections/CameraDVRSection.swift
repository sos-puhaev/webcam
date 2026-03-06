import SwiftUI

struct CameraDVRSection: View {
    @ObservedObject var streamVM: CameraStreamViewModel
    @ObservedObject var archiveVM: CameraArchiveViewModel
    @ObservedObject var ui: CameraDetailState

    let sliderMax: Double
    let majorTickEvery: Double
    let minorTickEvery: Double

    let onScrubEnded: () -> Void

    let currentDateText: String
    let previewDateText: String

    let labelForValue: (Double) -> String
    let compactLabelForValue: (Double) -> String

    /// true = в fullscreen/компактном режиме (убираем ±10 и play/pause)
    let compactControls: Bool

    /// Высота scrubber (обычно 110 в обычном, 76–90 в fullscreen)
    let scrubberHeight: CGFloat

    private var modeLabel: String { streamVM.mode == "live" ? "LIVE" : "ARCHIVE" }

    private let speeds: [Double] = [16, 8, 1]

    var body: some View {
        VStack(spacing: 8) {
            if !compactControls {
                HStack(spacing: 12) {
                    Button {
                        guard sliderMax > 1 else { return }
                        ui.debounceTask?.cancel()
                        ui.previewPositionSeconds = max(0, ui.previewPositionSeconds - 10)
                        onScrubEnded()
                    } label: { Image(systemName: "gobackward.10") }

                    Button { ui.isPlaying.toggle() } label: {
                        Image(systemName: ui.isPlaying ? "pause.fill" : "play.fill")
                    }

                    Button {
                        guard sliderMax > 1 else { return }
                        ui.debounceTask?.cancel()
                        ui.previewPositionSeconds = min(sliderMax, ui.previewPositionSeconds + 10)
                        onScrubEnded()
                    } label: { Image(systemName: "goforward.10") }

                    Spacer()

                    if streamVM.mode == "archive" {
                        speedMenu(isCompact: false)
                    }

                    Text(modeLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(streamVM.mode == "live" ? .green : .secondary)
                }
                .font(.title3)
                .padding(.horizontal)

                if streamVM.mode != "live" {
                    Text("Время: \(ui.isScrubbing ? previewDateText : currentDateText)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                        .padding(.top, 2)
                }

            } else {
                // Fullscreen — только скорость справа
                HStack(spacing: 12) {
                    Spacer()

                    if streamVM.mode == "archive" {
                        speedMenu(isCompact: true)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 2)
            }

            TimelineScrubber(
                maxValue: sliderMax,
                value: $ui.previewPositionSeconds,
                isScrubbing: $ui.isScrubbing,
                labelForValue: labelForValue,
                compactLabelForValue: compactLabelForValue,
                adaptiveTicks: true,
                majorTickEvery: majorTickEvery,
                minorTickEvery: minorTickEvery,
                onScrubEnded: onScrubEnded,
                markers: ui.cachedMarkers
            )
            .overlay(alignment: .top) {
                if compactControls && streamVM.mode != "live" {
                    Text(ui.isScrubbing ? previewDateText : currentDateText)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.35))
                        .cornerRadius(10)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .offset(y: -16)
                        .allowsHitTesting(false)
                }
            }
            .onAppear { clampValues() }
            .onChange(of: sliderMax) { _ in clampValues() }
            .onChange(of: ui.previewPositionSeconds) { _ in clampValuesIfNeeded() }
            .frame(height: scrubberHeight)
            .padding(.horizontal)
        }
        .padding(.top, 2)
    }

    // MARK: - Speed menu

    private func speedMenu(isCompact: Bool) -> some View {
        Menu {
            Button("1× (обычно)") {
                applyArchiveSpeed(nil)       // ✅ сразу переоткроет архив
            }

            ForEach(speeds.filter { $0 != 1 }, id: \.self) { s in
                Button(speedTitle(s)) {
                    applyArchiveSpeed(s)     // ✅ сразу переоткроет архив
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "speedometer")
                Text(speedTitle(ui.archiveSpeed ?? 1))
            }
            .font((isCompact ? Font.caption2 : Font.caption).weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isCompact ? Color.black.opacity(0.30) : Color.black.opacity(0.08))
            .foregroundColor(isCompact ? .white : .primary)
            .cornerRadius(10)
        }
    }

    /// ✅ Меняем скорость и сразу переоткрываем текущий архив без скраба
    private func applyArchiveSpeed(_ speed: Double?) {
        ui.archiveSpeed = speed

        guard streamVM.mode == "archive" else { return }

        ui.debounceTask?.cancel()
        ui.debounceTask = nil
        ui.lastOpenedPositionSeconds = nil

        let maxV = max(1, sliderMax)
        let back = maxV - ui.previewPositionSeconds

        let st = archiveVM.serverTime ?? Int(Date().timeIntervalSince1970)
        var fromTs = st - Int(back)

        if let minTs = archiveVM.availableFromTs {
            fromTs = max(fromTs, minTs)
        }

        ui.lastRequestedFromTs = fromTs

        // ✅ база для follow
        ui.archiveBaseFromTs = fromTs
        ui.archiveBaseSpeed = speed ?? 1

        // ✅ базовая точка player-time (после переоткрытия будет 0, но на всякий)
        ui.archiveBasePlayerSeconds = 0

        Task { @MainActor in
            await streamVM.openArchive(fromTs: fromTs, speed: speed)
        }
    }

    // MARK: - Clamp

    private func clampValues() {
        let maxV = max(1, sliderMax)
        if ui.previewPositionSeconds < 0 { ui.previewPositionSeconds = 0 }
        if ui.previewPositionSeconds > maxV { ui.previewPositionSeconds = maxV }

        if ui.positionSeconds < 0 { ui.positionSeconds = 0 }
        if ui.positionSeconds > maxV { ui.positionSeconds = maxV }
    }

    private func clampValuesIfNeeded() {
        let maxV = max(1, sliderMax)
        if ui.previewPositionSeconds < 0 || ui.previewPositionSeconds > maxV {
            clampValues()
        }
    }

    private func speedTitle(_ v: Double) -> String {
        if v == 1 { return "1×" }
        if v >= 1 { return "\(Int(v))×" }
        return "\(v)×"
    }
}
