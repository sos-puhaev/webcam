import SwiftUI
import AVFoundation

struct AdaptiveVideoPlayerView: UIViewRepresentable {
    let url: URL
    let containerSize: CGSize
    let aspectRatio: CGFloat
    @Binding var isLoading: Bool
    @Binding var showError: Bool
    @Binding var errorMessage: String
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        
        // Создание AVPlayer
        let asset = AVAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        playerItem.preferredForwardBufferDuration = 2
        
        let player = AVPlayer(playerItem: playerItem)
        player.isMuted = true
        
        // Настройка AVPlayerLayer с правильным масштабированием
        let playerLayer = AVPlayerLayer(player: player)
        
        // Рассчитываем размер видео для заполнения контейнера с сохранением пропорций
        let containerWidth = containerSize.width
        let containerHeight = containerSize.height
        
        // Рассчитываем размеры в зависимости от aspect ratio контейнера
        let containerAspectRatio = containerWidth / containerHeight
        let videoAspectRatio: CGFloat = 16/9 // Предполагаем стандартное соотношение видео
        
        var videoWidth: CGFloat
        var videoHeight: CGFloat
        
        if containerAspectRatio > videoAspectRatio {
            // Контейнер шире видео - масштабируем по высоте
            videoHeight = containerHeight
            videoWidth = videoHeight * videoAspectRatio
        } else {
            // Контейнер уже видео - масштабируем по ширине
            videoWidth = containerWidth
            videoHeight = videoWidth / videoAspectRatio
        }
        
        // Центрируем видео в контейнере
        let xOffset = (containerWidth - videoWidth) / 2
        let yOffset = (containerHeight - videoHeight) / 2
        
        playerLayer.frame = CGRect(x: xOffset, y: yOffset, width: videoWidth, height: videoHeight)
        playerLayer.videoGravity = .resizeAspect // Важно: resizeAspect сохраняет пропорции
        playerLayer.needsDisplayOnBoundsChange = true
        view.layer.addSublayer(playerLayer)
        
        // Сохранение ссылок в координаторе
        context.coordinator.player = player
        context.coordinator.playerLayer = playerLayer
        context.coordinator.containerSize = containerSize
        context.coordinator.aspectRatio = aspectRatio
        
        // Наблюдение за статусом
        playerItem.addObserver(context.coordinator,
                               forKeyPath: #keyPath(AVPlayerItem.status),
                               options: [.old, .new],
                               context: nil)
        
        // Наблюдение за буферизацией
        playerItem.addObserver(context.coordinator,
                               forKeyPath: #keyPath(AVPlayerItem.isPlaybackBufferEmpty),
                               options: [.new],
                               context: nil)
        
        playerItem.addObserver(context.coordinator,
                               forKeyPath: #keyPath(AVPlayerItem.isPlaybackLikelyToKeepUp),
                               options: [.new],
                               context: nil)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Обновление размера слоя при изменении размера view
        if let coordinator = context.coordinator as? Coordinator,
           let playerLayer = coordinator.playerLayer {
            
            let containerWidth = containerSize.width
            let containerHeight = containerSize.height
            
            // Рассчитываем размеры в зависимости от aspect ratio контейнера
            let containerAspectRatio = containerWidth / containerHeight
            let videoAspectRatio: CGFloat = 16/9 // Предполагаем стандартное соотношение видео
            
            var videoWidth: CGFloat
            var videoHeight: CGFloat
            
            if containerAspectRatio > videoAspectRatio {
                // Контейнер шире видео - масштабируем по высоте
                videoHeight = containerHeight
                videoWidth = videoHeight * videoAspectRatio
            } else {
                // Контейнер уже видео - масштабируем по ширине
                videoWidth = containerWidth
                videoHeight = videoWidth / videoAspectRatio
            }
            
            // Центрируем видео в контейнере
            let xOffset = (containerWidth - videoWidth) / 2
            let yOffset = (containerHeight - videoHeight) / 2
            
            playerLayer.frame = CGRect(x: xOffset, y: yOffset, width: videoWidth, height: videoHeight)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    class Coordinator: NSObject {
        var parent: AdaptiveVideoPlayerView
        var player: AVPlayer?
        var playerLayer: AVPlayerLayer?
        var containerSize: CGSize = .zero
        var aspectRatio: CGFloat = 1
        
        init(parent: AdaptiveVideoPlayerView) {
            self.parent = parent
        }
        
        override func observeValue(forKeyPath keyPath: String?,
                                   of object: Any?,
                                   change: [NSKeyValueChangeKey : Any]?,
                                   context: UnsafeMutableRawPointer?) {
            guard let playerItem = object as? AVPlayerItem else { return }
            
            DispatchQueue.main.async {
                if keyPath == #keyPath(AVPlayerItem.status) {
                    let status: AVPlayerItem.Status
                    if let statusNumber = change?[.newKey] as? NSNumber {
                        status = AVPlayerItem.Status(rawValue: statusNumber.intValue)!
                    } else {
                        status = .unknown
                    }
                    
                    switch status {
                    case .readyToPlay:
                        self.parent.isLoading = false
                        self.player?.play()
                    case .failed:
                        self.parent.isLoading = false
                        self.parent.showError = true
                        self.parent.errorMessage = playerItem.error?.localizedDescription ?? "Ошибка загрузки видео"
                    case .unknown:
                        self.parent.isLoading = true
                    @unknown default:
                        break
                    }
                }
                else if keyPath == #keyPath(AVPlayerItem.isPlaybackBufferEmpty) {
                    if playerItem.isPlaybackBufferEmpty {
                        self.parent.isLoading = true
                    }
                }
                else if keyPath == #keyPath(AVPlayerItem.isPlaybackLikelyToKeepUp) {
                    if playerItem.isPlaybackLikelyToKeepUp {
                        self.parent.isLoading = false
                    }
                }
            }
        }
        
        deinit {
            player?.currentItem?.removeObserver(self, forKeyPath: #keyPath(AVPlayerItem.status))
            player?.currentItem?.removeObserver(self, forKeyPath: #keyPath(AVPlayerItem.isPlaybackBufferEmpty))
            player?.currentItem?.removeObserver(self, forKeyPath: #keyPath(AVPlayerItem.isPlaybackLikelyToKeepUp))
            player?.pause()
            player = nil
        }
    }
    
    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.player?.pause()
        coordinator.player = nil
        coordinator.playerLayer?.removeFromSuperlayer()
        coordinator.playerLayer = nil
    }
}
