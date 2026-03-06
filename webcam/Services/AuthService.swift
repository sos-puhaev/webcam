import Foundation

struct TokensDTO: Decodable {
    let refresh: String
    let access: String
}

struct AuthResponse: Decodable {
    let tokens: TokensDTO?

    let access: String?
    let refresh: String?

    let user_id: Int?
    let user: UserDTO?
    let forpost: ForpostAnyDTO?

    var resolvedAccess: String? {
        tokens?.access ?? access
    }

    var resolvedRefresh: String? {
        tokens?.refresh ?? refresh
    }
}

struct UserDTO: Decodable {
    let id: Int
    let email: String
    let first_name: String
    let last_name: String
    let full_name: String
    let phone: String
    let account_type: String
    let business_name: String
    let max_cameras: Int
    let max_users: Int
    let is_active: Bool
    let date_joined: String
    let is_business_owner: Bool
    let is_business_employee: Bool
    let is_personal_account: Bool
}

struct ForpostAnyDTO: Decodable {
    let account_id: Int?
    let session_created: Bool?

    let authenticated: Bool?
    let error: String?
    let session_id: String?
}

struct RefreshRequestBody: Encodable {
    let refresh: String
}

final class AuthService {

    static let shared = AuthService()
    private let keychain = KeychainService.shared

    private init() {}
    
    private var refreshTask: Task<Bool, Error>?
    
    
    // MARK: - REFRESH
    func refreshAccessToken() async throws -> Bool {
        if let task = refreshTask { return try await task.value }

        let task = Task<Bool, Error> {
            defer { refreshTask = nil }

            guard let refreshToken = keychain.get(Constants.StorageKeys.refreshToken) else {
                return false
            }

            let body = RefreshRequestBody(refresh: refreshToken)
            let data = try JSONEncoder().encode(body)

            let response: AuthResponse = try await APIService.shared.request(
                endpoint: Constants.API.Auth.refresh,
                method: "POST",
                body: data,
                includeAuth: false,
                retryOnUnauthorized: false
            )

            guard let newAccess = response.resolvedAccess else { return false }

            
            let newRefresh = response.resolvedRefresh ?? refreshToken

            keychain.save(newAccess, for: Constants.StorageKeys.accessToken)
            keychain.save(newRefresh, for: Constants.StorageKeys.refreshToken)

            return true
        }

        refreshTask = task
        return try await task.value
    }
    
    // MARK: - LOGIN
    func login(email: String, password: String) async throws -> AuthResponse {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let body: [String: Any] = [
            "email": cleanEmail,
            "password": password
        ]
        let data = try JSONSerialization.data(withJSONObject: body)

        let response: AuthResponse = try await APIService.shared.request(
            endpoint: Constants.API.Auth.login,
            method: "POST",
            body: data
        )

        guard
            let access = response.resolvedAccess,
            let refresh = response.resolvedRefresh
        else { throw AuthError.serverError }

        saveTokens(access: access, refresh: refresh)
        return response
    }



    // MARK: - REGISTER
    func register(
        email: String,
        password: String,
        passwordConfirm: String,
        firstName: String,
        lastName: String,
        phone: String
    ) async throws -> AuthResponse {

        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let body: [String: Any] = [
            "email": cleanEmail,
            "password": password,
            "password_confirm": passwordConfirm,
            "first_name": firstName,
            "last_name": lastName,
            "phone": phone,
            "account_type": "personal",
            "create_forpost_account": true
        ]
        let data = try JSONSerialization.data(withJSONObject: body)

        let response: AuthResponse = try await APIService.shared.request(
            endpoint: Constants.API.Auth.register,
            method: "POST",
            body: data
        )

        guard
            let access = response.resolvedAccess,
            let refresh = response.resolvedRefresh
        else { throw AuthError.serverError }

        saveTokens(access: access, refresh: refresh)
        return response
    }


    // MARK: - TOKENS
    private func saveTokens(access: String, refresh: String) {
        keychain.save(access, for: Constants.StorageKeys.accessToken)
        keychain.save(refresh, for: Constants.StorageKeys.refreshToken)
        UserDefaults.standard.set(true, forKey: Constants.StorageKeys.isLoggedIn)
    }


    // MARK: - LOGOUT
    func logout() {
        keychain.delete(for: Constants.StorageKeys.accessToken)
        keychain.delete(for: Constants.StorageKeys.refreshToken)
        UserDefaults.standard.removeObject(forKey: Constants.StorageKeys.isLoggedIn)
    }

    func isLoggedIn() -> Bool {
        UserDefaults.standard.bool(forKey: Constants.StorageKeys.isLoggedIn) &&
        keychain.get(Constants.StorageKeys.refreshToken) != nil
    }
    
    enum AuthError: LocalizedError {
        case serverError

        var errorDescription: String? {
            switch self {
            case .serverError:
                return "Ошибка авторизации"
            }
        }
    }
}
