struct Constants {

    static let baseURL = "http://192.168.1.51:8081/api"
    
    struct StorageKeys {
        static let accessToken = "accessToken"
        static let refreshToken = "refreshToken"
        static let isLoggedIn = "isLoggedIn"
    }

    struct API {
        struct Auth {
            static let login = "/auth/login/"
            static let register = "/auth/register/"
            static let refresh = "/auth/refresh/"
        }
        struct Camera {
            static let add_camera = "/camera/add/"
            static let list_cameras = "/camera/list/"
            static func stream(cameraID: Int) -> String {
                    "/camera/\(cameraID)/stream/"
            }
            static func archiveRange(cameraID: Int, tz: Int) -> String {
                    "/camera/\(cameraID)/archive-range/?tz=\(tz)&platform=ios"
            }
            static func archiveEvents(cameraID: Int, tz: Int, limit: Int = 300, types: [Int] = []) -> String {
                var s = "/camera/\(cameraID)/archive-events/?tz=\(tz)&platform=ios&limit=\(limit)"
                for t in types { s += "&types[]=\(t)" }
                return s
            }
            static func ptz(cameraID: Int) -> String {
                "/camera/\(cameraID)/ptz/"
            }
        }
    }
}
