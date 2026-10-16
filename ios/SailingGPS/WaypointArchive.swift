import Foundation

enum WaypointArchive {
    static let maxBytes = 8 * 1024 * 1024
    static let maxCount = 10000
    struct Entry: Codable, Equatable {
        var id: UUID
        var name: String
        var latitude: Double
        var longitude: Double
        var mark: String
        var color: String
        var note: String?
        var group: String? = nil
        func sameContent(_ other: Entry) -> Bool {
            ((group ?? "").isEmpty ? "メインフォルダ" : group!) == ((other.group ?? "").isEmpty ? "メインフォルダ" : other.group!) && name == other.name && latitude == other.latitude && longitude == other.longitude && mark == other.mark && color.uppercased() == other.color.uppercased() && (note ?? "") == (other.note ?? "")
        }
    }
    private struct File: Codable {
        var format = "sailing-gps-waypoints"
        var version = 1
        var waypoints: [Entry]
    }
    enum ArchiveError: LocalizedError {
        case invalid
        var errorDescription: String? { "対応していない形式、無効な地点、または上限（8MB・10000件）を超えています。" }
    }
    static func validate(_ entries: [Entry]) throws {
        guard entries.count <= maxCount else { throw ArchiveError.invalid }
        for e in entries {
            guard e.latitude.isFinite, e.longitude.isFinite, (-90...90).contains(e.latitude), (-180...180).contains(e.longitude),
                  !e.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, e.name.utf8.count <= 1000,
                  e.mark.utf8.count <= 256, e.mark.hasPrefix("text:") || e.mark.hasPrefix("symbol:"),
                  e.color.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil, (e.note ?? "").utf8.count <= 100000 else { throw ArchiveError.invalid }
        }
    }
    static func encode(_ entries: [Entry]) throws -> Data {
        try validate(entries)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(File(waypoints: entries))
        guard data.count <= maxBytes else { throw ArchiveError.invalid }; return data
    }
    static func decode(_ data: Data) throws -> [Entry] {
        guard data.count <= maxBytes else { throw ArchiveError.invalid }
        let file = try JSONDecoder().decode(File.self, from: data)
        guard file.format == "sailing-gps-waypoints", file.version == 1 else { throw ArchiveError.invalid }
        try validate(file.waypoints); return file.waypoints
    }
    static func merge(existing: [Entry], incoming: [Entry]) throws -> (entries: [Entry], added: Int, skipped: Int) {
        try validate(incoming)
        var result = existing; var added = 0; var skipped = 0
        for var entry in incoming {
            if result.contains(where: { $0.sameContent(entry) }) { skipped += 1; continue }
            if result.contains(where: { $0.id == entry.id }) { entry.id = UUID() }
            result.append(entry); added += 1
        }
        guard result.count <= maxCount else { throw ArchiveError.invalid }
        return (result, added, skipped)
    }
}
