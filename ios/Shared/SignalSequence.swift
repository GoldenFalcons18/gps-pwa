import Foundation

/// Default visual start sequence used by Signal mode. Event timestamps are seconds
/// before the selected start time; race instructions can differ, so the list is
/// presented as an editable-style visual template rather than a rules guarantee.
struct SignalSequence {
    struct Event: Identifiable, Equatable {
        let id: Int
        let secondsBeforeStart: Int
        let title: String
        let flag: String
        let colorHex: UInt32
        let raised: Bool
    }

    static let events: [Event] = [
        Event(id: 0, secondsBeforeStart: 300, title: "オレンジ旗を掲揚", flag: "橙", colorHex: 0xF58A00, raised: true),
        Event(id: 1, secondsBeforeStart: 240, title: "グリーン旗を掲揚", flag: "緑", colorHex: 0x18D44B, raised: true),
        Event(id: 2, secondsBeforeStart: 180, title: "ブルー旗を掲揚", flag: "青", colorHex: 0x1769FF, raised: true),
        Event(id: 3, secondsBeforeStart: 120, title: "ブルー旗を降下", flag: "青", colorHex: 0x1769FF, raised: false),
        Event(id: 4, secondsBeforeStart: 60, title: "グリーン旗を降下", flag: "緑", colorHex: 0x18D44B, raised: false),
        Event(id: 5, secondsBeforeStart: 0, title: "グリーン start at", flag: "橙", colorHex: 0xF58A00, raised: false)
    ]

    static func events(durationMinutes: Int) -> [Event] {
        let duration = max(1, durationMinutes)
        return events.map { event in
            Event(id: event.id, secondsBeforeStart: Int((Double(event.secondsBeforeStart) * Double(duration) / 5).rounded()), title: event.title, flag: event.flag, colorHex: event.colorHex, raised: event.raised)
        }
    }

    static func nextEventIndex(secondsUntilStart: Double, durationMinutes: Int = 5) -> Int {
        let schedule = SignalSequence.events(durationMinutes: durationMinutes)
        guard secondsUntilStart > 0 else { return schedule.count - 1 }
        return schedule.firstIndex { secondsUntilStart >= Double($0.secondsBeforeStart) } ?? 0
    }

    static func secondsUntilNextEvent(secondsUntilStart: Double, index: Int, durationMinutes: Int = 5) -> Int {
        let schedule = SignalSequence.events(durationMinutes: durationMinutes)
        guard schedule.indices.contains(index) else { return 0 }
        let remaining = secondsUntilStart - Double(schedule[index].secondsBeforeStart)
        return Int(ceil(remaining))
    }

    static func clockText(_ date: Date, offset: Double = 0) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date.addingTimeInterval(offset))
    }
}
