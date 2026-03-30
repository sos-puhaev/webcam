import Foundation

struct ArchiveRangeResponse: Decodable {
    let cameraId: Int
    let serverTime: Int
    let recordingEnabled: Bool
    let tz: Int
    let platform: String?
    let format: String?
    let cached: Bool

    let camera: ArchiveCameraInfo?
    let message: String?
    let range: ArchiveRangeInfo?
    let hasArchive: Bool

    enum CodingKeys: String, CodingKey {
        case cameraId = "camera_id"
        case serverTime = "server_time"
        case recordingEnabled = "recording_enabled"
        case tz
        case platform
        case format
        case cached
        case camera
        case message
        case range
        case hasArchive = "has_archive"
    }
}

struct ArchiveCameraInfo: Decodable {
    let name: String
    let isActive: Bool
    let state: Bool
    let quotaSeconds: Int?
    let ptz: Bool
    let sound: Bool?
    let homeMode: Bool?

    enum CodingKeys: String, CodingKey {
        case name
        case isActive = "is_active"
        case state
        case quotaSeconds = "quota_seconds"
        case ptz
        case sound
        case homeMode = "home_mode"
    }
}

struct ArchiveRangeInfo: Decodable {
    let fromTs: Int
    let toTs: Int
    let from: String?
    let to: String?

    enum CodingKeys: String, CodingKey {
        case fromTs = "from_ts"
        case toTs = "to_ts"
        case from
        case to
    }
}
