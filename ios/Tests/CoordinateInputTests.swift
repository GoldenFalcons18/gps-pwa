import XCTest
@testable import CoordinateInput

final class CoordinateInputTests: XCTestCase {
    func testHemisphereConversion() throws {
        let cases: [(String, Bool, String, String, Double)] = [
            ("N", true, "35", "19.046", 35 + 19.046 / 60),
            ("S", true, "35", "19.046", -(35 + 19.046 / 60)),
            ("E", false, "139", "27.966", 139 + 27.966 / 60),
            ("W", false, "139", "27.966", -(139 + 27.966 / 60))
        ]
        for (direction, latitude, degree, minute, expected) in cases {
            XCTAssertEqual(try XCTUnwrap(CoordinateInput.decimal(degrees: degree, minutes: minute, direction: direction, isLatitude: latitude)), expected, accuracy: 1e-10)
        }
    }

    func testBoundariesAndInvalidInput() {
        XCTAssertEqual(CoordinateInput.decimal(degrees: "90", minutes: "0", direction: "N", isLatitude: true), 90)
        XCTAssertEqual(CoordinateInput.decimal(degrees: "180", minutes: "0", direction: "W", isLatitude: false), -180)
        for (degrees, minutes) in [("90", "0.001"), ("91", "0"), ("35", "60"), ("-1", "0"), ("35.5", "0"), ("", "0"), ("35", ""), ("35", "nan"), ("35", "inf"), ("35", "-1"), ("35", "1e2")] {
            XCTAssertNil(CoordinateInput.decimal(degrees: degrees, minutes: minutes, direction: "N", isLatitude: true))
        }
        XCTAssertNil(CoordinateInput.decimal(degrees: "180", minutes: "1", direction: "E", isLatitude: false))
        XCTAssertNil(CoordinateInput.decimal(degrees: "181", minutes: "0", direction: "E", isLatitude: false))
        XCTAssertNil(CoordinateInput.decimal(degrees: "35", minutes: "0", direction: "E", isLatitude: true))
        XCTAssertEqual(CoordinateInput.decimal(degrees: " 0 ", minutes: "0", direction: "S", isLatitude: true), 0)
    }

    func testDisplayAndMinuteRollover() {
        XCTAssertEqual(CoordinateInput.format(35 + 19.046 / 60, isLatitude: true), "35°19.0460′N")
        XCTAssertEqual(CoordinateInput.format(-(139 + 27.966 / 60), isLatitude: false), "139°27.9660′W")
        XCTAssertEqual(CoordinateInput.format(35 + 59.99999 / 60, isLatitude: true), "36°0.0000′N")
    }

    func testHeadingReferenceAndNorthCrossing() throws {
        let first = try XCTUnwrap(CoordinateInput.headingReference(preferGps: false, magnetic: 26, trueHeading: 18.1, course: 200, speed: 3))
        let second = try XCTUnwrap(CoordinateInput.headingReference(preferGps: false, magnetic: 119, trueHeading: 111.1, course: 200, speed: 3))
        XCTAssertTrue(first.magnetic)
        XCTAssertEqual(first.heading, 26)
        XCTAssertEqual(try XCTUnwrap(second.trueHeading), 111.1)
        XCTAssertEqual(132.1 - (try XCTUnwrap(first.trueHeading)), 140 - first.heading, accuracy: 0.0001)
        XCTAssertFalse(try XCTUnwrap(CoordinateInput.headingReference(preferGps: true, magnetic: 26, trueHeading: 18.1, course: 200, speed: 3)).magnetic)
        XCTAssertTrue(try XCTUnwrap(CoordinateInput.headingReference(preferGps: true, magnetic: 26, trueHeading: 18.1, course: 200, speed: 0)).magnetic)
        XCTAssertNil(CoordinateInput.headingReference(preferGps: true, magnetic: nil, trueHeading: nil, course: -1, speed: 3))
        XCTAssertEqual(CoordinateInput.unwrapHeading(from: 359, to: 1), 361)
        XCTAssertEqual(CoordinateInput.unwrapHeading(from: 1, to: 359), -1)
    }
}
