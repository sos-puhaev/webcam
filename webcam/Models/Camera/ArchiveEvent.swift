import Foundation

struct ArchiveEventsResponse: Decodable {
    let camera_id: Int
    let archive_from_ts: Int
    let archive_to_ts: Int
    let events: [ArchiveEvent]
    let cached: Bool
}

struct ArchiveEvent: Decodable, Identifiable {
    var id: String { "\(ts)-\(name ?? "")" }
    let ts: Int
    let duration: Int
    let name: String?
}
