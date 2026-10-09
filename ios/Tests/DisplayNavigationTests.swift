import XCTest
@testable import CoordinateInput
final class DisplayNavigationTests: XCTestCase {
    func testGeodesicMarksAndDateline() {
        for distance in stride(from: 100, through: 500, by: 100) {
            let p = CoordinateInput.destination(latitude: 0, longitude: 179.999, bearing: 90, meters: Double(distance))
            let difference = (p.longitude - 179.999 + 360).truncatingRemainder(dividingBy: 360) * .pi / 180
            XCTAssertEqual(difference * 6371000, Double(distance), accuracy: 0.001)
            XCTAssertEqual(p.latitude, 0, accuracy: 0.000001)
        }
    }
    func testDistanceUnits() {
        XCTAssertEqual(CoordinateInput.distance(999, metric: true), "999 m")
        XCTAssertEqual(CoordinateInput.distance(1000, metric: true), "1.00 km")
        XCTAssertEqual(CoordinateInput.distance(1852, metric: false), "1.00 nm")
    }
}
