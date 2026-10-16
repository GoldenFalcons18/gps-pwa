import XCTest
@testable import CoordinateInput

final class DefaultWaypointFolderTests:XCTestCase {
    func testSelectedEmptyFolderIsDefaultForCurrentPosition() {
        XCTAssertEqual(DefaultWaypointFolder.resolve(requested:"B",folders:["A","B"],waypointFolders:["A"]),"B")
    }
    func testUnsetOrDeletedDefaultUsesSameStableChoiceRegardlessOfPointOrder() {
        let requests:[String?]=[nil,"","deleted"]
        for requested in requests {
            XCTAssertEqual(DefaultWaypointFolder.resolve(requested:requested,folders:[],waypointFolders:["Z","A"]),"A")
            XCTAssertEqual(DefaultWaypointFolder.resolve(requested:requested,folders:[],waypointFolders:["A","Z"]),"A")
        }
    }
    func testNoPointsUsesExistingFolderAndEmptyLibraryGetsFallback() {
        XCTAssertEqual(DefaultWaypointFolder.resolve(requested:nil,folders:["B","A"],waypointFolders:[]),"A")
        XCTAssertEqual(DefaultWaypointFolder.resolve(requested:nil,folders:[],waypointFolders:[]),"メインフォルダ")
    }
    func testEditorChoiceIsKeptAndUnassignedCurrentPositionUsesDefault() {
        XCTAssertEqual(DefaultWaypointFolder.destination(explicit:"C",defaultFolder:"B"),"C")
        XCTAssertEqual(DefaultWaypointFolder.destination(explicit:nil,defaultFolder:"B"),"B")
        XCTAssertEqual(DefaultWaypointFolder.destination(explicit:" ",defaultFolder:"B"),"B")
    }
}
