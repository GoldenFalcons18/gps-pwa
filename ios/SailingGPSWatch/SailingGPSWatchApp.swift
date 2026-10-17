import SwiftUI
import CoreLocation
import WatchConnectivity

final class WatchNavigationReceiver: NSObject, ObservableObject, WCSessionDelegate {
    @Published var catalog: WatchWaypointCatalog?
    @Published var selectedID: String? = UserDefaults.standard.string(forKey: "watchSelectedID")
    @Published var reachable = false
    @Published var selectionPending = UserDefaults.standard.object(forKey: "watchSelectionTime") != nil
    @Published var message = ""
    private var pendingTime: Date? = (UserDefaults.standard.object(forKey: "watchSelectionTime") as? Double).map(Date.init(timeIntervalSince1970:))
    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: "watchCatalog") { catalog = try? JSONDecoder().decode(WatchWaypointCatalog.self, from: data) }
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
    private func clearPending() {
        pendingTime = nil; selectionPending = false; UserDefaults.standard.removeObject(forKey: "watchSelectionTime")
    }
    private func receive(_ context: [String: Any]) {
        guard let data = context["waypoints"] as? Data, let value = try? JSONDecoder().decode(WatchWaypointCatalog.self, from: data) else { return }
        DispatchQueue.main.async {
            guard self.catalog == nil || value.sentAt >= self.catalog!.sentAt else { return }
            self.catalog = value
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
                guard self.pendingTime == sentTime else { return }
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
                    VStack { Text("北"); Spacer(); Text("南") }.padding(15)
                    HStack { Text("西"); Spacer(); Text("東") }.padding(15)
                }.rotationEffect(.degrees(-dial))
                if canPoint, let bearing, heading != nil {
                    Image(systemName: "location.north.fill").font(.system(size: 24)).foregroundStyle(.green).offset(y: -radius * 0.64).rotationEffect(.degrees(bearing - dial))
                }
                VStack(spacing: 2) {
                    Text(magnetic ? "目標方位（磁北）" : "目標方位（真北）").font(.system(size: 9))
                    Text(bearing.map { String(format: "%.0f°", $0) } ?? "—").font(.system(size: 27, weight: .bold)).foregroundStyle(.green)
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
    @State private var targetPicker = false
    private var metric: Bool { receiver.catalog?.metric ?? false }
    private var folders: [String] { Array(Set(receiver.catalog?.waypoints.map(\.folder) ?? [])).sorted() }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            ScrollView {
                VStack(spacing: 5) {
                    HStack {
                        Button("ナビ") { mode = 0 }.tint(mode == 0 ? .orange : .gray)
                        Button("速度") { mode = 1 }.tint(mode == 1 ? .orange : .gray)
                    }.buttonStyle(.bordered)
                    let fix = sensors.fix(at: timeline.date)
                    let compass = sensors.compass(at: timeline.date)
                    if mode == 0 { navigation(fix: fix, compass: compass) }
                    else { speed(fix: fix) }
                    Text(sensors.status).font(.system(size: 10)).foregroundStyle(.secondary)
                    if fix == nil { Text("Watch GPS未取得").font(.caption2).foregroundStyle(.orange) }
                    if receiver.selectionPending { Text("目標：iPhoneへ同期待ち").font(.caption2).foregroundStyle(.orange) }
                    if !receiver.message.isEmpty { Text(receiver.message).font(.caption2).foregroundStyle(.orange) }
                    Button("目標を選ぶ") { targetPicker = true }.tint(.orange)
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
        let magnetic = trueHeading != nil && magneticHeading != nil
        let shownBearing = trueBearing.map { value in magnetic ? WatchNavigationMath.magneticBearing(trueBearing: value, trueHeading: trueHeading!, magneticHeading: magneticHeading!) : value }
        Text(target?.name ?? "目標なし").font(.caption).lineLimit(2)
        WatchCompass(heading: magnetic ? magneticHeading : (trueHeading ?? magneticHeading), bearing: shownBearing, magnetic: magnetic, canPoint: trueHeading != nil).frame(height: 150)
        let meters = target.flatMap { point in fix.map { $0.distance(from: CLLocation(latitude: point.latitude, longitude: point.longitude)) } }
        Text(WatchNavigationMath.distance(meters, metric: metric)).font(.title2.bold()).monospacedDigit()
        Text("目標距離・Watch GPS").font(.system(size: 10)).foregroundStyle(.secondary)
        Text("現在方位 " + (magneticHeading.map { String(format: "%.0f° 磁北", $0) } ?? "未取得")).font(.caption2)
    }
    @ViewBuilder private func speed(fix: CLLocation?) -> some View {
        Text("SOG").font(.caption).foregroundStyle(.orange)
        Text(WatchNavigationMath.speed(fix.map(\.speed), metric: metric)).font(.system(size: 42, weight: .bold, design: .rounded)).minimumScaleFactor(0.5).lineLimit(1)
        Text(metric ? "km/h" : "knot").font(.caption)
        Text("COG・真北基準").font(.caption).foregroundStyle(.orange)
        Text(fix.flatMap { $0.course >= 0 && $0.speed >= 0.5 ? String(format: "%.0f°", $0.course) : nil } ?? "—").font(.title.bold())
        Text("Watch GPS").font(.caption2).foregroundStyle(.secondary)
    }
}
@main struct SailingGPSWatchApp: App { var body: some Scene { WindowGroup { WatchNavigationView() } } }
