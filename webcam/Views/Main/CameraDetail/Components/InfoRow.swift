import SwiftUI

struct InfoRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundColor(.blue)

            Text(title)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.body.monospaced())
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}
