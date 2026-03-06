import Foundation

struct CameraStreamResponse: Decodable {
    let cameraId: Int
    let url: String?
    let format: String?
    let archive: Bool
    let mode: String?
    let availableFrom: String?
    let serverTime: Int?

    enum CodingKeys: String, CodingKey {
        case cameraId = "camera_id"
        case url, format, archive, mode
        case availableFrom = "available_from"
        case serverTime = "server_time"
    }
}


struct CameraStreamRequest: Encodable {
    let mode: String          // "live" | "archive"
    let platform: String      // "ios"
    let from: Int?            // TS seconds
    let tz: Int?              // secondsFromGMT
    let speed: Double?
}
