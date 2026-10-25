import XCTest
@testable import CoordinateInput

final class MapLibraryFolderColorTests: XCTestCase {
    func testFolderColorsRoundTripAndLegacyLibraryDecodes() throws {
        let library = MapLibrary(groups: ["Group A"], groupColors: ["Group A": "#12ABCD"])
        let data = try JSONEncoder().encode(library)
        XCTAssertEqual(try JSONDecoder().decode(MapLibrary.self, from: data).groupColors["Group A"], "#12ABCD")

        let legacy = Data("{\"groups\":[\"Old\"]}".utf8)
        XCTAssertTrue(try JSONDecoder().decode(MapLibrary.self, from: legacy).groupColors.isEmpty)
    }
}
