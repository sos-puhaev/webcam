import Foundation
import Combine

@MainActor
final class CameraPTZViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var isAvailable = false
    @Published var available: PTZCapabilitiesResponse? = nil

    private var cameraID: Int?

    // MARK: - Tunables (под UI и подсказки)

    /// Скорость для PTZ (0...1). Обычно 0.25–0.45 для "шагового" управления.
    let defaultPTZVelocity: Double = 0.25

    /// Скорость для zoom (обычно можно выше, чем PTZ)
    let defaultZoomVelocity: Double = 0.6

    /// Длина импульса. Чем меньше — тем меньше шаг.
    let pulseDurationNs: UInt64 = 120_000_000 // 160ms (можешь 120–220ms)

    /// Калибровка: сколько градусов/сек при velocity=1.0
    /// Это приблизительно и зависит от конкретной камеры.
    /// Подбирай опытно.
    let degPerSecAtV1: Double = 120.0

    /// Примерная оценка "на сколько градусов повернётся" за один импульс.
    /// Возвращаем Int градусов (минимум 1).
    func estimatedDegrees(velocity: Double? = nil) -> Int {
        let v = max(0, min(1, velocity ?? defaultPTZVelocity))
        let seconds = Double(pulseDurationNs) / 1_000_000_000.0
        let deg = degPerSecAtV1 * v * seconds
        return max(1, Int(deg.rounded()))
    }

    // MARK: - UI flags (derived from available_actions keys)

    var canUp: Bool { available?.ptzKeys.contains("up") == true }
    var canDown: Bool { available?.ptzKeys.contains("down") == true }
    var canLeft: Bool { available?.ptzKeys.contains("left") == true }
    var canRight: Bool { available?.ptzKeys.contains("right") == true }

    var canZoomIn: Bool { available?.zoomKeys.contains("zoomIn") == true }
    var canZoomOut: Bool { available?.zoomKeys.contains("zoomOut") == true }
    var hasZoom: Bool { canZoomIn || canZoomOut }

    // MARK: - Internals: anti-spam + auto-stop

    private var activeAction: String? = nil
    private var lastSendAt: Date = .distantPast
    private let minInterval: TimeInterval = 0.25

    private var autoStopTask: Task<Void, Never>?

    // MARK: - Lifecycle

    func setCamera(id: Int) {
        cameraID = id
    }

    func loadCapabilities() async {
        guard let cameraID else { return }
        isLoading = true

        do {
            let caps = try await PTZService.shared.getCapabilities(cameraID: cameraID)
            available = caps
            isAvailable = caps.hasAnyControl
        } catch {
            available = nil
            isAvailable = false
        }

        isLoading = false
    }

    // MARK: - Commands

    /// Универсальный старт. Для PTZ используй defaultPTZVelocity, для zoom — defaultZoomVelocity.
    func startMove(_ action: String, velocity: Double? = nil) {
        guard let cameraID else { return }

        // Базовая защита: если UI вызвал недоступное направление — не шлём.
        if !isActionAllowed(action) { return }

        // помечаем активное действие
        activeAction = action

        // ✅ гарантированный stop, даже если UI не вызвал onEnded
        autoStopTask?.cancel()
        autoStopTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: pulseDurationNs)
            if Task.isCancelled { return }
            if self.activeAction == action {
                self.stopMove(for: action)
            }
        }

        // антиспам только для START-запросов (stop всегда можно слать)
        let now = Date()
        if now.timeIntervalSince(lastSendAt) < minInterval { return }
        lastSendAt = now

        let v = velocity ?? defaultVelocity(for: action)

        Task {
            _ = try? await PTZService.shared.sendAction(
                cameraID: cameraID,
                action: action,
                velocity: v,
                checkCapabilities: true,
                timeout: 6
            )
        }
    }

    func stopMove(for action: String) {
        autoStopTask?.cancel()

        guard let cameraID else { return }
        if activeAction == action { activeAction = nil }

        let stopAction = action + "_stop"

        Task {
            // 1) первый stop сразу
            _ = try? await PTZService.shared.sendAction(
                cameraID: cameraID,
                action: stopAction,
                velocity: nil,
                checkCapabilities: false,
                timeout: 4
            )

            // 2) второй stop через 120ms (дожим)
            try? await Task.sleep(nanoseconds: 120_000_000)

            _ = try? await PTZService.shared.sendAction(
                cameraID: cameraID,
                action: stopAction,
                velocity: nil,
                checkCapabilities: false,
                timeout: 4
            )
        }
    }

    func stopActiveIfNeeded() {
        guard let a = activeAction else { return }
        stopMove(for: a)
    }

    // MARK: - Helpers

    private func defaultVelocity(for action: String) -> Double {
        switch action {
        case "zoom_in", "zoom_out":
            return defaultZoomVelocity
        default:
            return defaultPTZVelocity
        }
    }

    /// Проверяем доступность по keys из GET.
    /// Это защищает от ошибок UI и от ситуаций, когда capabilities изменились.
    private func isActionAllowed(_ action: String) -> Bool {
        // PTZ
        if action == "up" { return canUp }
        if action == "down" { return canDown }
        if action == "left" { return canLeft }
        if action == "right" { return canRight }

        // Zoom (в GET keys: zoomIn/zoomOut, в POST actions: zoom_in/zoom_out)
        if action == "zoom_in" { return canZoomIn }
        if action == "zoom_out" { return canZoomOut }

        // stop-команды сюда не должны попадать напрямую через startMove
        return true
    }
}
