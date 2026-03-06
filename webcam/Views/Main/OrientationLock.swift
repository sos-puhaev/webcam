import UIKit

final class OrientationLock {
    static var mask: UIInterfaceOrientationMask = .portrait

    static func lock(_ mask: UIInterfaceOrientationMask) {
        self.mask = mask
        UIViewController.attemptRotationToDeviceOrientation()
    }

    static func lockAndRotate(_ mask: UIInterfaceOrientationMask, to orientation: UIInterfaceOrientation) {
        self.mask = mask
        UIDevice.current.setValue(orientation.rawValue, forKey: "orientation")
        UIViewController.attemptRotationToDeviceOrientation()
    }
}
