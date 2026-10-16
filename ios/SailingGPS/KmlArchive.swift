import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import ZIPFoundation

enum KmlArchive {
    static let maxBytes = 32 * 1024 * 1024
    struct Import {
        var waypoints: [WaypointArchive.Entry] = []
        var features: [MapFeature] = []
        var warnings: [String] = []
    }
    final class Node {
        var name: String
        var attributes: [String:String]
        var text = ""
        var children: [Node] = []
        init(_ name: String, _ attributes: [String:String]) { self.name = name.components(separatedBy: ":").last!; self.attributes = attributes }
        func direct(_ name: String) -> Node? { children.first { $0.name == name } }
        func value(_ name: String) -> String { direct(name)?.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
        var content: String { text + children.map(\.content).joined() }
        func descendants(_ name: String) -> [Node] { children.flatMap { ($0.name == name ? [$0] : []) + $0.descendants(name) } }
    }
    final class Reader: NSObject, XMLParserDelegate {
        var root: Node?
        var stack: [Node] = []
        var count = 0
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String:String]) {
            count += 1
            guard stack.count < 64, count < 150000 else { parser.abortParsing(); return }
            let node = Node(elementName, attributes)
            if let parent = stack.last { parent.children.append(node) } else { root = node }
            stack.append(node)
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) { stack.last?.text += string }
        func parser(_ parser: XMLParser, foundCDATA data: Data) { stack.last?.text += String(decoding:data,as:UTF8.self) }
        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) { _ = stack.popLast() }
    }
    static func decode(_ data: Data) throws -> Import {
        guard data.count <= maxBytes else { throw WaypointArchive.ArchiveError.invalid }
        if data.starts(with: [0x50,0x4b]) {
            let archive = try Archive(data:data, accessMode:.read)
            var result = Import(), count = 0, expanded = 0, files = 0
            for entry in archive {
                count += 1; guard count <= 2000 else { throw WaypointArchive.ArchiveError.invalid }
                guard entry.type == .file, entry.path.lowercased().hasSuffix(".kml") else { continue }
                guard entry.uncompressedSize <= maxBytes else { throw WaypointArchive.ArchiveError.invalid }
                var xml = Data()
                let checksum = try archive.extract(entry) { chunk in
                    expanded += chunk.count
                    guard expanded <= maxBytes else { throw WaypointArchive.ArchiveError.invalid }
                    xml.append(chunk)
                }
                guard checksum == entry.checksum else { throw WaypointArchive.ArchiveError.invalid }
                let part = try parse(xml); result.waypoints += part.waypoints; result.features += part.features; result.warnings += part.warnings; files += 1
                guard result.waypoints.count <= 10000, result.features.count <= 1000 else { throw WaypointArchive.ArchiveError.invalid }
            }
            guard files > 0, !result.waypoints.isEmpty || !result.features.isEmpty else { throw WaypointArchive.ArchiveError.invalid }
            result.warnings = Array(Set(result.warnings)).sorted(); return result
        }
        let result = try parse(data)
        guard !result.waypoints.isEmpty || !result.features.isEmpty else { throw WaypointArchive.ArchiveError.invalid }
        return result
    }
    private static func coordinates(_ node: Node) throws -> [MapCoordinate] {
        let text = node.descendants("coordinates").first?.content ?? ""
        let points = try text.split(whereSeparator: { $0.isWhitespace }).map { row -> MapCoordinate in
            let a = row.split(separator:",",omittingEmptySubsequences:false)
            guard a.count >= 2, let lat = Double(a[1]), let lon = Double(a[0]) else { throw WaypointArchive.ArchiveError.invalid }
            let point = MapCoordinate(latitude:lat,longitude:lon)
            guard point.valid else { throw WaypointArchive.ArchiveError.invalid }; return point
        }
        guard points.count <= 10000 else { throw WaypointArchive.ArchiveError.invalid }; return points
    }
    private static func color(_ value: String?) -> String? {
        guard let value, value.range(of:"^[0-9A-Fa-f]{8}$",options:.regularExpression) != nil else { return nil }
        let a = Array(value); return "#" + String(a[6...7]) + String(a[4...5]) + String(a[2...3])
    }
    private static func parse(_ data: Data) throws -> Import {
        let raw = String(decoding:data,as:UTF8.self)
        guard !raw.uppercased().contains("<!DOCTYPE"), !raw.uppercased().contains("<!ENTITY") else { throw WaypointArchive.ArchiveError.invalid }
        let reader = Reader(), parser = XMLParser(data:data)
        parser.shouldResolveExternalEntities = false; parser.delegate = reader
        guard parser.parse(), let root = reader.root, root.name == "kml" else { throw WaypointArchive.ArchiveError.invalid }
        var result = Import()
        var styles: [String:Node] = [:], maps: [String:String] = [:]
        for s in root.descendants("Style") { if let id = s.attributes["id"] { styles[id] = s } }
        for s in root.descendants("StyleMap") { if let id = s.attributes["id"], let pair = s.descendants("Pair").first(where: { $0.value("key") == "normal" }) { maps[id] = String(pair.value("styleUrl").dropFirst()) } }
        func visit(_ node: Node, _ group: String) throws {
            let next = node.name == "Folder" ? [group,node.value("name")].filter { !$0.isEmpty }.joined(separator:" / ") : group
            if node.name == "Placemark" {
                let name = node.value("name").isEmpty ? "ウェイポイント" : node.value("name")
                var extras: [String:String] = [:]
                for d in node.descendants("Data") { if let k = d.attributes["name"] { extras[k] = d.value("value") } }
                for d in node.descendants("SimpleData") { if let k = d.attributes["name"] { extras[k] = d.content.trimmingCharacters(in:.whitespacesAndNewlines) } }
                let group = extras["sailing.group"] ?? group
                let styleID = String(node.value("styleUrl").dropFirst())
                let style = node.direct("Style") ?? styles[maps[styleID] ?? styleID]
                let rgb = extras["sailing.color"] ?? color(style?.descendants("color").first?.content) ?? "#FFAA00"
                let href = style?.descendants("href").first?.content ?? ""
                let mark = extras["sailing.mark"] ?? (href.contains("pushpin") ? "symbol:mappin" : "symbol:flag.fill")
                let id = UUID(uuidString:extras["sailing.id"] ?? extras["uuid"] ?? "") ?? UUID()
                let points = node.descendants("Point")
                for point in points {
                    let p = try coordinates(point); guard p.count == 1 else { throw WaypointArchive.ArchiveError.invalid }
                    result.waypoints.append(.init(id:points.count == 1 ? id : UUID(),name:name,latitude:p[0].latitude,longitude:p[0].longitude,mark:mark,color:rgb,note:node.value("description").isEmpty ? nil : node.value("description"),group:group))
                }
                let geometry = node.descendants("LineString") + node.descendants("Polygon")
                for (i,g) in geometry.enumerated() {
                    var points = try coordinates(g)
                    if g.name == "Polygon", points.first == points.last { points = Array(points.dropLast()) }
                    let kind = extras["sailing.kind"] ?? (g.name == "Polygon" ? "area" : "line")
                    var f = MapFeature(id:i == 0 ? id : UUID(),name:name,kind:kind)
                    if let rawIDs = extras["sailing.waypointIds"] { f.waypointIDs = rawIDs.split(separator:",").compactMap { UUID(uuidString:String($0)) } }
                    if kind == "circle", let rawCenter = extras["sailing.center"] {
                        let a = rawCenter.split(separator:",")
                        guard a.count == 2, let lat = Double(a[0]), let lon = Double(a[1]) else { throw WaypointArchive.ArchiveError.invalid }
                        points = [.init(latitude:lat,longitude:lon)]
                    }
                    f.coordinates = points; f.radius = Double(extras["sailing.radius"] ?? "200") ?? .nan; f.color = rgb; f.group = group
                    try f.validate(); result.features.append(f)
                    if !g.descendants("innerBoundaryIs").isEmpty { result.warnings.append("穴のあるエリアは外周のみ取り込みました") }
                }
                if !node.descendants("Track").isEmpty || !node.descendants("Model").isEmpty { result.warnings.append("軌跡時刻・3Dモデルは取り込み対象外です") }
                if !href.isEmpty && !href.contains("pushpin") && extras["sailing.mark"] == nil { result.warnings.append("外部アプリの画像マークは旗に置き換えました") }
                return
            }
            for child in node.children { try visit(child,next) }
        }
        try visit(root,""); try WaypointArchive.validate(result.waypoints)
        guard result.features.count <= 1000 else { throw WaypointArchive.ArchiveError.invalid }
        return result
    }
    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;").replacingOccurrences(of:">",with:"&gt;").replacingOccurrences(of:"\"",with:"&quot;").replacingOccurrences(of:"'",with:"&apos;")
    }
    private static func kmlColor(_ rgb: String, _ alpha: String = "ff") -> String { let a = Array(rgb); return alpha + String(a[5...6]) + String(a[3...4]) + String(a[1...2]) }
    static func encode(_ points: [WaypointArchive.Entry], features: [MapFeature], kmz: Bool) throws -> Data {
        try WaypointArchive.validate(points); for f in features { try f.validate() }
        func extra(_ k:String,_ v:String)->String { "<Data name=\"\(k)\"><value>\(escape(v))</value></Data>" }
        func coord(_ p:[MapCoordinate])->String { p.map { "\($0.longitude),\($0.latitude),0" }.joined(separator:" ") }
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><kml xmlns=\"http://www.opengis.net/kml/2.2\"><Document><name>Sailing GPS Logger</name>"
        let groups = Set(points.map { $0.group ?? "" } + features.map(\.group)).sorted()
        for group in groups {
            if !group.isEmpty { xml += "<Folder><name>\(escape(group))</name>" }
            for w in points where (w.group ?? "") == group {
                xml += "<Placemark><name>\(escape(w.name))</name><description>\(escape(w.note ?? ""))</description><Style><IconStyle><color>\(kmlColor(w.color))</color></IconStyle></Style><ExtendedData>"
                xml += extra("sailing.id",w.id.uuidString) + extra("sailing.group",group) + extra("sailing.color",w.color) + extra("sailing.mark",w.mark)
                xml += "</ExtendedData><Point><coordinates>\(w.longitude),\(w.latitude),0</coordinates></Point></Placemark>"
            }
            for f in features where f.group == group {
                let p = f.boundary(points); guard p.count >= 2 else { continue }
                xml += "<Placemark><name>\(escape(f.name))</name><Style><LineStyle><color>\(kmlColor(f.color))</color><width>3</width></LineStyle><PolyStyle><color>\(kmlColor(f.color,"40"))</color></PolyStyle></Style><ExtendedData>"
                xml += extra("sailing.id",f.id.uuidString) + extra("sailing.group",group) + extra("sailing.color",f.color) + extra("sailing.kind",f.kind) + extra("sailing.radius",String(f.radius)) + extra("sailing.waypointIds",f.waypointIDs.map(\.uuidString).joined(separator:","))
                if let c = f.points(points).first { xml += extra("sailing.center","\(c.latitude),\(c.longitude)") }; xml += "</ExtendedData>"
                if f.kind == "line" { xml += "<LineString><tessellate>1</tessellate><coordinates>\(coord(p))</coordinates></LineString>" }
                else { xml += "<Polygon><outerBoundaryIs><LinearRing><coordinates>\(coord(p + [p[0]]))</coordinates></LinearRing></outerBoundaryIs></Polygon>" }
                xml += "</Placemark>"
            }
            if !group.isEmpty { xml += "</Folder>" }
        }
        xml += "</Document></kml>"; let data = Data(xml.utf8)
        guard data.count <= maxBytes else { throw WaypointArchive.ArchiveError.invalid }
        if !kmz { return data }
        let archive = try Archive(accessMode:.create)
        try archive.addEntry(with:"doc.kml",type:.file,uncompressedSize:Int64(data.count),compressionMethod:.deflate) { position,size in data.subdata(in:Int(position)..<Int(position)+size) }
        guard let output = archive.data else { throw WaypointArchive.ArchiveError.invalid }; return output
    }
}
