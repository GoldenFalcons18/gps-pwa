import XCTest
@testable import WatchNavigation

final class SignalSequenceTests: XCTestCase {
    func testStandardStartScheduleUsesRaceStartOffsetsAndRequestedHornSignals() {
        let events = SignalSequence.events(profileID: "standard-start", classFlagID: "class-4", prepFlagID: "P")

        XCTAssertEqual(events.map(\.secondsAfterStart), [0, 300, 360, 540, 600, 840])
        XCTAssertEqual(events.map(\.raised), [true, true, true, false, false])
        XCTAssertEqual(events.map(\.hornPulses), [[0], [0], [0], [1], [0]])
        XCTAssertEqual(events.map(\.title), [
            "橙旗を掲揚（予告信号の5分前）",
            "クラス旗 4を掲揚（予告信号・スタート5分前）",
            "P旗を掲揚（準備信号・スタート4分前）",
            "P旗を降下（スタート1分前）",
            "クラス旗 4を降下（スタート）",
            "橙旗を降下（スタート約4分後）"
        ])
    }

    func testStandardSequenceIsTheDefaultAndHighlightsOrangeFlagFirst() {
        XCTAssertEqual(SignalSequence.events().map(\.secondsAfterStart), [0, 300, 360, 540, 600])
        XCTAssertEqual(SignalSequence.initialEventIndex(), 0)
    }

    func testRecallRestartAndOrangeFlagRemovalTimes() {
        let restart = SignalSequence.recallRestartEvents(classFlagID: "class-4", prepFlagID: "P")
        XCTAssertEqual(restart.map(\.secondsAfterStart), [0, 60, 240, 300, 540])
        XCTAssertEqual(restart.map(\.hornPulses), [[0], [0], [1], [0], []])
        XCTAssertEqual(SignalSequence.flags(elapsed: 839, profileID: "standard-start").map(\.id), ["orange"])
        XCTAssertEqual(SignalSequence.flags(elapsed: 840, profileID: "standard-start"), [])
    }

    func testFlagsChangeAtTheScheduledBoundaries() {
        func ids(at elapsed: Double) -> [String] {
            SignalSequence.flags(elapsed: elapsed, profileID: "standard-start", classFlagID: "class-4", prepFlagID: "P")
                .map(\.id)
                .sorted()
        }

        XCTAssertEqual(ids(at: 299), ["orange"])
        XCTAssertEqual(ids(at: 300), ["class-4", "orange"])
        XCTAssertEqual(ids(at: 360), ["P", "class-4", "orange"])
        XCTAssertEqual(ids(at: 540), ["class-4", "orange"])
        XCTAssertEqual(ids(at: 600), ["orange"])
    }
}
