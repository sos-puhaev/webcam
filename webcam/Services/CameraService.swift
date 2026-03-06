import Foundation

final class CameraService {

    func fetchCameras() async throws -> [Camera] {

        #if DEBUG
        print("📡 Fetch cameras started")
        #endif

        do {
            let response: CameraListResponse = try await APIService.shared.request(
                endpoint: Constants.API.Camera.list_cameras
            )

            #if DEBUG
            print("✅ Cameras fetched: \(response.list.count)")
            #endif

            return response.list

        } catch {

            #if DEBUG
            print("❌ Fetch cameras failed:", error)
            #endif

            throw error
        }
    }
}
