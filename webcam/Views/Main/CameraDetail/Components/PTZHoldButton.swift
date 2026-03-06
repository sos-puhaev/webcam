import SwiftUI

struct PTZHoldButton: View {
    let title: String
    let subtitle: String
    let onStart: () -> Void
    let onEnd: () -> Void

    @State private var pressed = false

    var body: some View {
        VStack(spacing: 4) {
            Text(title).font(.title2).bold()
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        .frame(width: 78, height: 62)
        .background(pressed ? .ultraThinMaterial : .thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.18))
        )
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !pressed {
                        pressed = true
                        onStart()
                    }
                }
                .onEnded { _ in
                    pressed = false
                    onEnd()
                }
        )
    }
}
