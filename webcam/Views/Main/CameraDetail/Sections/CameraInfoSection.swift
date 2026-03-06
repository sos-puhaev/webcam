import SwiftUI

struct CameraInfoSection: View {
    let camera: Camera
    @ObservedObject var streamVM: CameraStreamViewModel
    @ObservedObject var archiveVM: CameraArchiveViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(camera.name)
                .font(.title2)
                .bold()

            VStack(alignment: .leading, spacing: 8) {
                InfoRow(icon: "number", title: "ID камеры", value: "\(camera.id)")

                if let format = streamVM.format {
                    InfoRow(icon: "video", title: "Формат", value: format)
                } else if let format = camera.preview?.format {
                    InfoRow(icon: "video", title: "Формат", value: format)
                }

                InfoRow(icon: "checkmark.seal.fill", title: "Статус", value: "Камера активна")

                if let url = streamVM.streamURL {
                    InfoRow(icon: "link", title: "Stream URL", value: url.absoluteString)
                        .contextMenu {
                            Button("Копировать URL") { UIPasteboard.general.string = url.absoluteString }
                        }
                }

                if let af = archiveVM.availableFrom {
                    InfoRow(icon: "clock", title: "Архив доступен с", value: CameraTimeFormatter.archiveStart(af))
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }
}
