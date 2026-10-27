
import Foundation
import CoreLocation

@MainActor
final class GPSFilter {

    // MARK: - Configuration

    private let historyLimit = 10

    private let minimumMovement: CLLocationDistance = 10
    private let maximumAccuracy: CLLocationAccuracy = 20
    private let maximumLocationAge: TimeInterval = 10

    // MARK: - State

    private var history: [CLLocation] = []

    private(set) var lastUploadedLocation: CLLocation?

    // MARK: - Configure Session

    func configure(sessionID: String, userID: String) {

        // Each new tracking lifecycle starts fresh.
        // Previously uploaded GPS coordinates must
        // not prevent the first upload.
        //
        // Firebase may have deleted the previous
        // location when finding stopped.

        reset()

        // Keep the existing API compatible.
        _ = sessionID
        _ = userID
    }

    // MARK: - Process GPS Reading

    // Returns a location only when it is suitable
    // for uploading to Firebase.

    func process(_ location: CLLocation) -> CLLocation? {

        let now = Date()

        // Reject inaccurate or outdated GPS readings.
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= maximumAccuracy,
              abs(
                location.timestamp.timeIntervalSince(now)
              ) <= maximumLocationAge else {
            return nil
        }

        history.append(location)

        if history.count > historyLimit {
            history.removeFirst(
                history.count - historyLimit
            )
        }

        // Require at least two consistent readings.
        guard history.count >= 2 else {
            return nil
        }

        let previous = history[history.count - 2]

        let timeDifference = abs(
            location.timestamp.timeIntervalSince(
                previous.timestamp
            )
        )

        guard timeDifference <= 15 else {
            return nil
        }

        // Reject suspicious GPS jumps.
        let separation = location.distance(from: previous)

        let consistencyLimit = max(
            12,
            location.horizontalAccuracy +
                previous.horizontalAccuracy
        )

        guard separation <= consistencyLimit else {
            return nil
        }

        // First reliable location in this tracking lifecycle.
        guard let lastUploadedLocation else {
            return location
        }

        // Compare entirely on the device.
        // No Firebase read is needed.
        let movement = location.distance(
            from: lastUploadedLocation
        )

        // Higher GPS uncertainty requires more movement
        // before uploading a new coordinate.
        let requiredMovement = max(
            minimumMovement,
            location.horizontalAccuracy * 1.5,
            lastUploadedLocation.horizontalAccuracy * 1.5
        )

        guard movement >= requiredMovement else {
            return nil
        }

        // Confirm the new location using recent samples.
        let confirmations = history.suffix(4).filter {
            sample in

            abs(
                sample.timestamp.timeIntervalSince(
                    location.timestamp
                )
            ) <= 12 &&
            sample.distance(from: location) <= max(
                10,
                sample.horizontalAccuracy +
                    location.horizontalAccuracy
            )
        }

        guard confirmations.count >= 2 else {
            return nil
        }

        return location
    }

    // MARK: - Successful Upload

    // Called only after Firebase confirms
    // that the location was uploaded successfully.

    func markUploaded(_ location: CLLocation) {

        lastUploadedLocation = location
    }

    // MARK: - Reset

    func reset() {

        history.removeAll()
        lastUploadedLocation = nil
    }
}
