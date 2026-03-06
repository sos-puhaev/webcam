import SwiftUI
import UIKit
import AudioToolbox

struct TimelineScrubber: View {

    // MARK: - Label mode (stable with hysteresis)
    private enum LabelMode { case none, compact, full }

    // MARK: - Marker model

    /// Маркер события на шкале (например движение).
    /// value — позиция на шкале в секундах (0...maxValue) в той же системе, что и `value`.
    /// duration — длительность события в секундах (0 = точка/вертикальная линия).
    struct TimelineMarker: Identifiable, Hashable {
        enum Kind: Hashable {
            case motion
            case generic
            case custom(Color)
        }

        let id: String
        let value: Double
        let duration: Double
        let kind: Kind

        init(id: String, value: Double, duration: Double = 0, kind: Kind = .motion) {
            self.id = id
            self.value = value
            self.duration = duration
            self.kind = kind
        }

        var color: Color {
            switch kind {
            case .motion: return .green
            case .generic: return .blue
            case .custom(let c): return c
            }
        }
    }

    // MARK: - Inputs

    let maxValue: Double
    @Binding var value: Double
    @Binding var isScrubbing: Bool

    /// Полная подпись (может включать дату)
    let labelForValue: (Double) -> String

    /// Компактная подпись (обычно только время). Если nil — будет использоваться labelForValue.
    var compactLabelForValue: ((Double) -> String)? = nil

    /// Если true — шаги major/minor будут выбираться автоматически по текущему зуму.
    var adaptiveTicks: Bool = true

    /// Если adaptiveTicks=false, то используются эти значения
    let majorTickEvery: Double
    let minorTickEvery: Double

    let onScrubEnded: () -> Void

    var snapEvery: Double = 10
    var enableClicks: Bool = true

    /// Маркеры событий (например движение)
    var markers: [TimelineMarker] = []

    // MARK: - Drawing constants

    // База: 120px на 1 час = 120/3600 px на 1 секунду
    private let basePixelsPerSecond: CGFloat = 120 / 3600

    // Гистерезис для подписей (чтобы не "дребезжало" и не пропадали надписи возле порога)
    // none <-> compact
    private let compactOn: CGFloat  = 62   // none -> compact
    private let compactOff: CGFloat = 50   // compact -> none

    // compact <-> full
    private let fullOn: CGFloat  = 110     // compact -> full
    private let fullOff: CGFloat = 90      // full -> compact

    // Масштаб (pinch-zoom)
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var isPinching: Bool = false

    private var pixelsPerSecond: CGFloat { basePixelsPerSecond * scale }

    private let hitHeight: CGFloat = 110

    @State private var dragStartValue: Double? = nil
    @State private var lastSnapIndex: Int? = nil
    @State private var lastClickTs: CFTimeInterval = 0
    @State private var feedback = UISelectionFeedbackGenerator()
    
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let centerX = width / 2

