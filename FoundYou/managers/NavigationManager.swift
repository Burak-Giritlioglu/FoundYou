
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

    // MARK: - Published State

    @Published private(set) var distance: Double?
    @Published private(set) var bearing: Double?
    @Published private(set) var source: DirectionSource = .none

    // Direct device-relative UWB direction for the 3D arrow.
    @Published private(set) var uwbArrowDirection: SIMD3<Float>?

    // Existing diagnostic properties.
    @Published private(set) var uwbBearingCandidate: Double?
    @Published private(set) var uwbDirectionAvailable = false

    @Published private(set) var isUWBPreferred = false
    @Published private(set) var isMeasurementStale = false

    // MARK: - Friend GPS Freshness

    // The friend's timestamp is informational only.
    // An old timestamp never invalidates the location.

    @Published private(set) var friendLocationUpdatedAt: Date?
    @Published private(set) var isFriendLocationLastKnown = false

    // A UI indicator threshold, not a GPS expiry.
    private let friendFreshnessThreshold: TimeInterval = 90

    // MARK: - Configuration

    private let uwbGracePeriod: TimeInterval = 5
    private let uwbFreshnessInterval: TimeInterval = 2

    // Only the local GPS measurement requires freshness.
    private let gpsMaximumAge: TimeInterval = 90

    private let smoothingTime = 0.35

    // MARK: - UWB State

    private var lastUWBAt: Date?
    private var lastUWBDistance: Double?
    private var lastUWBDirection: SIMD3<Float>?

    private var lastProcessedMeasurementID: UInt64?

    // MARK: - GPS State

    private var lastKnownGPSBearing: Double?
    private var lastKnownDistance: Double?

    // MARK: - Smoothing

    private var smoothedBearing: Double?
    private var lastUpdate: Date?

    // MARK: - Update

    func update(
        myLocation: CLLocation?,
        friendLocation: CLLocation?,
        uwbDistance: Float?,
        uwbDirection: SIMD3<Float>?,
        uwbMeasurementID: UInt64,
        deviceQuaternion: simd_quatd?
    ) {

        let now = Date()

        // MARK: - Friend GPS Freshness

        if let friend = friendLocation {

            friendLocationUpdatedAt = friend.timestamp

            let age = max(
                now.timeIntervalSince(friend.timestamp),
                0
            )

            isFriendLocationLastKnown =
                age >= friendFreshnessThreshold

        } else {

            friendLocationUpdatedAt = nil
            isFriendLocationLastKnown = false
        }

        // MARK: - GPS Calculation

        var gpsDistance: Double?
        var gpsBearing: Double?

        // Keep using the friend's last known GPS location.
        // Only our own GPS measurement requires freshness.

        if let mine = myLocation,
           let friend = friendLocation,
           mine.horizontalAccuracy >= 0,
           friend.horizontalAccuracy >= 0,
           abs(mine.timestamp.timeIntervalSince(now)) < gpsMaximumAge {

            gpsDistance = DirectionCalculator.distance(
                from: mine.coordinate,
                to: friend.coordinate
            )

            gpsBearing = DirectionCalculator.bearing(
                from: mine.coordinate,
                to: friend.coordinate
            )
        }

        // MARK: - GPS Bearing Smoothing

        if let gpsBearing {

            let normalizedTarget = normalize(gpsBearing)

            if let previous = smoothedBearing {

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

                smoothedBearing = normalize(
                    previous + delta * alpha
                )

            } else {

                smoothedBearing = normalizedTarget
            }

            lastUpdate = now
            lastKnownGPSBearing = smoothedBearing
        }

        bearing = gpsBearing != nil
            ? smoothedBearing
            : lastKnownGPSBearing

        // MARK: - UWB Measurement

        let isNewMeasurement =
            lastProcessedMeasurementID != uwbMeasurementID

        if isNewMeasurement {

            lastProcessedMeasurementID = uwbMeasurementID

            if let uwbDistance,
               uwbDistance.isFinite,
               uwbDistance >= 0 {

                lastUWBDistance = Double(uwbDistance)
                lastUWBAt = now

                if let uwbDirection,
                   uwbDirection.x.isFinite,
                   uwbDirection.y.isFinite,
                   uwbDirection.z.isFinite {

                    let magnitude = simd_length(uwbDirection)

                    if magnitude > 0.001 {
                        lastUWBDirection =
                            uwbDirection / magnitude
                    } else {
                        lastUWBDirection = nil
                    }

                } else {
                    lastUWBDirection = nil
                }
            }
        }

        // MARK: - UWB Availability

        let uwbAge: TimeInterval

        if let lastUWBAt {
            uwbAge = max(
                now.timeIntervalSince(lastUWBAt),
                0
            )
        } else {
            uwbAge = .infinity
        }

        let useUWB =
            lastUWBDistance != nil &&
            uwbAge < uwbGracePeriod

        isUWBPreferred = useUWB

        // MARK: - Distance Selection

        if useUWB, let lastUWBDistance {

            distance = lastUWBDistance
            source = .uwb

            isMeasurementStale =
                uwbAge >= uwbFreshnessInterval

        } else if let gpsDistance {

            distance = gpsDistance
            source = .gps

            // The coordinate remains usable even when
            // the friend's last update is old.
            isMeasurementStale =
                isFriendLocationLastKnown

        } else {

            distance = lastKnownDistance
            source = .none

            isMeasurementStale = true
        }

        if let distance {
            lastKnownDistance = distance
        }

        // MARK: - Direct UWB Arrow Direction

        if useUWB,
           let lastUWBDirection {

            uwbArrowDirection = lastUWBDirection

        } else {
            uwbArrowDirection = nil
        }

        uwbDirectionAvailable =
            uwbArrowDirection != nil

        if let direction = uwbArrowDirection {

            uwbBearingCandidate = normalize(
                atan2(
                    Double(direction.x),
                    Double(direction.y)
                ) * 180 / .pi
            )

        } else {
            uwbBearingCandidate = nil
        }

        if uwbArrowDirection == nil &&
           gpsBearing == nil {

            isMeasurementStale = true
        }

        _ = deviceQuaternion
    }

    // MARK: - Reset

    func reset() {

        distance = nil
        bearing = nil
        source = .none

        uwbArrowDirection = nil
        uwbBearingCandidate = nil
        uwbDirectionAvailable = false

        isUWBPreferred = false
        isMeasurementStale = false

        friendLocationUpdatedAt = nil
        isFriendLocationLastKnown = false

        lastUWBAt = nil
        lastUWBDistance = nil
        lastUWBDirection = nil

        lastProcessedMeasurementID = nil

        lastKnownGPSBearing = nil
        lastKnownDistance = nil

        smoothedBearing = nil
        lastUpdate = nil
    }

    // MARK: - Angle Helpers

    private func normalize(_ angle: Double) -> Double {

        let result = angle.truncatingRemainder(
            dividingBy: 360
        )

        return result < 0
            ? result + 360
            : result
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
