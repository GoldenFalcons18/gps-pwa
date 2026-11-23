import XCTest
@testable import CoordinateInput

final class SailingSpeedBandTests: XCTestCase {
    func testSpeedBelowTarget() {
        XCTAssertEqual(InstrumentSettings.sailingSpeedBand(current: 4.94, target: 5.0, enabled: true), .belowTarget)
    }

    func testDisplayedEqualSpeed() {
        XCTAssertEqual(InstrumentSettings.sailingSpeedBand(current: 4.96, target: 5.0, enabled: true), .approximatelyTarget)
    }

    func testSpeedAboveTarget() {
        XCTAssertEqual(InstrumentSettings.sailingSpeedBand(current: 5.06, target: 5.0, enabled: true), .aboveTarget)
    }

    func testDisabledKeepsExistingGreenBand() {
        XCTAssertEqual(InstrumentSettings.sailingSpeedBand(current: 1.0, target: 5.0, enabled: false), .aboveTarget)
    }

    func testMissingSpeedIsUnavailable() {
        XCTAssertEqual(InstrumentSettings.sailingSpeedBand(current: nil, target: 5.0, enabled: true), .unavailable)
    }
}
