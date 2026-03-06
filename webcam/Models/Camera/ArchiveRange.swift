import Foundation

struct ArchiveRangeResponse: Decodable {
    let cameraId: Int
    let serverTime: Int
    let availableFromTs: Int
    let availableFrom: String
    let tz: Int
    let cached: Bool
    let platform: String?
    let format: String?

    enum CodingKeys: String, CodingKey {
        case cameraId = "camera_id"
        case serverTime = "server_time"
        case availableFromTs = "available_from_ts"
        case availableFrom = "available_from"
        case tz, cached, platform, format
    }
}
