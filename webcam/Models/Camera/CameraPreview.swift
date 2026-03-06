import Foundation

struct CameraPreview: Decodable {
    let url: String?
    let format: String?
    let archive: Bool?

    enum CodingKeys: String, CodingKey {
        case url
        case format
        case archive
    }
}
