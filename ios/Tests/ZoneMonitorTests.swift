import XCTest
@testable import CoordinateInput

final class ZoneMonitorTests:XCTestCase {
    let circle=ZoneMonitor.Zone(id:"reef",name:"障害物",circleRadius:100,points:[.init(latitude:0,longitude:0)])
    func testBaselineCrossingsAndDuplicateFixes() {
        var monitor=ZoneMonitor()
        func fix(_ longitude:Double,_ time:Double)->[ZoneMonitor.Event] {
            monitor.update(zones:[circle],point:.init(latitude:0,longitude:longitude),accuracy:5,timestamp:time,now:time,confirmations:2)
        }
        XCTAssertTrue(fix(0.002,1).isEmpty);XCTAssertTrue(fix(0.002,2).isEmpty)
        XCTAssertTrue(fix(0,3).isEmpty);XCTAssertTrue(fix(0,3).isEmpty)
        let entered=fix(0,4);XCTAssertEqual(entered.count,1);XCTAssertTrue(entered[0].entered)
        XCTAssertTrue(fix(0,5).isEmpty)
        XCTAssertTrue(fix(0.002,6).isEmpty);let exited=fix(0.002,7);XCTAssertEqual(exited.count,1);XCTAssertFalse(exited[0].entered)
    }
    func testUncertaintyAndBadAccuracyBreakConfirmation() {
        var monitor=ZoneMonitor()
        func fix(_ longitude:Double,_ time:Double,_ accuracy:Double=5,_ now:Double?=nil)->[ZoneMonitor.Event] {
            monitor.update(zones:[circle],point:.init(latitude:0,longitude:longitude),accuracy:accuracy,timestamp:time,now:now ?? time,confirmations:2)
        }
        _=fix(0.002,1);_=fix(0.002,2);_=fix(0,3)
        XCTAssertTrue(fix(0,4,100).isEmpty);XCTAssertTrue(fix(0,5).isEmpty)
        XCTAssertTrue(fix(0.0009,6).isEmpty);XCTAssertTrue(fix(0,7).isEmpty)
        XCTAssertTrue(fix(0,8,5,30).isEmpty);XCTAssertTrue(fix(0,31).isEmpty)
        XCTAssertEqual(fix(0,32).count,1)
    }
    func testChangedGeometryAndRemovedZonesResetBaseline() {
        var monitor=ZoneMonitor()
        for time in 1...2 {_=monitor.update(zones:[circle],point:.init(latitude:0,longitude:0.002),accuracy:5,timestamp:Double(time),now:Double(time),confirmations:2)}
        var changed=circle;changed.circleRadius=500
        for time in 3...4 {XCTAssertTrue(monitor.update(zones:[changed],point:.init(latitude:0,longitude:0),accuracy:5,timestamp:Double(time),now:Double(time),confirmations:2).isEmpty)}
        _=monitor.update(zones:[],point:.init(latitude:0,longitude:0),accuracy:5,timestamp:5,now:5)
        XCTAssertTrue(monitor.update(zones:[circle],point:.init(latitude:0,longitude:0.002),accuracy:5,timestamp:6,now:6,confirmations:1).isEmpty)
    }
    func testPolygonAndDateLine() {
        let polygon=ZoneMonitor.Zone(id:"area",name:"港",points:[.init(latitude:-0.01,longitude:179.99),.init(latitude:-0.01,longitude:-179.99),.init(latitude:0.01,longitude:-179.99),.init(latitude:0.01,longitude:179.99)])
        XCTAssertLessThan(polygon.clearance(.init(latitude:0,longitude:0))!,0)
        XCTAssertGreaterThan(polygon.clearance(.init(latitude:0,longitude:180))!,1000)
        XCTAssertLessThan(polygon.clearance(.init(latitude:0.02,longitude:180))!,-1000)
        XCTAssertEqual(polygon.clearance(.init(latitude:0.01,longitude:180))!,0,accuracy:0.001)
    }
    func testDisplayFormatsAndTwoDigitSpeeds() {
        XCTAssertEqual(InstrumentSettings.speedText(12.3,factor:1),"12.3")
        XCTAssertEqual(InstrumentSettings.speedText(99.9,factor:1),"99.9")
        XCTAssertEqual(InstrumentSettings.speedText(100,factor:1),"100.0")
        XCTAssertEqual(InstrumentSettings.speedText(.nan,factor:1),"—")
        XCTAssertEqual(InstrumentSettings.speedText(0.1,factor:1,zeroThreshold:0.25),"0.0")
        XCTAssertEqual(InstrumentSettings.coordinate(-35.5,isLatitude:true,format:"dd"),"35.500000°S")
        XCTAssertEqual(InstrumentSettings.coordinate(35.9999999,isLatitude:true,format:"dms"),"36°00′00.0″N")
        XCTAssertEqual(InstrumentSettings.arrival(distance:1000,speed:0,now:Date(),eta:true,twelveHour:false),"--:--:--")
    }
}
