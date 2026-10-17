import Foundation

struct WatchNavigationSnapshot: Codable, Equatable {
    var name: String?
    var bearing: Double?
    var distanceMeters: Double?
    var metric: Bool
    var locationTime: Date?
    var sentAt: Date

    var hasTarget: Bool { name != nil }
    func isFresh(at date: Date) -> Bool {
        guard let locationTime else { return false }
        return date.timeIntervalSince(locationTime) >= -5 && date.timeIntervalSince(locationTime) <= 30
    }
    var distanceText: String {
        guard let distanceMeters, distanceMeters.isFinite, distanceMeters >= 0 else { return "—" }
        if !metric { return String(format: "%.2f nm", distanceMeters / 1852) }
        return distanceMeters < 1000 ? String(format: "%.0f m", distanceMeters) : String(format: "%.2f km", distanceMeters / 1000)
    }
    static func bearing(fromLat: Double, fromLon: Double, toLat: Double, toLon: Double) -> Double {
        let a = fromLat * .pi / 180, b = toLat * .pi / 180, d = (toLon - fromLon) * .pi / 180
        let degrees = atan2(sin(d) * cos(b), cos(a) * sin(b) - sin(a) * cos(b) * cos(d)) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }
}
