import SwiftUI
import AVKit

struct CameraPlayerSection: View {
    @ObservedObject var streamVM: CameraStreamViewModel
    @ObservedObject var playerStore: DetailPlayerStore
    @ObservedObject var ui: CameraDetailState

    let backSeconds: Double
    let goLiveThreshold: Double
    let onGoLive: () -> Void
    let onFullscreen: () -> Void

    private var showGoLiveButton: Bool {
        streamVM.mode == "archive" || backSeconds > goLiveThreshold
    }

    var body: some View {
        VStack {
            ZStack {
                let hasPlayerItem = playerStore.player.currentItem != nil

                if hasPlayerItem || streamVM.streamURL != nil {
                    ZoomableDetailPlayerView(
                        player: playerStore.player,
                        isPlaying: $ui.isPlaying,
                        showError: $ui.showVideoError,
                        errorMessage: $ui.videoErrorMessage,
                        isLoading: $ui.isLoading
                    )
                    .frame(height: 240)
                    .cornerRadius(12)
                    .shadow(radius: 2)

                    // Fullscreen
                    Button(action: onFullscreen) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.title3.weight(.semibold))
                            .padding(10)
                            .background(.black.opacity(0.6))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                    if !playerStore.hasFirstFrame && (playerStore.isLoading || streamVM.isLoading) {
                        ProgressView().scaleEffect(1.5)
                    }

                    if playerStore.isRebuffering {
                        VStack {
                            Spacer()
                            HStack(spacing: 8) {
                                ProgressView().scaleEffect(0.9)
                                Text("Буферизация…").font(.caption.weight(.semibold))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.6))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                            .padding(.bottom, 10)
                        }
                    }

                    if playerStore.showError || ui.showVideoError {
                        VStack {
                            Spacer()
                            Button {
                                Task { @MainActor in
                                    // ✅ сразу прячем кнопку
                                    playerStore.clearError()
                                    ui.showVideoError = false
                                    ui.videoErrorMessage = ""
                                    ui.isLoading = true

                                    // ✅ реконнект
                                    playerStore.reconnect(autoplay: ui.isPlaying)
                                }
                                streamVM.reconnectStream(force: true)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Переподключиться")
                                }
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(.black.opacity(0.65))
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                            .padding(.bottom, 12)
                        }
                    }

                    if !ui.isPlaying {
                        ZStack {
                            Color.black.opacity(0.7)
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.white)
                        }
                        .frame(height: 240)
                        .cornerRadius(12)
                        .onTapGesture { ui.isPlaying = true }
                    }

                    if showGoLiveButton {
                        Button(action: onGoLive) {
                            Text("Онлайн")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.black.opacity(0.6))
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }

                } else if streamVM.isLoading || ui.isLoading {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.15))
                        .frame(height: 240)
                    ProgressView().scaleEffect(1.5)

                } else {
                    ZStack {
                        Color.gray.opacity(0.2)
                        VStack(spacing: 12) {
                            Image(systemName: "video.slash")
                                .font(.system(size: 60))
                            Text("Видеопоток недоступен").font(.headline)
                            Text(streamVM.errorMessage ?? "Проверьте доступ и настройки камеры")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .foregroundColor(.gray)
                    }
                    .frame(height: 240)
                    .cornerRadius(12)
                }
            }
        }
        .padding(.horizontal)
    }
}
