import SwiftUI
import AVKit
import Combine

@MainActor
class CameraListViewModel: ObservableObject {
    @Published var cameras: [Camera] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // Словарь для отслеживания состояния воспроизведения
    var playingStates: [Int: Bool] = [:]
    
    func loadCameras() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let cameras = try await CameraService().fetchCameras()
                self.cameras = cameras
                self.isLoading = false
            } catch {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    func getVideoURL(for camera: Camera) -> URL? {
        guard let urlString = camera.preview?.url,
              let url = URL(string: urlString) else {
            print("Invalid URL for camera \(camera.id): \(camera.preview?.url ?? "nil")")
            return nil
        }
        return url
    }
    
    func setPlayingState(for cameraId: Int, isPlaying: Bool) {
        playingStates[cameraId] = isPlaying
    }
    
    func getPlayingState(for cameraId: Int) -> Bool {
        return playingStates[cameraId] ?? true // по умолчанию воспроизводим
    }
}
