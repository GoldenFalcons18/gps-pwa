import SwiftUI
import MapKit
import CoreLocation
import UniformTypeIdentifiers

struct Waypoint: Identifiable, Codable {
    var id = UUID()
    var name: String
    var latitude: Double
    var longitude: Double
    var note: String?
    var colorName: String?
    var markSymbol: String?
    var markText: String?
    var group: String? = "メインフォルダ"
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

private struct TrackListView: View {
    @ObservedObject var gps: GPSRecorder
    var onSelect: (URL) -> Void
    var onExport: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var revision = 0
    @State private var renameFile: URL?
    @State private var renameText = ""
    private struct Summary: Identifiable {
        var id: URL { file }; let file: URL; let date: Date?; let points: Int; let coordinates:[CLLocationCoordinate2D]; let distance: Double; let duration: TimeInterval; let average: Double?; let maximum: Double?
    }
    private var summaries: [Summary] {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("tracks", isDirectory: true)
        var result = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? []).filter { $0.pathExtension == "csv" }
        let legacy = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("track.csv")
        if FileManager.default.fileExists(atPath: legacy.path) { result.append(legacy) }
        return result.map { file in
            let rows = ((try? String(contentsOf: file, encoding: .utf8)) ?? "").split(whereSeparator: { $0.isNewline }).compactMap { line -> (Date, CLLocation, Double?)? in
                let f=line.split(separator:","); guard f.count >= 5, let t=Double(f[0]), let lat=Double(f[1]), let lon=Double(f[2]) else { return nil }
                let altitude=Double(f[3]) ?? 0;let speed=Double(f[4]).flatMap{$0 >= 0 ? $0 : nil}
                return (Date(timeIntervalSince1970:t),CLLocation(coordinate:.init(latitude:lat,longitude:lon),altitude:altitude,horizontalAccuracy:0,verticalAccuracy:0,timestamp:Date(timeIntervalSince1970:t)),speed)
            }
            var distance=0.0
            for pair in zip(rows,rows.dropFirst()) { distance += pair.1.1.distance(from:pair.0.1) }
            let duration=rows.first.flatMap { first in rows.last.map { max(0,$0.0.timeIntervalSince(first.0)) } } ?? 0
            let speeds=rows.compactMap{$0.2}
            let average=duration > 0 ? distance/duration : nil
            return Summary(file:file,date:rows.first?.0,points:rows.count,coordinates:rows.map{$0.1.coordinate},distance:distance,duration:duration,average:average,maximum:speeds.max())
        }.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }
    var body: some View {
        NavigationStack {
            List {
                ForEach(summaries) { s in
                    let activeName=(try? String(contentsOf: FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("active-track.txt"),encoding:.utf8))?.trimmingCharacters(in:.whitespacesAndNewlines)
                    let active=activeName == s.file.lastPathComponent
                    HStack(alignment:.top,spacing:10) {
                        TrackThumbnail(points:s.coordinates).frame(width:76,height:82).clipShape(RoundedRectangle(cornerRadius:5))
                        VStack(alignment:.leading,spacing:6) {
                            HStack { Text(active ? (gps.recording ? "● 記録中" : "Ⅱ 一時停止中") : trackTitle(s)).font(.headline);if active && gps.recording { Spacer();Circle().fill(.green).frame(width:9,height:9) } }
                            Text("\(CoordinateInput.distance(s.distance,metric:false))   \(durationText(s.duration))   \(s.points) 点").font(.subheadline)
                            Text("平均 \(s.average.map{String(format:"%.1f",$0*1.943844)} ?? "--") kt   MAX \(s.maximum.map{String(format:"%.1f",$0*1.943844)} ?? "--") kt").font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button("地図") { onSelect(s.file);dismiss() }.buttonStyle(.bordered)
                                Button("GPX") { onExport(s.file);dismiss() }.buttonStyle(.bordered)
                                Button("名前変更") { renameText=s.file.deletingPathExtension().lastPathComponent;renameFile=s.file }.buttonStyle(.bordered)
                                if !active { Button("削除",role:.destructive) { try? FileManager.default.removeItem(at:s.file);revision += 1 }.buttonStyle(.bordered) }
                            }
                        }
                    }.padding(.vertical,5)
                }
            }.id(revision).navigationTitle("航跡一覧（\(summaries.count)件）").toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } } }
            .alert("航跡名を変更",isPresented:Binding(get:{renameFile != nil},set:{if !$0{renameFile=nil}})) {
                TextField("航跡名",text:$renameText)
                Button("保存") { if let file=renameFile,gps.renameTrack(file,name:renameText){revision += 1};renameFile=nil }
                Button("キャンセル",role:.cancel){renameFile=nil}
            } message:{Text("航跡一覧に表示する名前です。")}
        }
    }
    private func durationText(_ value:TimeInterval)->String { let n=max(0,Int(value));return String(format:"%02d:%02d:%02d",n/3600,(n/60)%60,n%60) }
    private func trackTitle(_ s:Summary)->String { let name=s.file.deletingPathExtension().lastPathComponent;return name.hasPrefix("track-") ? (s.date.map{DateFormatter.localizedString(from:$0,dateStyle:.short,timeStyle:.short)} ?? name) : name }
}

private struct TrackThumbnail: View {
    let points:[CLLocationCoordinate2D]
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(red:0.03,green:0.28,blue:0.38)
                TrackPolyline(points:points).stroke(Color.pink,lineWidth:2.5)
            }.frame(width:proxy.size.width,height:proxy.size.height)
        }
    }
}
private struct TrackPolyline: Shape {
    let points:[CLLocationCoordinate2D]
    func path(in rect:CGRect)->Path {
        guard !points.isEmpty else{return Path()}
        let minLat=points.map(\.latitude).min() ?? 0,maxLat=points.map(\.latitude).max() ?? 0
        let minLon=points.map(\.longitude).min() ?? 0,maxLon=points.map(\.longitude).max() ?? 0
        let dx=max(maxLon-minLon,0.000001),dy=max(maxLat-minLat,0.000001)
        let scale=min((rect.width-10)/dx,(rect.height-10)/dy)
        let usedW=dx*scale,usedH=dy*scale,ox=(rect.width-usedW)/2,oy=(rect.height-usedH)/2
        var p=Path()
        for (i,c) in points.enumerated(){let pt=CGPoint(x:ox+(c.longitude-minLon)*scale,y:rect.height-oy-(c.latitude-minLat)*scale);if i==0{p.move(to:pt)}else{p.addLine(to:pt)}}
        return p
    }
}

extension Waypoint {
    var archiveEntry: WaypointArchive.Entry {
        let ui = UIColor(waypointColor(colorName)); var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        ui.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let color = String(format: "#%02X%02X%02X", Int((red*255).rounded()), Int((green*255).rounded()), Int((blue*255).rounded()))
        let mark = (markText?.isEmpty == false) ? "text:" + markText! : "symbol:" + (markSymbol ?? "flag.fill")
        return .init(id: id, name: name, latitude: latitude, longitude: longitude, mark: mark, color: color, note: note, group: group)
    }
    init(archive e: WaypointArchive.Entry) {
        self.init(id: e.id, name: e.name, latitude: e.latitude, longitude: e.longitude, note: e.note, colorName: e.color,
                  markSymbol: e.mark.hasPrefix("symbol:") ? String(e.mark.dropFirst(7)) : nil,
                  markText: e.mark.hasPrefix("text:") ? String(e.mark.dropFirst(5)) : nil, group: e.group)
    }
}

