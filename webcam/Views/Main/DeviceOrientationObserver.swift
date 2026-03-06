import SwiftUI
import Combine
import UIKit

final class DeviceOrientationObserver: ObservableObject {
    @Published var isLandscape: Bool = false
    private var cancellable: AnyCancellable?

    init() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()

        cancellable = NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { _ in
                let o = UIDevice.current.orientation
                guard o == .portrait || o == .portraitUpsideDown || o == .landscapeLeft || o == .landscapeRight else { return }
                self.isLandscape = o.isLandscape
            }
    }

    deinit {
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
        cancellable?.cancel()
    }
}
