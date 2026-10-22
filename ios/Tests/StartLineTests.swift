import XCTest
@testable import WatchNavigation

final class StartLineTests: XCTestCase {
    func testDistanceToSegmentAndBeyondEndpoints() {
        let west = StartLineCoordinate(latitude: 0, longitude: 0)
        let east = StartLineCoordinate(latitude: 0, longitude: 0.01)
        let midpoint = StartLineCoordinate(latitude: 0.001, longitude: 0.005)
        let distance = StartLineMath.distanceMeters(from: midpoint, outerMark: west, signalBoat: east)
        XCTAssertEqual(distance ?? -1, 111.2, accuracy: 1.0)

        let beyond = StartLineCoordinate(latitude: 0, longitude: -0.001)
        let beyondDistance = StartLineMath.distanceMeters(from: beyond, outerMark: west, signalBoat: east)
        XCTAssertEqual(beyondDistance ?? -1, 111.2, accuracy: 1.0)
    }

    func testMissingOrInvalidEndpointsAndCountdown() {
        let boat = StartLineCoordinate(latitude: 35, longitude: 139)
        XCTAssertNil(StartLineMath.distanceMeters(from: boat, outerMark: nil, signalBoat: boat))
        XCTAssertNil(StartLineMath.distanceMeters(from: boat, outerMark: boat, signalBoat: StartLineCoordinate(latitude: 91, longitude: 0)))
        XCTAssertEqual(StartLineMath.countdown(300), "05:00")
        XCTAssertEqual(StartLineMath.countdown(0.1), "00:01")
    }
}
