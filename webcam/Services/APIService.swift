import Foundation

final class APIService {
    static let shared = APIService()
    private init() {}

    private let baseURL = "http://192.168.1.51:8081/api"

    private var token: String? {
        KeychainService.shared.get(Constants.StorageKeys.accessToken)
    }

    // MARK: - Request builder

    private func createRequest(
        endpoint: String,
        method: String,
        body: Data? = nil,
        includeAuth: Bool = true,
        timeout: TimeInterval = 15
    ) -> URLRequest? {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // ✅ таймаут чтобы не висеть бесконечно
        request.timeoutInterval = timeout

        if includeAuth, let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = body
        return request
    }

    private func performRequest<T: Decodable>(
        endpoint: String,
        method: String,
        body: Data?,
        includeAuth: Bool,
        timeout: TimeInterval
    ) async throws -> T {

        guard let request = createRequest(
            endpoint: endpoint,
            method: method,
            body: body,
            includeAuth: includeAuth,
            timeout: timeout
        ) else {
            throw NetworkError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.serverError(statusCode: -1, message: "Invalid response")
        }

        let raw = String(data: data, encoding: .utf8) ?? ""

        switch httpResponse.statusCode {
        case 200...299:
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                print("❌ Decoding error:", error)
                print("📦 Raw:", raw)
                throw NetworkError.decodingError(underlying: error, raw: raw)
            }

        case 401:
            throw NetworkError.unauthorized

        default:
            throw NetworkError.serverError(statusCode: httpResponse.statusCode, message: raw)
        }
    }

    // MARK: - Public API

    /// - timeoutOverride: если нужно увеличить таймаут для тяжёлых GET (например archive-events)
    func request<T: Decodable>(
        endpoint: String,
        method: String = "GET",
        body: Data? = nil,
        includeAuth: Bool = true,
        retryOnUnauthorized: Bool = true,
        timeoutOverride: TimeInterval? = nil
    ) async throws -> T {

        let timeout = timeoutOverride ?? 15
        let isGET = method.uppercased() == "GET"

        // ✅ 1 retry только для GET и только на сетевые "временные" ошибки (после простоя/смены сети)
        func shouldRetryNetwork(_ error: Error) -> Bool {
            guard isGET else { return false }
            let ns = error as NSError
            if ns.domain != NSURLErrorDomain { return false }
            // -1001 timedOut, -1005 connectionLost, -1009 notConnected, -1020 dataNotAllowed (иногда)
            return ns.code == NSURLErrorTimedOut
                || ns.code == NSURLErrorNetworkConnectionLost
                || ns.code == NSURLErrorNotConnectedToInternet
                || ns.code == NSURLErrorDataNotAllowed
        }

        do {
            return try await performRequest(
                endpoint: endpoint,
                method: method,
                body: body,
                includeAuth: includeAuth,
                timeout: timeout
            )
        } catch NetworkError.unauthorized {
            guard includeAuth, retryOnUnauthorized else { throw NetworkError.unauthorized }

            let refreshed = try await AuthService.shared.refreshAccessToken()
            guard refreshed else { throw NetworkError.unauthorized }

            return try await performRequest(
                endpoint: endpoint,
                method: method,
                body: body,
                includeAuth: includeAuth,
                timeout: timeout
            )
        } catch {
            if shouldRetryNetwork(error) {
                // небольшой backoff, чтобы "пробуждение" сети/сервера успело пройти
                try? await Task.sleep(nanoseconds: 350_000_000) // 350ms

                return try await performRequest(
                    endpoint: endpoint,
                    method: method,
                    body: body,
                    includeAuth: includeAuth,
                    timeout: timeout
                )
            }
            throw error
        }
    }
}
