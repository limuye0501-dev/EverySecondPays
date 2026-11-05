import CoreMotion
import SwiftUI

/// Low-rate device tilt for the glass specular highlight. 15 Hz, low-pass filtered, stopped when not visible.
@MainActor
final class TiltManager: ObservableObject {
    static let shared = TiltManager()
    @Published var tilt: CGSize = .zero          // -1…1 each axis
    private let mm = CMMotionManager()
    private var users = 0

    func start() {
        users += 1
        guard users == 1, mm.isDeviceMotionAvailable else { return }
        mm.deviceMotionUpdateInterval = 1.0 / 15
        mm.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let self, let g = m?.gravity else { return }
            let t = CGSize(width: max(-1, min(1, g.x * 1.6)), height: max(-1, min(1, (g.y + 0.6) * 1.6)))
            let k = 0.15
            let n = CGSize(width: tilt.width + (t.width - tilt.width) * k, height: tilt.height + (t.height - tilt.height) * k)
            if abs(n.width - tilt.width) + abs(n.height - tilt.height) > 0.004 { tilt = n }
        }
    }
    func stop() {
        users = max(0, users - 1)
        if users == 0 { mm.stopDeviceMotionUpdates(); tilt = .zero }
    }
}
