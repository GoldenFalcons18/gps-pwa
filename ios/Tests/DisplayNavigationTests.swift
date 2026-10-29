import XCTest
@testable import CoordinateInput
@testable import WatchNavigation
final class DisplayNavigationTests: XCTestCase {
    func testGeodesicMarksAndDateline() {
        for distance in stride(from: 100, through: 500, by: 100) {
            let p = CoordinateInput.destination(latitude: 0, longitude: 179.999, bearing: 90, meters: Double(distance))
            let difference = (p.longitude - 179.999 + 360).truncatingRemainder(dividingBy: 360) * .pi / 180
            XCTAssertEqual(difference * 6371000, Double(distance), accuracy: 0.001)
            XCTAssertEqual(p.latitude, 0, accuracy: 0.000001)
        }
    }
    func testFollowAnchorScalesWithZoom() {
        let close = CoordinateInput.followCenter(latitude: 0, longitude: 0, heading: 0, mapHeight: 400, pointsPerCm: 50, metersPerCm: 100)
        let far = CoordinateInput.followCenter(latitude: 0, longitude: 0, heading: 0, mapHeight: 400, pointsPerCm: 50, metersPerCm: 400)
        XCTAssertEqual(far.latitude, close.latitude * 4, accuracy: 0.000001)
        XCTAssertEqual(close.longitude, 0, accuracy: 0.000001)
    }
    func testDistanceUnits() {
        XCTAssertEqual(CoordinateInput.distance(999, metric: true), "999 m")
        XCTAssertEqual(CoordinateInput.distance(1000, metric: true), "1.00 km")
        XCTAssertEqual(CoordinateInput.distance(1852, metric: false), "1.00 nm")
    }
    func testInitialSignalRowSupportsLegacyFourEventProfiles() {
        let legacyEvents = SignalSequence.events(durationMinutes: 20, profileID: "class-p")
        let legacyIndex = SignalSequence.initialEventIndex(durationMinutes: 20, profileID: "class-p")
        XCTAssertEqual(legacyEvents.count, 4)
        XCTAssertTrue(legacyEvents.indices.contains(legacyIndex))
        XCTAssertEqual(legacyIndex, legacyEvents.count - 1)

        let videoEvents = SignalSequence.events(durationMinutes: 20, profileID: "video-20")
        let videoIndex = SignalSequence.initialEventIndex(durationMinutes: 20, profileID: "video-20")
        XCTAssertEqual(videoEvents[videoIndex].secondsAfterStart, 600)
    }

    func testVideoReferenceSequencesKeepExactElapsedCalls() {
        let videoA = SignalSequence.events(profileID: "video-20")
        XCTAssertEqual(videoA.map(\\.secondsAfterStart), [0, 300, 360, 540, 600, 1200])
        XCTAssertEqual(videoA.map(\\.hornPulses), [[0], [0], [0], [1], [0], []])

        let videoB = SignalSequence.events(profileID: "video-13")
        XCTAssertEqual(videoB.map(\\.secondsAfterStart), [0, 240, 300, 480, 540, 780])
        XCTAssertEqual(videoB[1].flags.map(\\.id), ["class-4", "diagonal"])
        XCTAssertEqual(videoB[4].flags.map(\\.id), ["class-4", "diagonal"])
    }

    func testVideoBCombinesAndLowersFlagsTogether() {
        XCTAssertEqual(SignalSequence.flags(elapsed: 239, profileID: "video-13").map(\\.id), ["orange"])
        XCTAssertEqual(SignalSequence.flags(elapsed: 240, profileID: "video-13").count, 3)
        XCTAssertEqual(SignalSequence.flags(elapsed: 480, profileID: "video-13").count, 2)
        XCTAssertEqual(SignalSequence.flags(elapsed: 540, profileID: "video-13").map(\\.id), ["orange", "checker"])
        XCTAssertEqual(SignalSequence.flags(elapsed: 780, profileID: "video-13"), [])
    }

    func testCustomSequenceCanChooseCommonRaceFlags() {
        XCTAssertGreaterThanOrEqual(SignalSequence.flagCatalog.count, 20)
        let events = SignalSequence.events(profileID: "custom-five", classFlagID: "class-10", prepFlagID: "U")
        XCTAssertEqual(events[0].flags.first?.id, "class-10")
        XCTAssertEqual(events[1].flags.first?.id, "U")
        XCTAssertEqual(events[0].secondsAfterStart, 0)
        XCTAssertEqual(events[3].secondsAfterStart, 300)
        XCTAssertEqual(SignalSequence.initialEventIndex(profileID: "video-13"), 4)
    }

}