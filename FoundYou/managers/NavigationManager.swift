
import Foundation
import Combine
import CoreLocation
import simd

@MainActor
final class NavigationManager: ObservableObject {

    enum DirectionSource: String {
        case none
        case gps
        case uwb
    }

    @Published private(set) var distance: Double?
    @Published private(set) var bearing: Double?
    @Published private(set) var source: DirectionSource = .none

    @Published private(set) var uwbBearingCandidate: Double?
    @Published private(set) var uwbDirectionAvailable = false

    // Experimental mode for two-iPhone testing.
    // UWB orientation has NOT been verified yet.
    private let enableUWBDirection = true

    private let requiredSamples = 3
    private let smoothingTime: Double = 0.35

    private var smoothedBearing: Double?
    private var lastUpdate: Date?

    private var lastProcessedMeasurementID: UInt64?
    private var consecutiveUWBSamples = 0

    func update(
        myLocation: CLLocation?,
        friendLocation: CLLocation?,
        uwbDistance: Float?,
        uwbDirection: SIMD3<Float>?,
        uwbMeasurementID: UInt64,
        deviceQuaternion: simd_quatd?
    ) {
        let now = Date()

        // MARK: - GPS

        var gpsDistance: Double?
        var gpsBearing: Double?

        if let mine = myLocation,
           let friend = friendLocation,
           mine.horizontalAccuracy >= 0,
           friend.horizontalAccuracy >= 0,
           abs(mine.timestamp.timeIntervalSince(now)) < 15,
           abs(friend.timestamp.timeIntervalSince(now)) < 15 {

            gpsDistance = DirectionCalculator.distance(
                from: mine.coordinate,
                to: friend.coordinate
            )

            gpsBearing = DirectionCalculator.bearing(
                from: mine.coordinate,
                to: friend.coordinate
            )
        }

        // MARK: - UWB measurement validation

        var validUWBDistance: Double?

        if let uwbDistance,
           uwbDistance.isFinite,
           uwbDistance >= 0 {
            validUWBDistance = Double(uwbDistance)
        }

        if lastProcessedMeasurementID != uwbMeasurementID {
            lastProcessedMeasurementID = uwbMeasurementID

            if validUWBDistance != nil {
                consecutiveUWBSamples = min(
                    consecutiveUWBSamples + 1,
                    requiredSamples
                )
            } else {
                consecutiveUWBSamples = 0
            }
        }

        if validUWBDistance == nil {
            consecutiveUWBSamples = 0
        }

        let stableUWB =
            consecutiveUWBSamples >= requiredSamples &&
            validUWBDistance != nil

        distance = stableUWB
            ? validUWBDistance
            : gpsDistance

        // MARK: - Experimental UWB direction

        var candidate: Double?

        if let uwbDirection,
           let deviceQuaternion,
           uwbDirection.x.isFinite,
           uwbDirection.y.isFinite,
           uwbDirection.z.isFinite {

            let rawVector = SIMD3<Double>(
                Double(uwbDirection.x),
                Double(uwbDirection.y),
                Double(uwbDirection.z)
            )

            let magnitude = simd_length(rawVector)

            if magnitude > 0.001 {

                let normalized = rawVector / magnitude

                // Experimental transformation.
                // NearbyInteraction uses a device-relative
                // vector, while CoreMotion provides a
                // device attitude quaternion.
                //
                // The precise frame mapping still needs
                // physical verification.

                let worldVector = deviceQuaternion.act(
                    normalized
                )

                let horizontalMagnitude = hypot(
                    worldVector.x,
                    worldVector.y
                )

                if horizontalMagnitude > 0.05 {
                    let radians = atan2(
                        worldVector.x,
                        worldVector.y
                    )

                    candidate = normalize(
                        radians * 180 / .pi
                    )
                }
            }
        }

        uwbBearingCandidate = candidate
        uwbDirectionAvailable = candidate != nil

        // MARK: - Source selection

        let targetBearing: Double?
        let selectedSource: DirectionSource

        if enableUWBDirection,
           stableUWB,
           let candidate {

            targetBearing = candidate
            selectedSource = .uwb

        } else if let gpsBearing {

            targetBearing = gpsBearing
            selectedSource = .gps

        } else {
            targetBearing = nil
            selectedSource = .none
        }

        source = selectedSource

        // MARK: - Smooth direction changes

        guard let targetBearing else {
            bearing = nil
            smoothedBearing = nil
            lastUpdate = nil
            return
        }

        let normalizedTarget = normalize(targetBearing)

        guard let previous = smoothedBearing else {
            smoothedBearing = normalizedTarget
            bearing = normalizedTarget
            lastUpdate = now
            return
        }

        let elapsed = min(
            max(
                now.timeIntervalSince(lastUpdate ?? now),
                0
            ),
            1
        )

        let alpha = 1 - exp(
            -elapsed / smoothingTime
        )

        let delta = shortestAngle(
            from: previous,
            to: normalizedTarget
        )

        let next = normalize(
            previous + delta * alpha
        )

        smoothedBearing = next
        bearing = next
        lastUpdate = now
    }

    func reset() {
        distance = nil
        bearing = nil
        source = .none

        uwbBearingCandidate = nil
        uwbDirectionAvailable = false

        smoothedBearing = nil
        lastUpdate = nil

        lastProcessedMeasurementID = nil
        consecutiveUWBSamples = 0
    }

    private func normalize(_ angle: Double) -> Double {
        let result = angle.truncatingRemainder(
            dividingBy: 360
        )

        return result < 0 ? result + 360 : result
    }

    private func shortestAngle(
        from current: Double,
        to target: Double
    ) -> Double {
        let difference = (
            target - current + 540
        ).truncatingRemainder(dividingBy: 360)

        return difference - 180
    }
}
