import Foundation

final class PTZService {
    static let shared = PTZService()
    private init() {}

    func getCapabilities(cameraID: Int) async throws -> PTZCapabilitiesResponse {
        try await APIService.shared.request(
            endpoint: Constants.API.Camera.ptz(cameraID: cameraID),
            method: "GET",
            includeAuth: true,
            timeoutOverride: 10
        )
    }

    func sendAction(
        cameraID: Int,
        action: String,
        velocity: Double? = nil,
        checkCapabilities: Bool = true,
        timeout: TimeInterval = 8
    ) async throws -> PTZActionResponse {

        let body = PTZActionRequest(
            action: action,
            velocity: velocity,
            check_capabilities: checkCapabilities
        )

        let data = try JSONEncoder().encode(body)

        return try await APIService.shared.request(
            endpoint: Constants.API.Camera.ptz(cameraID: cameraID),
            method: "POST",
            body: data,
            includeAuth: true,
            timeoutOverride: timeout
        )
    }
}
