import Foundation

struct User: Codable, Identifiable {
    let id: String
    let email: String
    let name: String?
    let phone: String?
    let token: String?
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id, email, name, phone, token
        case createdAt = "created_at"
    }
}

struct LoginRequest: Codable {
    let email: String
    let password: String
}

struct RegisterRequest: Encodable {
    let email: String
    let password: String
    let password_confirm: String
    let first_name: String
    let last_name: String
    let phone: String
    let account_type: String
    let create_forpost_account: Bool
}
