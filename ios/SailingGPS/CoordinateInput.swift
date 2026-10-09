import Foundation

enum CoordinateInput {
    static func decimal(degrees: String, minutes: String, direction: String, isLatitude: Bool) -> Double? {
        let degreeText = degrees.trimmingCharacters(in: .whitespacesAndNewlines)
        let minuteText = minutes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !degreeText.isEmpty, degreeText.allSatisfy({ "0123456789".contains($0) }),
              let degree = Int(degreeText), !minuteText.isEmpty,
              minuteText.allSatisfy({ "0123456789.".contains($0) }),
              let minute = Double(minuteText), minute.isFinite,
              (0...(isLatitude ? 90 : 180)).contains(degree), (0..<60).contains(minute),
              degree != (isLatitude ? 90 : 180) || minute == 0,
              (isLatitude ? ["N", "S"] : ["E", "W"]).contains(direction) else { return nil }
        let value = Double(degree) + minute / 60
        return direction == "S" || direction == "W" ? -value : value
    }

    // Straight-line distance at current SOG; below ~0.5 kt the estimate is hidden.
    static func ete(distanceMeters: Double?, speedMps: Double?) -> String {
        guard let distance = distanceMeters, distance.isFinite, distance >= 0 else { return "--:--:--" }
        if distance == 0 { return "00:00:00" }
        guard let speed = speedMps, speed.isFinite, speed >= 0.25 else { return "--:--:--" }
        let seconds = ceil(distance / speed)
        guard seconds.isFinite, seconds <= 2_147_483_647 else { return "--:--:--" }
        let total = Int(seconds)
        return String(format: "%02d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
    }

    static func format(_ value: Double, isLatitude: Bool) -> String {
        guard value.isFinite else { return "—" }
        var degrees = Int(abs(value).rounded(.down))
        var minutes = (abs(value) - Double(degrees)) * 60
        if minutes >= 59.99995 { degrees += 1; minutes = 0 }
        let direction = isLatitude ? (value < 0 ? "S" : "N") : (value < 0 ? "W" : "E")
        return String(format: "%d°%.4f′%@", locale: Locale(identifier: "en_US_POSIX"), degrees, minutes, direction)
    }
    static func distance(_ meters: Double, metric: Bool) -> String {
        if !metric { return String(format: "%.2f nm", meters / 1852) }
        return meters < 1000 ? String(format: "%.0f m", meters) : String(format: "%.2f km", meters / 1000)
    }

    static func destination(latitude: Double, longitude: Double, bearing: Double, meters: Double) -> (latitude: Double, longitude: Double) {
        let a = latitude * .pi / 180, b = longitude * .pi / 180
        let h = bearing * .pi / 180, d = meters / 6371000
        let x = asin(min(1, max(-1, sin(a)*cos(d) + cos(a)*sin(d)*cos(h))))
        let y = b + atan2(sin(h)*sin(d)*cos(a), cos(d)-sin(a)*sin(x))
        return (x * 180 / .pi, (y * 180 / .pi + 540).truncatingRemainder(dividingBy: 360) - 180)
    }
}
