import SwiftUI

struct StartTimerPanel: View {
    let currentLocation: StartLineCoordinate?
    let metric: Bool
    var compact = false
    var onRegisterWaypoint: (String, StartLineCoordinate) -> Void = { _, _ in }

    @AppStorage("startLineOuterSet") private var outerSet = false
    @AppStorage("startLineOuterLat") private var outerLatitude = 0.0
    @AppStorage("startLineOuterLon") private var outerLongitude = 0.0
    @AppStorage("startLineSignalSet") private var signalSet = false
    @AppStorage("startLineSignalLat") private var signalLatitude = 0.0
    @AppStorage("startLineSignalLon") private var signalLongitude = 0.0
    @AppStorage("startTimerDeadline") private var deadline = 0.0
    @AppStorage("startTimerPaused") private var pausedSeconds = 0.0
    @AppStorage("startTimerMinutes") private var selectedMinutes = 5

    private var outer: StartLineCoordinate? {
        let value = StartLineCoordinate(latitude: outerLatitude, longitude: outerLongitude)
        return outerSet && value.isValid ? value : nil
    }
    private var signal: StartLineCoordinate? {
        let value = StartLineCoordinate(latitude: signalLatitude, longitude: signalLongitude)
        return signalSet && value.isValid ? value : nil
    }
    private func assign(_ kind: String) -> StartLineCoordinate? {
        guard let currentLocation, currentLocation.isValid else { return nil }
        if kind == "outer" { outerLatitude = currentLocation.latitude; outerLongitude = currentLocation.longitude; outerSet = true }
        else { signalLatitude = currentLocation.latitude; signalLongitude = currentLocation.longitude; signalSet = true }
        return currentLocation
    }
    private func toggle(at now: Date) {
        let timestamp = now.timeIntervalSince1970
        if deadline > timestamp {
            pausedSeconds = max(1, ceil(deadline - timestamp)); deadline = 0
        } else {
            let remaining = pausedSeconds > 0 ? pausedSeconds : Double(selectedMinutes * 60)
            deadline = timestamp + remaining; pausedSeconds = 0
        }
    }
    private func distanceText() -> String {
        guard let currentLocation, let distance = StartLineMath.distanceMeters(from: currentLocation, outerMark: outer, signalBoat: signal) else { return "—" }
        return metric ? (distance < 1000 ? String(format: "%.0f m", distance) : String(format: "%.2f km", distance / 1000)) : String(format: "%.2f nm  ·  %.0f m", distance / 1852, distance)
    }
    private func endpointText(_ value: StartLineCoordinate?) -> String {
        guard let value else { return "未設定" }
        return String(format: "%.5f, %.5f", value.latitude, value.longitude)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let running = deadline > now.timeIntervalSince1970
            let paused = !running && pausedSeconds > 0
            let finished = deadline > 0 && !running && !paused
            let remain = running ? deadline - now.timeIntervalSince1970 : pausedSeconds
            VStack(spacing: compact ? 5 : 10) {
                Text("スタートタイマー")
                    .font(compact ? .headline : .largeTitle)
                    .foregroundStyle(.orange)
                Text(finished ? "START!" : StartLineMath.countdown(remain))
                    .font(.system(size: compact ? 38 : 78, weight: .bold, design: .monospaced))
                    .minimumScaleFactor(0.5).lineLimit(1)
                    .foregroundStyle(finished ? .orange : .green)
                    .accessibilityLabel(finished ? "スタート" : "残り " + StartLineMath.countdown(remain))
                Text("スタートラインまで  " + distanceText())
                    .font(compact ? .caption : .title2.bold())
                    .minimumScaleFactor(0.6).lineLimit(1)
                    .padding(.vertical, compact ? 2 : 8)
                VStack(spacing: compact ? 3 : 6) {
                    Text("アウターマーク：\(endpointText(outer))").font(compact ? .caption2 : .subheadline).lineLimit(1).minimumScaleFactor(0.6)
                    Button("現在地をアウターマークに登録") { if let point = assign("outer") { onRegisterWaypoint("outer", point) } }
                        .disabled(currentLocation?.isValid != true)
                    Text("シグナルボート：\(endpointText(signal))").font(compact ? .caption2 : .subheadline).lineLimit(1).minimumScaleFactor(0.6)
                    Button("現在地をシグナルボートに登録") { if let point = assign("signal") { onRegisterWaypoint("signal", point) } }
                        .disabled(currentLocation?.isValid != true)
                    Text("登録地点は地図とウェイポイント一覧にも追加されます")
                        .font(compact ? .caption2 : .caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.65)
                }.buttonStyle(.bordered).tint(.orange)
                HStack(spacing: compact ? 2 : 8) {
                    ForEach([1, 3, 5, 10], id: \.self) { minute in
                        Button("\(minute)分") { selectedMinutes = minute; if !running { pausedSeconds = 0; deadline = 0 } }
                            .buttonStyle(.bordered).tint(selectedMinutes == minute ? .green : .gray)
                            .font(compact ? .caption2 : .body)
                    }
                }
                HStack {
                    Button(running ? "一時停止" : paused ? "再開" : "開始") { toggle(at: now) }
                        .buttonStyle(.borderedProminent).tint(.green)
                    Button("リセット") { deadline = 0; pausedSeconds = 0 }
                        .buttonStyle(.bordered).tint(.orange)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(compact ? 4 : 10)
            .background(Color.black)
            .preferredColorScheme(.dark)
        }
    }
}
