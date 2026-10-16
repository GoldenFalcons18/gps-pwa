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
}
