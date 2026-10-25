import XCTest
@testable import CoordinateInput

final class CoordinateInputTests: XCTestCase {
    func testLowerBoatAnchorLooksAhead() {
        let north = CoordinateInput.followCenter(latitude: 0, longitude: 0, heading: 0, mapHeight: 600, pointsPerCm: 100)
        let south = CoordinateInput.followCenter(latitude: 0, longitude: 0, heading: 180, mapHeight: 600, pointsPerCm: 100)
        let east = CoordinateInput.followCenter(latitude: 0, longitude: 0, heading: 90, mapHeight: 600, pointsPerCm: 100)
        XCTAssertEqual(north.latitude * .pi / 180 * 6371000, 264, accuracy: 0.01)
        XCTAssertEqual(south.latitude, -north.latitude, accuracy: 0.0000001)
        XCTAssertEqual(east.longitude, north.latitude, accuracy: 0.0000001)
    }

    func testCoordinateWheels() {
        XCTAssertEqual(CoordinateInput.wheelRows(35 + 19.528 / 60, latitude: true, format: 1), [35,19,5,2,8,0])
        XCTAssertEqual(CoordinateInput.wheelValue([139,27,1,3,0,0], latitude: false, format: 1), 139 + 27.130/60, accuracy: 1e-10)
        for format in 0...2 {
            for value in [0.0, -0.0, 35.3254666667, -35.3254666667, 90.0, -90.0] {
                let rows = CoordinateInput.wheelRows(value, latitude: true, format: format)
                XCTAssertEqual(CoordinateInput.wheelValue(rows, latitude: true, format: format), value, accuracy: 0.000009)
            }
        }
        XCTAssertEqual(CoordinateInput.wheelValue([90,59,9,9,9,0], latitude: true, format: 1), 90)
        XCTAssertEqual(CoordinateInput.wheelValue([180,59,59,9,9,1], latitude: false, format: 2), -180)
        XCTAssertEqual(CoordinateInput.wheelValue([0,0,0,0,0,1], latitude: true, format: 1).sign, .minus)
    }

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
        XCTAssertEqual(try XCTUnwrap(second.trueHeading), 111.1, accuracy: 0.0001)
        XCTAssertEqual(132.1 - (try XCTUnwrap(first.trueHeading)), 140 - first.heading, accuracy: 0.0001)
        XCTAssertFalse(try XCTUnwrap(CoordinateInput.headingReference(preferGps: true, magnetic: 26, trueHeading: 18.1, course: 200, speed: 3)).magnetic)
        XCTAssertTrue(try XCTUnwrap(CoordinateInput.headingReference(preferGps: true, magnetic: 26, trueHeading: 18.1, course: 200, speed: 0)).magnetic)
        let forced = try XCTUnwrap(CoordinateInput.headingReference(preferGps: true, magnetic: 26, trueHeading: 18.1, course: 200, speed: 3, compassWhileMoving: true))
        XCTAssertTrue(forced.magnetic)
        XCTAssertEqual(try XCTUnwrap(forced.trueHeading),18.1,accuracy:0.0001)
        XCTAssertFalse(try XCTUnwrap(CoordinateInput.headingReference(preferGps: true, magnetic: nil, trueHeading: nil, course: 200, speed: 3, compassWhileMoving: true)).magnetic)
        XCTAssertNil(CoordinateInput.headingReference(preferGps: true, magnetic: nil, trueHeading: nil, course: -1, speed: 3))
        XCTAssertEqual(CoordinateInput.unwrapHeading(from: 359, to: 1), 361)
        XCTAssertEqual(CoordinateInput.unwrapHeading(from: 1, to: 359), -1)
    }
}
