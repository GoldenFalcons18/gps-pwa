import Foundation

/// Signal events are timed from the first signal. The standard profile starts
/// with the orange starting-line flag, five minutes before the warning signal.
/// Video profiles remain available as alternate reference sequences.
struct SignalSequence {
    struct Flag: Identifiable, Equatable {
        let id: String
        let name: String
        let style: String
        let colors: [UInt32]
        let symbol: String
        var artworkName: String? = nil
    }

    struct Event: Identifiable, Equatable {
        let id: Int
        let secondsAfterStart: Int
        let title: String
        let flags: [Flag]
        let raised: Bool
        let hornPulses: [Int]

        // Kept as convenience accessors for older timeline consumers.
        var flag: String { flags.first?.name ?? "" }
        var colorHex: UInt32 { flags.first?.colors.first ?? 0xFFFFFF }
    }

    struct Profile: Identifiable {
        let id: String
        let name: String
        let events: [Event]
        var baseDurationMinutes: Int = 20
    }

    private static func f(_ id: String, _ name: String, _ style: String, _ colors: [UInt32], _ symbol: String = "", _ artworkName: String? = nil) -> Flag {
        Flag(id: id, name: name, style: style, colors: colors, symbol: symbol, artworkName: artworkName)
    }

    /// Sailing signal flags plus the flag types visible in both reference videos.
    /// The drawing style is deliberately part of the flag so same-color flags remain distinguishable.
    static let flagCatalog: [Flag] = [
        f("orange", "橙旗", "solid", [0xF58A00]),
        f("green", "緑旗", "solid", [0x00B83F], "G"),
        f("blue-square", "青旗（白四角）", "blueSquare", [0x1769FF, 0xFFFFFF], "4"),
        f("class-4", "クラス旗 4", "classLogo", [0xFFFFFF, 0x1769FF], "4"),
        f("diagonal", "斜め二色旗", "diagonal", [0xE6D300, 0xD71920], ""),
        f("checker", "赤白チェック旗", "checker", [0xE32636, 0xFFFFFF], ""),
        f("P", "P旗", "internationalFlag", [0x1769FF, 0xFFFFFF], "", "Papa"),
        f("I", "I旗", "internationalFlag", [0xF5D328, 0x111111], "", "India"),
        f("Z", "Z旗", "internationalFlag", [0xF5D328, 0x111111], "", "Zulu"),
        f("U", "U旗", "internationalFlag", [0xD71920, 0xFFFFFF], "", "Uniform"),
        f("black", "黒色旗", "black", [0x111111], ""),
        f("AP", "回答旗（AP）", "internationalFlag", [0xD71920, 0xFFFFFF], "", "Answering Pennant"),
        f("N", "N旗", "internationalFlag", [0x1769FF, 0xFFFFFF], "", "November"),
        f("H", "H旗", "internationalFlag", [0xD71920, 0xFFFFFF], "", "Hotel"),
        f("L", "L旗", "internationalFlag", [0xF5D328, 0x111111], "", "Lima"),
        f("O", "O旗", "internationalFlag", [0xF5D328, 0xD71920], "", "Oscar"),
        f("first-sub", "第一代表旗", "internationalFlag", [0x1769FF, 0xD71920], "", "First Substitute"),
        f("X", "X旗（個別リコール）", "internationalFlag", [0xFFFFFF, 0x1769FF], "", "X-Ray"),
        f("class-1", "クラス旗 1", "classLogo", [0xFFFFFF, 0xD71920], "1"),
        f("class-2", "クラス旗 2", "classLogo", [0xFFFFFF, 0x1769FF], "2"),
        f("class-3", "クラス旗 3", "classLogo", [0xFFFFFF, 0x00A650], "3"),
        f("class-5", "クラス旗 5", "classLogo", [0xFFFFFF, 0xF58A00], "5"),
        f("class-6", "クラス旗 6", "classLogo", [0xFFFFFF, 0x7A35A8], "6"),
        f("class-7", "クラス旗 7", "classLogo", [0xFFFFFF, 0xD71920], "7"),
        f("class-8", "クラス旗 8", "classLogo", [0xFFFFFF, 0x111111], "8"),
        f("class-9", "クラス旗 9", "classLogo", [0xFFFFFF, 0xF5D328], "9"),
        f("class-10", "クラス旗 10", "classLogo", [0xFFFFFF, 0x00A6A6], "10")
    ]

