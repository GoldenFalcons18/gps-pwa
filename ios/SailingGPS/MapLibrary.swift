import Foundation

struct MapCoordinate: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    var valid: Bool { latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude) }
}
struct MapFeature: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var kind: String
    var waypointIDs: [UUID] = []
    var coordinates: [MapCoordinate] = []
    var radius = 200.0
    var color = "#00AAFF"
    var group = ""
    var visible = true
    func points(_ entries: [WaypointArchive.Entry]) -> [MapCoordinate] {
        if waypointIDs.isEmpty { return coordinates }
        return waypointIDs.compactMap { id in entries.first { $0.id == id }.map { MapCoordinate(latitude: $0.latitude, longitude: $0.longitude) } }
    }
    func boundary(_ entries: [WaypointArchive.Entry]) -> [MapCoordinate] {
        let p = points(entries)
        guard kind == "circle", let c = p.first else { return p }
        return (0...72).map { i in
            let value = CoordinateInput.destination(latitude: c.latitude, longitude: c.longitude, bearing: Double(i)*5, meters: radius)
            return MapCoordinate(latitude: value.latitude, longitude: value.longitude)
        }
    }
    func validate() throws {
        let count = waypointIDs.isEmpty ? coordinates.count : waypointIDs.count
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.utf8.count <= 1000,
              ["circle","area","line"].contains(kind), count >= (kind == "area" ? 3 : kind == "line" ? 2 : 1), count <= 10000,
              radius.isFinite, radius > 0, radius <= 1000000, coordinates.allSatisfy(\.valid),
              color.range(of:"^#[0-9A-Fa-f]{6}$",options:.regularExpression) != nil else { throw WaypointArchive.ArchiveError.invalid }
    }
}
struct MapLibrary: Codable, Equatable {
    var groups: [String] = []
    var hiddenGroups: [String] = []
    var features: [MapFeature] = []
    var groupColors: [String: String] = [:]

    private enum CodingKeys: String, CodingKey { case groups, hiddenGroups, features, groupColors }
    init(groups: [String] = [], hiddenGroups: [String] = [], features: [MapFeature] = [], groupColors: [String: String] = [:]) {
        self.groups = groups
        self.hiddenGroups = hiddenGroups
        self.features = features
        self.groupColors = groupColors
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        groups = try values.decodeIfPresent([String].self, forKey: .groups) ?? []
        hiddenGroups = try values.decodeIfPresent([String].self, forKey: .hiddenGroups) ?? []
        features = try values.decodeIfPresent([MapFeature].self, forKey: .features) ?? []
        groupColors = try values.decodeIfPresent([String: String].self, forKey: .groupColors) ?? [:]
    }
}

struct WaypointFolderColor: Identifiable {
    let name: String
    let hex: String
    var id: String { hex }
}

enum WaypointFolderColors {
    static let fallback = "#FFAA00"
    static let palette: [WaypointFolderColor] = [
        .init(name: "オレンジ", hex: "#FFAA00"), .init(name: "赤", hex: "#FF3333"), .init(name: "ピンク", hex: "#FF00D4"),
        .init(name: "紫", hex: "#9900AA"), .init(name: "水色", hex: "#00C8D7"), .init(name: "青", hex: "#2233FF"),
        .init(name: "緑", hex: "#00C820"), .init(name: "白", hex: "#FFFFFF")
    ]
    static func color(for folder: String, in library: MapLibrary) -> String {
        library.groupColors[folder] ?? fallback
    }
}


/// One rule shared by the displayed default and current-position saves.
enum DefaultWaypointFolder {
    static func resolve(requested:String?,folders:[String],waypointFolders:[String])->String {
        let populated=Array(Set(waypointFolders)).filter{!$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty}.sorted()
        let available=Set(folders+populated).filter{!$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty}.sorted()
        if let requested,available.contains(requested) { return requested }
        return populated.first ?? available.first ?? "メインフォルダ"
    }
    static func destination(explicit:String?,defaultFolder:String)->String {
        guard let explicit,!explicit.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { return defaultFolder }
        return explicit
    }
}
