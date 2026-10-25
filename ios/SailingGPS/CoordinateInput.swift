import Foundation

enum CoordinateInput {
    static func isDaylight(latitude: Double, longitude: Double, date: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents([.day, .hour, .minute, .second], from: date)
        let hour = Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60 + Double(parts.second ?? 0) / 3600
        let gamma = 2 * .pi / 365 * (Double(parts.day ?? 1) - 1 + (hour - 12) / 24)
        let equation = 229.18 * (0.000075 + 0.001868*cos(gamma) - 0.032077*sin(gamma) - 0.014615*cos(2*gamma) - 0.040849*sin(2*gamma))
        let declination = 0.006918 - 0.399912*cos(gamma) + 0.070257*sin(gamma) - 0.006758*cos(2*gamma) + 0.000907*sin(2*gamma) - 0.002697*cos(3*gamma) + 0.00148*sin(3*gamma)
        let solarMinutes = hour * 60 + equation + 4 * longitude
        let hourAngle = (solarMinutes / 4 - 180) * .pi / 180
        let lat = latitude * .pi / 180
        let elevation = asin(sin(lat)*sin(declination) + cos(lat)*cos(declination)*cos(hourAngle)) * 180 / .pi
        return elevation > -0.833
    }

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

    static let boatScreenFraction = 0.72
    static func followCenter(latitude: Double, longitude: Double, heading: Double, mapHeight: Double, pointsPerCm: Double, metersPerCm: Double = 200) -> (latitude: Double, longitude: Double) {
        let ahead = mapHeight * (boatScreenFraction - 0.5) * metersPerCm / pointsPerCm
        return destination(latitude: latitude, longitude: longitude, bearing: heading, meters: ahead)
    }

    static func wheelRows(_ value: Double, latitude: Bool, format: Int) -> [Int] {
        let maximum = latitude ? 90 : 180
        let scale = format == 0 ? 1000000 : format == 1 ? 60000 : 360000
        let total = min(maximum * scale, Int((abs(value) * Double(scale)).rounded()))
        let degrees = total / scale, remainder = total % scale
        let sign = value.sign == .minus ? 1 : 0
        if format == 0 { return [degrees] + (0..<6).map { remainder / Int(pow(10.0, Double(5-$0))) % 10 } + [sign] }
        if format == 1 { return [degrees, remainder / 1000, remainder / 100 % 10, remainder / 10 % 10, remainder % 10, sign] }
        return [degrees, remainder / 6000, remainder / 100 % 60, remainder / 10 % 10, remainder % 10, sign]
    }
    static func wheelValue(_ rows: [Int], latitude: Bool, format: Int) -> Double {
        var result = Double(rows[0])
        if format == 0 { for index in 1...6 { result += Double(rows[index]) / pow(10, Double(index)) } }
        else if format == 1 { result += (Double(rows[1]) + Double(rows[2]*100 + rows[3]*10 + rows[4])/1000) / 60 }
        else { result += Double(rows[1])/60 + (Double(rows[2]) + Double(rows[3]*10 + rows[4])/100)/3600 }
        result = min(Double(latitude ? 90 : 180), result)
        return rows.last == 1 ? -result : result
    }

    struct HeadingReading {
        let heading: Double
        let trueHeading: Double?
        let magnetic: Bool
    }
    static func normalizeHeading(_ value: Double) -> Double {
        (value.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    }
    static func relativeBearing(_ target: Double, heading: Double) -> Double {
        let value=(normalizeHeading(target-heading+180)-180)
        return value == -180 ? 180 : value
    }
    static func relativeBearingText(_ value: Double) -> String {
        let rounded=Int(value.rounded())
        if rounded == 0 { return "前方 0°" }
        return rounded > 0 ? "右 \(rounded)°" : "左 \(-rounded)°"
    }
    // Unwrapped angles keep 359 -> 1 a two-degree animation, not a full reverse turn.
    static func unwrapHeading(from previous: Double, to target: Double) -> Double {
        previous + normalizeHeading(target - previous + 180) - 180
    }
    static func headingReference(preferGps: Bool, magnetic: Double?, trueHeading: Double?, course: Double?, speed: Double?, compassWhileMoving:Bool=false) -> HeadingReading? {
        let mag = magnetic.flatMap { $0.isFinite && $0 >= 0 ? normalizeHeading($0) : nil }
        let trueNorth = trueHeading.flatMap { $0.isFinite && $0 >= 0 ? normalizeHeading($0) : nil }
        let gps = course.flatMap { value -> Double? in
            guard value.isFinite, value >= 0, let speed, speed.isFinite, speed >= 0.25 else { return nil }
            return normalizeHeading(value)
        }
        if preferGps, !compassWhileMoving, let gps { return HeadingReading(heading: gps, trueHeading: gps, magnetic: false) }
        if let mag { return HeadingReading(heading: mag, trueHeading: trueNorth, magnetic: true) }
        return gps.map { HeadingReading(heading: $0, trueHeading: $0, magnetic: false) }
    }
}

