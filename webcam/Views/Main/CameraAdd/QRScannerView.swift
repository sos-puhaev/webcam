import SwiftUI
import UIKit
import AVFoundation

struct QRScannerView: UIViewControllerRepresentable {

    var completion: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = .black

        let session = AVCaptureSession()
        session.sessionPreset = .high

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return controller
        }

        let output = AVCaptureMetadataOutput()
        output.setMetadataObjectsDelegate(context.coordinator, queue: .main)

        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(output) { session.addOutput(output) }

        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = UIScreen.main.bounds

        controller.view.layer.addSublayer(preview)

        context.coordinator.session = session

        // ⚠️ ВАЖНО: запуск НЕ в main thread
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }

        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let completion: (String) -> Void
        var session: AVCaptureSession?

        init(completion: @escaping (String) -> Void) {
            self.completion = completion
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput metadataObjects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {

            guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let value = object.stringValue else { return }

            // ⛔ остановка сессии
            session?.stopRunning()

            // ✅ возврат в main thread
            DispatchQueue.main.async {
                self.completion(value)
            }
        }
    }
}