            ZStack {
                Color.clear
                    .frame(height: hitHeight)
                    .contentShape(Rectangle())

                // Игла по центру
                Needle()
                    .position(x: centerX, y: hitHeight / 2)
                    .zIndex(100)

                // Шкала
                timeline(width: width)

                // Центральная линия под иглой (ориентир)
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 1, height: hitHeight - 30)
                    .position(x: centerX, y: hitHeight / 2)
            }
            .frame(height: hitHeight)
            .onAppear {
                feedback.prepare()
                let safeValue = clamp(value, 0, maxValue)
                lastSnapIndex = snapIndex(for: safeValue)
            }
            // DRAG: перемотка
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        // ✅ если сейчас pinch — не запускаем scrubbing и не трогаем value
                        guard !isPinching else { return }

                        if dragStartValue == nil {
                            dragStartValue = value
                            isScrubbing = true
                            feedback.prepare()
                            lastSnapIndex = snapIndex(for: value)
                        }

                        let dx = g.translation.width
                        let deltaSeconds = Double(dx / pixelsPerSecond)
                        let start = dragStartValue ?? clamp(value, 0, maxValue)
                        let newValue = clamp(start - deltaSeconds, 0, maxValue)

                        if abs(newValue - value) > 0.01 {
                            value = newValue
                            handleClickIfNeeded(for: newValue)
                        }
                    }
                    .onEnded { _ in
                        dragStartValue = nil
                        isScrubbing = false

                        let snapped = snap(value: value)
                        if abs(snapped - value) > 0.0001 {
                            withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.9)) {
                                value = snapped
                            }
                        }

                        onScrubEnded()
                    }
            )
            // PINCH: зум шкалы
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { magnification in
                        isPinching = true
                        scale = clampScale(lastScale * magnification)
                    }
                    .onEnded { _ in
                        lastScale = scale
                        isPinching = false

                        // ✅ на всякий: если drag “подхватился”, выключаем scrubbing
                        dragStartValue = nil
                        isScrubbing = false
                    }
            )
        }
        .frame(height: hitHeight)
    }

    // MARK: - Timeline

    private func timeline(width: CGFloat) -> some View {
        let safeValue = clamp(value, 0, maxValue)
        let offsetX = -CGFloat(safeValue) * pixelsPerSecond

        let visibleSeconds = secondsVisibleOnScreen(width: width)
        let startValue = max(0, safeValue - visibleSeconds / 2)
        let endValue = min(maxValue, safeValue + visibleSeconds / 2)

        // Выбор шагов по зуму
        let majorStep = adaptiveTicks ? chooseMajorStep(visibleSeconds: visibleSeconds) : majorTickEvery
        let minorStep = adaptiveTicks ? chooseMinorStep(majorStep: majorStep) : minorTickEvery

        // Обновляем режим подписей стабильно (с гистерезисом)
        let majorSpacingPx = CGFloat(majorStep) * pixelsPerSecond
        let labelMode = labelMode(for: majorSpacingPx)

        // MARKERS — отрисуем ДО тиков, но так, чтобы не мешали подписи
        let markerLayer = markersLayer(
            from: startValue,
            to: endValue,
            offsetX: offsetX
        )

        return ZStack {
            // Маркеры
            markerLayer

            // Minor ticks
            ticksLayer(
                from: startValue,
                to: endValue,
                step: minorStep,
                height: 8,
                opacity: 0.25,
                labelMode: .none,
                offsetX: offsetX
            )

            // Major ticks (+ labels)
            ticksLayer(
                from: startValue,
                to: endValue,
                step: majorStep,
                height: 12,
                opacity: 0.7,
                labelMode: labelMode,
                offsetX: offsetX
            )

            // LIVE метка (в конце)
            VStack(spacing: 3) {
                Rectangle()
                    .fill(Color.green)
                    .frame(width: 2, height: 16)

                Text("LIVE")
                    .font(.caption2)
                    .foregroundColor(.green)
                    .bold()
            }
            .offset(x: offsetX + CGFloat(maxValue) * pixelsPerSecond, y: 6)

            // START метка (0)
            VStack(spacing: 3) {
                Rectangle()
                    .fill(Color.gray.opacity(0.7))
                    .frame(width: 2, height: 16)

                Text(compactLabel(for: 0))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .offset(x: offsetX, y: 6)
        }
    }
    
    private func labelMode(for majorSpacingPx: CGFloat) -> LabelMode {
        if majorSpacingPx >= fullOn { return .full }
        if majorSpacingPx >= compactOn { return .compact }
        return .none
    }
    
    // MARK: - Markers layer

    private func markersLayer(from startValue: Double, to endValue: Double, offsetX: CGFloat) -> some View {
        // Чтобы маркеры выглядели "как в плеере":
        // рисуем на отдельной высоте, ниже подписей, но выше низа.
        let y: CGFloat = 34

        // фильтруем по видимому диапазону (+ небольшой запас)
        let pad = max(5, Double(20 / max(pixelsPerSecond, 0.0001))) // ~20px в секундах
        let vMin = max(0, startValue - pad)
        let vMax = min(maxValue, endValue + pad)

        let visible = markers.filter { m in
            let start = m.value
            let end = m.value + max(0, m.duration)
            return end >= vMin && start <= vMax
        }

        // ✅ лимит, чтобы не рисовать тысячи маркеров при большом архиве
        let limited = visible.prefix(250)

        return ZStack {
            ForEach(Array(limited)) { m in
                markerView(m, offsetX: offsetX, y: y)
            }
        }
        .allowsHitTesting(false)
    }

    private func markerView(_ m: TimelineMarker, offsetX: CGFloat, y: CGFloat) -> some View {
        let x = offsetX + CGFloat(m.value) * pixelsPerSecond

        // Минимальная видимая ширина
        let rawWidth = CGFloat(max(0, m.duration)) * pixelsPerSecond
        let width = max(rawWidth, m.duration > 0 ? 6 : 2)

        // Высота маркера
        let height: CGFloat = 6

        // Вертикальный маркер (duration == 0) — тонкая линия
        if m.duration <= 0.0001 {
            return AnyView(
                Rectangle()
                    .fill(m.color.opacity(0.95))
                    .frame(width: 2, height: 14)
                    .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 1)
                    .offset(x: x, y: y)
            )
        }

        // Диапазонный маркер — капсула
        return AnyView(
            Capsule(style: .continuous)
                .fill(m.color.opacity(0.85))
                .frame(width: width, height: height)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
                .offset(x: x + width / 2, y: y) // сдвиг на половину ширины, чтобы value была началом
        )
    }

    // MARK: - Ticks

    private func ticksLayer(
        from: Double,
        to: Double,
        step: Double,
        height: CGFloat,
        opacity: Double,
        labelMode: LabelMode,
        offsetX: CGFloat
    ) -> some View {
        let ticks = tickValues(from: from, to: to, step: step)

        return ForEach(ticks, id: \.self) { tickValue in
            if tickValue == 0 || tickValue == maxValue {
                EmptyView()
            } else {
                VStack(spacing: 3) {
                    Rectangle()
                        .fill(Color.primary.opacity(opacity))
                        .frame(width: 1, height: height)

                    switch labelMode {
                    case .none:
                        EmptyView()

                    case .compact, .full:
                        Text(compactLabel(for: tickValue))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fixedSize()
                    }
                }
                .offset(
                    x: offsetX + CGFloat(tickValue) * pixelsPerSecond,
                    y: (labelMode == .none) ? 18 : 6
                )
            }
        }
    }

    private func compactLabel(for v: Double) -> String {
        if let compact = compactLabelForValue { return compact(v) }
        return labelForValue(v)
    }

    private func tickValues(from: Double, to: Double, step: Double) -> [Double] {
        guard step > 0 else { return [] }
        if from >= to { return [] }

        let start = ceil(from / step) * step
        let end = floor(to / step) * step

        var arr: [Double] = []
        var v = start
        while v <= end + 0.0001 {
            arr.append(v)
            v += step
            if arr.count > 160 { break } // лимит для производительности
        }
        return arr
    }

    private func secondsVisibleOnScreen(width: CGFloat) -> Double {
        Double(width / pixelsPerSecond)
    }

    // MARK: - Adaptive steps

    /// Хотим, чтобы major-тиков на экране было примерно 6–10
    private func chooseMajorStep(visibleSeconds: Double) -> Double {
        let target = visibleSeconds / 8.0

        let steps: [Double] = [
            5, 10, 15, 30,
            60, 120, 300, 600, 900,
            1800, 3600, 7200,
            14400, 21600, 43200,
            86400
        ]

        for s in steps where s >= target { return s }
        return steps.last ?? 3600
    }

    private func chooseMinorStep(majorStep: Double) -> Double {
        if majorStep <= 30 { return 5 }
        if majorStep <= 60 { return 10 }
        if majorStep <= 300 { return majorStep / 5 }
        if majorStep <= 3600 { return majorStep / 6 }
        return majorStep / 4
    }

    // MARK: - Snap / Click / Haptic

    private func snapIndex(for v: Double) -> Int {
        Int((v / snapEvery).rounded())
    }

    private func snap(value v: Double) -> Double {
        guard snapEvery > 0 else { return clamp(v, 0, maxValue) }
        return clamp((v / snapEvery).rounded() * snapEvery, 0, maxValue)
    }

    private func handleClickIfNeeded(for v: Double) {
        guard enableClicks, snapEvery > 0 else { return }

        let idx = snapIndex(for: v)
        if lastSnapIndex == nil { lastSnapIndex = idx; return }
        guard idx != lastSnapIndex else { return }
        lastSnapIndex = idx

        let now = CACurrentMediaTime()
        if now - lastClickTs < 0.03 { return }
        lastClickTs = now

        feedback.selectionChanged()
        feedback.prepare()
        AudioServicesPlaySystemSound(1104)
    }

    // MARK: - Helpers

    private func clamp(_ v: Double, _ a: Double, _ b: Double) -> Double {
        min(Swift.max(v, a), b)
    }

    private func clampScale(_ s: CGFloat) -> CGFloat {
        // меньше -> больше времени на экране
        // больше -> точнее
        min(max(s, 0.25), 7.0)
    }
}

// MARK: - Needle

private struct Needle: View {
    var body: some View {
        VStack(spacing: 0) {
            TrianglePointer()
                .fill(Color.white)
                .frame(width: 18, height: 10)
                .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)

            Rectangle()
                .fill(Color.white)
                .frame(width: 2, height: 40)
                .shadow(color: .black.opacity(0.6), radius: 1.5)

            Circle()
                .fill(Color.white)
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(Color.black.opacity(0.3), lineWidth: 1))
                .shadow(color: .black.opacity(0.6), radius: 1)

            Rectangle()
                .fill(Color.white)
                .frame(width: 2, height: 30)
                .shadow(color: .black.opacity(0.6), radius: 1.5)
        }
        .zIndex(100)
        .allowsHitTesting(false)
    }
}

private struct TrianglePointer: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
