import XCTest
@testable import CoordinateInput

final class NavigationEteTests: XCTestCase {
    func testTravelTimeAndRounding() {
        XCTAssertEqual(CoordinateInput.ete(distanceMeters: 1000, speedMps: 2), "00:08:20")
        XCTAssertEqual(CoordinateInput.ete(distanceMeters: 3661, speedMps: 1), "01:01:01")
        XCTAssertEqual(CoordinateInput.ete(distanceMeters: 0.1, speedMps: 1), "00:00:01")
        XCTAssertEqual(CoordinateInput.ete(distanceMeters: 0, speedMps: nil), "00:00:00")
        XCTAssertEqual(CoordinateInput.ete(distanceMeters: 1, speedMps: 0.25), "00:00:04")
    }
    func testMissingOrUnreliableData() {
        let speeds: [Double?] = [nil, 0, -1, 0.24, .nan, .infinity]
        for speed in speeds { XCTAssertEqual(CoordinateInput.ete(distanceMeters: 1000, speedMps: speed), "--:--:--") }
        let distances: [Double?] = [nil, -1, .nan, .infinity, .greatestFiniteMagnitude]
        for distance in distances { XCTAssertEqual(CoordinateInput.ete(distanceMeters: distance, speedMps: 1), "--:--:--") }
    }
}
