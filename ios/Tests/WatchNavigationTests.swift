import XCTest
@testable import WatchNavigation

final class WatchNavigationTests: XCTestCase {
    func testBearingAcrossNorthAndEast() {
        XCTAssertEqual(WatchNavigationSnapshot.bearing(fromLat: 35, fromLon: 139, toLat: 36, toLon: 139), 0, accuracy: 0.01)
        XCTAssertEqual(WatchNavigationSnapshot.bearing(fromLat: 0, fromLon: 179, toLat: 0, toLon: -179), 90, accuracy: 0.01)
    }
    func testUnitsFreshnessAndRoundTrip() throws {
        let now = Date()
        var s = WatchNavigationSnapshot(name: "港", bearing: 90, distanceMeters: 1852, metric: false, locationTime: now, sentAt: now)
        XCTAssertEqual(s.distanceText, "1.00 nm")
        s.metric = true
        XCTAssertEqual(s.distanceText, "1.85 km")
        XCTAssertTrue(s.isFresh(at: now.addingTimeInterval(29)))
        XCTAssertFalse(s.isFresh(at: now.addingTimeInterval(31)))
        XCTAssertEqual(try JSONDecoder().decode(WatchNavigationSnapshot.self, from: JSONEncoder().encode(s)), s)
        s.locationTime = nil
        XCTAssertFalse(s.isFresh(at: now))
        s.name = nil
        XCTAssertFalse(s.hasTarget)
    }
}
