import CoreLocation
import Observation
import ZahoriCore

/// When-in-use location, used only as the proximity origin when no library is selected.
/// Falls back to Madrid center when permission is denied or location is unavailable.
@MainActor @Observable
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private(set) var authorization: CLAuthorizationStatus
    private(set) var coordinate: Coordinate?
    private let manager = CLLocationManager()

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isDenied: Bool { authorization == .denied || authorization == .restricted }

    /// The point distances are measured from when nothing is selected.
    var origin: Proximity.ReferencePoint {
        if let coordinate {
            return .init(name: String(localized: "tu ubicación"), coordinate: coordinate)
        }
        return .init(name: String(localized: "el centro de Madrid"), coordinate: .madridCenter)
    }

    func requestIfNeeded() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        default: break
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if status == .authorizedWhenInUse || status == .authorizedAlways { self.manager.requestLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let c = locations.last?.coordinate else { return }
        Task { @MainActor in self.coordinate = Coordinate(lat: c.latitude, lon: c.longitude) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Keep the Madrid-center fallback; nothing to surface to the user here.
    }
}
