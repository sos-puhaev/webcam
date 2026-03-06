import SwiftUI

struct PTZJoystick: View {
    let canUp: Bool
    let canDown: Bool
    let canLeft: Bool
    let canRight: Bool

    /// сколько градусов добавлять за один "такт" удержания (например 6°)
    let degreesPerTick: Int

    let onStart: (String) -> Void
    let onStop: (String) -> Void

    var body: some View {
        VStack(spacing: 10) {
            PTZDirectionButton(
                system: "chevron.up",
                action: "up",
                enabled: canUp,
                degreesPerTick: degreesPerTick,
                onStart: onStart,
                onStop: onStop
            )

            HStack(spacing: 10) {
                PTZDirectionButton(
                    system: "chevron.left",
                    action: "left",
                    enabled: canLeft,
                    degreesPerTick: degreesPerTick,
                    onStart: onStart,
                    onStop: onStop
                )

                Circle()
                    .fill(.thinMaterial)
                    .frame(width: 52, height: 52)
                    .overlay(Circle().strokeBorder(.white.opacity(0.15)))
                    .opacity((canUp || canDown || canLeft || canRight) ? 1 : 0.4)

                PTZDirectionButton(
                    system: "chevron.right",
                    action: "right",
                    enabled: canRight,
                    degreesPerTick: degreesPerTick,
                    onStart: onStart,
                    onStop: onStop
                )
            }

            PTZDirectionButton(
                system: "chevron.down",
                action: "down",
                enabled: canDown,
                degreesPerTick: degreesPerTick,
                onStart: onStart,
                onStop: onStop
            )
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.18))
        )
    }
}

struct PTZDirectionButton: View {
    let system: String
    let action: String
    let enabled: Bool

    /// сколько градусов прибавлять за тик удержания
    let degreesPerTick: Int

    let onStart: (String) -> Void
    let onStop: (String) -> Void

    @State private var pressed = false
    @State private var repeatTask: Task<Void, Never>?

    /// Растущий счётчик градусов при удержании
    @State private var accumulatedDegrees: Int = 0

    private let repeatEveryNs: UInt64 = 140_000_000 // частота "тика"

    var body: some View {
        Image(systemName: system)
            .font(.title3.weight(.semibold))
            .frame(width: 62, height: 46)
            .background(pressed ? .ultraThinMaterial : .thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.15)))
            .opacity(enabled ? 1 : 0.35)
            .allowsHitTesting(enabled)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            // ✅ пузырёк с растущими градусами
            .overlay(alignment: .topTrailing) {
                if pressed {
                    Text("~\(max(1, accumulatedDegrees))°")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.18)))
                        .offset(x: 12, y: -12)
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .animation(.easeOut(duration: 0.12), value: pressed)

            // ✅ выше приоритет чем ScrollView
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard enabled else { return }
                        if !pressed {
                            beginPress()
                        }
                    }
                    .onEnded { _ in
                        endPress()
                    }
            )
            .onDisappear {
                endPress()
            }
    }

    private func beginPress() {
        pressed = true
        accumulatedDegrees = 0

        // старт сразу + первый "тик"
        onStart(action)
        accumulatedDegrees += max(1, degreesPerTick)

        repeatTask?.cancel()
        repeatTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: repeatEveryNs)
                if Task.isCancelled { return }
                if !pressed { return }

                // каждый тик — продлеваем движение и наращиваем градусы
                onStart(action)
                accumulatedDegrees += max(1, degreesPerTick)
            }
        }
    }

    private func endPress() {
        guard pressed else {
            repeatTask?.cancel()
            repeatTask = nil
            return
        }

        // ✅ сначала отменяем повтор, потом стоп
        repeatTask?.cancel()
        repeatTask = nil

        pressed = false
        onStop(action)

        // можно сбрасывать сразу или оставить последнее значение на долю секунды
        accumulatedDegrees = 0
    }
}
