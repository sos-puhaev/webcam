import Foundation

struct Camera: Decodable, Identifiable {
    let id: Int
    let name: String
    let preview: CameraPreview?

    enum CodingKeys: String, CodingKey {
        case id = "CameraID"
        case name = "Name"
        case preview = "PreviewURL"
    }
}