final class GPSRecorder: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var location: CLLocation?
    @Published var magneticHeading: Double?
    @Published var trueHeading: Double?
    @Published var headingUpdatedAt:Date?
    private var foregroundActive = false
    @Published var recording = false
    @Published var recordingPaused = false
    @Published var track: [CLLocationCoordinate2D] = []
    @Published var recordedDistance = 0.0
    @Published var maximumSpeed = 0.0
    @Published var elapsedBeforeStart = 0.0
    @Published var recordingStartedAt: Date?
    private var previousRecordedLocation: CLLocation?
    func elapsed(at date: Date) -> Double { elapsedBeforeStart + (recordingStartedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0) }
    @Published var message = "記録を開始してください"
    @Published var recordingRecoveryMessage: String?
    @Published var waypoints: [Waypoint] = []
    @Published var library = MapLibrary()
    var defaultWaypointFolder:String { DefaultWaypointFolder.resolve(requested:UserDefaults.standard.string(forKey:"mainWaypointFolder"),folders:library.groups,waypointFolders:waypoints.compactMap(\.group)) }
    private struct LibraryDocument: Codable { var waypoints: [Waypoint]; var library: MapLibrary }
    @Published var quickWaypointID: UUID?
    @Published var savingCurrentWaypoint = false
    private var waypointTimeout: Timer?
    private let manager = CLLocationManager()
    private var pendingStart = false
    private var handle: FileHandle?
    private let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    private var activeSessionFile: URL { directory.appendingPathComponent("active-track.txt") }
    private var pausedSessionFile: URL { directory.appendingPathComponent("paused-track.txt") }
    private var tracksDirectory: URL { directory.appendingPathComponent("tracks", isDirectory: true) }
    private var csv: URL {
        if let name = try? String(contentsOf: activeSessionFile, encoding: .utf8), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return tracksDirectory.appendingPathComponent(name.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let files = (try? FileManager.default.contentsOfDirectory(at: tracksDirectory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { $0.pathExtension == "csv" }.sorted { ($0.lastPathComponent) < ($1.lastPathComponent) }.last ?? directory.appendingPathComponent("track.csv")
    }
    private var waypointFile: URL { directory.appendingPathComponent("waypoints.json") }

    private var libraryFile: URL { directory.appendingPathComponent("map-library-v2.json") }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.headingFilter = kCLHeadingFilterNone
        manager.activityType = .otherNavigation
        manager.pausesLocationUpdatesAutomatically = false
        if let data = try? Data(contentsOf: waypointFile), let saved = try? JSONDecoder().decode([Waypoint].self, from: data) { waypoints = saved }
        if let data = try? Data(contentsOf: libraryFile), let saved = try? JSONDecoder().decode(LibraryDocument.self, from: data) { waypoints = saved.waypoints; library = saved.library }
        waypoints=waypoints.map { item in var item=item;if (item.group ?? "").isEmpty { item.group="メインフォルダ" };return item }
        if FileManager.default.fileExists(atPath: activeSessionFile.path) && FileManager.default.fileExists(atPath: pausedSessionFile.path) {
            recordingPaused = true
            recordingRecoveryMessage = "航跡記録は一時停止中です。再開または終了できます。"
        } else if FileManager.default.fileExists(atPath: activeSessionFile.path) {
            recordingRecoveryMessage = "前回の記録が未完了です。復旧を確認してください。"
            pendingStart = true
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.pendingStart else { return }
            self.pendingStart = false; self.start()
        }
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
            try FileManager.default.createDirectory(at: tracksDirectory, withIntermediateDirectories: true)
            let resumedName = !newTrack ? (try? String(contentsOf: activeSessionFile, encoding: .utf8))?.trimmingCharacters(in:.whitespacesAndNewlines) : nil
            let name = resumedName.flatMap { $0.isEmpty ? nil : $0 } ?? "track-\(ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "").replacingOccurrences(of: ".", with: "" )).csv"
            let sessionURL = tracksDirectory.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: sessionURL.path) { try Data().write(to: sessionURL) }
            try name.write(to: activeSessionFile, atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(at: pausedSessionFile)
            let csv = sessionURL
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: csv.path)
            handle = try FileHandle(forWritingTo: csv)
            try handle?.seekToEnd()
            if let lastLine = (try? String(contentsOf: sessionURL, encoding: .utf8))?.split(whereSeparator: { $0.isNewline }).last(where: { $0 != "#session" }) {
                let fields = lastLine.split(separator:",")
                if fields.count >= 3, let timestamp=Double(fields[0]), let latitude=Double(fields[1]), let longitude=Double(fields[2]) {
                    previousRecordedLocation = CLLocation(coordinate:.init(latitude:latitude,longitude:longitude),altitude:fields.count>3 ? (Double(fields[3]) ?? 0) : 0,horizontalAccuracy:0,verticalAccuracy:0,timestamp:Date(timeIntervalSince1970:timestamp))
                }
            }
            try handle?.write(contentsOf: Data("#session\n".utf8))
            if newTrack {
                track.removeAll()
                recordedDistance = 0; maximumSpeed = 0; elapsedBeforeStart = 0
            }
            previousRecordedLocation = nil; recordingStartedAt = Date()
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
            recording = true; recordingPaused = false
            if CLLocationManager.significantLocationChangeMonitoringAvailable() { manager.startMonitoringSignificantLocationChanges() }
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
        let waypoint = Waypoint(name: "現在地 \(waypoints.count + 1)", latitude: point.coordinate.latitude, longitude: point.coordinate.longitude, colorName: WaypointFolderColors.color(for: defaultWaypointFolder, in: library), group: defaultWaypointFolder)
        add(waypoint)
        quickWaypointID = waypoint.id
        message = "\(waypoint.name) を「\(waypoint.group ?? defaultWaypointFolder)」に保存しました"
    }

    func stop() {
        pendingStart = false
        manager.stopUpdatingLocation(); manager.stopUpdatingHeading()
        manager.stopMonitoringSignificantLocationChanges()
        manager.allowsBackgroundLocationUpdates = false
        do { try handle?.synchronize(); try handle?.close() } catch { fail(error) }
        try? FileManager.default.removeItem(at: activeSessionFile)
        try? FileManager.default.removeItem(at: pausedSessionFile)
        elapsedBeforeStart = elapsed(at: Date()); recordingStartedAt = nil
        handle = nil; recording = false; recordingPaused = false; message = "記録終了・保存済み"; log("Recording stopped")
        preview(foregroundActive)
    }

    func pause() {
        guard recording else { return }
        manager.stopUpdatingLocation(); manager.stopUpdatingHeading(); manager.stopMonitoringSignificantLocationChanges()
        manager.allowsBackgroundLocationUpdates = false
        do { try handle?.synchronize(); try handle?.close() } catch { fail(error) }
        handle=nil;elapsedBeforeStart=elapsed(at:Date());recordingStartedAt=nil;recording=false;recordingPaused=true
        try? "paused".write(to:pausedSessionFile,atomically:true,encoding:.utf8)
        message="記録一時停止中";log("Recording paused")
        preview(foregroundActive)
    }

    func renameTrack(_ file:URL, name:String)->Bool {
        let clean=name.trimmingCharacters(in:.whitespacesAndNewlines).replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:":",with:"_")
        guard !clean.isEmpty else{return false}
        let destination=file.deletingLastPathComponent().appendingPathComponent(clean).appendingPathExtension("csv")
        guard !FileManager.default.fileExists(atPath:destination.path) || destination==file else{return false}
        do {
            if recording && csv==file { try handle?.synchronize();try handle?.close();handle=nil }
            try FileManager.default.moveItem(at:file,to:destination)
            if let active=try? String(contentsOf:activeSessionFile,encoding:.utf8),active.trimmingCharacters(in:.whitespacesAndNewlines)==file.lastPathComponent { try destination.lastPathComponent.write(to:activeSessionFile,atomically:true,encoding:.utf8) }
            if recording && csv==destination { handle=try FileHandle(forWritingTo:destination);try handle?.seekToEnd() }
            return true
        } catch { message="航跡名を変更できませんでした";return false }
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
        if newHeading.headingAccuracy >= 0 { headingUpdatedAt=newHeading.timestamp; magneticHeading = newHeading.magneticHeading; trueHeading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : nil }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for point in locations where point.horizontalAccuracy >= 0 && abs(point.timestamp.timeIntervalSinceNow) < 30 {
            location = point
            if let alert=ZoneAlerts.shared.check(point,library:library,waypoints:waypoints) { message=alert }
            WatchNavigationBridge.shared.updateLocation(point)
            if savingCurrentWaypoint { finishCurrentWaypoint(point) }
            guard recording else { continue }
            if let previous = previousRecordedLocation {
                let gap = point.timestamp.timeIntervalSince(previous.timestamp)
                if gap > 30 { recordingRecoveryMessage = "GPS欠落: \(Int(gap))秒。航跡に空白があります。"; log("GPS gap \(gap)s") }
            }
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
        var waypoint=waypoint
        waypoint.group=DefaultWaypointFolder.destination(explicit:waypoint.group,defaultFolder:defaultWaypointFolder)
        waypoints.append(waypoint); saveWaypoints()
        log("Waypoint added: \(CoordinateInput.format(waypoint.latitude, isLatitude: true)) \(CoordinateInput.format(waypoint.longitude, isLatitude: false))")
    }
    func upsert(_ waypoint: Waypoint) {
        if let index = waypoints.firstIndex(where: { $0.id == waypoint.id }) { waypoints[index] = waypoint; saveWaypoints(); log("Waypoint updated: " + waypoint.name) }
        else { add(waypoint) }
    }
    func upsertStartLineWaypoint(kind: String, coordinate: StartLineCoordinate) {
        guard coordinate.isValid, ["outer", "signal"].contains(kind) else { return }
        let isOuter = kind == "outer"
        let name = isOuter ? "アウターマーク" : "シグナルボート"
        let key = "startLine.\(kind).waypointID"
        let storedID = UserDefaults.standard.string(forKey: key).flatMap(UUID.init(uuidString:))
        let id = storedID ?? UUID()
        let waypoint = Waypoint(
            id: id,
            name: name,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            note: "スタートライン基準点",
            colorName: isOuter ? "#FFAA00" : "#00C8D7",
            markSymbol: isOuter ? "marine.buoy" : "sailboat.fill",
            group: defaultWaypointFolder
        )
        upsert(waypoint)
        UserDefaults.standard.set(id.uuidString, forKey: key)
    }
    func resetCounter() {
        recordedDistance = 0; maximumSpeed = 0; elapsedBeforeStart = 0
        previousRecordedLocation = nil; recordingStartedAt = recording ? Date() : nil
        log("Dashboard counter reset; saved track retained")
    }
    func remove(_ id: UUID) {
        library.features=library.features.map { f in var f=f;if f.waypointIDs.contains(id) { f.coordinates=f.points(waypoints.map(\.archiveEntry));f.waypointIDs=[] };return f }
        waypoints.removeAll { $0.id == id };saveWaypoints()
    }
    func exportWaypoints(_ items: [Waypoint]? = nil, features: [MapFeature] = [], format: String = "json") throws -> URL {
        let entries=(items ?? waypoints).map(\.archiveEntry)
        let data = try format == "json" ? WaypointArchive.encode(entries) : KmlArchive.encode(entries,features:features,kmz:format == "kmz")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SailingGPS-waypoints-\(UUID().uuidString).\(format)")
        try data.write(to:url,options:.atomic);log("Waypoints exported count=\(entries.count) features=\(features.count) format=\(format)");return url
    }
    func saveLibrary(_ items: [Waypoint], _ updated: MapLibrary) throws {
        let items=items.map { item in var item=item;if (item.group ?? "").trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { item.group="メインフォルダ" };return item }
        try WaypointArchive.validate(items.map(\.archiveEntry));for f in updated.features { try f.validate() }
        try JSONEncoder().encode(LibraryDocument(waypoints:items,library:updated)).write(to:libraryFile,options:.atomic)
        waypoints=items;library=updated;log("Map library saved groups=\(updated.groups.count) features=\(updated.features.count)")
    }
    func importWaypoints(_ archive: KmlArchive.Import) throws -> (Int, Int) {
        let incoming=archive.waypoints.map { item in var item=item;if (item.group ?? "").isEmpty { item.group="メインフォルダ" };return item }
        let result = try WaypointArchive.merge(existing: waypoints.map(\.archiveEntry), incoming: incoming)
        var mapping: [UUID:UUID] = [:]
        for e in incoming { mapping[e.id]=result.entries.first(where:{$0.sameContent(e)})?.id ?? e.id }
        var updated=library
        for var feature in archive.features {
            feature.waypointIDs=feature.waypointIDs.map{mapping[$0] ?? $0}
            if updated.features.contains(where:{$0.name==feature.name && $0.kind==feature.kind && $0.group==feature.group && $0.radius==feature.radius && $0.points(result.entries)==feature.points(result.entries)}) { continue }
            if updated.features.contains(where:{$0.id==feature.id}) { feature.id=UUID() };updated.features.append(feature)
        }
        updated.groups=Array(Set(updated.groups + incoming.compactMap(\.group) + archive.features.map(\.group))).filter{!$0.isEmpty}.sorted()
        try saveLibrary(result.entries.map{Waypoint(archive:$0)},updated)
        log("Waypoints imported added=\(result.added) skipped=\(result.skipped) features=\(archive.features.count)")
        return (result.added,result.skipped)
    }
    private func saveWaypoints() { do { try saveLibrary(waypoints,library) } catch { fail(error) } }
    func loadTrack(_ file: URL) {
        DispatchQueue.global(qos:.userInitiated).async {
            let coords=((try? String(contentsOf:file,encoding:.utf8)) ?? "").split(whereSeparator:{$0.isNewline}).compactMap { line -> CLLocationCoordinate2D? in
                let f=line.split(separator:",");guard f.count>=3,let lat=Double(f[1]),let lon=Double(f[2]),(-90...90).contains(lat),(-180...180).contains(lon) else{return nil};return .init(latitude:lat,longitude:lon)
            }
            DispatchQueue.main.async { self.track=Array(coords.suffix(10000));self.message="航跡を表示中：\(file.deletingPathExtension().lastPathComponent)" }
        }
    }
    func export(source: URL? = nil) -> URL? {
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
            let source=source ?? csv
            if FileManager.default.fileExists(atPath: source.path) {
                let input = try FileHandle(forReadingFrom: source)
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
    func log(_ text: String) {
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
    @State private var mapMetersPerCm = 200.0
    @State private var showAllRequest = 0
    @StateObject private var gps = GPSRecorder()
    @AppStorage("displayMode") private var mode = 0
    @AppStorage("magneticHeadingMode") private var magnetic = true
    @AppStorage("relativeTargetBearing") private var relativeTargetBearing = false
    @AppStorage("compassWhileMoving") private var compassWhileMoving = false
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
    @State private var importingWaypoints = false
    @State private var pendingWaypointImport = KmlArchive.Import()
    @State private var libraryPresented = false
    @State private var importConfirmation = false
    @State private var transferNotice = ""
    @State private var showTransferNotice = false
    @State private var importSummary = ""
    @State private var settings = false
    @State private var modeSelectionPresented = false
    @State private var menuPresented = false
    @State private var confirmFinishRecording = false
    @State private var waypointListPresented = false
    @State private var trackListPresented = false
    @State private var waypointFolder = ""
    @AppStorage("mainWaypointFolder") private var savedMainWaypointFolder = ""
    private var waypointFolders: [String] { Array(Set(gps.library.groups + gps.waypoints.compactMap(\.group))).filter{!$0.isEmpty}.sorted() }
    private var mainWaypointFolder: String { DefaultWaypointFolder.resolve(requested:savedMainWaypointFolder,folders:gps.library.groups,waypointFolders:gps.waypoints.compactMap(\.group)) }
    @State private var editorDraft: Waypoint?
    @State private var mapOperationsCoordinate: CLLocationCoordinate2D?
    @State private var mapOperationsPresented = false
    @State private var navigationOptionsPresented = false
    @State private var nearestWaypoints = false
    @State private var navigationCandidate: Waypoint?
    @State private var confirmNavigation = false
    @State private var pendingNavigationEditor = false
    @AppStorage("showMapWaypoints") private var showMapWaypoints = true
    @AppStorage("showCourseLine") private var showCourseLine = true
    private var navigationReference: CoordinateInput.HeadingReading? {
        CoordinateInput.headingReference(preferGps: !magnetic, magnetic: gps.magneticHeading, trueHeading: gps.trueHeading, course: gps.location?.course, speed: gps.location?.speed, compassWhileMoving: compassWhileMoving)
    }
    private var heading: Double? { navigationReference?.heading }
    private var mapHeading: Double? { navigationReference?.trueHeading }
    private var speedUnit: String { metricUnits ? "km/h" : "knot" }
    @AppStorage("instrumentMagnetic") private var instrumentMagnetic=false
    @AppStorage("largeDecimal") private var largeDecimal=true
    @AppStorage("coordinateFormat") private var coordinateFormat="dm"
    @AppStorage("twelveHourClock") private var twelveHourClock=false
    @AppStorage("keepScreenAwake") private var keepScreenAwake=false
    @AppStorage("zeroSpeedThreshold") private var zeroSpeedThreshold=0.0
    @AppStorage("arrivalUsesAverage") private var arrivalUsesAverage=false
    @AppStorage("showETA") private var showETA=false
    private var speedText:String {
        #if DEBUG
        if let index=ProcessInfo.processInfo.arguments.firstIndex(of:"--preview-speed-value"), ProcessInfo.processInfo.arguments.count>index+1 {
            return ProcessInfo.processInfo.arguments[index+1]
        }
        #endif
        return InstrumentSettings.speedText(gps.location?.speed,factor:metricUnits ? 3.6:1.943844,zeroThreshold:zeroSpeedThreshold)
    }
    private func displayCoordinate(_ value:Double,isLatitude:Bool)->String { InstrumentSettings.coordinate(value,isLatitude:isLatitude,format:coordinateFormat) }
    private func clock(_ date:Date)->String {
        let formatter=DateFormatter();formatter.locale=Locale(identifier:"en_US_POSIX");formatter.dateFormat=twelveHourClock ? "h:mm:ss a":"HH:mm:ss"
        return formatter.string(from:date)
    }
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
        let elapsed=gps.elapsed(at:Date())
        let speed=arrivalUsesAverage ? (elapsed>0 ? gps.recordedDistance/elapsed:nil):point.speed
        return InstrumentSettings.arrival(distance:point.distance(from:CLLocation(latitude:target.latitude,longitude:target.longitude)),speed:speed,now:Date(),eta:showETA,twelveHour:twelveHourClock)
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
                Text(relativeTargetBearing ? "目標相対方位（前方0°）" : (navigationReference?.magnetic == true ? "目標方位（磁北）" : "目標方位（真北）")).font(.caption2)
                let relative = targetDisplayBearing.flatMap { value in compassReferenceHeading.map { CoordinateInput.relativeBearing(value,heading:$0) } }
                Text(relativeTargetBearing ? (relative.map(CoordinateInput.relativeBearingText) ?? "—") : (targetDisplayBearing.map { String(format: "%.0f°", $0) } ?? "—")).font(.title.bold()).foregroundStyle(.green)
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
                    Label(showETA ? "目標, ETA":"目標, ETE", systemImage: "clock").font(.caption2).foregroundStyle(.gray)
                    Text(ete).font(.system(size: 22, weight: .bold, design: .monospaced)).foregroundStyle(.orange).minimumScaleFactor(0.45).lineLimit(1)
                }.frame(width: proxy.size.width * 0.26, alignment: .leading)
                compass.scaleEffect(dial / 154).frame(width: dial, height: dial)
                VStack(spacing: 8) {
                    Button("目標") { navigationOptionsPresented = true }.font(.headline).foregroundStyle(.orange)
                        .frame(maxWidth: .infinity).overlay(RoundedRectangle(cornerRadius: 4).stroke(.orange))
                    Text(target?.name ?? "設定目標").font(.system(size: 23, weight: .bold)).foregroundStyle(target == nil ? .orange : .white).minimumScaleFactor(0.5).lineLimit(2)
                    if let target {
                        Text(displayCoordinate(target.latitude, isLatitude: true) + "\n" + displayCoordinate(target.longitude, isLatitude: false))
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
            NavigationMapView(location: gps.location, heading: mapHeading, waypoints: gps.waypoints, library: gps.library, showWaypoints: showMapWaypoints, showCourse: showCourseLine, track: gps.track, selected: $selected, following: $following, metersPerCm: mapMetersPerCm, showAllRequest: showAllRequest, editWaypoint: { editorDraft = $0 }, createWaypoint: { coordinate in
                mapOperationsCoordinate = coordinate; mapOperationsPresented = true
            })
            .overlay(alignment: .trailing) {
                VStack(spacing: 4) {
                    Button { mapMetersPerCm = max(12.5, mapMetersPerCm / 2) } label: { Image(systemName: "plus") }
                        .accessibilityLabel("地図を拡大").disabled(mapMetersPerCm <= 12.5)
                    Button { mapMetersPerCm = min(6400, mapMetersPerCm * 2) } label: { Image(systemName: "minus") }
                        .accessibilityLabel("地図を縮小").disabled(mapMetersPerCm >= 6400)
                }.font(.title2).tint(.orange).buttonStyle(.borderedProminent).padding(8)
            }
            .overlay(alignment: .top) {
                if !following { Button("再度中心に配置") { following = true }.font(.caption).buttonStyle(.borderedProminent).tint(.orange).foregroundStyle(.black).padding(.top, 48) }
            }
            HStack {
                Button { following = true } label: { Image(systemName: "location.north.fill") }
                    .accessibilityLabel("現在地へ追従")
                Spacer()
                Text("長押しで地図操作").font(.caption2).padding(4).background(.black.opacity(0.5)).foregroundStyle(.white)
                Spacer()
                Button { following = false; showAllRequest += 1 } label: { Image(systemName: "square.3.layers.3d") }
                    .accessibilityLabel("全ウェイポイント")
            }.font(.title3).tint(.black).buttonStyle(.borderedProminent).padding(8)
        }
    }
    private var appVersionText: String {
        let version=Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? ""
        let build=Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? ""
        return "Sailing GPS \(version) · build \(build)"
    }
    private var waypointEditor: some View {
        NavigationStack {
            Form {
                Section("表示") {
                    Picker("単位", selection: $metricUnits) { Text("knot / nm").tag(false); Text("km/h / m・km").tag(true) }
                    Picker("モード", selection: $mode) { Text("スピードメーター").tag(0); Text("ナビゲーター").tag(1); Text("セーリング").tag(2); Text("タイマー").tag(3); Text("シグナル").tag(4) }
                    Toggle("端末の向きで追従", isOn: $magnetic)
                    Text("OFFではGPS進行方位で追従します").font(.caption)
                    Toggle("移動中も磁気コンパスを使用",isOn:$compassWhileMoving)
                    Text("ONでは移動中も磁気コンパスを優先します。磁気コンパスを取得できない場合はGPS進行方位を使います。").font(.caption)
                }
                DetailedSettingsView(gps:gps)
                Section("ウェイポイント") {
                    Picker("デフォルトの保存先", selection: Binding(get: { mainWaypointFolder }, set: { savedMainWaypointFolder = $0 })) {
                        ForEach(waypointFolders, id: \.self) { folder in
                            Text(folder + (folder == mainWaypointFolder ? " ★デフォルト" : "")).tag(folder)
                        }
                    }
                    Text("現在地WP・新規ウェイポイントの保存先：\(mainWaypointFolder)").font(.caption)
                    Text("既存のウェイポイントは移動しません。個別の編集画面で保存フォルダを変更できます。").font(.caption)
                }
                Section("GPS") {
                    reading("GPS精度", gps.location.map { String(format: "±%.0f m", $0.horizontalAccuracy) } ?? "—")
                    Text(gps.message).font(.caption)
                }
                Section("アプリ") { Text(appVersionText) }
            }.navigationTitle("設定").toolbar { Button("完了") { settings = false } }
        }.tint(.orange).preferredColorScheme(.dark)
    }
    private func makeDraft(_ coordinate: CLLocationCoordinate2D? = nil) -> Waypoint {
        let coordinate = coordinate ?? gps.location?.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        return Waypoint(name: Date.now.formatted(date: .numeric, time: .shortened), latitude: coordinate.latitude, longitude: coordinate.longitude, group: mainWaypointFolder)
    }
    private var waypointList: some View {
        NavigationStack {
            List {
                Button { selected = nil; savedTarget = "__none__"; waypointListPresented = false } label: {
                    HStack { Text("目標なし"); Spacer(); if selected == nil { Image(systemName: "checkmark") } }
                }
                Picker("フォルダ",selection:$waypointFolder) { ForEach(waypointFolders,id:\.self){Text($0 + ($0 == mainWaypointFolder ? " ★デフォルト" : "")).tag($0)} }
                Text("現在地WPの保存先：\(mainWaypointFolder)").font(.caption).foregroundStyle(.orange)
                Button(waypointFolder == mainWaypointFolder ? "このフォルダがデフォルトです" : "このフォルダをデフォルトにする") { savedMainWaypointFolder=waypointFolder }.disabled(waypointFolder.isEmpty || waypointFolder == mainWaypointFolder)
                if orderedWaypoints.filter({($0.group ?? "")==waypointFolder}).isEmpty { Text("このフォルダにウェイポイントはありません") }
                ForEach(orderedWaypoints.filter{($0.group ?? "")==waypointFolder}) { wp in
                    HStack {
                        Button {
                            waypointListPresented = false; proposeNavigation(wp)
                        } label: {
                            VStack(alignment: .leading) {
                                HStack {
                                    if let text = wp.markText, !text.isEmpty { Text(text) }
                                    else { WaypointMarkIcon(symbol: wp.markSymbol ?? "flag.fill") }
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
            }.navigationTitle(nearestWaypoints ? "目標・近い順" : "ウェイポイント・最近")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完了") { waypointListPresented = false } }
                    ToolbarItem(placement: .primaryAction) { Button { waypointListPresented = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { editorDraft = makeDraft() } } label: { Image(systemName: "plus") } }
                }
        }.tint(.orange).preferredColorScheme(.dark)
    }
    private var orderedWaypoints: [Waypoint] {
        if nearestWaypoints, let point = gps.location {
            return gps.waypoints.sorted { point.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) < point.distance(from: CLLocation(latitude: $1.latitude, longitude: $1.longitude)) }
        }
        return Array(gps.waypoints.reversed())
    }
    private func proposeNavigation(_ waypoint: Waypoint) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { navigationCandidate = waypoint; confirmNavigation = true }
    }
    private var modeSelection: some View {
        ModeSelectionView(onSelect: { selectedMode in
            mode = selectedMode
            modeSelectionPresented = false
        }, onCancel: { modeSelectionPresented = false })
    }
    private func operationButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).font(.subheadline.bold()).multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 62).padding(5)
            .foregroundStyle(.white).background(Color(white: 0.18)).overlay(RoundedRectangle(cornerRadius: 4).stroke(.orange)) }
    }
    private var mapOperations: some View {
        VStack(spacing: 5) {
            HStack {
                VStack(alignment: .leading) {
                    Text("地図の操作").font(.headline)
                    if let coordinate = mapOperationsCoordinate { Text(CoordinateInput.format(coordinate.latitude, isLatitude: true) + ", " + CoordinateInput.format(coordinate.longitude, isLatitude: false)).font(.caption.monospacedDigit()) }
                }
                Spacer(); Button { mapOperationsPresented = false } label: { Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.orange) }
            }
            HStack {
                operationButton("ここにウェイポイントを作成") { mapOperationsPresented = false; if let coordinate = mapOperationsCoordinate { editorDraft = makeDraft(coordinate) } }
                operationButton("座標をコピー") { if let coordinate = mapOperationsCoordinate { UIPasteboard.general.string = CoordinateInput.format(coordinate.latitude, isLatitude: true) + ", " + CoordinateInput.format(coordinate.longitude, isLatitude: false) }; mapOperationsPresented = false }
            }
            HStack {
                operationButton(showMapWaypoints ? "ウェイポイントを非表示" : "ウェイポイントを表示") { showMapWaypoints.toggle(); mapOperationsPresented = false }
                operationButton(showCourseLine ? "進路ラインを隠す" : "進路ラインを表示") { showCourseLine.toggle(); mapOperationsPresented = false }
            }
            operationButton("再度中心に配置") { following = true; mapOperationsPresented = false }
        }.padding(8).background(Color(white: 0.08).opacity(0.97)).overlay(RoundedRectangle(cornerRadius: 8).stroke(.orange)).padding(4)
    }
    private var navigationOptions: some View {
        VStack(spacing: 5) {
            HStack { Text("ナビゲーションのオプション").font(.headline); Spacer(); Button { navigationOptionsPresented = false } label: { Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.orange) } }
            HStack {
                operationButton("新規ウェイポイント") { navigationOptionsPresented = false; pendingNavigationEditor = true; editorDraft = makeDraft() }
                operationButton("既存ウェイポイント\n（近い順）") { navigationOptionsPresented = false; nearestWaypoints = true; waypointListPresented = true }
            }
            HStack {
                operationButton("既存ウェイポイント\n（最近）") { navigationOptionsPresented = false; nearestWaypoints = false; waypointListPresented = true }
                operationButton("目標なし") { navigationOptionsPresented = false; selected = nil; savedTarget = "__none__" }
            }
        }.padding(8).background(Color(white: 0.08).opacity(0.97)).overlay(RoundedRectangle(cornerRadius: 8).stroke(.orange)).padding(4)
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
                    menuTile("新しい航跡を開始", detail: "現在の記録を保存して別航跡を作成") { menuAction { if gps.recording || gps.recordingPaused { gps.stop() }; gps.start(newTrack: true) } }
                    if gps.recording { menuTile("Ⅱ 記録を一時停止") { menuAction { gps.pause() } } }
                    if gps.recordingPaused { menuTile("▶ 記録を再開") { menuAction { gps.start() } } }
                    if !gps.recording && !gps.recordingPaused { menuTile("● 記録開始") { menuAction { gps.start(newTrack:true) } } }
                    if gps.recording || gps.recordingPaused { menuTile("■ 記録終了・保存") { menuAction { confirmFinishRecording=true } } }
                    menuTile("カウンターをリセット", detail: "保存した航跡は保持") { menuAction { gps.resetCounter() } }
                    menuTile("地点・グループ・エリア", detail: "入出力・円・囲み・直線") { menuAction { libraryPresented = true } }
                    menuTile("WPインポート", detail: "既存の地点を残して追加") { menuAction { importingWaypoints = true } }
                    menuTile("追跡・GPX出力") { menuAction { exported = gps.export(); sharing = exported != nil } }
                    menuTile("航跡一覧", detail: "保存済み記録を確認") { menuAction { trackListPresented = true } }
                    menuTile("設定") { menuAction { settings = true } }
                    menuTile("モード", detail: "ナビゲーション／スピード") { menuAction { modeSelectionPresented = true } }
                }
                VStack(spacing: 5) {
                    menuTile("新規ウェイポイント") { menuAction { editorDraft = makeDraft() } }
                    menuTile("目標", detail: target?.name ?? "未設定") { menuAction { navigationOptionsPresented = true } }
                    menuTile("📍 ウェイポイント", detail: "一覧・編集・削除") { menuAction { waypointListPresented = true } }
                    menuTile("現在地に打つ", detail:"保存先：\(mainWaypointFolder)") { menuAction { gps.saveCurrentWaypoint() } }
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
            Button { mode = (mode + 1) % 5 } label: {
                Text(["スピードメーター", "ナビゲーション", "セーリング", "タイマー", "シグナル"][max(0, min(4, mode))])
                    .font(.caption.bold()).lineLimit(1).minimumScaleFactor(0.7)
            }.accessibilityLabel("現在のモード。タップで次のモードに切替")
            Spacer()
            if mode == 0 { Text(speedUnit).font(.title2.bold()) }
            Spacer()
            HStack(spacing:6) {
                if !gps.recording { Button { gps.start() } label:{Image(systemName:gps.recordingPaused ? "play.fill":"record.circle.fill").foregroundStyle(.red)}.accessibilityLabel(gps.recordingPaused ? "航跡記録を再開":"航跡記録を開始") }
                if gps.recording { Button { gps.pause() } label:{Image(systemName:"pause.fill").foregroundStyle(.orange)}.accessibilityLabel("航跡記録を一時停止") }
                if gps.recording || gps.recordingPaused { Button { confirmFinishRecording=true } label:{Image(systemName:"stop.fill").foregroundStyle(.red)}.accessibilityLabel("航跡記録を終了") }
            }
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
                    instrument(clock(context.date), label: "時間", size: 23)
                }
            }.padding(8).frame(maxHeight: .infinity)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.gray))
        }
    }
    private var modeTitle: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            Button {
                mode = (mode + 1) % 5
            } label: {
                Text(["スピードメーター", "ナビゲーション", "セーリング", "スタートタイマー", "シグナル"][max(0, min(4, mode))])
                    .font(.system(size: 29, weight: .medium)).minimumScaleFactor(0.6).lineLimit(1).foregroundStyle(.orange)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("現在のモード。タップで次のモードに切替")
            Text(gps.recording ? "● 記録中" : (gps.recordingPaused ? "Ⅱ 一時停止中" : "○ 停止中"))
                .font(.caption.bold()).foregroundStyle(gps.recording ? .green : .orange)
                .lineLimit(1).minimumScaleFactor(0.65).fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel("航跡記録の状態")
            Spacer(minLength: 0)
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
                Text(gps.location.map { displayCoordinate($0.coordinate.latitude, isLatitude:true) } ?? "---")
                Text(gps.location.map { displayCoordinate($0.coordinate.longitude, isLatitude:false) } ?? "---")
            }.font(.system(size: 23, weight: .bold, design: .monospaced)).minimumScaleFactor(0.5).lineLimit(1).frame(maxWidth: .infinity)
        }.padding(.horizontal, 5).overlay(alignment: .top) { Rectangle().fill(.gray).frame(height: 1) }
    }
    private var focusTargetBearing:Double? {
        guard let target,let point=gps.location,point.distance(from:CLLocation(latitude:target.latitude,longitude:target.longitude))>1 else {return nil}
        return targetBearing
    }
    private var focusDashboard:some View {
        TimelineView(.periodic(from:.now,by:1)) { _ in
            let age=gps.location.map{Date().timeIntervalSince($0.timestamp)} ?? .infinity
            let fresh=age>=0 && age<=15
            #if DEBUG
            let preview=ProcessInfo.processInfo.arguments.contains("--preview-focus")
            #else
            let preview=false
            #endif
            let compassFresh=gps.headingUpdatedAt.map{(-5...15).contains(Date().timeIntervalSince($0))} ?? false
            let magHeading=preview ? 218:(compassFresh ? gps.magneticHeading:nil)
            let trueHeading=preview ? 210:(compassFresh ? gps.trueHeading:nil)
            let reading=InstrumentHeading.resolve(course:preview ? 82:InstrumentSettings.course(gps.location?.course,speed:gps.location?.speed,age:age),speed:preview ? 3:(fresh ? gps.location?.speed:nil),magneticHeading:magHeading,trueHeading:trueHeading,magnetic:instrumentMagnetic,compassWhileMoving:compassWhileMoving)
            let targetValue=InstrumentHeading.bearing(preview ? 144:(fresh ? focusTargetBearing:nil),magnetic:instrumentMagnetic,declination:InstrumentHeading.declination(magnetic:magHeading,trueHeading:trueHeading))
            FocusDashboardView(speed:preview ? "12.3":(fresh ? speedText:"—"),
                course:reading?.value,isCompass:reading?.compass ?? false,
                targetBearing:targetValue,relativeTargetBearing:relativeTargetBearing,unit:speedUnit,mode:$mode,magnetic:$instrumentMagnetic,
                chooseTarget:{navigationOptionsPresented=true},openMenu:{menuPresented=true})
        }
    }
    private var startTimerDashboard: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<5) { index in
                    Button(["速度","地図","セーリング","タイマー","シグナル"][index]) { mode = index }
                        .frame(maxWidth: .infinity).buttonStyle(.bordered)
                        .tint(index == mode ? .green : .orange)
                }
                Button { menuPresented = true } label: { Image(systemName: "line.3.horizontal") }
                    .buttonStyle(.bordered).tint(.orange).accessibilityLabel("メニュー")
            }.font(.caption)
            StartTimerPanel(
                currentLocation: gps.location.flatMap { Date().timeIntervalSince($0.timestamp) <= 15 && $0.horizontalAccuracy >= 0
                    ? StartLineCoordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) : nil },
                metric: metricUnits,
                onRegisterWaypoint: { kind, coordinate in gps.upsertStartLineWaypoint(kind: kind, coordinate: coordinate) }
            )
        }.padding(8).background(.black).preferredColorScheme(.dark)
    }
    private var signalDashboard: some View {
        VStack(spacing: 4) {
            modeTitle.frame(height: 38)
            SignalTimerPanel(compact: false).padding(.horizontal, 8)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black).foregroundStyle(.white).preferredColorScheme(.dark)
    }
    private var dashboard: some View {
        GeometryReader { geometry in
            let height = max(620, geometry.size.height)
            if mode == 2 { focusDashboard }
            else if mode == 3 { startTimerDashboard }
            else if mode == 4 { signalDashboard }
            else { ScrollView {
                VStack(spacing: 6) {
                    ZStack(alignment: .top) {
                        if mode == 1 { mapPanel }
                        else {
                            SevenSegmentSpeed(text: speedText, largeDecimal:largeDecimal).padding(.horizontal, 12).padding(.top, 48).padding(.bottom, 12)
                        }
                        topControls
                    }.frame(height: height * 0.39)
                    targetPanel.frame(height: height * 0.205).padding(.horizontal, 3)
                    modeTitle.frame(height: 40)
                    instruments.frame(height: height * 0.205).padding(.horizontal, 3)
                    positionReadings.frame(height: height * 0.11)
                }.frame(minHeight: geometry.size.height)
            }.scrollIndicators(.hidden) }
        }.background(.black).foregroundStyle(.white).preferredColorScheme(.dark)
    }
    private func reportTransfer(_ text: String) {
        transferNotice = text; showTransferNotice = true
    }
    private func readWaypointImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
            let data = try handle.read(upToCount: KmlArchive.maxBytes + 1) ?? Data()
            let archive: KmlArchive.Import
            if String(decoding:data.prefix(40),as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines).hasPrefix("{") { archive = .init(waypoints:try WaypointArchive.decode(data)) } else { archive = try KmlArchive.decode(data) }
            let entries = archive.waypoints
            let preview = try WaypointArchive.merge(existing: gps.waypoints.map(\.archiveEntry), incoming: entries)
            pendingWaypointImport = archive
            importSummary = "追加 \(preview.added)件・重複 \(preview.skipped)件・図形 \(archive.features.count)件\n\(archive.warnings.joined(separator:"\n"))\n既存の地点と選択中の目標は保持します。"
            importConfirmation = true
        } catch { gps.log("Waypoint import rejected: " + error.localizedDescription); reportTransfer("取り込みできませんでした。\n" + error.localizedDescription) }
    }
    private var navigationDashboard: some View {
        ZStack {
            dashboard
            if menuPresented { navigationMenu }
            VStack { Spacer(); if mapOperationsPresented { mapOperations } else if navigationOptionsPresented { navigationOptions } }
        }
        .alert("この目標へナビ開始", isPresented: $confirmNavigation) {
            Button("Go!") { if let waypoint = navigationCandidate { selected = waypoint.id; following = true } }
            Button("キャンセル", role: .cancel) { navigationCandidate = nil }
        } message: {
            if let waypoint = navigationCandidate { Text(waypoint.name + "\n" + CoordinateInput.format(waypoint.latitude, isLatitude: true) + ", " + CoordinateInput.format(waypoint.longitude, isLatitude: false)) }
        }
    }
    private var transferDashboard: some View {
        navigationDashboard
        .fileImporter(isPresented: $importingWaypoints, allowedContentTypes: [.json, .xml, .zip, .data, UTType(filenameExtension:"kmz") ?? .data, UTType(filenameExtension:"kml") ?? .xml], allowsMultipleSelection: false, onCompletion: readWaypointImport)
        .confirmationDialog("ウェイポイントを取り込みますか？", isPresented: $importConfirmation, titleVisibility: .visible) {
            Button("追加する") {
                do { let counts = try gps.importWaypoints(pendingWaypointImport); reportTransfer("追加 \(counts.0)件・重複 \(counts.1)件") }
                catch { gps.log("Waypoint import save failed: " + error.localizedDescription); reportTransfer("保存できませんでした。\n" + error.localizedDescription) }
                pendingWaypointImport = KmlArchive.Import()
            }
            Button("キャンセル", role: .cancel) { pendingWaypointImport = KmlArchive.Import() }
        } message: { Text(importSummary) }
        .alert("ウェイポイントの入出力", isPresented: $showTransferNotice) { Button("OK", role: .cancel) {} } message: { Text(transferNotice) }
    }
    private var presentedDashboard: some View {
        transferDashboard
        .sheet(isPresented: $sharing) { if let exported { ShareView(url: exported) } }
        .sheet(isPresented: $modeSelectionPresented) { modeSelection.presentationDetents([.large]).presentationDragIndicator(.hidden) }
        .sheet(isPresented: $libraryPresented) { MapLibraryView(gps:gps,export:exportLibrary,importFile:beginLibraryImport) }
        .sheet(isPresented: $settings) { waypointEditor }
        .sheet(isPresented: $waypointListPresented) { waypointList.onAppear { waypointFolder=mainWaypointFolder } }
        .sheet(isPresented: $trackListPresented) {
            TrackListView(gps:gps,onSelect:{ file in gps.loadTrack(file);mode=1;following=false },onExport:{ file in exported=gps.export(source:file);sharing=exported != nil })
        }
        .sheet(item: $editorDraft, onDismiss: { pendingNavigationEditor = false }) { draft in
            WaypointEntryView(waypoint: draft, folders: waypointFolders, defaultFolder: mainWaypointFolder, folderColors: gps.library.groupColors) { waypoint, navigate in
                gps.upsert(waypoint)
                if navigate || pendingNavigationEditor { proposeNavigation(waypoint) }
            }
        }
    }
    private func exportLibrary(_ items:[Waypoint], _ features:[MapFeature], _ format:String) {
        do { exported=try gps.exportWaypoints(items,features:features,format:format);libraryPresented=false
            DispatchQueue.main.asyncAfter(deadline:.now()+0.5){sharing=true}
        } catch { reportTransfer(error.localizedDescription) }
    }
    private func beginLibraryImport() { libraryPresented=false;DispatchQueue.main.asyncAfter(deadline:.now()+0.5){importingWaypoints=true} }
    private var previewDashboard: some View {
        presentedDashboard.onChange(of: scenePhase) { _, phase in gps.preview(phase == ScenePhase.active) }
        .onAppear {
            gps.preview(true)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--preview-library-overlays") {
                var items=gps.waypoints
                if items.count<3 { items.append(Waypoint(name:"TEST C",latitude:35.316,longitude:139.468)) }
                if items.count>=3 {
                    var circle=MapFeature(name:"半径200m",kind:"circle");circle.waypointIDs=[items[0].id];circle.group="デモ海域"
                    var area=MapFeature(name:"囲みエリア",kind:"area");area.waypointIDs=Array(items.prefix(3)).map(\.id);area.color="#CC44AA";area.group="デモ海域"
                    var line=MapFeature(name:"地点間の直線",kind:"line");line.waypointIDs=Array(items.prefix(2)).map(\.id);line.color="#FFFF00";line.group="デモ海域"
                    try? gps.saveLibrary(items,MapLibrary(groups:["デモ海域"],features:[circle,area,line]))
                }
            }
            if ProcessInfo.processInfo.arguments.contains("--preview-library") || ProcessInfo.processInfo.arguments.contains("--preview-circle-editor") { libraryPresented=true }
            if ProcessInfo.processInfo.arguments.contains("--preview-map-operations") { mapOperationsCoordinate = .init(latitude: 35.318, longitude: 139.467); mapOperationsPresented = true }
            if ProcessInfo.processInfo.arguments.contains("--preview-navigation-options") { navigationOptionsPresented = true }
            if ProcessInfo.processInfo.arguments.contains("--preview-focus") { mode=2 }
            if ProcessInfo.processInfo.arguments.contains("--preview-settings") { settings=true }
            if ProcessInfo.processInfo.arguments.contains("--preview-menu") { menuPresented = true }
            if ProcessInfo.processInfo.arguments.contains("--preview-waypoint") {
                gps.library.groups=Array(Set(gps.library.groups+["港一覧","デモ海域"])).sorted()
                savedMainWaypointFolder="港一覧"
                editorDraft = Waypoint(name: "新規ウェイポイント", latitude: 35 + 19.528/60, longitude: 139 + 27.130/60, colorName: "#12ABCD", markSymbol: "marine.harbor", group:"港一覧")
            }
            #endif
            selected = savedTarget == "__none__" ? nil : (gps.waypoints.first { $0.id.uuidString == savedTarget }?.id ?? gps.waypoints.first?.id)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--target-none") { selected = nil; savedTarget = "__none__" }
            #endif
            WatchNavigationBridge.shared.setWaypoints(gps.waypoints)
            WatchNavigationBridge.shared.setTarget(target, metric: metricUnits)
        }
    }
    var body: some View {
        previewDashboard.onChange(of: gps.quickWaypointID) { _, value in
            if let value { selected = value; following = true }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled=keepScreenAwake }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled=false }
        .onChange(of:keepScreenAwake) { _, value in UIApplication.shared.isIdleTimerDisabled=value }
        .onChange(of: selected) { _, value in
            savedTarget = value?.uuidString ?? "__none__"
            WatchNavigationBridge.shared.setTarget(target, metric: metricUnits)
        }
        .onChange(of: metricUnits) { _, _ in WatchNavigationBridge.shared.setTarget(target, metric: metricUnits) }
        .onReceive(gps.$recording) { recording in
            WatchNavigationBridge.shared.setRecording(recording, message: gps.message)
        }
        .onReceive(gps.$message) { message in
            WatchNavigationBridge.shared.setRecording(gps.recording, message: message)
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchRecordingRequested)) { notification in
            guard let shouldStart = notification.userInfo?["start"] as? Bool else { return }
            UserDefaults.standard.removeObject(forKey: "watchPendingRecordingStart")
            if shouldStart && !gps.recording { gps.start() }
            if !shouldStart && gps.recording { gps.stop() }
            WatchNavigationBridge.shared.setRecording(gps.recording, message: gps.message)
        }
        .onAppear { consumePendingWatchRecordingCommand() }
        .confirmationDialog("航跡記録を終了しますか？",isPresented:$confirmFinishRecording,titleVisibility:.visible) {
            Button("記録終了して保存",role:.destructive){gps.stop()}
            Button("キャンセル",role:.cancel){}
        } message:{Text("ここまでの航跡を保存し、次回は別の航跡として記録します。")}
        .onReceive(gps.$waypoints) { points in
            WatchNavigationBridge.shared.setWaypoints(points)
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchTargetChanged)) { notification in
            guard let id = notification.userInfo?["targetID"] as? String else { return }
            selected = gps.waypoints.first { $0.id.uuidString == id }?.id
            savedTarget = selected?.uuidString ?? "__none__"
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchStartLineWaypointRequested)) { notification in
            guard let kind = notification.userInfo?["kind"] as? String,
                  let latitude = notification.userInfo?["latitude"] as? Double,
                  let longitude = notification.userInfo?["longitude"] as? Double else { return }
            gps.upsertStartLineWaypoint(kind: kind, coordinate: StartLineCoordinate(latitude: latitude, longitude: longitude))
        }
        .onChange(of: gps.waypoints.count) { _, _ in
            if let selected, !gps.waypoints.contains(where: { $0.id == selected }) { self.selected = nil }
        }
    }
    private func consumePendingWatchRecordingCommand() {
        guard let shouldStart = UserDefaults.standard.object(forKey: "watchPendingRecordingStart") as? Bool else { return }
        UserDefaults.standard.removeObject(forKey: "watchPendingRecordingStart")
        if shouldStart && !gps.recording { gps.start() }
        if !shouldStart && gps.recording { gps.stop() }
        WatchNavigationBridge.shared.setRecording(gps.recording, message: gps.message)
    }
}
private struct ModeSelectionView: View {
    let onSelect: (Int) -> Void
    let onCancel: () -> Void
    @State private var expandedInfoID: Int?
    private struct Mode: Identifiable {
        let id: Int
        let title: String
        let summary: String
        let details: String
    }
    private let modes: [Mode] = [
        Mode(id: 1, title: "ナビゲーション", summary: "目標への方位・距離と現在地を確認します。", details: "地図、ウェイポイント、目標方位、距離を表示します。"),
        Mode(id: 0, title: "スピードメーター", summary: "スピードメーター", details: "GPS速度を大きく表示します。"),
        Mode(id: 2, title: "セーリング", summary: "SOG・COG・目標方位を大きく表示します。", details: "SOG（対地速度）、COG（対地針路）、目標方位を大きく表示します。真北／磁北を切り替えられます。"),
        Mode(id: 3, title: "スタートタイマー", summary: "スタートラインまでの距離とカウントダウンを表示します。", details: "アウターマークとシグナルボートを登録し、ラインまでの距離を確認できます."),
        Mode(id: 4, title: "シグナル", summary: "旗のアニメーションとスタートまでの時間を表示します。", details: "ntp.nict.jpの時刻と同期するか、手動ゼロ合わせで開始できます。")
    ]
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("希望のモードを選択して切り替えます。設定情報ボタンをタップすると、各モードの説明が表示されます。")
                    .font(.body).multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.bottom, 2)
                ForEach(modes) { mode in
                    HStack(spacing: 12) {
                        Button { onSelect(mode.id) } label: {
                            VStack(alignment: .leading, spacing: 14) {
                                Text(mode.title).font(.title3.bold()).foregroundStyle(.white)
                                Text(mode.summary).font(.body).foregroundStyle(.white.opacity(0.78))
                            }.frame(maxWidth: .infinity, minHeight: 86, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 12)
                                .background(Color.black).overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.orange, lineWidth: 2))
                        }.buttonStyle(.plain).accessibilityHint("この表示モードに切り替えます")
                        Button { expandedInfoID = expandedInfoID == mode.id ? nil : mode.id } label: {
                            Image(systemName: expandedInfoID == mode.id ? "info.circle.fill" : "info.circle")
                                .font(.title2).foregroundStyle(.orange).frame(width: 38, height: 54)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(expandedInfoID == mode.id ? "\(mode.title)の説明を閉じる" : "\(mode.title)の説明")
                    }
                    if expandedInfoID == mode.id {
                        Text(mode.details).font(.body).foregroundStyle(.white.opacity(0.78))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 16).padding(.top, 10).background(Color.black.ignoresSafeArea())
                .navigationTitle("モード").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("キャンセル", action: onCancel).foregroundStyle(.orange) } }
                .toolbarBackground(Color(white: 0.08), for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
                .preferredColorScheme(.dark)
        }
    }
}

struct ShareView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
@main struct SailingGPSApp: App { var body: some Scene { WindowGroup { ContentView() } } }


