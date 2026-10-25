import Foundation

struct StartLineCoordinate: Codable, Equatable {
    var latitude: Double
    var longitude: Double

    var isValid: Bool {
        latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}

enum StartLineMath {
    private static let earthRadius = 6_371_008.8

    static func distanceMeters(from boat: StartLineCoordinate, outerMark: StartLineCoordinate?, signalBoat: StartLineCoordinate?) -> Double? {
        guard boat.isValid, let outerMark, let signalBoat, outerMark.isValid, signalBoat.isValid else { return nil }
        let originLatitude = boat.latitude * .pi / 180
        let cosine = cos(originLatitude)
        func project(_ point: StartLineCoordinate) -> (x: Double, y: Double) {
            let longitudeDelta = (point.longitude - boat.longitude) * .pi / 180
            let latitudeDelta = (point.latitude - boat.latitude) * .pi / 180
            return (earthRadius * longitudeDelta * cosine, earthRadius * latitudeDelta)
        }
        let a = project(outerMark)
        let b = project(signalBoat)
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(a.x, a.y) }
        let fraction = min(1, max(0, -(a.x * dx + a.y * dy) / lengthSquared))
        return hypot(a.x + fraction * dx, a.y + fraction * dy)
    }

    static func countdown(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded(.up)))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    static func isMinuteCountdown(_ seconds: TimeInterval) -> Bool {
        let value = max(0, Int(seconds.rounded(.up)))
        return value > 0 && (1...10).contains(value % 60)
    }

    static func isThirtySecondWarning(_ seconds: TimeInterval) -> Bool {
        let value = max(0, Int(seconds.rounded(.up)))
        return value > 0 && value % 60 == 30
    }

    static func nearestMinute(_ seconds: TimeInterval) -> TimeInterval {
        max(60, (seconds / 60).rounded() * 60)
    }
}
