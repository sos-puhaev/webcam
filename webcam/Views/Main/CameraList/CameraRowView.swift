import SwiftUI
import AVFoundation

struct CameraRowView: View {
    let camera: Camera
    @ObservedObject var viewModel: CameraListViewModel
    let gridLayout: GridLayoutType
    let prefetchCameraIds: [Int]

    @State private var player: AVPlayer?
    @State private var lastURL: String?
    @State private var isLoading = true
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isPlaying = true

    var body: some View {
        VStack(spacing: 6) {
            videoView
                .aspectRatio(gridLayout.aspectRatio, contentMode: .fit)

            Text(camera.name)
                .font(.caption)
                .lineLimit(1)
        }
        .onAppear {
            ListPlayerPool.shared.prefetch(cameraIds: prefetchCameraIds)
            ensurePlayerAndItem()
        }
        .onChange(of: camera.preview?.url) { _ in
            ensurePlayerAndItem()
        }
        .onDisappear {
            // держим тёплым, но останавливаем
            isPlaying = false
            ListPlayerPool.shared.release(cameraId: camera.id, keepWarm: true)
            player = nil
        }
    }

    private var videoView: some View {
        ZStack {
            if let player {
                HLSPlayerView(
                    player: player,
                    isPlaying: $isPlaying,
                    showError: $showError,
                    errorMessage: $errorMessage,
                    isLoading: $isLoading
                )
            } else {
                Color.gray.opacity(0.2)
            }
        }
    }

    private func ensurePlayerAndItem() {
        guard let urlString = camera.preview?.url,
              let url = URL(string: urlString) else {
            showError = true
            errorMessage = "Нет видео"
            isLoading = false
            return
        }

        let p = player ?? ListPlayerPool.shared.acquire(for: camera.id)
        p.isMuted = true
        p.automaticallyWaitsToMinimizeStalling = true
        player = p

        let status = p.currentItem?.status
        let needsReplace =
            (lastURL != urlString) ||
            (p.currentItem == nil) ||
            (status == .failed)

        if needsReplace {
            lastURL = urlString
            isLoading = true
            showError = false
            errorMessage = ""

            let item = AVPlayerItem(url: url)
            item.preferredForwardBufferDuration = 1.0
            item.preferredPeakBitRate = 0

            p.replaceCurrentItem(with: item)
        }

        if isPlaying {
            p.play()
        } else {
            p.pause()
        }
    }
}
