import CoreLocation
import Combine

final class WatchSensors: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var location: CLLocation?
    @Published var heading: CLHeading?
    @Published var status = "Watch GPSを取得中"
    private let manager = CLLocationManager()
    private var active = false
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.headingFilter = 1
        manager.activityType = .otherNavigation
    }
    func setActive(_ value: Bool) {
        active = value
        if !value { manager.stopUpdatingLocation(); manager.stopUpdatingHeading(); return }
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
            status = CLLocationManager.headingAvailable() ? "Watch GPS・コンパス" : "コンパス非対応"
        default:
            location = nil; heading = nil; status = "Watchの位置情報を許可してください"
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { if active { setActive(true) } }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let fix = locations.last(where: { WatchNavigationMath.validFix(timestamp: $0.timestamp, accuracy: $0.horizontalAccuracy, now: Date()) }) { location = fix }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        if newHeading.headingAccuracy >= 0 { heading = newHeading }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if (error as? CLError)?.code == .denied { location = nil; heading = nil }
        status = (error as? CLError)?.code == .denied ? "位置情報が許可されていません" : "Watch GPSを取得中"
    }
    func fix(at date: Date) -> CLLocation? {
        guard let location, WatchNavigationMath.validFix(timestamp: location.timestamp, accuracy: location.horizontalAccuracy, now: date) else { return nil }
        return location
    }
    func compass(at date: Date) -> CLHeading? {
        guard let heading, (-5...15).contains(date.timeIntervalSince(heading.timestamp)), heading.headingAccuracy >= 0 else { return nil }
        return heading
    }
}
