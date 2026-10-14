
import Foundation
import CoreMotion
import Combine
import simd

final class MotionManager: ObservableObject {

    private let motionManager = CMMotionManager()

    // MARK: - Euler Angles

    @Published private(set) var roll: Double = 0
    @Published private(set) var pitch: Double = 0
    @Published private(set) var yaw: Double = 0

    // MARK: - 3D Orientation

    @Published private(set) var quaternion = simd_quatd(
        ix: 0,
        iy: 0,
        iz: 0,
        r: 1
    )

    @Published private(set) var rotationMatrix = matrix_identity_double3x3

    // MARK: - Sensor Status

    @Published private(set) var isAvailable = false
    @Published private(set) var isRunning = false

    // MARK: - Start

    func start() {
        let supported = CMMotionManager.availableAttitudeReferenceFrames()

        print(
            "True North supported:",
            supported.contains(.xTrueNorthZVertical)
        )
        guard motionManager.isDeviceMotionAvailable else {
            isAvailable = false
            isRunning = false
            return
        }

        isAvailable = true

        // 30 Hz
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0

        motionManager.startDeviceMotionUpdates(
            using: .xTrueNorthZVertical,
            to: .main
        ) { [weak self] motion, error in

            guard let self else { return }

            guard error == nil, let motion else {
                self.isRunning = false
                return
            }

            let attitude = motion.attitude

            // Euler angles (degrees)
            self.roll = attitude.roll * 180 / .pi
            self.pitch = attitude.pitch * 180 / .pi
            self.yaw = attitude.yaw * 180 / .pi

            // Quaternion
            let q = attitude.quaternion

            self.quaternion = simd_quatd(
                ix: q.x,
                iy: q.y,
                iz: q.z,
                r: q.w
            )

            // Rotation matrix
            let m = attitude.rotationMatrix

            self.rotationMatrix = simd_double3x3(
                SIMD3(m.m11, m.m12, m.m13),
                SIMD3(m.m21, m.m22, m.m23),
                SIMD3(m.m31, m.m32, m.m33)
            )

            self.isRunning = true
        }
    }

    // MARK: - Stop

    func stop() {
        motionManager.stopDeviceMotionUpdates()
        isRunning = false
    }
}
