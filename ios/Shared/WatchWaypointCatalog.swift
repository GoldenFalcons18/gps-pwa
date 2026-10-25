import Foundation

struct WatchWaypoint: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var latitude: Double
    var longitude: Double
    var folder: String
}
struct WatchWaypointCatalog: Codable, Equatable {
    var waypoints: [WatchWaypoint]
    var targetID: String?
    var metric: Bool
    var selectionChangedAt: Date
    var sentAt: Date
    var recording: Bool? = nil
    var statusMessage: String? = nil
}

enum WatchNavigationMath {
    static func normalize(_ degrees: Double) -> Double { (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) }
    static func magneticBearing(trueBearing: Double, trueHeading: Double, magneticHeading: Double) -> Double {
        normalize(trueBearing - trueHeading + magneticHeading)
    }
    static func unwrap(from: Double, to: Double) -> Double {
        from + (normalize(to - from + 180) - 180)
    }
    static func distance(_ meters: Double?, metric: Bool) -> String {
        guard let meters, meters.isFinite, meters >= 0 else { return "—" }
        return metric ? (meters < 1000 ? String(format: "%.0f m", meters) : String(format: "%.2f km", meters / 1000)) : String(format: "%.2f nm", meters / 1852)
    }
    static func speed(_ mps: Double?, metric: Bool) -> String {
        guard let mps, mps.isFinite, mps >= 0 else { return "—" }
        return String(format: "%.1f", mps * (metric ? 3.6 : 1.943844492))
    }
    static func validFix(timestamp: Date?, accuracy: Double, now: Date) -> Bool {
        guard let timestamp else { return false }
        return accuracy >= 0 && accuracy.isFinite && (-5...15).contains(now.timeIntervalSince(timestamp))
    }
}
