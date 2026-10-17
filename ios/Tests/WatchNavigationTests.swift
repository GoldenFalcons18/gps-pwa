import XCTest
@testable import WatchNavigation

final class WatchNavigationTests: XCTestCase {
    func testBearingAcrossNorthAndEast() {
        XCTAssertEqual(WatchNavigationSnapshot.bearing(fromLat: 35, fromLon: 139, toLat: 36, toLon: 139), 0, accuracy: 0.01)
        XCTAssertEqual(WatchNavigationSnapshot.bearing(fromLat: 0, fromLon: 179, toLat: 0, toLon: -179), 90, accuracy: 0.01)
    }
    func testUnitsFreshnessAndRoundTrip() throws {
        let now = Date()
        var s = WatchNavigationSnapshot(name: "貂ｯ", bearing: 90, distanceMeters: 1852, metric: false, locationTime: now, sentAt: now)
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
    func testMagneticReferenceAndNorthWrap() {
        XCTAssertEqual(WatchNavigationMath.magneticBearing(trueBearing: 144, trueHeading: 10, magneticHeading: 18), 152, accuracy: 0.001)
        XCTAssertEqual(WatchNavigationMath.unwrap(from: 359, to: 1), 361, accuracy: 0.001)
        XCTAssertEqual(WatchNavigationMath.unwrap(from: 1, to: 359), -1, accuracy: 0.001)
    }
    func testWatchFixAndSpeedValidity() {
        let now = Date()
        XCTAssertTrue(WatchNavigationMath.validFix(timestamp: now, accuracy: 10, now: now))
        XCTAssertFalse(WatchNavigationMath.validFix(timestamp: now.addingTimeInterval(-16), accuracy: 10, now: now))
        XCTAssertFalse(WatchNavigationMath.validFix(timestamp: now, accuracy: -1, now: now))
        XCTAssertEqual(WatchNavigationMath.speed(-1, metric: false), "—")
        XCTAssertEqual(WatchNavigationMath.speed(1, metric: false), "1.9")
        XCTAssertEqual(WatchNavigationMath.speed(1, metric: true), "3.6")
        XCTAssertEqual(WatchNavigationMath.distance(1852, metric: false), "1.00 nm")
    }
    func testCatalogContainsCoordinatesFoldersAndNoTarget() throws {
        let p = WatchWaypoint(id: "point-a", name: "灯台", latitude: 35, longitude: 139, folder: "障害物")
        let c = WatchWaypointCatalog(waypoints: [p], targetID: nil, metric: false, selectionChangedAt: Date(), sentAt: Date())
        XCTAssertEqual(try JSONDecoder().decode(WatchWaypointCatalog.self, from: JSONEncoder().encode(c)), c)
    }
}
