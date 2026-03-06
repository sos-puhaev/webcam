import Foundation

struct PTZActionLinks: Decodable {
    let mousedown: String
    let mouseup: String
}

struct PTZCapabilitiesResponse: Decodable {
    let camera_id: Int
    let capabilities: PTZCapabilities
    let available_actions: PTZAvailableActions

    struct PTZCapabilities: Decodable {
        let repeatSending: Bool
        let ptz: [String: PTZActionLinks]?
        let zoom: [String: PTZActionLinks]?
        let focus: [String: PTZActionLinks]?
        let patrol: Bool?
        let center: [String: PTZActionLinks]?
        let homePosition: [String: PTZActionLinks]?
        let reset: [String: PTZActionLinks]?
    }

    struct PTZAvailableActions: Decodable {
        let ptz: [String: PTZActionLinks]?
        let zoom: [String: PTZActionLinks]?
        let focus: [String: PTZActionLinks]?
    }
}

extension PTZCapabilitiesResponse {

    var hasPTZ: Bool {
        guard let ptz = available_actions.ptz else { return false }
        return !ptz.isEmpty
    }

    var hasZoom: Bool {
        guard let zoom = available_actions.zoom else { return false }
        return !zoom.isEmpty
    }

    var hasAnyControl: Bool {
        hasPTZ || hasZoom
    }

    var ptzKeys: Set<String> {
        guard let ptz = available_actions.ptz else { return [] }
        return Set(ptz.keys)
    }

    var zoomKeys: Set<String> {
        guard let zoom = available_actions.zoom else { return [] }
        return Set(zoom.keys)
    }
}

struct PTZActionRequest: Encodable {
    let action: String
    let velocity: Double?
    let check_capabilities: Bool
}

struct PTZActionResponse: Decodable {
    let camera_id: Int
    let action: String
    let velocity: Double?
    let status: String
    let result: JSONValue?
}
