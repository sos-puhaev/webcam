import SwiftUI

struct CameraLiveOnlySection: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("LIVE")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.12))
                    .clipShape(Capsule())

                Spacer()
            }

            HStack(spacing: 10) {
                Image(systemName: "externaldrive.badge.xmark")
                    .foregroundColor(.orange)

                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()
            }
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
    }
}
