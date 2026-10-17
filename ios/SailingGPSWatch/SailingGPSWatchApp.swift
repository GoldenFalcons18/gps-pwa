import SwiftUI
import WatchConnectivity

final class WatchNavigationReceiver: NSObject, ObservableObject, WCSessionDelegate {
    @Published var snapshot: WatchNavigationSnapshot?
    @Published var reachable = false
    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: "lastNavigation") { snapshot = try? JSONDecoder().decode(WatchNavigationSnapshot.self, from: data) }
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }
    private func receive(_ context: [String: Any]) {
        guard let data = context["navigation"] as? Data, let value = try? JSONDecoder().decode(WatchNavigationSnapshot.self, from: data) else { return }
        DispatchQueue.main.async {
            guard self.snapshot == nil || value.sentAt >= self.snapshot!.sentAt else { return }
            self.snapshot = value
            UserDefaults.standard.set(data, forKey: "lastNavigation")
        }
    }
    func refresh() {
        let session = WCSession.default
        reachable = session.isReachable
        receive(session.receivedApplicationContext)
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(["requestNavigation": true], replyHandler: { self.receive($0) }, errorHandler: { _ in })
    }
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) { DispatchQueue.main.async { self.refresh() } }
    func sessionReachabilityDidChange(_ session: WCSession) { DispatchQueue.main.async { self.refresh() } }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { receive(applicationContext) }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { receive(message) }
}

struct WatchNavigationView: View {
    @StateObject private var receiver = WatchNavigationReceiver()
    @Environment(\.scenePhase) private var phase
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            ScrollView {
                VStack(spacing: 6) {
                    Text("目標ナビ").font(.caption).foregroundStyle(.orange)
                    if let reading = receiver.snapshot {
                        if reading.hasTarget {
                            Text(reading.name ?? "").font(.headline).multilineTextAlignment(.center)
                            Text(reading.distanceText).font(.system(size: 30, weight: .bold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
                            Text(reading.bearing.map { String(format: "%.0f°", $0) } ?? "—").font(.title2).foregroundStyle(.green)
                            Text("目標方位・真北基準").font(.caption2)
                            if !reading.isFresh(at: timeline.date) {
                                Text("古い情報・iPhoneのGPSを確認").font(.caption2).foregroundStyle(.orange).multilineTextAlignment(.center)
                            }
                            if let time = reading.locationTime { Text(time, style: .time).font(.caption2).foregroundStyle(.secondary) }
                        } else {
                            Text("目標なし").font(.headline)
                            Text("iPhoneで目標を選んでください").font(.caption).multilineTextAlignment(.center)
                        }
                    } else {
                        Text("iPhoneの情報を待っています").font(.headline).multilineTextAlignment(.center)
                    }
                    if !receiver.reachable { Text("iPhoneと未接続").font(.caption2).foregroundStyle(.orange) }
                    Button("更新") { receiver.refresh() }.tint(.orange)
                }.padding(.horizontal, 6)
            }
        }
        .onAppear { receiver.refresh() }
        .onChange(of: phase) { _, value in if value == .active { receiver.refresh() } }
    }
}

@main struct SailingGPSWatchApp: App {
    var body: some Scene { WindowGroup { WatchNavigationView() } }
}
