import SwiftUI
import MapKit
import CoreLocation

struct Waypoint: Identifiable, Codable {
    var id = UUID()
    var name: String
    var latitude: Double
    var longitude: Double
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

final class GPSRecorder: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var location: CLLocation?
    @Published var magneticHeading: Double = 0
    @Published var recording = false
    @Published var track: [CLLocationCoordinate2D] = []
    @Published var message = "記録を開始してください"
    @Published var waypoints: [Waypoint] = []
    private let manager = CLLocationManager()
    private var pendingStart = false
    private var handle: FileHandle?
    private let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    private var csv: URL { directory.appendingPathComponent("track.csv") }
    private var waypointFile: URL { directory.appendingPathComponent("waypoints.json") }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .otherNavigation
        manager.pausesLocationUpdatesAutomatically = false
        if let data = try? Data(contentsOf: waypointFile), let saved = try? JSONDecoder().decode([Waypoint].self, from: data) { waypoints = saved }
    }

    func start() {
        guard !recording else { return }
        if manager.authorizationStatus == .notDetermined {
            pendingStart = true
            manager.requestWhenInUseAuthorization()
            return
        }
        guard [.authorizedAlways, .authorizedWhenInUse].contains(manager.authorizationStatus) else {
            message = "設定で位置情報の使用を許可してください"; return
        }
        do {
            if !FileManager.default.fileExists(atPath: csv.path) { try Data().write(to: csv) }
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: csv.path)
            handle = try FileHandle(forWritingTo: csv)
            try handle?.seekToEnd()
            try handle?.write(contentsOf: Data("#session\n".utf8))
            track.removeAll()
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
            recording = true
            manager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
            message = "記録中（画面OFFでも継続）"
            log("Recording started")
        } catch { fail(error) }
    }

    func stop() {
        pendingStart = false
        manager.stopUpdatingLocation(); manager.stopUpdatingHeading()
        manager.allowsBackgroundLocationUpdates = false
        do { try handle?.synchronize(); try handle?.close() } catch { fail(error) }
        handle = nil; recording = false; message = "記録停止"; log("Recording stopped")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if pendingStart && manager.authorizationStatus != .notDetermined { pendingStart = false; start() }
        if recording && ![.authorizedAlways, .authorizedWhenInUse].contains(manager.authorizationStatus) { stop(); message = "位置情報の許可が解除されました" }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        if newHeading.headingAccuracy >= 0 { magneticHeading = newHeading.magneticHeading }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for point in locations where point.horizontalAccuracy >= 0 && abs(point.timestamp.timeIntervalSinceNow) < 30 {
            location = point
            guard recording else { continue }
            let row = "\(point.timestamp.timeIntervalSince1970),\(point.coordinate.latitude),\(point.coordinate.longitude),\(point.altitude),\(point.speed),\(point.course)\n"
            do { try handle?.write(contentsOf: Data(row.utf8)) } catch { stop(); fail(error); return }
            track.append(point.coordinate)
            if track.count > 10000 { track.removeFirst(track.count - 10000) }
        }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { fail(error) }
    func add(_ waypoint: Waypoint) {
        waypoints.append(waypoint); saveWaypoints()
        log("Waypoint added: \(CoordinateInput.format(waypoint.latitude, isLatitude: true)) \(CoordinateInput.format(waypoint.longitude, isLatitude: false))")
    }
    func remove(_ id: UUID) { waypoints.removeAll { $0.id == id }; saveWaypoints() }
    private func saveWaypoints() {
        do { try JSONEncoder().encode(waypoints).write(to: waypointFile, options: .atomic) } catch { fail(error) }
    }
    func export() -> URL? {
        do {
            try handle?.synchronize()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Sailing-\(Int(Date().timeIntervalSince1970)).gpx")
            FileManager.default.createFile(atPath: url.path, contents: nil)
            let output = try FileHandle(forWritingTo: url)
            defer { try? output.close() }
            func write(_ value: String) throws { try output.write(contentsOf: Data(value.utf8)) }
            try write("<?xml version=\"1.0\" encoding=\"UTF-8\"?><gpx version=\"1.1\" creator=\"SailingGPS\" xmlns=\"http://www.topografix.com/GPX/1/1\">")
            for wp in waypoints { try write("<wpt lat=\"\(wp.latitude)\" lon=\"\(wp.longitude)\"><name>\(escape(wp.name))</name></wpt>") }
            try write("<trk><name>Sailing track</name><trkseg>")
            if FileManager.default.fileExists(atPath: csv.path) {
                let input = try FileHandle(forReadingFrom: csv)
                defer { try? input.close() }
                var pending = Data()
                let formatter = ISO8601DateFormatter()
                while let chunk = try input.read(upToCount: 65536), !chunk.isEmpty {
                    pending.append(chunk)
                    while let newline = pending.firstIndex(of: 10) {
                        let line = String(decoding: pending.prefix(upTo: newline), as: UTF8.self)
                        pending.removeSubrange(...newline)
                        if line == "#session" { try write("</trkseg><trkseg>"); continue }
                        let fields = line.split(separator: ",")
                        if fields.count >= 4, let time = Double(fields[0]), let lat = Double(fields[1]), let lon = Double(fields[2]), let alt = Double(fields[3]) {
                            try write("<trkpt lat=\"\(lat)\" lon=\"\(lon)\"><ele>\(alt)</ele><time>\(formatter.string(from: Date(timeIntervalSince1970: time)))</time></trkpt>")
                        }
                    }
                }
            }
            try write("</trkseg></trk></gpx>"); log("GPX exported"); return url
        } catch { fail(error); return nil }
    }
    private func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&apos;")
    }
    private func fail(_ error: Error) { message = error.localizedDescription; log("Error: \(error.localizedDescription)") }
    private func log(_ text: String) {
        let url = directory.appendingPathComponent("debug.log")
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        if let file = try? FileHandle(forWritingTo: url) {
            defer { try? file.close() }
            if ((try? file.seekToEnd()) ?? 0) > 1024 * 1024 { try? file.truncate(atOffset: 0); try? file.seek(toOffset: 0) }
            try? file.write(contentsOf: Data("\(Date()) \(text)\n".utf8))
        }
    }
}

