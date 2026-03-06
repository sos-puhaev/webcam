import Foundation

struct APIResponse<T: Codable>: Codable {
    let success: Bool
    let data: T?
    let message: String?
    let error: String?
}

struct RegisterResponse: Decodable {
    let tokens: Tokens
    
    struct Tokens: Decodable {
        let access: String
        let refresh: String
    }
}

// Для логина
struct LoginResponse: Decodable {
    let access: String
    let refresh: String
}