    static func flag(_ id: String) -> Flag {
        if let known = flagCatalog.first(where: { $0.id == id }) { return known }
        if id.hasPrefix("intl:") {
            let artwork = String(id.dropFirst("intl:".count))
            return Flag(id: id, name: artwork, style: "internationalFlag", colors: [0xFFFFFF], symbol: "", artworkName: artwork)
        }
        if id.hasPrefix("text:") {
            let label = String(id.dropFirst("text:".count))
            return Flag(id: id, name: label, style: "textFlag", colors: [0xFFFFFF], symbol: label)
        }
        if id.hasPrefix("class-") {
            let name = String(id.dropFirst("class-".count))
            return Flag(id: id, name: name, style: "classLogo", colors: [0xFFFFFF, 0x1769FF], symbol: name)
        }
        return flagCatalog[0]
    }

    /// Align sequence zero to the next real clock minute boundary, respecting the minimum lead time.
    static func nextMinuteBoundary(at now: Double, minimumLeadSeconds: Int) -> Double {
        let minute = 60.0
        let earliest = now + Double(max(0, minimumLeadSeconds))
        return ceil(earliest / minute) * minute
    }

    /// Restart warning is exactly one minute after AP, N, or first-substitute is lowered.
    static func restartWarningTime(loweredAt: Double) -> Double { loweredAt + 60 }

    static func countdownSeconds(_ remaining: Double) -> Int {
        max(0, Int(ceil(remaining)))
    }

    private static func e(_ id: Int, _ seconds: Int, _ title: String, _ flags: [Flag], _ raised: Bool, _ pulses: [Int] = []) -> Event {
        Event(id: id, secondsAfterStart: seconds, title: title, flags: flags, raised: raised, hornPulses: pulses)
    }

    static let individualRecallRaise = e(-1, 0, "X旗を掲揚（個別リコール）", [flag("X")], true, [0])
    static let abandonRaise = e(-6, 0, "N旗を掲揚（レース中止）", [flag("N")], true, [0, 0, 0])
    static let abandonLower = e(-7, 0, "N旗を降下", [flag("N")], false, [0])
    static let generalRecallRaise = e(-2, 0, "第一代表旗を掲揚（ゼネラルリコール）", [flag("first-sub")], true, [0, 0])
    static let generalRecallLower = e(-3, 0, "第一代表旗を降下", [flag("first-sub")], false, [0])
    static let postponementRaise = e(-4, 0, "回答旗（AP）を掲揚", [flag("AP")], true, [0, 0])
    static let postponementLower = e(-5, 0, "回答旗（AP）を降下", [flag("AP")], false, [0])

    private static let orange = flag("orange")
    private static let green = flag("green")
    private static let blue = flag("blue-square")
    private static let classFour = flag("class-4")
    private static let diagonal = flag("diagonal")
    private static let checker = flag("checker")

    /// Standard 14-minute sequence measured from raising the orange flag.
    /// Orange flag is raised 5 minutes before the warning signal.
    private static func standardStart(classFlag: Flag, prepFlag: Flag) -> [Event] {
        [
            e(0, 0, "橙旗を掲揚（予告信号の5分前）", [orange], true, [0]),
            e(1, 300, "\(classFlag.name)を掲揚（予告信号・スタート5分前）", [classFlag], true, [0]),
            e(2, 360, "\(prepFlag.name)を掲揚（準備信号・スタート4分前）", [prepFlag], true, [0]),
            e(3, 540, "\(prepFlag.name)を降下（スタート1分前）", [prepFlag], false, [1]),
            e(4, 600, "\(classFlag.name)を降下（スタート）", [classFlag], false, [0]),
            e(5, 840, "橙旗を降下（スタート約4分後）", [orange], false)
        ]
    }

    /// After a general recall or postponement, the restarted warning signal is
    /// made one minute after the recall/postponement flag is lowered.
    private static func recallRestart(classFlag: Flag, prepFlag: Flag) -> [Event] {
        [
            e(0, 0, "\(classFlag.name)を掲揚（再予告信号）", [classFlag], true, [0]),
            e(1, 60, "\(prepFlag.name)を掲揚（準備信号）", [prepFlag], true, [0]),
            e(2, 240, "\(prepFlag.name)を降下（スタート1分前）", [prepFlag], false, [1]),
            e(3, 300, "\(classFlag.name)を降下（スタート）", [classFlag], false, [0])
        ]
    }