struct ContentView: View {
    @StateObject private var gps = GPSRecorder()
    @State private var mode = 0
    @State private var magnetic = false
    @State private var selected: UUID?
    @State private var name = ""
    @State private var latitudeDegrees = ""
    @State private var latitudeMinutes = ""
    @State private var latitudeDirection = "N"
    @State private var longitudeDegrees = ""
    @State private var longitudeMinutes = ""
    @State private var longitudeDirection = "E"
    @State private var camera: MapCameraPosition = .automatic
    @State private var exported: URL?
    @State private var sharing = false
    private var heading: Double? { magnetic ? gps.magneticHeading : gps.location.flatMap { $0.course >= 0 ? $0.course : nil } }
    private var target: Waypoint? { gps.waypoints.first { $0.id == selected } }
    private func bearing(to waypoint: Waypoint, from point: CLLocation) -> Double {
        let a = point.coordinate.latitude * .pi / 180
        let b = waypoint.latitude * .pi / 180
        let difference = (waypoint.longitude - point.coordinate.longitude) * .pi / 180
        return (atan2(sin(difference) * cos(b), cos(a) * sin(b) - sin(a) * cos(b) * cos(difference)) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
    private func coordinateFields(_ title: String, degrees: Binding<String>, minutes: Binding<String>, direction: Binding<String>, directions: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline)
            HStack {
                TextField("度", text: degrees).keyboardType(.numberPad).accessibilityLabel("\(title)の度")
                Text("°")
                TextField("分", text: minutes).keyboardType(.decimalPad).accessibilityLabel("\(title)の分")
                Text("′")
            }.textFieldStyle(.roundedBorder)
            Picker("\(title)の方向", selection: direction) {
                ForEach(directions, id: \.self) { value in Text(value).tag(value) }
            }.pickerStyle(.segmented)
        }
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Picker("表示", selection: $mode) { Text("スピードメーター").tag(0); Text("ナビゲーター").tag(1) }.pickerStyle(.segmented)
                if mode == 0 {
                    Text(gps.location.map { String(format: "%.1f", max(0, $0.speed) * 1.943844) } ?? "—")
                        .font(.system(size: 100, weight: .bold, design: .monospaced)).minimumScaleFactor(0.4).foregroundStyle(.green)
                    Text("SOG / kts")
                } else {
                    Map(position: $camera) {
                        if let p = gps.location { Annotation("現在地", coordinate: p.coordinate) { Image(systemName: "location.north.fill").foregroundStyle(.red) } }
                        ForEach(gps.waypoints) { wp in Marker(wp.name, coordinate: wp.coordinate) }
                        if gps.track.count > 1 { MapPolyline(coordinates: gps.track).stroke(.orange, lineWidth: 3) }
                    }.frame(height: 320)
                    Button("現在地へ") { if let p = gps.location { camera = .region(.init(center: p.coordinate, latitudinalMeters: 1500, longitudinalMeters: 1500)) } }
                }
                ZStack {
                    Circle().stroke(.gray, lineWidth: 2)
                    ForEach(0..<12) { index in
                        Rectangle().fill(.orange).frame(width: 2, height: 12).offset(y: -99).rotationEffect(.degrees(Double(index) * 30))
                    }
                    VStack { Text("北 N"); Spacer(); Text("南 S") }.padding(12)
                    HStack { Text("西 W"); Spacer(); Text("東 E") }.padding(12)
                    Image(systemName: "location.north.fill").font(.system(size: 50)).foregroundStyle(.orange).rotationEffect(.degrees(heading ?? 0))
                    Text(heading.map { String(format: "%.0f°", $0) } ?? "—").offset(y: 50)
                }.frame(width: 220, height: 220)
                Toggle("磁気コンパス（OFF: GPS進行方位）", isOn: $magnetic)
                Text(gps.message).font(.caption)
                HStack {
                    Button(gps.recording ? "記録停止" : "記録開始") { gps.recording ? gps.stop() : gps.start() }.buttonStyle(.borderedProminent)
                    Button("GPX保存") { exported = gps.export(); sharing = exported != nil }.buttonStyle(.bordered)
                }
                if let point = gps.location {
                    Text(String(format: "緯度 %.6f / 経度 %.6f\n精度 ±%.0f m / 高度 %.0f m", point.coordinate.latitude, point.coordinate.longitude, point.horizontalAccuracy, point.altitude)).font(.caption.monospacedDigit())
                }
                if let target, let point = gps.location {
                    Text("目標: \(target.name) / \(String(format: "%.2f", point.distance(from: CLLocation(latitude: target.latitude, longitude: target.longitude)) / 1852)) nm")
                    Text(String(format: "目標方位（真北） %.0f°", bearing(to: target, from: point)))
                }
                Text("ウェイポイント").font(.headline)
                ForEach(gps.waypoints) { wp in
                    HStack {
                        Button { selected = wp.id } label: {
                            VStack(alignment: .leading) {
                                Text(wp.name)
                                Text("\(CoordinateInput.format(wp.latitude, isLatitude: true)) / \(CoordinateInput.format(wp.longitude, isLatitude: false))").font(.caption.monospacedDigit())
                            }
                        }
                        Spacer()
                        Button("削除", role: .destructive) { gps.remove(wp.id) }
                    }
                }
                TextField("名前", text: $name)
                coordinateFields("緯度", degrees: $latitudeDegrees, minutes: $latitudeMinutes, direction: $latitudeDirection, directions: ["N", "S"])
                coordinateFields("経度", degrees: $longitudeDegrees, minutes: $longitudeMinutes, direction: $longitudeDirection, directions: ["E", "W"])
                Text("例：35°19.046′N → 度 35 ／ 分 19.046 ／ N").font(.caption)
                Button("追加") {
                    guard let lat = CoordinateInput.decimal(degrees: latitudeDegrees, minutes: latitudeMinutes, direction: latitudeDirection, isLatitude: true),
                          let lon = CoordinateInput.decimal(degrees: longitudeDegrees, minutes: longitudeMinutes, direction: longitudeDirection, isLatitude: false) else {
                        gps.message = "度は緯度0〜90・経度0〜180の整数、分は0以上60未満で入力してください。90度・180度では分は0です。"
                        return
                    }
                    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let waypoint = Waypoint(name: trimmedName.isEmpty ? "Waypoint \(gps.waypoints.count + 1)" : trimmedName, latitude: lat, longitude: lon)
                    gps.add(waypoint); selected = waypoint.id
                    name = ""; latitudeDegrees = ""; latitudeMinutes = ""; longitudeDegrees = ""; longitudeMinutes = ""
                    latitudeDirection = "N"; longitudeDirection = "E"
                }
            }.padding()
        }.preferredColorScheme(.dark)
        .sheet(isPresented: $sharing) { if let exported { ShareView(url: exported) } }
    }
}
struct ShareView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
@main struct SailingGPSApp: App { var body: some Scene { WindowGroup { ContentView() } } }
