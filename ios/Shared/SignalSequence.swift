import Foundation

/// Flag events are scheduled from the operator's Start press (elapsed time).
struct SignalSequence {
    struct Event: Identifiable, Equatable {
        let id: Int
        let secondsAfterStart: Int
        let title: String
        let flag: String
        let colorHex: UInt32
        let raised: Bool
        let hornPulses: [Int]
    }
    struct Profile: Identifiable {
        let id: String
        let name: String
        let events: [Event]
        var baseDurationMinutes: Int = 20
    }

    private static func e(_ id: Int, _ seconds: Int, _ title: String, _ flag: String, _ color: UInt32, _ raised: Bool, _ pulses: [Int] = []) -> Event {
        Event(id: id, secondsAfterStart: seconds, title: title, flag: flag, colorHex: color, raised: raised, hornPulses: pulses)
    }

    /// Default sequence transcribed from the supplied signal-timer video.
    /// Times are elapsed after Start: 0, 5, 6, 9, 10, and 20 minutes.
    static let profiles: [Profile] = [
        Profile(id: "video-20", name: "動画の信号（20分）", events: [
            e(0, 0, "橙旗を掲揚", "橙", 0xF58A00, true, [0]),
            e(1, 300, "緑旗を掲揚", "緑", 0x00D228, true, [0]),
            e(2, 360, "青旗を掲揚", "青", 0x1769FF, true, [0]),
            e(3, 540, "青旗を降下", "青", 0x1769FF, false, [1]),
            e(4, 600, "緑旗を降下", "緑", 0x00D228, false, [0]),
            e(5, 1200, "橙旗を降下", "橙", 0xF58A00, false)
        ]),
        Profile(id: "class-p", name: "カスタム（クラス旗＋P旗）", events: [
            e(0, 0, "クラス旗を掲揚", "級", 0xF58A00, true, [0]),
            e(1, 60, "P旗を掲揚", "P", 0x1769FF, true, [0]),
            e(2, 240, "P旗を降下", "P", 0x1769FF, false, [1]),
            e(3, 300, "クラス旗を降下", "級", 0xF58A00, false, [0])
        ], baseDurationMinutes: 5),
        Profile(id: "class-i", name: "カスタム（クラス旗＋I旗）", events: [
            e(0, 0, "クラス旗を掲揚", "級", 0xF58A00, true, [0]),
            e(1, 60, "I旗を掲揚", "I", 0xF5D328, true, [0]),
            e(2, 240, "I旗を降下", "I", 0xF5D328, false, [1]),
            e(3, 300, "クラス旗を降下", "級", 0xF58A00, false, [0])
        ], baseDurationMinutes: 5)
    ]

    static func events(durationMinutes: Int = 20, profileID: String = "video-20") -> [Event] {
        let profile = profiles.first { $0.id == profileID } ?? profiles[0]
        guard profile.id != "video-20" else { return profile.events }
        let scale = Double(max(1, durationMinutes)) / Double(max(1, profile.baseDurationMinutes))
        return profile.events.map {
            e($0.id, Int((Double($0.secondsAfterStart) * scale).rounded()), $0.title, $0.flag, $0.colorHex, $0.raised, $0.hornPulses)
        }
    }

    static func activeEventIndex(elapsed: Double, durationMinutes: Int = 20, profileID: String = "video-20") -> Int {
        let list = events(durationMinutes: durationMinutes, profileID: profileID)
        guard !list.isEmpty else { return 0 }
        return list.lastIndex { Double($0.secondsAfterStart) <= elapsed } ?? 0
    }

    static func flags(elapsed: Double, durationMinutes: Int = 20, profileID: String = "video-20") -> [Event] {
        var raised: [String: Event] = [:]
        for event in events(durationMinutes: durationMinutes, profileID: profileID) where Double(event.secondsAfterStart) <= elapsed {
            if event.raised { raised[event.flag] = event }
            else { raised.removeValue(forKey: event.flag) }
        }
        return raised.values.sorted { $0.id < $1.id }
    }

    static func clockText(_ date: Date, offset: Double = 0) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date.addingTimeInterval(offset))
    }
}