    private static var orangeFlagEnabled: Bool {
        UserDefaults.standard.object(forKey: "signalOrangeEnabled") as? Bool ?? true
    }

    private static func orangeDisplayedMinutes(for profileID: String) -> Int {
        let defaultValue = profileID == "video-13" ? 4 : 5
        let stored = UserDefaults.standard.object(forKey: "signalOrangeDisplayedMinutes") as? Int
        return min(30, max(0, stored ?? defaultValue))
    }

    private static func orangeRemovalMinutes(for profileID: String) -> Int {
        let defaultValue = profileID == "video-20" ? 10 : 4
        let stored = UserDefaults.standard.object(forKey: "signalOrangeRemovedAfterMinutes") as? Int
        return min(30, max(0, stored ?? defaultValue))
    }

    /// Race-start T+00 reference, relative to the synchronized first action.
    static func startReferenceOffset(profileID: String) -> Int {
        guard profileID == "standard-start" else { return 0 }
        let warningAfterOrange = orangeFlagEnabled ? orangeDisplayedMinutes(for: profileID) : 0
        return (warningAfterOrange + 5) * 60
    }

    private static func applyOrangeSettings(_ source: [Event], profileID: String) -> [Event] {
        let nonOrangeEvents = source.filter { !$0.flags.contains(where: { $0.id == "orange" }) }
        guard let firstSignal = nonOrangeEvents.first(where: \.raised)?.secondsAfterStart else {
            return source.filter { !$0.flags.contains(where: { $0.id == "orange" }) }
        }
        // Sequence zero is the orange raise only when that flag is enabled.
        // Otherwise the first race signal must be the first action at zero.
        let shift = orangeFlagEnabled
            ? orangeDisplayedMinutes(for: profileID) * 60 - firstSignal
            : -firstSignal
        let lastSignal = nonOrangeEvents.last?.secondsAfterStart ?? firstSignal
        let orangeDownAt = lastSignal + shift + orangeRemovalMinutes(for: profileID) * 60

        return source.compactMap { event in
            let isOrange = event.flags.contains(where: { $0.id == "orange" })
            if isOrange && !orangeFlagEnabled { return nil }
            if isOrange && !event.raised {
                return Event(id: event.id, secondsAfterStart: orangeDownAt, title: "橙旗を降下（最後の信号から設定時間後）",
                             flags: event.flags, raised: false, hornPulses: event.hornPulses)
            }
            if isOrange { return event }
            return Event(id: event.id, secondsAfterStart: max(0, event.secondsAfterStart + shift), title: event.title,
                         flags: event.flags, raised: event.raised, hornPulses: event.hornPulses)
        }.sorted { $0.secondsAfterStart == $1.secondsAfterStart ? $0.id < $1.id : $0.secondsAfterStart < $1.secondsAfterStart }
    }

    static func recallRestartEvents(classFlagID: String = "class-4", prepFlagID: String = "P") -> [Event] {
        recallRestart(classFlag: flag(classFlagID), prepFlag: flag(prepFlagID))
    }

    /// Exact 0/5/6/9/10/20-minute sequence visible in 20261026.MP4.
    private static let video20: [Event] = [
        e(0, 0, "橙旗を掲揚", [orange], true, [0]),
        e(1, 300, "緑旗を掲揚", [green], true, [0]),
        e(2, 360, "青旗を掲揚", [blue], true, [0]),
        e(3, 540, "青旗を降下", [blue], false, [1]),
        e(4, 600, "緑旗を降下", [green], false, [0]),
        e(5, 1200, "橙旗を降下", [orange], false)
    ]

    /// Exact 0/4/5/8/9/13-minute sequence visible in ScreenRecording_10-25-2026.
    /// The 4- and 9-minute calls handle two flags together, as shown in the recording.
    private static func video13(classFlag: Flag) -> [Event] {
        [
            e(0, 0, "橙旗を掲揚", [orange], true, [0]),
            e(1, 240, "クラス旗・斜め旗を掲揚", [classFlag, diagonal], true, [0]),
            e(2, 300, "赤白チェック旗を掲揚", [checker], true, [0]),
            e(3, 480, "赤白チェック旗を降下", [checker], false, [1]),
            e(4, 540, "クラス旗・斜め旗を降下", [classFlag, diagonal], false, [0]),
            e(5, 780, "橙旗を降下", [orange], false)
        ]
    }

