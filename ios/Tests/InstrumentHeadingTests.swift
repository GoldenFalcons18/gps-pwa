import XCTest
@testable import WatchNavigation

final class InstrumentHeadingTests:XCTestCase {
    func testCourseAndTargetUseSameMagneticCorrection() {
        let correction=InstrumentHeading.declination(magnetic:226,trueHeading:218)
        XCTAssertEqual(correction!,-8,accuracy:0.0001)
        XCTAssertEqual(InstrumentHeading.bearing(144,magnetic:true,declination:correction)!,152,accuracy:0.0001)
        let value=InstrumentHeading.resolve(course:230,speed:3,magneticHeading:226,trueHeading:218,magnetic:true)
        XCTAssertEqual(value,.init(value:238,compass:false))
        XCTAssertEqual(InstrumentHeading.resolve(course:230,speed:3,magneticHeading:226,trueHeading:218,magnetic:false),.init(value:230,compass:false))
    }
    func testMagneticCompassCanBeForcedWhileMovingAndFallsBackToGPS() {
        XCTAssertEqual(InstrumentHeading.resolve(course:230,speed:3,magneticHeading:226,trueHeading:218,magnetic:true,compassWhileMoving:true),.init(value:226,compass:true))
        XCTAssertEqual(InstrumentHeading.resolve(course:230,speed:3,magneticHeading:226,trueHeading:218,magnetic:false,compassWhileMoving:true),.init(value:218,compass:true))
        XCTAssertEqual(InstrumentHeading.resolve(course:230,speed:3,magneticHeading:nil,trueHeading:nil,magnetic:false,compassWhileMoving:true),.init(value:230,compass:false))
    }
    func testLowSpeedAndMissingCourseUseCompass() {
        for speed in [0.0,0.24,nil] as [Double?] {
            XCTAssertEqual(InstrumentHeading.resolve(course:82,speed:speed,magneticHeading:226,trueHeading:218,magnetic:true),.init(value:226,compass:true))
            XCTAssertEqual(InstrumentHeading.resolve(course:82,speed:speed,magneticHeading:226,trueHeading:218,magnetic:false),.init(value:218,compass:true))
        }
        XCTAssertEqual(InstrumentHeading.resolve(course:-1,speed:3,magneticHeading:226,trueHeading:218,magnetic:true),.init(value:226,compass:true))
    }
    func testMissingCompassDoesNotInventCorrection() {
        XCTAssertNil(InstrumentHeading.bearing(144,magnetic:true,declination:nil))
        XCTAssertEqual(InstrumentHeading.bearing(144,magnetic:false,declination:nil),144)
        XCTAssertNil(InstrumentHeading.resolve(course:82,speed:0,magneticHeading:nil,trueHeading:nil,magnetic:true))
        XCTAssertNil(InstrumentHeading.resolve(course:82,speed:3,magneticHeading:226,trueHeading:nil,magnetic:true))
        XCTAssertEqual(InstrumentHeading.resolve(course:82,speed:3,magneticHeading:nil,trueHeading:nil,magnetic:false),.init(value:82,compass:false))
    }
    func testNorthWrapAndInvalidAngles() {
        XCTAssertEqual(InstrumentHeading.bearing(2,magnetic:true,declination:8)!,354,accuracy:0.0001)
        XCTAssertEqual(InstrumentHeading.bearing(358,magnetic:true,declination:-8)!,6,accuracy:0.0001)
        XCTAssertNil(InstrumentHeading.bearing(.nan,magnetic:false,declination:0))
        XCTAssertNil(InstrumentHeading.declination(magnetic:-1,trueHeading:20))
    }
}
