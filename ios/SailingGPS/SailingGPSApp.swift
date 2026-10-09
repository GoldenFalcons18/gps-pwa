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
    @Published var magneticHeading: Double?
    @Published var trueHeading: Double?
    private var foregroundActive = false
    @Published var recording = false
    @Published var track: [CLLocationCoordinate2D] = []
    @Published var message = "記録を開始してください"
    @Published var waypoints: [Waypoint] = []
    @Published var quickWaypointID: UUID?
    @Published var savingCurrentWaypoint = false
    private var waypointTimeout: Timer?
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

    func preview(_ active: Bool) {
        foregroundActive = active
        guard !recording else { return }
        if !active { manager.stopUpdatingLocation(); manager.stopUpdatingHeading(); return }
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization(); return }
        guard [.authorizedAlways, .authorizedWhenInUse].contains(manager.authorizationStatus) else { return }
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
        log("Foreground GPS/compass preview (no recording)")
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

    func saveCurrentWaypoint() {
        guard !savingCurrentWaypoint else { return }
        if let point = location, point.horizontalAccuracy >= 0, abs(point.timestamp.timeIntervalSinceNow) < 30 {
            finishCurrentWaypoint(point)
            return
        }
        guard ![.denied, .restricted].contains(manager.authorizationStatus) else {
            message = "設定で位置情報の使用を許可してください"; return
        }
        savingCurrentWaypoint = true
        message = "現在地を取得しています"
        waypointTimeout = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            guard let self, self.savingCurrentWaypoint else { return }
            self.savingCurrentWaypoint = false
            self.message = "現在地を取得できません。屋外で再試行してください"
            self.log("Quick waypoint location timeout")
        }
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        else { manager.requestLocation() }
    }

    private func finishCurrentWaypoint(_ point: CLLocation) {
        waypointTimeout?.invalidate(); waypointTimeout = nil
        savingCurrentWaypoint = false
        let waypoint = Waypoint(name: "現在地 \(waypoints.count + 1)", latitude: point.coordinate.latitude, longitude: point.coordinate.longitude)
        add(waypoint)
        quickWaypointID = waypoint.id
        message = "\(waypoint.name) を保存しました"
    }

    func stop() {
        pendingStart = false
        manager.stopUpdatingLocation(); manager.stopUpdatingHeading()
        manager.allowsBackgroundLocationUpdates = false
        do { try handle?.synchronize(); try handle?.close() } catch { fail(error) }
        handle = nil; recording = false; message = "記録停止"; log("Recording stopped")
        preview(foregroundActive)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        preview(foregroundActive)
        if savingCurrentWaypoint && manager.authorizationStatus != .notDetermined {
            if [.authorizedAlways, .authorizedWhenInUse].contains(manager.authorizationStatus) { manager.requestLocation() }
            else {
                savingCurrentWaypoint = false; waypointTimeout?.invalidate()
                message = "位置情報の使用を許可してください"
            }
        }
        if pendingStart && manager.authorizationStatus != .notDetermined { pendingStart = false; start() }
        if recording && ![.authorizedAlways, .authorizedWhenInUse].contains(manager.authorizationStatus) { stop(); message = "位置情報の許可が解除されました" }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        if newHeading.headingAccuracy >= 0 { magneticHeading = newHeading.magneticHeading; trueHeading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : nil }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for point in locations where point.horizontalAccuracy >= 0 && abs(point.timestamp.timeIntervalSinceNow) < 30 {
            location = point
            if savingCurrentWaypoint { finishCurrentWaypoint(point) }
            guard recording else { continue }
            let row = "\(point.timestamp.timeIntervalSince1970),\(point.coordinate.latitude),\(point.coordinate.longitude),\(point.altitude),\(point.speed),\(point.course)\n"
            do { try handle?.write(contentsOf: Data(row.utf8)) } catch { stop(); fail(error); return }
            track.append(point.coordinate)
            if track.count > 10000 { track.removeFirst(track.count - 10000) }
        }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        savingCurrentWaypoint = false; waypointTimeout?.invalidate(); fail(error)
    }
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
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("metricUnits") private var metricUnits = false
    @State private var following = true
    @State private var showAllRequest = 0
    @StateObject private var gps = GPSRecorder()
    @AppStorage("displayMode") private var mode = 0
    @State private var magnetic = false
    @State private var selected: UUID?
    @AppStorage("activeWaypointID") private var savedTarget = ""
    @State private var name = ""
    @State private var latitudeDegrees = ""
    @State private var latitudeMinutes = ""
    @State private var latitudeDirection = "N"
    @State private var longitudeDegrees = ""
    @State private var longitudeMinutes = ""
    @State private var longitudeDirection = "E"
    @State private var exported: URL?
    @State private var sharing = false
    @State private var settings = false
    private var hasCourse: Bool { gps.location.map { $0.speed >= 0.25 && $0.course >= 0 } ?? false }
    private var heading: Double? { !magnetic && hasCourse ? gps.location?.course : gps.magneticHeading }
    private var mapHeading: Double? {
        if let p = gps.location, p.speed >= 0.25, p.course >= 0 { return p.course }
        return gps.trueHeading
    }
    private var speedUnit: String { metricUnits ? "km/h" : "knot" }
    private var speedText: String { gps.location.flatMap { $0.speed >= 0 ? String(format: "%.1f", $0.speed * (metricUnits ? 3.6 : 1.943844)) : nil } ?? "—" }
    private var target: Waypoint? { gps.waypoints.first { $0.id == selected } }
    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
    private var ete: String {
        guard let target, let point = gps.location else { return "--:--:--" }
        return CoordinateInput.ete(distanceMeters: point.distance(from: CLLocation(latitude: target.latitude, longitude: target.longitude)), speedMps: point.speed)
    }
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
    private var compass: some View {
        ZStack {
                    Circle().stroke(.gray, lineWidth: 2)
                    ForEach(0..<12) { index in
                        Rectangle().fill(.orange).frame(width: 2, height: 12).offset(y: -67).rotationEffect(.degrees(Double(index) * 30))
                    }
                    VStack { Text("北 N"); Spacer(); Text("南 S") }.padding(8)
                    HStack { Text("西 W"); Spacer(); Text("東 E") }.padding(8)
                    Image(systemName: "location.north.fill").font(.system(size: 34)).foregroundStyle(.orange).rotationEffect(.degrees(heading ?? 0))
                    Text(heading.map { String(format: "%.0f°", $0) } ?? "—").offset(y: 38)
                }.frame(width: 154, height: 154)
    }
    private func reading(_ label: String, _ value: String) -> some View {
        VStack(spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.gray)
            Text(value).font(.title2.bold().monospacedDigit()).minimumScaleFactor(0.5).lineLimit(2)
        }.frame(maxWidth: .infinity)
    }
    private var targetPanel: some View {
        HStack(spacing: 4) {
            VStack(spacing: 12) {
                Text("目標まで").font(.caption).foregroundStyle(.gray)
                if let target, let point = gps.location {
                    Text(CoordinateInput.distance(point.distance(from: CLLocation(latitude: target.latitude, longitude: target.longitude)), metric: metricUnits)).font(.title2.bold()).minimumScaleFactor(0.5)
                    Text(String(format: "目標 %.0f°", bearing(to: target, from: point))).font(.caption)
                } else { Text("—").font(.title); Text(metricUnits ? "m/km" : "nm").font(.caption) }
            }.frame(maxWidth: .infinity)
            compass
            VStack(spacing: 8) {
                Button("設定目標") { settings = true }.font(.headline).tint(.orange)
                Text(target?.name ?? "未設定").font(.caption).lineLimit(2)
            }.frame(maxWidth: .infinity)
        }.padding(.vertical, 8).overlay(RoundedRectangle(cornerRadius: 8).stroke(.gray))
    }
    private var mapPanel: some View {
        VStack(spacing: 4) {
            NavigationMapView(location: gps.location, heading: mapHeading, waypoints: gps.waypoints, track: gps.track, selected: $selected, following: $following, showAllRequest: showAllRequest).frame(height: 270)
            HStack {
                Button("追従 1cm≒200m") { following = true }
                Spacer()
                Button("全ウェイポイント") { following = false; showAllRequest += 1 }
            }.font(.caption).tint(.orange)
        }
    }
    private var waypointEditor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack { Text("ウェイポイント・設定").font(.title2); Spacer(); Button("閉じる") { settings = false } }
                Picker("単位", selection: $metricUnits) { Text("knot / nm").tag(false); Text("km/h / m・km").tag(true) }.pickerStyle(.segmented)
                Toggle("磁気コンパス（OFF: GPS進行方位）", isOn: $magnetic)
                Text(gps.message).font(.caption)
                reading("GPS精度", gps.location.map { String(format: "±%.0f m", $0.horizontalAccuracy) } ?? "—")
                Text("ETEは目標までの直線距離と現在速度から計算します。約0.5 kt未満では表示しません。").font(.caption)
                Text("ウェイポイント").font(.headline)
                ForEach(gps.waypoints) { wp in
                    HStack {
                        Button { selected = wp.id; settings = false } label: {
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
                    gps.add(waypoint); selected = waypoint.id; following = false; showAllRequest += 1
                    name = ""; latitudeDegrees = ""; latitudeMinutes = ""; longitudeDegrees = ""; longitudeMinutes = ""
                    latitudeDirection = "N"; longitudeDirection = "E"
                }
            }.padding()
        }.preferredColorScheme(.dark)
    }
    private var recordControls: some View {
                HStack {
                    Text(mode == 0 ? "スピードメーター" : "ナビゲーター").font(.title2).foregroundStyle(.orange)
                    Spacer()
                    Button { gps.saveCurrentWaypoint() } label: {
                        Image(systemName: "mappin.and.ellipse").font(.title2).foregroundStyle(.orange)
                    }.accessibilityLabel("現在地をウェイポイント保存").disabled(gps.savingCurrentWaypoint)
                    Button { gps.recording ? gps.stop() : gps.start() } label: {
                        Image(systemName: gps.recording ? "pause.fill" : "record.circle").font(.title2).foregroundStyle(.red)
                    }.accessibilityLabel(gps.recording ? "GPS記録停止" : "GPS記録開始")
                }
    }
    private var navigationReadings: some View {
                HStack {
                    reading("SOG / \(speedUnit)", speedText)
                    reading("ETE", ete)
                    Button { settings = true } label: { Image(systemName: "line.3.horizontal").font(.title).foregroundStyle(.orange) }.accessibilityLabel("ウェイポイント・設定メニュー")
                }.padding(10).overlay(RoundedRectangle(cornerRadius: 8).stroke(.gray))
    }
    private var timeReadings: some View {
                HStack {
                    reading("高度", gps.location.map { String(format: "%.0f m", $0.altitude) } ?? "—")
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        reading("時間", Self.clockFormatter.string(from: context.date))
                    }
                    Button("GPX共有") { exported = gps.export(); sharing = exported != nil }.tint(.orange)
                }
    }
    private var positionReadings: some View {
                HStack {
                    reading(magnetic || !hasCourse ? "コンパス（磁）" : "GPS進行方位", heading.map { String(format: "%.0f°", $0) } ?? "—")
                    Rectangle().fill(.orange).frame(width: 1)
                    VStack(alignment: .trailing, spacing: 5) {
                        Text("緯度・経度").font(.caption).foregroundStyle(.gray)
                        Text(gps.location.map { CoordinateInput.format($0.coordinate.latitude, isLatitude: true) } ?? "—")
                        Text(gps.location.map { CoordinateInput.format($0.coordinate.longitude, isLatitude: false) } ?? "—")
                    }.font(.headline.monospacedDigit()).frame(maxWidth: .infinity)
                }.frame(height: 92)
    }
    private var dashboard: some View {
        ScrollView {
            VStack(spacing: 10) {
                Picker("表示", selection: $mode) { Text("スピードメーター").tag(0); Text("ナビゲーター").tag(1) }.pickerStyle(.segmented)
                if mode == 0 {
                    VStack(spacing: 0) {
                        Text(speedUnit).font(.title.bold()).foregroundStyle(.orange)
                        Text(speedText)
                            .font(.system(size: 130, weight: .bold, design: .monospaced)).minimumScaleFactor(0.4).foregroundStyle(.green).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }.frame(height: 270)
                } else { mapPanel }
                targetPanel
                recordControls
                navigationReadings
                timeReadings
                positionReadings
                Text(gps.message).font(.caption).foregroundStyle(.gray)
            }.padding(8)
        }.background(.black).preferredColorScheme(.dark)
    }
    private var presentedDashboard: some View {
        dashboard.sheet(isPresented: $sharing) { if let exported { ShareView(url: exported) } }
        .sheet(isPresented: $settings) { waypointEditor }
    }
    private var previewDashboard: some View {
        presentedDashboard.onChange(of: scenePhase) { _, phase in gps.preview(phase == ScenePhase.active) }
        .onAppear {
            gps.preview(true)
            selected = gps.waypoints.first { $0.id.uuidString == savedTarget }?.id ?? gps.waypoints.first?.id
        }
    }
    var body: some View {
        previewDashboard.onChange(of: gps.quickWaypointID) { _, value in
            if let value { selected = value; following = true }
        }
        .onChange(of: selected) { _, value in
            savedTarget = value?.uuidString ?? ""
        }
        .onChange(of: gps.waypoints.count) { _, _ in
            if !gps.waypoints.contains(where: { $0.id == selected }) { selected = gps.waypoints.first?.id }
        }
    }
}
struct ShareView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
@main struct SailingGPSApp: App { var body: some Scene { WindowGroup { ContentView() } } }
