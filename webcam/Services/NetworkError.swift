import Foundation

enum NetworkError: Error, LocalizedError {
    case invalidURL
    case noData
    case decodingError(underlying: Error? = nil, raw: String? = nil)
    case serverError(statusCode: Int, message: String)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Неверный URL"
        case .noData:
            return "Пустой ответ сервера"
        case .decodingError(let underlying, let raw):
            var s = "Ошибка декодирования ответа"
            if let underlying { s += ": \(underlying.localizedDescription)" }
            if let raw, !raw.isEmpty { s += " | Raw: \(raw.prefix(200))" }
            return s
        case .serverError(let statusCode, let message):
            let msg = message.isEmpty ? "Unknown error" : message
            return "Ошибка сервера \(statusCode): \(msg)"
        case .unauthorized:
            return "Не авторизован (401)"
        }
    }
}
