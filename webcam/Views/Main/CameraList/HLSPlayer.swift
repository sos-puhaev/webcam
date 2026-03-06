import SwiftUI
import AVFoundation

struct HLSPlayerView: UIViewRepresentable {
    let player: AVPlayer
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill   // ✅ новое

    @Binding var isPlaying: Bool
    @Binding var showError: Bool
    @Binding var errorMessage: String
    @Binding var isLoading: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            player: player,
            isPlaying: $isPlaying,
            showError: $showError,
            errorMessage: $errorMessage,
            isLoading: $isLoading
        )
    }

    func makeUIView(context: Context) -> PlayerUIView {
        let v = PlayerUIView()
        v.playerLayer.player = player
        v.playerLayer.videoGravity = videoGravity            // ✅
        context.coordinator.attach(player: player)
        context.coordinator.rebindIfNeeded()
        context.coordinator.syncPlayback()
        return v
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.playerLayer.player = player
        uiView.playerLayer.videoGravity = videoGravity        // ✅
        context.coordinator.attach(player: player)
        context.coordinator.rebindIfNeeded()
        context.coordinator.syncPlayback()
    }

    final class Coordinator {
        private weak var player: AVPlayer?

        private var isPlaying: Binding<Bool>
        private var showError: Binding<Bool>
        private var errorMessage: Binding<String>
        private var isLoading: Binding<Bool>

        private weak var observedItem: AVPlayerItem?
        private var itemStatusObs: NSKeyValueObservation?
        private var lastIsPlaying: Bool?

        init(
            player: AVPlayer,
            isPlaying: Binding<Bool>,
            showError: Binding<Bool>,
            errorMessage: Binding<String>,
            isLoading: Binding<Bool>
        ) {
            self.player = player
            self.isPlaying = isPlaying
            self.showError = showError
            self.errorMessage = errorMessage
            self.isLoading = isLoading
        }

        func attach(player: AVPlayer) { self.player = player }

        func syncPlayback() {
            let current = isPlaying.wrappedValue
            if lastIsPlaying == current { return }
            lastIsPlaying = current
            current ? player?.play() : player?.pause()
        }

        func rebindIfNeeded() {
            guard let player else { return }
            let currentItem = player.currentItem
            if currentItem === observedItem { return }
            observe(item: currentItem)
        }

        private func observe(item: AVPlayerItem?) {
            itemStatusObs?.invalidate()
            itemStatusObs = nil
            observedItem = item
            guard let item else { return }

            itemStatusObs = item.observe(\.status, options: [.initial, .new]) { [weak self] it, _ in
                guard let self else { return }
                Task { @MainActor in
                    await Task.yield()
                    switch it.status {
                    case .unknown:
                        self.isLoading.wrappedValue = true
                    case .readyToPlay:
                        self.isLoading.wrappedValue = false
                        self.showError.wrappedValue = false
                        self.errorMessage.wrappedValue = ""
                    case .failed:
                        self.isLoading.wrappedValue = false
                        self.showError.wrappedValue = true
                        self.errorMessage.wrappedValue =
                            it.error?.localizedDescription ?? "Ошибка воспроизведения"
                    @unknown default:
                        break
                    }
                }
            }
        }
    }
}

final class PlayerUIView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
