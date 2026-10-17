import XCTest
@testable import CoordinateInput
import ZIPFoundation

final class KmlArchiveTests: XCTestCase {
    let source = """
    <kml xmlns="http://www.opengis.net/kml/2.2"><Document><Style id="pin"><IconStyle><color>FF0080FF</color><Icon><href>http://maps.google.com/mapfiles/kml/pushpin/ylw-pushpin.png</href></Icon></IconStyle></Style><StyleMap id="normal"><Pair><key>normal</key><styleUrl>#pin</styleUrl></Pair></StyleMap><Folder><name>Group A</name><Placemark><name>A &amp; B</name><ExtendedData><SchemaData><SimpleData name="uuid">00000000-0000-0000-0000-000000000001</SimpleData></SchemaData></ExtendedData><description><![CDATA[note &lt;test&gt;]]></description><styleUrl>#normal</styleUrl><Point><coordinates>10,20,0</coordinates></Point></Placemark></Folder></Document></kml>
    """
    func testCompassMultiKmlAndStyles() throws {
        let zip=try Archive(accessMode:.create)
        let contents=["doc.kml":"<kml><Document><NetworkLink><Link><href>sub/doc.kml</href></Link></NetworkLink></Document></kml>","sub/doc.kml":source,"other/doc.kml":source.replacingOccurrences(of:"Group A",with:"Group B").replacingOccurrences(of:"000000000001",with:"000000000002")]
        for (name,content) in contents { let data=Data(content.utf8);try zip.addEntry(with:name,type:.file,uncompressedSize:Int64(data.count),compressionMethod:.deflate){position,size in data.subdata(in:Int(position)..<Int(position)+size)} }
        let result=try KmlArchive.decode(zip.data!)
        XCTAssertEqual(result.waypoints.count,2);XCTAssertEqual(Set(result.waypoints.compactMap(\.group)),Set(["Group A","Group B"]))
        XCTAssertEqual(result.waypoints[0].color,"#FF8000");XCTAssertEqual(result.waypoints[0].mark,"symbol:mappin")
    }
    func testFeatureRoundTripAndOldJsonCompatibility() throws {
        var points=try KmlArchive.decode(Data(source.utf8)).waypoints
        points += [.init(id:UUID(),name:"two",latitude:20.002,longitude:10.002,mark:"symbol:marine.net",color:"#12ABCD",group:"Group A"),.init(id:UUID(),name:"three",latitude:20,longitude:10.003,mark:"text:★",color:"#12ABCD",group:"Group A")]
        var circle=MapFeature(name:"circle",kind:"circle");circle.waypointIDs=[points[0].id];circle.radius=321.5
        var area=MapFeature(name:"area",kind:"area");area.waypointIDs=points.map(\.id)
        var line=MapFeature(name:"line",kind:"line");line.waypointIDs=Array(points.prefix(2)).map(\.id)
        for kmz in [false,true] {
            let result=try KmlArchive.decode(KmlArchive.encode(points,features:[circle,area,line],kmz:kmz))
            XCTAssertEqual(result.features.count,3);XCTAssertEqual(result.features.first{$0.kind=="circle"}?.radius,321.5)
            XCTAssertEqual(try WaypointArchive.merge(existing:points,incoming:result.waypoints).added,0)
        }
        let old="""
        {"format":"sailing-gps-waypoints","version":1,"waypoints":[{"id":"00000000-0000-0000-0000-000000000001","name":"old","latitude":1,"longitude":2,"mark":"symbol:flag.fill","color":"#FFAA00"}]}
        """
        XCTAssertNil(try WaypointArchive.decode(Data(old.utf8))[0].group)
    }
    func testRejectUnsafeXmlAndBadCoordinates() {
        XCTAssertThrowsError(try KmlArchive.decode(Data("<!DOCTYPE kml [<!ENTITY x SYSTEM 'file:///etc/passwd'>]><kml>&x;</kml>".utf8)))
        XCTAssertThrowsError(try KmlArchive.decode(Data(source.replacingOccurrences(of:"10,20,0",with:"10,200,0").utf8)))
    }
}
