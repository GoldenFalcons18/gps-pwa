import SwiftUI
import CoreLocation
import WatchConnectivity

final class WatchNavigationReceiver: NSObject, ObservableObject, WCSessionDelegate {
    @Published var catalog: WatchWaypointCatalog?
    @Published var selectedID: String? = UserDefaults.standard.string(forKey: "watchSelectedID")
    @Published var reachable = false
    @Published var selectionPending = UserDefaults.standard.object(forKey: "watchSelectionTime") != nil
    @Published var recording = false
    @Published var recordingRequestPending = false
    @Published var recordingMessage = ""
    @Published var message = ""
    private var pendingTime: Date? = (UserDefaults.standard.object(forKey: "watchSelectionTime") as? Double).map(Date.init(timeIntervalSince1970:))
    private var requestedRecordingState: Bool?
    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: "watchCatalog"), let saved = try? JSONDecoder().decode(WatchWaypointCatalog.self, from: data) {
            catalog = saved; recording = saved.recording ?? false; recordingMessage = saved.statusMessage ?? ""
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-watch") {
            catalog = WatchWaypointCatalog(waypoints: [WatchWaypoint(id: "demo", name: "江の島灯台", latitude: 35.30, longitude: 139.48, folder: "目標")], targetID: "demo", metric: false, selectionChangedAt: Date(), sentAt: Date())
            selectedID = "demo"; selectionPending = false; pendingTime = nil
            return
        }
        #endif
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self; WCSession.default.activate()
    }
    var target: WatchWaypoint? { catalog?.waypoints.first { $0.id == selectedID } }
    func choose(_ id: String?) {
        selectedID = id
        UserDefaults.standard.set(id, forKey: "watchSelectedID")
        pendingTime = Date(); selectionPending = true
        UserDefaults.standard.set(pendingTime!.timeIntervalSince1970, forKey: "watchSelectionTime")
        message = ""; sendSelection()
    }
    func requestRecordingToggle() {
        let session = WCSession.default
        guard WCSession.isSupported(), session.activationState == .activated, session.isReachable else {
            message = "iPhoneに接続してから記録を操作してください"; return
        }
        let shouldStart = !recording
        requestedRecordingState = shouldStart
        recordingRequestPending = true
        message = "iPhoneへ記録操作を送信中"
        session.sendMessage(["recordingAction": shouldStart ? "start" : "stop"], replyHandler: { [weak self] reply in
            DispatchQueue.main.async {
                guard let self, self.requestedRecordingState == shouldStart else { return }
                guard reply["recordingRequestAccepted"] as? Bool == true else {
                    self.requestedRecordingState = nil; self.recordingRequestPending = false
                    self.message = "iPhoneで記録操作を受け付けられませんでした"; return
                }
                self.message = shouldStart ? "記録開始を依頼しました" : "記録停止を依頼しました"
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                    guard self.requestedRecordingState == shouldStart else { return }
                    self.requestedRecordingState = nil; self.recordingRequestPending = false
                    self.message = "記録状態が変わりません。iPhoneの位置情報許可を確認してください"
                }
                self.receive(reply)
            }
        }, errorHandler: { [weak self] _ in
            DispatchQueue.main.async {
                self?.requestedRecordingState = nil; self?.recordingRequestPending = false
                self?.message = "iPhoneに接続してから記録を操作してください"
            }
        })
    }
    func registerStartLineWaypoint(kind: String, coordinate: StartLineCoordinate) {
        guard ["outer", "signal"].contains(kind), coordinate.isValid,
              WCSession.isSupported(), WCSession.default.activationState == .activated,
              WCSession.default.isReachable else {
            DispatchQueue.main.async { self.message = "iPhoneに接続してから地点を登録してください" }
            return
        }
        WCSession.default.sendMessage([
            "registerStartLineWaypoint": kind,
            "latitude": coordinate.latitude,
            "longitude": coordinate.longitude
        ], replyHandler: { [weak self] reply in
            DispatchQueue.main.async {
                self?.message = (reply["selectionAccepted"] as? Bool == false)
                    ? "地点を登録できませんでした"
                    : "ウェイポイントに追加しました"
            }
        }, errorHandler: { [weak self] _ in
            DispatchQueue.main.async { self?.message = "iPhoneに接続してから地点を登録してください" }
        })
    }
    private func clearPending() {
        pendingTime = nil; selectionPending = false; UserDefaults.standard.removeObject(forKey: "watchSelectionTime")
    }
    private func receive(_ context: [String: Any]) {
        guard let data = context["waypoints"] as? Data, let value = try? JSONDecoder().decode(WatchWaypointCatalog.self, from: data) else { return }
        DispatchQueue.main.async {
            guard self.catalog == nil || value.sentAt >= self.catalog!.sentAt else { return }
            self.catalog = value
            self.recording = value.recording ?? self.recording
            self.recordingMessage = value.statusMessage ?? self.recordingMessage
            if let requested = self.requestedRecordingState, self.recording == requested {
                self.requestedRecordingState = nil; self.recordingRequestPending = false; self.message = ""
            }
            UserDefaults.standard.set(data, forKey: "watchCatalog")
            if self.pendingTime == nil || value.selectionChangedAt >= self.pendingTime! {
                self.selectedID = value.targetID; self.clearPending()
            } else if let selected = self.selectedID, !value.waypoints.contains(where: { $0.id == selected }) {
                self.selectedID = value.targetID; self.clearPending(); self.message = "選んだ地点は削除されています"
            }
            UserDefaults.standard.set(self.selectedID, forKey: "watchSelectedID")
        }
    }
    private func sendSelection() {
        let session = WCSession.default
        guard let time = pendingTime, session.activationState == .activated, session.isReachable else { return }
        let sentTime = time
        session.sendMessage(["selectTarget": selectedID ?? "__none__", "selectionTime": time.timeIntervalSince1970], replyHandler: { reply in
            DispatchQueue.main.async {
                guard self.pendingTime == sentTime, reply["deferred"] as? Bool != true else { return }
                if reply["selectionAccepted"] as? Bool == false { self.message = "iPhoneの新しい目標を反映します" }
                self.clearPending(); self.receive(reply)
            }
        }, errorHandler: { _ in })
    }
    func refresh() {
        let session = WCSession.default
        reachable = session.isReachable
        receive(session.receivedApplicationContext)
        guard session.activationState == .activated, session.isReachable else { return }
        if selectionPending { sendSelection() }
        else { session.sendMessage(["requestNavigation": true], replyHandler: { self.receive($0) }, errorHandler: { _ in }) }
    }
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) { DispatchQueue.main.async { self.refresh() } }
    func sessionReachabilityDidChange(_ session: WCSession) { DispatchQueue.main.async { self.refresh() } }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { receive(applicationContext) }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { receive(message) }
}

