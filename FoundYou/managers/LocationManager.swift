import Foundation
import CoreLocation
import Combine

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    @Published private(set) var location: CLLocation?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRunning = false

    private let manager = CLLocationManager()

    override init() {
        super.init()

        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 2

        authorizationStatus = manager.authorizationStatus
    }

    func start() {
        errorMessage = nil

        switch manager.authorizationStatus {

        case .notDetermined:
            manager.requestWhenInUseAuthorization()

        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
            isRunning = true

        case .denied, .restricted:
            manager.stopUpdatingLocation()
            isRunning = false
            location = nil
            errorMessage = "Konum izni verilmedi."

        @unknown default:
            errorMessage = "Bilinmeyen konum izni durumu."
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        isRunning = false
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        switch manager.authorizationStatus {

        case .authorizedWhenInUse, .authorizedAlways:
            start()

        case .denied, .restricted:
            stop()
            location = nil
            errorMessage = "Konum izni verilmedi."

        case .notDetermined:
            break

        @unknown default:
            break
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let newLocation = locations.last else {
            return
        }

        guard newLocation.horizontalAccuracy >= 0 else {
            return
        }

        guard abs(newLocation.timestamp.timeIntervalSinceNow) <= 10 else {
            return
        }

        location = newLocation
        errorMessage = nil
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        errorMessage = error.localizedDescription
    }
}
