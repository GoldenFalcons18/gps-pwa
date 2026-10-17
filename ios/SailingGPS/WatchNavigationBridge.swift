import Foundation
import CoreLocation
import WatchConnectivity

extension Notification.Name { static let watchTargetChanged = Notification.Name("SailingGPSWatchTargetChanged") }

/// Syncs saved waypoints and target selection; Watch navigation uses its own sensors.
final class WatchNavigationBridge: NSObject, WCSessionDelegate {
    static let shared = WatchNavigationBridge()
    private var target: Waypoint?
    private var waypoints: [Waypoint] = []
    private var waypointsReady = false
    private var selectionChangedAt = (UserDefaults.standard.object(forKey: "watchTargetChangedAt") as? Double).map(Date.init(timeIntervalSince1970:)) ?? .distantPast
    private var lastSelectedID = UserDefaults.standard.string(forKey: "activeWaypointID")
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
        let id = waypoint?.id.uuidString ?? "__none__"
        if lastSelectedID != id {
            selectionChangedAt = Date()
            UserDefaults.standard.set(selectionChangedAt.timeIntervalSince1970, forKey: "watchTargetChangedAt")
        }
        lastSelectedID = id
        target = waypoint; self.metric = metric; publish()
    }
    func setWaypoints(_ points: [Waypoint]) {
        waypoints = points; waypointsReady = true
        if let id = target?.id { target = points.first { $0.id == id } }
        publish()
    }
    func updateLocation(_ point: CLLocation) { location = point }
    private func selectFromWatch(_ message: [String: Any]) -> Bool {
        guard let id = message["selectTarget"] as? String,
              let time = message["selectionTime"] as? Double,
              Date(timeIntervalSince1970: time) >= selectionChangedAt else { return false }
        guard id == "__none__" || waypoints.contains(where: { $0.id.uuidString == id }) else { return false }
        target = waypoints.first { $0.id.uuidString == id }
        selectionChangedAt = Date(timeIntervalSince1970: time)
        lastSelectedID = id
        UserDefaults.standard.set(time, forKey: "watchTargetChangedAt")
        UserDefaults.standard.set(id, forKey: "activeWaypointID")
        NotificationCenter.default.post(name: .watchTargetChanged, object: nil, userInfo: ["targetID": id])
        publish()
        return true
    }
    private func publish() {
        guard waypointsReady else { return }
        let point = location
        let snapshot = WatchNavigationSnapshot(
            name: target?.name,
            bearing: target.flatMap { wp in point.map { WatchNavigationSnapshot.bearing(fromLat: $0.coordinate.latitude, fromLon: $0.coordinate.longitude, toLat: wp.latitude, toLon: wp.longitude) } },
            distanceMeters: target.flatMap { wp in point.map { $0.distance(from: CLLocation(latitude: wp.latitude, longitude: wp.longitude)) } },
            metric: metric, locationTime: point?.timestamp, sentAt: Date())
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        let catalog = WatchWaypointCatalog(waypoints: waypoints.map { WatchWaypoint(id: $0.id.uuidString, name: $0.name, latitude: $0.latitude, longitude: $0.longitude, folder: $0.group ?? "メインフォルダ") }, targetID: target?.id.uuidString, metric: metric, selectionChangedAt: selectionChangedAt, sentAt: Date())
        guard let catalogData = try? JSONEncoder().encode(catalog) else { return }
        latest = ["navigation": data, "waypoints": catalogData]
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
        DispatchQueue.main.async {
            guard self.waypointsReady else { replyHandler(["deferred": true]); return }
            var accepted = true
            if message["selectTarget"] != nil { accepted = self.selectFromWatch(message) }
            self.publish()
            var reply = self.latest; reply["selectionAccepted"] = accepted
            replyHandler(reply)
        }
    }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