struct WatchCompass: View {
    let heading: Double?
    let bearing: Double?
    let magnetic: Bool
    let canPoint: Bool
    @State private var dial = 0.0
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let radius = size / 2
            ZStack {
                Circle().stroke(.gray, lineWidth: 2)
                ZStack {
                    ForEach(0..<36) { tick in
                        Rectangle().fill(.gray).frame(width: 1, height: tick % 3 == 0 ? 10 : 5).offset(y: -radius + 8).rotationEffect(.degrees(Double(tick) * 10))
                    }
                    VStack { Text("北"); Spacer(); Text("南") }.font(.system(size: 10)).padding(9)
                    HStack { Text("西"); Spacer(); Text("東") }.font(.system(size: 10)).padding(9)
                }.rotationEffect(.degrees(-dial))
                if canPoint, let bearing, heading != nil {
                    Image(systemName: "location.north.fill").font(.system(size: 17)).foregroundStyle(.green).offset(y: -radius * 0.87).rotationEffect(.degrees(bearing - dial))
                }
                VStack(spacing: 2) {
                    Text(magnetic ? "目標方位（磁北）" : "目標方位（真北）").font(.system(size: 7))
                    Text(bearing.map { String(format: "%.0f°", $0) } ?? "—").font(.system(size: 23, weight: .bold)).foregroundStyle(.green)
                }
            }.frame(width: size, height: size).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { dial = heading ?? 0 }
        .onChange(of: heading) { _, value in if let value { dial = WatchNavigationMath.unwrap(from: dial, to: value) } }
        .animation(.linear(duration: 0.12), value: dial)
    }
}

