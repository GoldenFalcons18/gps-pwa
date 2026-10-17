import Foundation
import CoreLocation
import WatchConnectivity

/// Shares only the current navigation reading with the paired watch.
final class WatchNavigationBridge: NSObject, WCSessionDelegate {
    static let shared = WatchNavigationBridge()
    private var target: Waypoint?
    private var location: CLLocation?
    private var metric = false
    private var latest: [String: Any] = [:]
    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }
    func setTarget(_ waypoint: Waypoint?, metric: Bool) {
        target = waypoint; self.metric = metric; publish()
    }
    func updateLocation(_ point: CLLocation) { location = point; publish() }
    private func publish() {
        let point = location
        let snapshot = WatchNavigationSnapshot(
            name: target?.name,
            bearing: target.flatMap { wp in point.map { WatchNavigationSnapshot.bearing(fromLat: $0.coordinate.latitude, fromLon: $0.coordinate.longitude, toLat: wp.latitude, toLon: wp.longitude) } },
            distanceMeters: target.flatMap { wp in point.map { $0.distance(from: CLLocation(latitude: wp.latitude, longitude: wp.longitude)) } },
            metric: metric, locationTime: point?.timestamp, sentAt: Date())
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        latest = ["navigation": data]
        let session = WCSession.default
        guard WCSession.isSupported(), session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        // Context replaces older pending readings instead of queuing obsolete fixes.
        try? session.updateApplicationContext(latest)
        if session.isReachable { session.sendMessage(latest, replyHandler: nil, errorHandler: nil) }
    }
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { self.publish() }
    }
    func sessionWatchStateDidChange(_ session: WCSession) { DispatchQueue.main.async { self.publish() } }
    func sessionReachabilityDidChange(_ session: WCSession) { DispatchQueue.main.async { self.publish() } }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        DispatchQueue.main.async { self.publish(); replyHandler(self.latest) }
    }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
