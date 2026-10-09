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

    static func format(_ value: Double, isLatitude: Bool) -> String {
        guard value.isFinite else { return "—" }
        var degrees = Int(abs(value).rounded(.down))
        var minutes = (abs(value) - Double(degrees)) * 60
        if minutes >= 59.99995 { degrees += 1; minutes = 0 }
        let direction = isLatitude ? (value < 0 ? "S" : "N") : (value < 0 ? "W" : "E")
        return String(format: "%d°%.4f′%@", locale: Locale(identifier: "en_US_POSIX"), degrees, minutes, direction)
    }
}
