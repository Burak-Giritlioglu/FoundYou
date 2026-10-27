import Foundation

@MainActor
final class FoundDetectionManager {

    // MARK: - Configuration

    private let maximumDistance: Float = 1.5
    private let requiredDuration: TimeInterval = 2
    private let maximumMeasurementAge: TimeInterval = 1.5
    private let maximumMeasurementGap: TimeInterval = 1.5

    // MARK: - State

    private var proximityStartedAt: Date?
    private var lastMeasurementAt: Date?
    private var lastMeasurementID: UInt64?

    private(set) var hasFoundFriend = false

    // MARK: - Process UWB Measurement

    // Returns true only when the friend
    // has been found using fresh UWB measurements.

    @discardableResult
    func update(
        distance: Float?,
        measurementID: UInt64,
        measuredAt: Date?
    ) -> Bool {

        guard !hasFoundFriend else {
            return true
        }

        let now = Date()

        // Reject missing or stale UWB data.
        guard let distance,
              distance.isFinite,
              distance >= 0,
              let measuredAt,
              measuredAt <= now,
              now.timeIntervalSince(measuredAt)
                  <= maximumMeasurementAge else {

            resetProximity()
            return false
        }

        // Reject a gap in continuous ranging.
        if let lastMeasurementAt,
           measuredAt.timeIntervalSince(lastMeasurementAt)
                > maximumMeasurementGap {

            resetProximity()
        }

        // A repeated measurement cannot advance
        // the proximity confirmation.
        guard lastMeasurementID != measurementID else {
            return false
        }

        // Reject out-of-order measurements.
        if let lastMeasurementAt,
           measuredAt <= lastMeasurementAt {
            return false
        }

        lastMeasurementID = measurementID
        lastMeasurementAt = measuredAt

        // Moving outside the threshold resets
        // the continuous proximity period.
        guard distance <= maximumDistance else {
            proximityStartedAt = nil
            return false
        }

        // First close-range measurement.
        guard let startedAt = proximityStartedAt else {
            proximityStartedAt = measuredAt
            return false
        }

        // Require sustained proximity.
        guard measuredAt.timeIntervalSince(startedAt)
                >= requiredDuration else {
            return false
        }

        hasFoundFriend = true
        return true
    }

    // MARK: - Reset Proximity

    private func resetProximity() {
        proximityStartedAt = nil
        lastMeasurementAt = nil
        lastMeasurementID = nil
    }

    // MARK: - Reset Finding Session

    func reset() {
        resetProximity()
        hasFoundFriend = false
    }
}
