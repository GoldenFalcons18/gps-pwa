import XCTest
@testable import WatchNavigation

final class SignalSequenceTests: XCTestCase {
    func testVideoSchedulesMatchReferenceTimesFlagStatesAndHornSignals() {
        let videoA = SignalSequence.events(profileID: "video-20")
        XCTAssertEqual(videoA.map(\.secondsAfterStart), [0, 300, 360, 540, 600, 1200])
        XCTAssertEqual(videoA.map { $0.flags.map(\.id) }, [["orange"], ["green"], ["blue-square"], ["blue-square"], ["green"], ["orange"]])
        XCTAssertEqual(videoA.map(\.raised), [true, true, true, false, false, false])
        XCTAssertEqual(videoA.map(\.hornPulses), [[0], [0], [0], [1], [0], []])

        let videoB = SignalSequence.events(profileID: "video-13")
        XCTAssertEqual(videoB.map(\.secondsAfterStart), [0, 240, 300, 480, 540, 780])
        XCTAssertEqual(videoB.map { $0.flags.map(\.id) }, [["orange"], ["class-4", "diagonal"], ["checker"], ["checker"], ["class-4", "diagonal"], ["orange"]])
        XCTAssertEqual(videoB.map(\.raised), [true, true, true, false, false, false])
        XCTAssertEqual(videoB.map(\.hornPulses), [[0], [0], [0], [1], [0], []])
    }

    func testSequenceZeroAlignsToRealMinuteAfterMinimumLeadTime() {
        XCTAssertEqual(SignalSequence.nextMinuteBoundary(at: 10, minimumLeadSeconds: 15), 60)
        XCTAssertEqual(SignalSequence.nextMinuteBoundary(at: 60, minimumLeadSeconds: 0), 60)
        XCTAssertEqual(SignalSequence.nextMinuteBoundary(at: 50, minimumLeadSeconds: 15), 120)
        XCTAssertEqual(SignalSequence.countdownSeconds(50.1), 51)
        XCTAssertEqual(SignalSequence.countdownSeconds(51.0), 51)
        XCTAssertEqual(SignalSequence.countdownSeconds(0.0), 0)
    }

    func testStandardStartScheduleUsesRaceStartOffsetsAndRequestedHornSignals() {
        let events = SignalSequence.events(profileID: "standard-start", classFlagID: "class-4", prepFlagID: "P")

        XCTAssertEqual(events.map(\.secondsAfterStart), [0, 300, 360, 540, 600, 840])
        XCTAssertEqual(events.map(\.raised), [true, true, true, false, false, false])
        XCTAssertEqual(events.map(\.hornPulses), [[0], [0], [0], [1], [0], []])
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
        XCTAssertEqual(SignalSequence.events().map(\.secondsAfterStart), [0, 300, 360, 540, 600, 840])
        XCTAssertEqual(SignalSequence.initialEventIndex(), 0)
    }

    func testRecallRestartAndOrangeFlagRemovalTimes() {
        let restart = SignalSequence.recallRestartEvents(classFlagID: "class-4", prepFlagID: "P")
        XCTAssertEqual(restart.map(\.secondsAfterStart), [0, 60, 240, 300, 540])
        XCTAssertEqual(restart.map(\.hornPulses), [[0], [0], [1], [0], []])
        XCTAssertEqual(SignalSequence.flags(elapsed: 839, profileID: "standard-start").map(\.id), ["orange"])
        XCTAssertEqual(SignalSequence.flags(elapsed: 840, profileID: "standard-start"), [])
    }

    func testRecallAndPostponementUseRequestedShortHornCounts() {
        XCTAssertEqual(SignalSequence.individualRecallRaise.flags.map(\.id), ["X"])
        XCTAssertEqual(SignalSequence.individualRecallRaise.hornPulses, [0])
        XCTAssertEqual(SignalSequence.generalRecallRaise.flags.map(\.id), ["first-sub"])
        XCTAssertEqual(SignalSequence.generalRecallRaise.hornPulses, [0, 0])
        XCTAssertEqual(SignalSequence.generalRecallLower.hornPulses, [0])
        XCTAssertEqual(SignalSequence.postponementRaise.flags.map(\.id), ["AP"])
        XCTAssertEqual(SignalSequence.postponementRaise.hornPulses, [0, 0])
        XCTAssertEqual(SignalSequence.postponementLower.hornPulses, [0])
    }

    func testAbandonAllUsesThreeShortSoundsAndLowerUsesOne() {
        XCTAssertEqual(SignalSequence.abandonRaise.hornPulses, [0, 0, 0])
        XCTAssertEqual(SignalSequence.abandonLower.hornPulses, [0])
        XCTAssertEqual(SignalSequence.nextMinuteBoundary(at: 125, minimumLeadSeconds: 0), 180)
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