struct WatchNavigationView: View {
    @StateObject private var receiver = WatchNavigationReceiver()
    @StateObject private var sensors = WatchSensors()
    @Environment(\.scenePhase) private var phase
    @AppStorage("watchMode") private var mode = 0
    @AppStorage("watchMagnetic") private var useMagnetic=true
    @AppStorage("watchCompassWhileMoving") private var compassWhileMoving=false
    @State private var targetPicker = false
    private var metric: Bool { receiver.catalog?.metric ?? false }
    private var folders: [String] { Array(Set(receiver.catalog?.waypoints.map(\.folder) ?? [])).sorted() }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            ScrollView {
                VStack(spacing: 2) {
                    HStack {
                        Button("ナビ") { mode = 0 }.foregroundStyle(mode == 0 ? .orange : .gray).frame(maxWidth: .infinity, minHeight: 22)
                        Button("速度") { mode = 1 }.foregroundStyle(mode == 1 ? .orange : .gray).frame(maxWidth: .infinity, minHeight: 22)
                        Button("タイマー") { mode = 2 }.foregroundStyle(mode == 2 ? .orange : .gray).frame(maxWidth: .infinity, minHeight: 22)
                        Button(useMagnetic ? "磁北":"真北") {useMagnetic.toggle()}.foregroundStyle(.orange).frame(maxWidth:.infinity,minHeight:22)
                    }.buttonStyle(.plain).font(.caption2).padding(.vertical, 3)
                    Button("移動中もコンパス：\(compassWhileMoving ? "ON" : "OFF")") { compassWhileMoving.toggle() }
                        .buttonStyle(.plain).font(.system(size: 9)).foregroundStyle(.orange)
                    Button { receiver.requestRecordingToggle() } label: {
                        Label(receiver.recording ? "記録停止" : "記録開始", systemImage: receiver.recording ? "stop.circle.fill" : "record.circle")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(receiver.recording ? .red : .orange)
                            .frame(maxWidth: .infinity, minHeight: 30).overlay(RoundedRectangle(cornerRadius: 8).stroke(receiver.recording ? .red : .orange, lineWidth: 1))
                    }.buttonStyle(.plain).disabled(!receiver.reachable || receiver.recordingRequestPending)
                    Text(receiver.recordingRequestPending ? "iPhoneへ送信中" : receiver.recording ? "iPhoneで航跡を記録中" : receiver.reachable ? "iPhoneの航跡記録は停止中" : "iPhoneと接続してください")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                    Button(receiver.target?.name ?? "目標を選ぶ") { targetPicker = true }.buttonStyle(.plain).font(.caption2).foregroundStyle(.orange).lineLimit(1)
                    let fix = sensors.fix(at: Date())
                    let compass = sensors.compass(at: Date())
                    if mode == 0 { navigation(fix: fix, compass: compass) }
                    else if mode == 1 { speed(fix: fix,compass:compass) }
                    else {
                        StartTimerPanel(
                            currentLocation: fix.map { StartLineCoordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) },
                            metric: metric,
                            compact: true,
                            onRegisterWaypoint: { kind, coordinate in receiver.registerStartLineWaypoint(kind: kind, coordinate: coordinate) }
                        )
                    }
                    if fix == nil { Text(sensors.status).font(.caption2).foregroundStyle(.orange) }
                    if receiver.selectionPending { Text("目標：iPhoneへ同期待ち").font(.caption2).foregroundStyle(.orange) }
                    if !receiver.recordingMessage.isEmpty { Text(receiver.recordingMessage).font(.system(size: 9)).foregroundStyle(.secondary) }
                    if !receiver.message.isEmpty { Text(receiver.message).font(.caption2).foregroundStyle(.orange) }
                }.padding(.horizontal, 3)
            }
        }
        .sheet(isPresented: $targetPicker) {
            NavigationStack {
                List {
                    Button("目標なし") { receiver.choose(nil); targetPicker = false }
                    if folders.isEmpty { Text("iPhoneを開いて地点を同期してください") }
                    ForEach(folders, id: \.self) { folder in
                        Section(folder) {
                            ForEach(receiver.catalog?.waypoints.filter { $0.folder == folder } ?? []) { point in
                                Button { receiver.choose(point.id); targetPicker = false } label: {
                                    HStack { Text(point.name); Spacer(); if point.id == receiver.selectedID { Image(systemName: "checkmark") } }
                                }
                            }
                        }
                    }
                    Button("iPhoneから更新") { receiver.refresh() }
                }.navigationTitle("目標")
            }
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--preview-speed") { mode = 1 }
            if ProcessInfo.processInfo.arguments.contains("--preview-navigation") { mode = 0 }
            #endif
            receiver.refresh(); sensors.setActive(phase == .active)
        }
        .onChange(of: phase) { _, value in sensors.setActive(value == .active); if value == .active { receiver.refresh() } }
    }
    @ViewBuilder private func navigation(fix: CLLocation?, compass: CLHeading?) -> some View {
        let target = receiver.target
        let trueBearing = target.flatMap { point in fix.map { WatchNavigationSnapshot.bearing(fromLat: $0.coordinate.latitude, fromLon: $0.coordinate.longitude, toLat: point.latitude, toLon: point.longitude) } }
        #if DEBUG
        let demo = ProcessInfo.processInfo.arguments.contains("--preview-watch")
        #else
        let demo = false
        #endif
        let trueHeading = compass.flatMap { $0.trueHeading >= 0 ? $0.trueHeading : nil } ?? (demo ? 218 : nil)
        let magneticHeading = compass?.magneticHeading ?? (demo ? 226 : nil)
        let correction=InstrumentHeading.declination(magnetic:magneticHeading,trueHeading:trueHeading)
        let shownBearing=InstrumentHeading.bearing(trueBearing,magnetic:useMagnetic,declination:correction)
        let shownHeading=useMagnetic ? magneticHeading:trueHeading
        WatchCompass(heading:shownHeading,bearing:shownBearing,magnetic:useMagnetic,canPoint:shownHeading != nil).frame(height: 96)
        let meters = target.flatMap { point in fix.map { $0.distance(from: CLLocation(latitude: point.latitude, longitude: point.longitude)) } }
        HStack {
            VStack(spacing: 1) {
                Text(WatchNavigationMath.distance(meters, metric: metric)).font(.system(size: 20, weight: .bold)).minimumScaleFactor(0.6).lineLimit(1)
                Text("目標距離").font(.system(size: 9)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity)
            VStack(spacing: 1) {
                Text(shownHeading.map { String(format: "%.0f°", $0) } ?? "—").font(.system(size: 20, weight: .bold))
                Text(useMagnetic ? "現在方位（磁北）":"現在方位（真北）").font(.system(size: 9)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity)
        }
        if compass == nil && !demo { Text("コンパス未取得／非対応").font(.system(size: 9)).foregroundStyle(.orange) }
    }
    @ViewBuilder private func speed(fix: CLLocation?,compass:CLHeading?) -> some View {
        #if DEBUG
        let demo=ProcessInfo.processInfo.arguments.contains("--preview-watch")
        #else
        let demo=false
        #endif
        let mag=compass?.magneticHeading ?? (demo ? 226:nil)
        let trueHeading=compass.flatMap{$0.trueHeading>=0 ? $0.trueHeading:nil} ?? (demo ? 218:nil)
        let reading=InstrumentHeading.resolve(course:fix?.course,speed:fix?.speed,magneticHeading:mag,trueHeading:trueHeading,magnetic:useMagnetic,compassWhileMoving:compassWhileMoving)
        Text("SOG").font(.caption).foregroundStyle(.orange)
        Text(WatchNavigationMath.speed(fix.map(\.speed), metric: metric)).font(.system(size: 32, weight: .bold, design: .rounded)).minimumScaleFactor(0.5).lineLimit(1)
        Text(metric ? "km/h" : "knot").font(.caption)
        Text((reading?.compass==true ? "コンパス方位":"COG")+(useMagnetic ? "・磁北":"・真北")).font(.caption).foregroundStyle(.orange)
        Text(reading.map{String(format:"%.0f°",$0.value.rounded().truncatingRemainder(dividingBy:360))} ?? "—").font(.title3.bold())
        Text(reading?.compass==true ? "Watchコンパス":"Watch GPS").font(.caption2).foregroundStyle(.secondary)
    }
}
@main struct SailingGPSWatchApp: App { var body: some Scene { WindowGroup { WatchNavigationView() } } }
