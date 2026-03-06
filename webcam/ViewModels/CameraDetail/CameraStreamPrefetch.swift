import Foundation

/// Быстрый prefetch live stream URL по cameraId.
/// Работает без UI, только сеть + кэш.
@MainActor
final class CameraStreamPrefetch {
    static let shared = CameraStreamPrefetch()

    private let api = APIService.shared
    private var tasks: [Int: Task<URL?, Never>] = [:]
    private var cache: [Int: URL] = [:]

    private init() {}

    /// Запустить prefetch live URL (если уже запущено — не дублируем).
    func prefetchLive(cameraId: Int) {
        if cache[cameraId] != nil { return }
        if tasks[cameraId] != nil { return }

        tasks[cameraId] = Task { [weak self] in
            guard let self else { return nil }
            defer { self.tasks[cameraId] = nil }

            let req = CameraStreamRequest(mode: "live", platform: "ios", from: nil, tz: nil, speed: nil)

            do {
                let body = try JSONEncoder().encode(req)

                let resp: CameraStreamResponse = try await api.request(
                    endpoint: Constants.API.Camera.stream(cameraID: cameraId),
                    method: "POST",
                    body: body
                )

                guard let s = resp.url, let url = URL(string: s) else { return nil }
                self.cache[cameraId] = url
                return url
            } catch {
                return nil
            }
        }
    }

    /// Забрать prefetched URL (и удалить из кэша).
    func takeLive(cameraId: Int) -> URL? {
        defer { cache[cameraId] = nil }
        return cache[cameraId]
    }

    /// Если нужно — можно отменить prefetch (не обязательно).
    func cancel(cameraId: Int) {
        tasks[cameraId]?.cancel()
        tasks[cameraId] = nil
        cache[cameraId] = nil
    }
}
