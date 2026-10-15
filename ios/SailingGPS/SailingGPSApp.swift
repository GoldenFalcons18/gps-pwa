import SwiftUI
import MapKit
import CoreLocation

struct Waypoint: Identifiable, Codable {
    var id = UUID()
    var name: String
    var latitude: Double
    var longitude: Double
    var note: String?
    var colorName: String?
    var markSymbol: String?
    var markText: String?
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

final class GPSRecorder: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var location: CLLocation?
    @Published var magneticHeading: Double?
    @Published var trueHeading: Double?
    private var foregroundActive = false
    @Published var recording = false
    @Published var track: [CLLocationCoordinate2D] = []
    @Published var recordedDistance = 0.0
    @Published var maximumSpeed = 0.0
    @Published var elapsedBeforeStart = 0.0
    @Published var recordingStartedAt: Date?
    private var previousRecordedLocation: CLLocation?
    func elapsed(at date: Date) -> Double { elapsedBeforeStart + (recordingStartedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0) }
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

    func start(newTrack: Bool = false) {
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
            if newTrack {
                track.removeAll()
                recordedDistance = 0; maximumSpeed = 0; elapsedBeforeStart = 0
            }
            previousRecordedLocation = nil; recordingStartedAt = Date()
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
        elapsedBeforeStart = elapsed(at: Date()); recordingStartedAt = nil
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
            if let previous = previousRecordedLocation { recordedDistance += point.distance(from: previous) }
            previousRecordedLocation = point
            maximumSpeed = max(maximumSpeed, max(0, point.speed))
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
    func upsert(_ waypoint: Waypoint) {
        if let index = waypoints.firstIndex(where: { $0.id == waypoint.id }) { waypoints[index] = waypoint; saveWaypoints(); log("Waypoint updated: " + waypoint.name) }
        else { add(waypoint) }
    }
    func resetCounter() {
        recordedDistance = 0; maximumSpeed = 0; elapsedBeforeStart = 0
        previousRecordedLocation = nil; recordingStartedAt = recording ? Date() : nil
        log("Dashboard counter reset; saved track retained")
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
            for wp in waypoints { try write("<wpt lat=\"\(wp.latitude)\" lon=\"\(wp.longitude)\"><name>\(escape(wp.name))</name><desc>\(escape(wp.note ?? ""))</desc></wpt>") }
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
    @State private var mapDraft: CLLocationCoordinate2D?
    @State private var mapDraftName = ""
    @State private var mapDraftPresented = false
    @State private var following = true
    @State private var showAllRequest = 0
    @StateObject private var gps = GPSRecorder()
    @AppStorage("displayMode") private var mode = 0
    @AppStorage("magneticHeadingMode") private var magnetic = true
    @State private var compassDialAngle = 0.0
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
    @State private var menuPresented = false
    @State private var waypointListPresented = false
    @State private var editorDraft: Waypoint?
    private var navigationReference: CoordinateInput.HeadingReading? {
        CoordinateInput.headingReference(preferGps: !magnetic, magnetic: gps.magneticHeading, trueHeading: gps.trueHeading, course: gps.location?.course, speed: gps.location?.speed)
    }
    private var heading: Double? { navigationReference?.heading }
    private var mapHeading: Double? { navigationReference?.trueHeading }
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
    private var targetBearing: Double? {
        guard let target, let point = gps.location else { return nil }
        return bearing(to: target, from: point)
    }
    private var compassReferenceHeading: Double? { navigationReference?.heading }
    private var targetDisplayBearing: Double? {
        guard let bearing = targetBearing else { return nil }
        guard let reference = navigationReference, let trueHeading = reference.trueHeading else { return nil }
        return CoordinateInput.normalizeHeading(bearing - trueHeading + reference.heading)
    }
    private var compass: some View {
        ZStack {
            Circle().stroke(.gray, lineWidth: 2)
            ZStack {
                ForEach(0..<36) { index in
                    Rectangle().fill(.gray).frame(width: 1, height: index % 3 == 0 ? 10 : 5).offset(y: -71).rotationEffect(.degrees(Double(index) * 10))
                }
                VStack { Text("北"); Spacer(); Text("南") }.padding(12)
                HStack { Text("西"); Spacer(); Text("東") }.padding(12)
            }.rotationEffect(.degrees(-compassDialAngle))
            if let targetAngle = targetDisplayBearing, compassReferenceHeading != nil {
                Image(systemName: "location.north.fill").font(.system(size: 28)).foregroundStyle(.green).offset(y: -55).rotationEffect(.degrees(targetAngle - compassDialAngle))
            }
            VStack(spacing: 4) {
                Text(navigationReference?.magnetic == true ? "目標方位（磁北）" : "目標方位（真北）").font(.caption2)
                Text(targetDisplayBearing.map { String(format: "%.0f°", $0) } ?? "—").font(.title.bold()).foregroundStyle(.green)
            }
        }.frame(width: 154, height: 154)
        .animation(.linear(duration: 0.12), value: compassDialAngle)
        .onAppear { compassDialAngle = compassReferenceHeading ?? 0 }
        .onChange(of: compassReferenceHeading) { _, value in
            if let value { compassDialAngle = CoordinateInput.unwrapHeading(from: compassDialAngle, to: value) }
        }
    }
    private func reading(_ label: String, _ value: String) -> some View {
        VStack(spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.gray)
            Text(value).font(.title2.bold().monospacedDigit()).minimumScaleFactor(0.5).lineLimit(2)
        }.frame(maxWidth: .infinity)
    }
    private var targetPanel: some View {
        GeometryReader { proxy in
            let dial = min(proxy.size.height, proxy.size.width * 0.45)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("目標", systemImage: "ruler").font(.caption).foregroundStyle(.gray)
                    Text(targetDistance).font(.system(size: 25, weight: .bold)).minimumScaleFactor(0.45).lineLimit(1)
                    Label("目標, ETE", systemImage: "clock").font(.caption2).foregroundStyle(.gray)
                    Text(ete).font(.system(size: 22, weight: .bold, design: .monospaced)).foregroundStyle(.orange).minimumScaleFactor(0.45).lineLimit(1)
                }.frame(width: proxy.size.width * 0.26, alignment: .leading)
                compass.scaleEffect(dial / 154).frame(width: dial, height: dial)
                VStack(spacing: 8) {
                    Button("目標") { waypointListPresented = true }.font(.headline).foregroundStyle(.orange)
                        .frame(maxWidth: .infinity).overlay(RoundedRectangle(cornerRadius: 4).stroke(.orange))
                    Text(target?.name ?? "設定目標").font(.system(size: 23, weight: .bold)).foregroundStyle(target == nil ? .orange : .white).minimumScaleFactor(0.5).lineLimit(2)
                    if let target {
                        Text(CoordinateInput.format(target.latitude, isLatitude: true) + "\n" + CoordinateInput.format(target.longitude, isLatitude: false))
                            .font(.caption.monospacedDigit()).minimumScaleFactor(0.5).lineLimit(2)
                    }
                }.frame(maxWidth: .infinity)
            }.padding(.horizontal, 5).frame(height: proxy.size.height)
        }.overlay(RoundedRectangle(cornerRadius: 5).stroke(.gray))
    }
    private var targetDistance: String {
        guard let target, let point = gps.location else { return "---" }
        return CoordinateInput.distance(point.distance(from: CLLocation(latitude: target.latitude, longitude: target.longitude)), metric: metricUnits)
    }
    private var mapPanel: some View {
        ZStack(alignment: .bottom) {
            NavigationMapView(location: gps.location, heading: mapHeading, waypoints: gps.waypoints, track: gps.track, selected: $selected, following: $following, showAllRequest: showAllRequest, createWaypoint: { coordinate in
                editorDraft = makeDraft(coordinate)
            })
            HStack {
                Button { following = true } label: { Image(systemName: "location.north.fill") }
                    .accessibilityLabel("現在地へ追従 1cm約200m")
                Spacer()
                Text("長押しで地点追加").font(.caption2).padding(4).background(.black.opacity(0.5)).foregroundStyle(.white)
                Spacer()
                Button { following = false; showAllRequest += 1 } label: { Image(systemName: "square.3.layers.3d") }
                    .accessibilityLabel("全ウェイポイント")
            }.font(.title3).tint(.black).buttonStyle(.borderedProminent).padding(8)
        }
    }
    private var waypointEditor: some View {
        NavigationStack {
            Form {
                Section("表示") {
                    Picker("単位", selection: $metricUnits) { Text("knot / nm").tag(false); Text("km/h / m・km").tag(true) }
                    Picker("モード", selection: $mode) { Text("スピードメーター").tag(0); Text("ナビゲーター").tag(1) }
                    Toggle("端末の向きで追従", isOn: $magnetic)
                    Text("OFFではGPS進行方位で追従します").font(.caption)
                }
                Section("GPS") {
                    reading("GPS精度", gps.location.map { String(format: "±%.0f m", $0.horizontalAccuracy) } ?? "—")
                    Text(gps.message).font(.caption)
                }
                Section("アプリ") { Text("Sailing GPS 1.6.3 · build 14") }
            }.navigationTitle("設定").toolbar { Button("完了") { settings = false } }
        }.tint(.orange).preferredColorScheme(.dark)
    }
    private func makeDraft(_ coordinate: CLLocationCoordinate2D? = nil) -> Waypoint {
        let coordinate = coordinate ?? gps.location?.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        return Waypoint(name: Date.now.formatted(date: .numeric, time: .shortened), latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
    private var waypointList: some View {
        NavigationStack {
            List {
                if gps.waypoints.isEmpty { Text("ウェイポイントはありません") }
                ForEach(gps.waypoints) { wp in
                    HStack {
                        Button {
                            selected = wp.id; following = true; waypointListPresented = false
                        } label: {
                            VStack(alignment: .leading) {
                                HStack {
                                    if let text = wp.markText, !text.isEmpty { Text(text) }
                                    else { Image(systemName: wp.markSymbol ?? "flag.fill") }
                                    Text(wp.name)
                                    if selected == wp.id { Image(systemName: "checkmark") }
                                }.foregroundStyle(waypointColor(wp.colorName))
                                Text(CoordinateInput.format(wp.latitude, isLatitude: true) + " / " + CoordinateInput.format(wp.longitude, isLatitude: false)).font(.caption)
                            }
                        }
                        Spacer()
                        Button("編集") {
                            waypointListPresented = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { editorDraft = wp }
                        }.buttonStyle(.borderless)
                    }.swipeActions { Button("削除", role: .destructive) { gps.remove(wp.id) } }
                }
            }.navigationTitle("ウェイポイント")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完了") { waypointListPresented = false } }
                    ToolbarItem(placement: .primaryAction) { Button { waypointListPresented = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { editorDraft = makeDraft() } } label: { Image(systemName: "plus") } }
                }
        }.tint(.orange).preferredColorScheme(.dark)
    }
    private func menuAction(_ action: () -> Void) { menuPresented = false; action() }
    private func menuTile(_ title: String, detail: String = "", done: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(title).font(.headline).multilineTextAlignment(.center).foregroundStyle(.white)
                if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.gray).multilineTextAlignment(.center) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(6).background(.black.opacity(0.93))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(done ? Color.green : .orange))
        }
    }
    private var navigationMenu: some View {
        GeometryReader { proxy in
            HStack(spacing: proxy.size.width * 0.12) {
                VStack(spacing: 5) {
                    menuTile("新規追跡", detail: "新しいカウンターで記録") { menuAction { if gps.recording { gps.stop() }; gps.start(newTrack: true) } }
                    menuTile(gps.recording ? "カウンターを一時停止" : "カウンターを再開") { menuAction { gps.recording ? gps.stop() : gps.start() } }
                    menuTile("カウンターをリセット", detail: "保存した航跡は保持") { menuAction { gps.resetCounter() } }
                    menuTile("追跡・GPX出力") { menuAction { exported = gps.export(); sharing = exported != nil } }
                    menuTile("設定") { menuAction { settings = true } }
                    menuTile("モード", detail: mode == 0 ? "スピードメーター → ナビゲーター" : "ナビゲーター → スピードメーター") { menuAction { mode = mode == 0 ? 1 : 0 } }
                }
                VStack(spacing: 5) {
                    menuTile("新規ウェイポイント") { menuAction { editorDraft = makeDraft() } }
                    menuTile("目標", detail: target?.name ?? "未設定") { menuAction { waypointListPresented = true } }
                    menuTile("📍 ウェイポイント", detail: "一覧・編集・削除") { menuAction { waypointListPresented = true } }
                    menuTile("現在地に打つ") { menuAction { gps.saveCurrentWaypoint() } }
                    menuTile("全ウェイポイント", detail: "地図に表示") { menuAction { mode = 1; following = false; showAllRequest += 1 } }
                    menuTile("完了", done: true) { menuPresented = false }
                }
            }.padding(4)
        }.background(.black.opacity(0.45))
    }
    private var topControls: some View {
        HStack {
            Button { gps.saveCurrentWaypoint() } label: { Image(systemName: "mappin.and.ellipse") }
                .accessibilityLabel("現在地をウェイポイント保存").disabled(gps.savingCurrentWaypoint)
            Button { mode = mode == 0 ? 1 : 0 } label: { Image(systemName: mode == 0 ? "map" : "speedometer") }
                .accessibilityLabel("表示モードを切替")
            Spacer()
            if mode == 0 { Text(speedUnit).font(.title2.bold()) }
            Spacer()
            Button { gps.recording ? gps.stop() : gps.start() } label: {
                Image(systemName: "record.circle.fill").foregroundStyle(.red)
            }.accessibilityLabel(gps.recording ? "GPS記録停止" : "GPS記録開始")
        }.font(.title2).foregroundStyle(.orange).padding(.horizontal, 12).padding(.vertical, 6)
            .background(mode == 0 ? Color.black : Color.black.opacity(0.25))
    }
    private func instrument(_ value: String, label: String, size: CGFloat = 25) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: size, weight: .bold, design: .monospaced)).minimumScaleFactor(0.45).lineLimit(1)
            Text(label).font(.caption2).foregroundStyle(.gray).lineLimit(1)
        }.frame(maxWidth: .infinity)
    }
    private func duration(_ seconds: Double) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%02d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
    }
    private var pace: String {
        guard let speed = gps.location?.speed, speed > 0.25 else { return "--" }
        return duration((metricUnits ? 1000 : 1852) / speed)
    }
    private var instruments: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = gps.elapsed(at: context.date)
            VStack(spacing: 10) {
                HStack(alignment: .top, spacing: 5) {
                    VStack(spacing: 2) {
                        Image(systemName: "location.fill").foregroundStyle(gps.location == nil ? .gray : .green)
                        Text("GPS").font(.caption2).foregroundStyle(.gray)
                    }
                    if mode == 1 {
                        instrument(duration(elapsed), label: "追跡タイマー", size: 26)
                        instrument(CoordinateInput.distance(gps.recordedDistance, metric: metricUnits), label: "追跡距離")
                    } else {
                        instrument(elapsed > 0 ? String(format: "%.1f", gps.recordedDistance / elapsed * (metricUnits ? 3.6 : 1.943844)) : "--", label: "平均速度 / " + speedUnit)
                        instrument(String(format: "%.1f", gps.maximumSpeed * (metricUnits ? 3.6 : 1.943844)), label: "MAX / " + speedUnit)
                    }
                    Button { menuPresented = true } label: { Image(systemName: "line.3.horizontal").font(.title).foregroundStyle(.orange) }
                        .accessibilityLabel("ウェイポイント・設定メニュー")
                }
                HStack(alignment: .bottom, spacing: 4) {
                    instrument(gps.location.map { String(format: "%.0f", $0.altitude) } ?? "--", label: "高度 m")
                    instrument(pace, label: metricUnits ? "ペース / km" : "ペース / 海里", size: 19)
                    instrument(speedText, label: speedUnit)
                    instrument(Self.clockFormatter.string(from: context.date), label: "時間", size: 23)
                }
            }.padding(8).frame(maxHeight: .infinity)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.gray))
        }
    }
    private var modeTitle: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            Text(mode == 0 ? "スピードメーター" : "ナビゲーター")
                .font(.system(size: 29, weight: .medium)).minimumScaleFactor(0.6).lineLimit(1).foregroundStyle(.orange)
            Button { gps.recording ? gps.stop() : gps.start() } label: {
                HStack(spacing: 3) {
                    Text(gps.recording ? "カウンター\n一時停止" : "記録開始").font(.caption2).foregroundStyle(.orange)
                    Image(systemName: gps.recording ? "pause.fill" : "record.circle").font(.title2).foregroundStyle(.red)
                }
            }
        }.padding(.horizontal, 5)
    }
    private var positionReadings: some View {
        HStack(spacing: 5) {
            VStack(spacing: 1) {
                Text(navigationReference?.magnetic == true ? "コンパス（磁）" : "GPS進行方位").font(.caption2).foregroundStyle(.gray)
                Text(heading.map { String(format: "%.0f°", $0) } ?? "---")
                    .font(.system(size: 45, weight: .medium, design: .monospaced)).minimumScaleFactor(0.5).lineLimit(1)
            }.frame(maxWidth: .infinity)
            Rectangle().fill(.orange).frame(width: 1)
            VStack(alignment: .trailing, spacing: 2) {
                Text(gps.location.map { CoordinateInput.format($0.coordinate.latitude, isLatitude: true) } ?? "---")
                Text(gps.location.map { CoordinateInput.format($0.coordinate.longitude, isLatitude: false) } ?? "---")
            }.font(.system(size: 23, weight: .bold, design: .monospaced)).minimumScaleFactor(0.5).lineLimit(1).frame(maxWidth: .infinity)
        }.padding(.horizontal, 5).overlay(alignment: .top) { Rectangle().fill(.gray).frame(height: 1) }
    }
    private var dashboard: some View {
        GeometryReader { geometry in
            let height = max(620, geometry.size.height)
            ScrollView {
                VStack(spacing: 6) {
                    ZStack(alignment: .top) {
                        if mode == 1 { mapPanel }
                        else {
                            SevenSegmentSpeed(text: speedText).padding(.horizontal, 12).padding(.top, 48).padding(.bottom, 12)
                        }
                        topControls
                    }.frame(height: height * 0.39)
                    targetPanel.frame(height: height * 0.205).padding(.horizontal, 3)
                    modeTitle.frame(height: 40)
                    instruments.frame(height: height * 0.205).padding(.horizontal, 3)
                    positionReadings.frame(height: height * 0.11)
                }.frame(minHeight: geometry.size.height)
            }.scrollIndicators(.hidden)
        }.background(.black).foregroundStyle(.white).preferredColorScheme(.dark)
    }
    private var presentedDashboard: some View {
        ZStack {
            dashboard
            if menuPresented { navigationMenu }
        }
        .sheet(isPresented: $sharing) { if let exported { ShareView(url: exported) } }
        .sheet(isPresented: $settings) { waypointEditor }
        .sheet(isPresented: $waypointListPresented) { waypointList }
        .sheet(item: $editorDraft) { draft in
            WaypointEntryView(waypoint: draft) { waypoint in
                gps.upsert(waypoint); selected = waypoint.id; following = true
            }
        }
    }
    private var previewDashboard: some View {
        presentedDashboard.onChange(of: scenePhase) { _, phase in gps.preview(phase == ScenePhase.active) }
        .onAppear {
            gps.preview(true)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--preview-menu") { menuPresented = true }
            if ProcessInfo.processInfo.arguments.contains("--preview-waypoint") {
                editorDraft = Waypoint(name: "新規ウェイポイント", latitude: 35 + 19.528/60, longitude: 139 + 27.130/60)
            }
            #endif
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
