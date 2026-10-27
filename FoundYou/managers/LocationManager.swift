
import Foundation
import CoreLocation
import Combine

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    // MARK: - Published State

    @Published private(set) var location: CLLocation?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRunning = false
    @Published private(set) var isBackgroundTrackingEnabled = false

    // MARK: - Core Location

    private let manager = CLLocationManager()

    private var wantsLocationUpdates = false
    private var wantsBackgroundTracking = false
    private var hasRequestedAlwaysAuthorization = false

    // MARK: - Initialization

    override init() {
        super.init()

        manager.delegate = self

        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 2

        manager.pausesLocationUpdatesAutomatically = true

        authorizationStatus = manager.authorizationStatus
    }

    // MARK: - Background Tracking Configuration

    // Call this when a paired session needs
    // background location availability.
    //
    // This does not create another CLLocationManager.
    // It configures the existing manager.

    func setBackgroundTrackingEnabled(_ enabled: Bool) {

        wantsBackgroundTracking = enabled

        if enabled {

            // Request Always only after When In Use
            // permission is already available.
            //
            // iOS controls whether and when
            // the permission prompt appears.

            if manager.authorizationStatus == .authorizedWhenInUse,
               !hasRequestedAlwaysAuthorization {

                hasRequestedAlwaysAuthorization = true
                manager.requestAlwaysAuthorization()
            }
        }

        applyBackgroundConfiguration()
    }

    private func applyBackgroundConfiguration() {

        // Background location updates are enabled
        // only with Always authorization and
        // the Background Modes location capability.

        let canTrackInBackground =
            wantsBackgroundTracking &&
            manager.authorizationStatus == .authorizedAlways

        manager.allowsBackgroundLocationUpdates =
            canTrackInBackground

        manager.showsBackgroundLocationIndicator =
            canTrackInBackground

        manager.pausesLocationUpdatesAutomatically =
            !canTrackInBackground

        isBackgroundTrackingEnabled =
            canTrackInBackground

        if wantsBackgroundTracking && !canTrackInBackground {

            print(
                "GPS DEBUG: Background tracking unavailable",
                manager.authorizationStatus.rawValue
            )
        }
    }

    // MARK: - Start

    func start() {

        wantsLocationUpdates = true
        errorMessage = nil

        print("GPS DEBUG: start() called")

        switch manager.authorizationStatus {

        case .notDetermined:

            manager.requestWhenInUseAuthorization()

        case .authorizedWhenInUse, .authorizedAlways:

            applyBackgroundConfiguration()

            manager.startUpdatingLocation()
            isRunning = true

        case .denied, .restricted:

            manager.stopUpdatingLocation()
            isRunning = false
            location = nil

            errorMessage = "Location access is denied. Please enable it in Settings."

        @unknown default:

            errorMessage = "Unknown location authorization status."
        }
    }

    // MARK: - Stop

    func stop() {

        print("GPS DEBUG: stop() called")

        wantsLocationUpdates = false

        manager.stopUpdatingLocation()
        isRunning = false

        // Do not keep background execution enabled
        // after GPS updates are stopped.

        wantsBackgroundTracking = false
        applyBackgroundConfiguration()
    }

    // MARK: - Authorization Changes

    func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager
    ) {

        authorizationStatus = manager.authorizationStatus

        print(
            "GPS DEBUG: Authorization changed:",
            manager.authorizationStatus.rawValue
        )

        applyBackgroundConfiguration()

        switch manager.authorizationStatus {

        case .authorizedWhenInUse, .authorizedAlways:

            // Do not automatically start GPS after
            // the user or coordinator stopped it.

            if wantsLocationUpdates {
                start()
            }

        case .denied, .restricted:

            manager.stopUpdatingLocation()

            isRunning = false
            location = nil

            errorMessage = "Location access is denied. Please enable it in Settings."

        case .notDetermined:
            break

        @unknown default:
            break
        }
    }

    // MARK: - Location Updates

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {

        guard wantsLocationUpdates,
              let newLocation = locations.last else {
            return
        }

        let age = Date().timeIntervalSince(
            newLocation.timestamp
        )

        print(
            "GPS DEBUG: Location received",
            "accuracy:", newLocation.horizontalAccuracy,
            "age:", age
        )

        guard newLocation.horizontalAccuracy >= 0 else {
            print("GPS DEBUG: Invalid accuracy")
            return
        }

        // Reject stale local sensor readings.
        // This does NOT invalidate the friend's
        // last known location in NavigationManager.

        guard abs(age) <= 10 else {
            print("GPS DEBUG: Stale local location rejected")
            return
        }

        location = newLocation
        errorMessage = nil

        print("GPS DEBUG: Location published")
    }

    // MARK: - Location Errors

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {

        print(
            "GPS DEBUG: Location error:",
            error.localizedDescription
        )

        errorMessage = error.localizedDescription
    }
}
