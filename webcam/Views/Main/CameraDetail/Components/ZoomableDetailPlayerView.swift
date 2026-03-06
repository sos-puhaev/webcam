import SwiftUI
import AVKit

struct ZoomableDetailPlayerView: View {
    let player: AVPlayer
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill   // ✅ новое

    @Binding var isPlaying: Bool
    @Binding var showError: Bool
    @Binding var errorMessage: String
    @Binding var isLoading: Bool

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let minScale: CGFloat = 1
    private let maxScale: CGFloat = 4

    var body: some View {
        HLSPlayerView(
            player: player,
            videoGravity: videoGravity,              // ✅ прокинули
            isPlaying: $isPlaying,
            showError: $showError,
            errorMessage: $errorMessage,
            isLoading: $isLoading
        )
        .scaleEffect(scale)
        .offset(offset)
        .gesture(magnificationGesture.simultaneously(with: dragGesture))
        .onTapGesture(count: 2) { resetTransform() }
        .clipped()
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let newScale = lastScale * value
                scale = min(max(newScale, minScale), maxScale)
                if scale <= 1.01 {
                    offset = .zero
                    lastOffset = .zero
                }
            }
            .onEnded { _ in
                lastScale = scale
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1.01 else { return }
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                guard scale > 1.01 else { return }
                lastOffset = offset
            }
    }

    private func resetTransform() {
        withAnimation(.spring()) {
            scale = 1
            lastScale = 1
            offset = .zero
            lastOffset = .zero
        }
    }
}
