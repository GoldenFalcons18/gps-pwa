import XCTest
@testable import CoordinateInput

final class HarborMarkTests:XCTestCase {
    func testHarborSurvivesJsonAndKmz() throws {
        let point=WaypointArchive.Entry(id:UUID(),name:"港",latitude:35,longitude:139,mark:"symbol:marine.harbor",color:"#12ABCD",note:nil,group:"港一覧")
        let json=try WaypointArchive.decode(WaypointArchive.encode([point]))
        let kmz=try KmlArchive.decode(KmlArchive.encode([point],features:[],kmz:true)).waypoints
        for restored in [json,kmz] {
            XCTAssertEqual(restored.count,1)
            XCTAssertEqual(restored[0].mark,point.mark)
            XCTAssertEqual(restored[0].color,point.color)
            XCTAssertEqual(restored[0].group,point.group)
        }
    }
}
