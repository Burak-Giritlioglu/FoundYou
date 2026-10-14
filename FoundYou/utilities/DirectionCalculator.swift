import Foundation
import CoreLocation

struct DirectionCalculator {

    // İki GPS noktası arasındaki yönü hesaplar.
    // 0° = Kuzey, 90° = Doğu, 180° = Güney, 270° = Batı.
    static func bearing(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) -> Double {

        let lat1 = origin.latitude * .pi / 180
        let lat2 = destination.latitude * .pi / 180
        let deltaLon = (destination.longitude - origin.longitude) * .pi / 180

        let y = sin(deltaLon) * cos(lat2)

        let x = cos(lat1) * sin(lat2)
              - sin(lat1) * cos(lat2) * cos(deltaLon)

        let angle = atan2(y, x) * 180 / .pi

        return (angle + 360).truncatingRemainder(dividingBy: 360)
    }

    // İki GPS noktası arasındaki yaklaşık yüzey mesafesi (metre).
    static func distance(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) -> Double {

        let start = CLLocation(
            latitude: origin.latitude,
            longitude: origin.longitude
        )

        let end = CLLocation(
            latitude: destination.latitude,
            longitude: destination.longitude
        )

        return start.distance(from: end)
    }
}