    private static func customFive(classFlag: Flag, prepFlag: Flag) -> [Event] {
        [
            e(0, 0, "\(classFlag.name)を掲揚", [classFlag], true, [0]),
            e(1, 60, "\(prepFlag.name)を掲揚", [prepFlag], true, [0]),
            e(2, 240, "\(prepFlag.name)を降下", [prepFlag], false, [1]),
            e(3, 300, "\(classFlag.name)を降下", [classFlag], false, [0])
        ]
    }

    static let profiles: [Profile] = [
        Profile(id: "standard-start", name: "帆走スタート（Rule 26・5分＋橙旗）", events: standardStart(classFlag: flag("class-4"), prepFlag: flag("P")), baseDurationMinutes: 14),
        Profile(id: "video-20", name: "動画A（0・5・6・9・10・20分）", events: video20),
        Profile(id: "video-13", name: "動画B（0・4・5・8・9・13分）", events: video13(classFlag: flag("class-4")), baseDurationMinutes: 13),
        Profile(id: "custom-five", name: "5分シーケンス（旗を選択）", events: customFive(classFlag: flag("class-1"), prepFlag: flag("P")), baseDurationMinutes: 5),
        Profile(id: "class-p", name: "カスタム（クラス旗＋P旗）", events: customFive(classFlag: flag("class-1"), prepFlag: flag("P")), baseDurationMinutes: 5),
        Profile(id: "class-i", name: "カスタム（クラス旗＋I旗）", events: customFive(classFlag: flag("class-1"), prepFlag: flag("I")), baseDurationMinutes: 5)
    ]

    static func events(durationMinutes: Int = 20, profileID: String = "standard-start", classFlagID: String = "class-4", prepFlagID: String = "P") -> [Event] {
        switch profileID {
        case "standard-start":
            return applyOrangeSettings(standardStart(classFlag: flag(classFlagID), prepFlag: flag(prepFlagID)), profileID: profileID)
        case "video-13":
            return applyOrangeSettings(video13(classFlag: flag(classFlagID)), profileID: profileID)
        case "custom-five":
            return customFive(classFlag: flag(classFlagID), prepFlag: flag(prepFlagID))
        case "class-p":
            return customFive(classFlag: flag("class-1"), prepFlag: flag("P"))
        case "class-i":
            return customFive(classFlag: flag("class-1"), prepFlag: flag("I"))
        default:
            return applyOrangeSettings(video20, profileID: profileID)
        }
    }

    /// Select the pre-start row highlighted in each reference recording.
    static func initialEventIndex(durationMinutes: Int = 20, profileID: String = "standard-start") -> Int {
        let list = events(durationMinutes: durationMinutes, profileID: profileID)
        guard !list.isEmpty else { return 0 }
        let highlightedSecond = profileID == "standard-start" ? 0 : (profileID == "video-13" ? 540 : (profileID == "custom-five" ? 240 : 600))
        return list.firstIndex { $0.secondsAfterStart == highlightedSecond } ?? (list.count - 1)
    }

    static func activeEventIndex(elapsed: Double, durationMinutes: Int = 20, profileID: String = "standard-start", classFlagID: String = "class-4", prepFlagID: String = "P") -> Int {
        let list = events(durationMinutes: durationMinutes, profileID: profileID, classFlagID: classFlagID, prepFlagID: prepFlagID)
        guard !list.isEmpty else { return 0 }
        return list.lastIndex { Double($0.secondsAfterStart) <= elapsed } ?? 0
    }

    /// Resolves simultaneous raise/lower calls by the individual flag identity.
    static func raisedFlags(events: [Event], elapsed: Double) -> [Flag] {
        var raised: [String: Flag] = [:]
        for event in events where Double(event.secondsAfterStart) <= elapsed {
            for flag in event.flags {
                if event.raised { raised[flag.id] = flag }
                else { raised.removeValue(forKey: flag.id) }
            }
        }
        return raised.values.sorted { $0.id < $1.id }
    }

    static func flags(elapsed: Double, durationMinutes: Int = 20, profileID: String = "standard-start", classFlagID: String = "class-4", prepFlagID: String = "P") -> [Flag] {
        raisedFlags(events: events(durationMinutes: durationMinutes, profileID: profileID, classFlagID: classFlagID, prepFlagID: prepFlagID), elapsed: elapsed)
    }

    static func clockText(_ date: Date, offset: Double = 0) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date.addingTimeInterval(offset))
    }
}
