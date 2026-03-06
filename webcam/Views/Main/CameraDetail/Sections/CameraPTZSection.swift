import SwiftUI

struct CameraPTZSection: View {
    @ObservedObject var vm: CameraPTZViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Управление камерой").font(.headline)
                Spacer()
            }

            HStack(spacing: 16) {
                PTZJoystick(
                    canUp: vm.canUp,
                    canDown: vm.canDown,
                    canLeft: vm.canLeft,
                    canRight: vm.canRight,
                    degreesPerTick: vm.estimatedDegrees(),   // ← “сколько градусов за импульс”
                    onStart: { action in vm.startMove(action) },
                    onStop: { action in vm.stopMove(for: action) }
                )

                VStack(spacing: 12) {
                    if vm.canZoomIn {
                        PTZHoldButton(title: "＋", subtitle: "Zoom") {
                            vm.startMove("zoom_in", velocity: 0.6)
                        } onEnd: {
                            vm.stopMove(for: "zoom_in")
                        }
                    }

                    if vm.canZoomOut {
                        PTZHoldButton(title: "－", subtitle: "Zoom") {
                            vm.startMove("zoom_out", velocity: 0.6)
                        } onEnd: {
                            vm.stopMove(for: "zoom_out")
                        }
                    }

                    if !vm.hasZoom {
                        Text("Зум недоступен")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
        .onDisappear {
            // чтобы камера не "ехала" если ушли со страницы удерживая кнопку
            vm.stopActiveIfNeeded()
        }
    }
}
