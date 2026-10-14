
import Foundation
import CoreLocation
import Combine

final class HeadingManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    private let locationManager = CLLocationManager()

    @Published private(set) var heading: Double?
    @Published private(set) var accuracy: Double?
    @Published private(set) var isAvailable = false
    @Published private(set) var isRunning = false

    override init() {
        super.init()

        locationManager.delegate = self
        locationManager.headingFilter = 1
        isAvailable = CLLocationManager.headingAvailable()
    }

    func start() {
        guard CLLocationManager.headingAvailable() else {
            isAvailable = false
            isRunning = false
            return
        }

        isAvailable = true

        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.startUpdatingHeading()
            isRunning = true

        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()

        default:
            isRunning = false
        }
    }

    func stop() {
        locationManager.stopUpdatingHeading()
        isRunning = false
        heading = nil
        accuracy = nil
    }

    func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager
    ) {
        if manager.authorizationStatus == .authorizedAlways ||
           manager.authorizationStatus == .authorizedWhenInUse {
            start()
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateHeading newHeading: CLHeading
    ) {
        guard newHeading.headingAccuracy >= 0 else {
            heading = nil
            accuracy = nil
            return
        }

        // Öncelik true north, yoksa magnetic north
        let value = newHeading.trueHeading >= 0
            ? newHeading.trueHeading
            : newHeading.magneticHeading

        heading = value
        accuracy = newHeading.headingAccuracy
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        isRunning = false
        heading = nil
        accuracy = nil
    }
}
