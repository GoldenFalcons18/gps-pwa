import SwiftUI
import CoreLocation

private struct WindMarkPoint: Codable {
    var time: String
    var mark_a_latitude: Double
    var mark_a_longitude: Double
    var mark_b_latitude: Double
    var mark_b_longitude: Double
}

private struct WindObservation: Codable {
    var time: String
    var latitude: Double
    var longitude: Double
    var wind_from_deg: Double
    var wind_speed_kn: Double
}

/// Wind readings are entered by the sailor; GPS supplies the observation position.
/// Marks A and B are captured independently from the current GPS fix.
struct WindMarkLogView: View {
    @ObservedObject var gps: GPSRecorder
    var onClose: () -> Void

    @State private var selectedLog = 0
    @State private var markA: CLLocationCoordinate2D?
    @State private var markB: CLLocationCoordinate2D?
    @State private var windDirection = ""
    @State private var windSpeed = ""
    @State private var markRows: [WindMarkPoint] = []
    @State private var windRows: [WindObservation] = []
    @State private var notice = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("記録", selection: $selectedLog) {
                    Text("マーク").tag(0)
                    Text("風").tag(1)
                }.pickerStyle(.segmented)

                if selectedLog == 0 {
                    Section("マーク位置") {
                        Text("現在地: " + coordinateText(gps.location?.coordinate))
                            .font(.footnote).foregroundStyle(gps.location == nil ? .orange : .secondary)
                        HStack {
                            Text("A").font(.headline).frame(width: 28)
                            Text(coordinateText(markA)).font(.footnote.monospacedDigit())
                            Spacer()
                            Button("A点を記録") { captureMark(isA: true) }
                                .buttonStyle(.borderedProminent).tint(.orange)
                        }
                        HStack {
                            Text("B").font(.headline).frame(width: 28)
                            Text(coordinateText(markB)).font(.footnote.monospacedDigit())
                            Spacer()
                            Button("B点を記録") { captureMark(isA: false) }
                                .buttonStyle(.borderedProminent).tint(.orange)
                        }
                        Button("このA・B位置を記録", systemImage: "mappin.and.ellipse") { saveMarks() }
                            .disabled(markA == nil || markB == nil)
                    }
                    Section("記録済み: \(markRows.count)組") {
                        ShareLinkButton(title: "マークCSVを共有", url: exportMarks())
                    }
                } else {
                    Section("風の記録") {
                        Text("記録位置: " + coordinateText(gps.location?.coordinate))
                            .font(.footnote).foregroundStyle(gps.location == nil ? .orange : .secondary)
                        HStack {
                            Text("風向（風上の方位）")
                            Spacer()
                            TextField("0–359", text: $windDirection).keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing).frame(width: 100)
                            Text("°")
                        }
                        HStack {
                            Text("風速")
                            Spacer()
                            TextField("例 8.5", text: $windSpeed).keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing).frame(width: 100)
                            Text("kn")
                        }
                        Button("現在地で風を記録", systemImage: "wind") { saveWind() }
                            .disabled(gps.location == nil)
                    }
                    Section("記録済み: \(windRows.count)件") {
                        ShareLinkButton(title: "風CSVを共有", url: exportWind())
                    }
                }
                if !notice.isEmpty {
                    Section { Text(notice).foregroundStyle(.orange) }
                }
            }
            .navigationTitle("風・マーク記録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了", action: onClose).foregroundStyle(.orange)
                }
            }
            .onAppear(perform: loadRows)
        }
        .preferredColorScheme(.dark)
    }

    private func captureMark(isA: Bool) {
        guard let coordinate = gps.location?.coordinate else { notice = "GPS位置を取得できません"; return }
        if isA { markA = coordinate } else { markB = coordinate }
        notice = isA ? "A点を記録しました" : "B点を記録しました"
    }

    private func saveMarks() {
        guard let a = markA, let b = markB else { notice = "A点とB点を記録してください"; return }
        markRows.append(WindMarkPoint(time: timestamp(), mark_a_latitude: a.latitude, mark_a_longitude: a.longitude,
                                      mark_b_latitude: b.latitude, mark_b_longitude: b.longitude))
        save(markRows, name: "mark-log.json")
        notice = "マーク位置を保存しました"
    }

    private func saveWind() {
        guard let location = gps.location else { notice = "GPS位置を取得できません"; return }
        guard let direction = Double(windDirection), (0...360).contains(direction),
              let speed = Double(windSpeed), speed >= 0 else {
            notice = "風向は0〜360°、風速は0以上の数値を入力してください"
            return
        }
        windRows.append(WindObservation(time: timestamp(), latitude: location.coordinate.latitude,
                                        longitude: location.coordinate.longitude, wind_from_deg: direction == 360 ? 0 : direction,
                                        wind_speed_kn: speed))
        save(windRows, name: "wind-log.json")
        notice = "風を保存しました"
    }

    private func loadRows() {
        markRows = load("mark-log.json", as: [WindMarkPoint].self)
        windRows = load("wind-log.json", as: [WindObservation].self)
    }

    private func load<T: Decodable>(_ name: String, as type: T.Type) -> T {
        guard let url = dataDirectory()?.appendingPathComponent(name),
              let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(type, from: data) else { return [] as! T }
        return value
    }

    private func save<T: Encodable>(_ value: T, name: String) {
        do {
            guard let url = dataDirectory()?.appendingPathComponent(name) else { throw CocoaError(.fileNoSuchFile) }
            try JSONEncoder().encode(value).write(to: url, options: .atomic)
        } catch { notice = "保存に失敗しました: \(error.localizedDescription)" }
    }

    private func dataDirectory() -> URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let dir = docs.appendingPathComponent("wind-mark-logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func exportMarks() -> URL {
        let rows = load("mark-log.json", as: [WindMarkPoint].self)
        let body = (["time,mark_a_latitude,mark_a_longitude,mark_b_latitude,mark_b_longitude"] + rows.map {
            "\($0.time),\(number($0.mark_a_latitude)),\(number($0.mark_a_longitude)),\(number($0.mark_b_latitude)),\(number($0.mark_b_longitude))"
        }).joined(separator: "\n") + "\n"
        return export(body, filename: "mark-log.csv")
    }

    private func exportWind() -> URL {
        let rows = load("wind-log.json", as: [WindObservation].self)
        let body = (["time,latitude,longitude,wind_from_deg,wind_speed_kn"] + rows.map {
            "\($0.time),\(number($0.latitude)),\(number($0.longitude)),\(number($0.wind_from_deg)),\(number($0.wind_speed_kn))"
        }).joined(separator: "\n") + "\n"
        return export(body, filename: "wind-log.csv")
    }

    private func export(_ text: String, filename: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? text.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }

    private func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private func number(_ value: Double) -> String { String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value) }

    private func coordinateText(_ coordinate: CLLocationCoordinate2D?) -> String {
        guard let c = coordinate else { return "GPS受信待ち" }
        return String(format: "%.6f, %.6f", locale: Locale(identifier: "en_US_POSIX"), c.latitude, c.longitude)
    }
}

private struct ShareLinkButton: View {
    let title: String
    let url: URL
    var body: some View {
        ShareLink(item: url) {
            Label(title, systemImage: "square.and.arrow.up")
        }.foregroundStyle(.orange)
    }
}
