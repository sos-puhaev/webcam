import SwiftUI
import AVKit

struct CameraFullscreenView: View {
    @ObservedObject var streamVM: CameraStreamViewModel
    @ObservedObject var archiveVM: CameraArchiveViewModel
    @ObservedObject var playerStore: DetailPlayerStore
    @ObservedObject var ui: CameraDetailState

    let sliderMax: Double
    let majorTickEvery: Double
    let minorTickEvery: Double

    let currentDateText: String
    let previewDateText: String

    let labelForValue: (Double) -> String
    let compactLabelForValue: (Double) -> String

    let onScrubEnded: () -> Void
    let onGoLive: () -> Void
    let onDismiss: () -> Void

    /// Высота scrubber в fullscreen (обычно 76–90)
    let scrubberHeight: CGFloat

    @State private var dvrExpanded: Bool = true
    @State private var autoHideTask: Task<Void, Never>?

    private let autoHideSeconds: UInt64 = 5

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Видео на весь экран
            ZoomableDetailPlayerView(
                player: playerStore.player,
                videoGravity: .resizeAspect,
                isPlaying: $ui.isPlaying,
                showError: $ui.showVideoError,
                errorMessage: $ui.videoErrorMessage,
                isLoading: $ui.isLoading
            )
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture {
                // тап по видео — показать DVR
                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                    dvrExpanded = true
                }
                scheduleAutoHideIfNeeded()
            }

            // Play/Pause по центру сверху
            playPauseTopCenter
                .zIndex(11)

            // Верхние кнопки (закрыть/онлайн)
            topButtons
                .zIndex(10)

            // Нижняя панель DVR (только низ)
            dvrOverlay
                .zIndex(9)
        }
        .statusBarHidden(true)
        .onAppear { scheduleAutoHideIfNeeded() }
        .onChange(of: ui.isPlaying) { _ in scheduleAutoHideIfNeeded() }
        .onChange(of: ui.isScrubbing) { _ in scheduleAutoHideIfNeeded() }
        .onDisappear { autoHideTask?.cancel() }
    }

    private var topButtons: some View {
        HStack {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .padding(10)
                    .background(.black.opacity(0.45))
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.leading, 16)
            .padding(.top, 12)

            Spacer()

            if streamVM.mode == "archive" {
                Button(action: onGoLive) {
                    Text("Онлайн")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.45))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding(.trailing, 16)
                .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(true)
    }

    private var playPauseTopCenter: some View {
        Button {
            ui.isPlaying.toggle()
            scheduleAutoHideIfNeeded()
        } label: {
            Image(systemName: ui.isPlaying ? "pause.fill" : "play.fill")
                .font(.title3.weight(.semibold))
                .padding(12)
                .background(.black.opacity(0.45))
                .foregroundColor(.white)
                .cornerRadius(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 10)
    }

    private var dvrOverlay: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 6) {
                // header + toggle
                HStack {
                    Capsule()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: 44, height: 5)
                        .padding(.vertical, 8)

                    Spacer()

                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                            dvrExpanded.toggle()
                        }
                        scheduleAutoHideIfNeeded()
                    } label: {
                        Image(systemName: dvrExpanded ? "chevron.down" : "chevron.up")
                            .font(.headline.weight(.semibold))
                            .padding(8)
                            .background(.black.opacity(0.30))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
                .padding(.horizontal, 12)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                        dvrExpanded.toggle()
                    }
                    scheduleAutoHideIfNeeded()
                }

                if dvrExpanded {
                    CameraDVRSection(
                        streamVM: streamVM,
                        archiveVM: archiveVM,
                        ui: ui,
                        sliderMax: sliderMax,
                        majorTickEvery: majorTickEvery,
                        minorTickEvery: minorTickEvery,
                        onScrubEnded: {
                            onScrubEnded()
                            scheduleAutoHideIfNeeded()
                        },
                        currentDateText: currentDateText,
                        previewDateText: previewDateText,
                        labelForValue: labelForValue,
                        compactLabelForValue: compactLabelForValue,
                        compactControls: true,
                        scrubberHeight: scrubberHeight
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.bottom, 8)
            .background(
                // компактная "тень" снизу, не заливать полэкрана
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.black.opacity(0.0),
                        Color.black.opacity(0.65)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .bottom)
            )
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onEnded { value in
                        if value.translation.height > 30 {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                dvrExpanded = false
                            }
                        } else if value.translation.height < -30 {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                dvrExpanded = true
                            }
                        }
                        scheduleAutoHideIfNeeded()
                    }
            )
        }
        .allowsHitTesting(true)
    }

    private func scheduleAutoHideIfNeeded() {
        autoHideTask?.cancel()

        // Не прячем, если пауза или пользователь скрабит
        guard ui.isPlaying else { return }
        guard ui.isScrubbing == false else { return }

        autoHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: autoHideSeconds * 1_000_000_000)
            if Task.isCancelled { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                dvrExpanded = false
            }
        }
    }
}
