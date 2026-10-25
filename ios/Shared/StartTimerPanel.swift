import SwiftUI
import AVFoundation
import Network

private enum StartTimerVoice {
    static let synthesizer = AVSpeechSynthesizer()
    static func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        utterance.rate = 0.48
        synthesizer.speak(utterance)
    }
}

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
    @State private var lastVoiceCue = ""

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
    private func alignToNearestMinute(at now: Date) {
        let isRunning = deadline > now.timeIntervalSince1970
        let seconds = isRunning ? deadline - now.timeIntervalSince1970 : pausedSeconds
        guard isRunning || pausedSeconds > 0 else { return }
        let aligned = StartLineMath.nearestMinute(seconds)
        if isRunning { deadline = now.timeIntervalSince1970 + aligned }
        else { pausedSeconds = aligned }
    }
    private func toggle(at now: Date) {
        let timestamp = now.timeIntervalSince1970
        if deadline > timestamp {
            pausedSeconds = max(1, ceil(deadline - timestamp)); deadline = 0
        } else {
            if pausedSeconds <= 0 { lastVoiceCue = "" }
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
            let wholeSeconds = max(0, Int(remain.rounded(.up)))
            let voiceCue: String = {
                if finished { return "start" }
                guard running else { return "" }
                if StartLineMath.isThirtySecondWarning(remain) { return "warning-30" }
                if StartLineMath.isMinuteMarker(remain) { return "minute-\(wholeSeconds / 60)" }
                if StartLineMath.isMinuteCountdown(remain) { return "countdown-\(wholeSeconds)" }
                return ""
            }()
            VStack(spacing: compact ? 5 : 10) {
                Text("スタートタイマー")
                    .font(compact ? .headline : .largeTitle)
                    .foregroundStyle(.orange)
                Text(finished ? "START!" : StartLineMath.countdown(remain))
                    .font(.system(size: compact ? 38 : 78, weight: .bold, design: .monospaced))
                    .minimumScaleFactor(0.5).lineLimit(1)
                    .foregroundStyle(finished || (running && StartLineMath.isMinuteCountdown(remain)) ? .orange : .green)
                    .accessibilityLabel(finished ? "スタート" : "残り " + StartLineMath.countdown(remain))
                Text(running && StartLineMath.isMinuteCountdown(remain)
                     ? "音声カウントダウン：\(wholeSeconds)秒"
                     : "各分の残り10秒を音声案内・0分30秒と各分00秒も案内")
                    .font(compact ? .system(size: 8) : .caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
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
                HStack(spacing: compact ? 8 : 14) {
                    Text("時間").font(compact ? .caption2 : .body).foregroundStyle(.secondary)
                    Button("−") { selectedMinutes = max(1, selectedMinutes - 1); if !running { pausedSeconds = 0; deadline = 0 } }
                        .accessibilityLabel("タイマー時間を1分短く").buttonStyle(.bordered).tint(.orange)
                    Text(compact ? "\(selectedMinutes)分" : "\(selectedMinutes)分シーケンス").font(compact ? .caption : .headline).monospacedDigit().frame(minWidth: compact ? 38 : 52)
                    Button("＋") { selectedMinutes = min(60, selectedMinutes + 1); if !running { pausedSeconds = 0; deadline = 0 } }
                        .accessibilityLabel("タイマー時間を1分長く").buttonStyle(.bordered).tint(.orange)
                }
                HStack {
                    Button(running ? "一時停止" : paused ? "再開" : "開始") { toggle(at: now) }
                        .buttonStyle(.borderedProminent).tint(.green)
                    Button(compact ? "近い:00へ同期" : "残り時間を近い「:00」に合わせる") { alignToNearestMinute(at: now) }
                        .buttonStyle(.bordered).tint(.orange)
                        .disabled(!running && !paused)
                    Button("リセット") { deadline = 0; pausedSeconds = 0; lastVoiceCue = "" }
                        .buttonStyle(.bordered).tint(.orange)
                }
                .font(compact ? .system(size: 9) : .body)
                .onChange(of: voiceCue) { _, cue in
                    guard !cue.isEmpty, cue != lastVoiceCue else { return }
                    lastVoiceCue = cue
                    if cue == "start" { StartTimerVoice.speak("スタート") }
                    else if cue == "warning-30" { StartTimerVoice.speak("あと30秒") }
                    else if cue.hasPrefix("minute-"), let minutes = Int(cue.replacingOccurrences(of: "minute-", with: "")) {
                        StartTimerVoice.speak("あと\(minutes)分")
                    } else if cue.hasPrefix("countdown-"), let seconds = Int(cue.replacingOccurrences(of: "countdown-", with: "")) {
                        StartTimerVoice.speak(String(seconds))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(compact ? 4 : 10)
            .background(Color.black)
            .preferredColorScheme(.dark)
        }
    }
}


private final class SignalNtpSync: ObservableObject {
    private final class Once {
        private let lock = NSLock()
        private var done = false
        func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
    }
    static func synchronize(completion: @escaping (Result<Double, Error>) -> Void) {
        let queue = DispatchQueue(label: "signal.nict.ntp")
        let connection = NWConnection(host: NWEndpoint.Host("ntp.nict.jp"), port: NWEndpoint.Port(rawValue: 123)!, using: .udp)
        let once = Once()
        let started = Date()
        func finish(_ result: Result<Double, Error>) {
            guard once.claim() else { return }
            connection.cancel()
            DispatchQueue.main.async { completion(result) }
        }
        var request = Data(repeating: 0, count: 48)
        request[0] = 0x23
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: request, completion: .contentProcessed { error in
                    if let error { finish(.failure(error)); return }
                    connection.receive(minimumIncompleteLength: 48, maximumLength: 512) { data, _, _, error in
                        if let error { finish(.failure(error)); return }
                        guard let data, data.count >= 48 else {
                            finish(.failure(NSError(domain: "NICT NTP", code: 1, userInfo: [NSLocalizedDescriptionKey: "応答データが不足しています"])))
                            return
                        }
                        let seconds = data[40..<44].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
                        let fraction = data[44..<48].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
                        let serverUnix = Double(seconds) - 2_208_988_800 + Double(fraction) / 4_294_967_296
                        let received = Date()
                        let midpoint = started.timeIntervalSince1970 + received.timeIntervalSince(started) / 2
                        finish(.success(serverUnix - midpoint))
                    }
                })
            case .failed(let error): finish(.failure(error))
            default: break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 5) {
            finish(.failure(NSError(domain: "NICT NTP", code: 2, userInfo: [NSLocalizedDescriptionKey: "NICT時刻への接続がタイムアウトしました"])))
        }
    }
}


#if os(iOS)
private enum SignalHorn {
    static var player: AVAudioPlayer?
    static func play(seconds: Int) {
        let rate = 16_000
        let count = max(1, rate * min(10, max(1, seconds)))
        var pcm = Data(capacity: count * 2)
        for i in 0..<count {
            let t = Double(i) / Double(rate)
            let envelope = min(1.0, Double(i) / 320.0) * min(1.0, Double(count - i) / 640.0)
            let sample = Int16(sin(2 * .pi * 440 * t) * 9000 * envelope)
            var little = sample.littleEndian
            withUnsafeBytes(of: &little) { pcm.append(contentsOf: $0) }
        }
        var wav = Data()
        func appendString(_ value: String) { wav.append(contentsOf: value.utf8) }
        func append32(_ value: UInt32) { var v = value.littleEndian; withUnsafeBytes(of: &v) { wav.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { var v = value.littleEndian; withUnsafeBytes(of: &v) { wav.append(contentsOf: $0) } }
        appendString("RIFF"); append32(UInt32(36 + pcm.count)); appendString("WAVEfmt ")
        append32(16); append16(1); append16(1); append32(UInt32(rate))
        append32(UInt32(rate * 2)); append16(2); append16(16); appendString("data")
        append32(UInt32(pcm.count)); wav.append(pcm)
        do {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try? AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(data: wav, fileTypeHint: AVFileType.wav.rawValue)
            player?.prepareToPlay()
            player?.play()
        }
        catch { }
    }
}
#endif

private struct WavingSignalFlags: View {
    let stage: String
    let compact: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.045, paused: false)) { timeline in
            Canvas { context, size in
                let poleX = size.width * 0.50
                var pole = Path()
                pole.move(to: CGPoint(x: poleX, y: size.height * 0.06))
                pole.addLine(to: CGPoint(x: poleX, y: size.height * 0.94))
                context.stroke(pole, with: .color(.gray), lineWidth: compact ? 2 : 4)
                let palette: [Color] = stage == "start" ? [.green, .white] : stage == "warning" ? [.orange] : stage == "preparatory" ? [.orange, .blue] : stage == "one-minute" ? [.orange] : []
                let phase = timeline.date.timeIntervalSinceReferenceDate * 4
                for (index, color) in palette.enumerated() {
                    let top = size.height * (0.13 + Double(index) * 0.31)
                    let flagWidth = size.width * 0.40
                    let flagHeight = size.height * 0.24
                    var flag = Path()
                    flag.move(to: CGPoint(x: poleX, y: top))
                    for step in 0...18 {
                        let t = Double(step) / 18
                        let y = top + sin(phase + t * 7) * size.height * 0.018
                        flag.addLine(to: CGPoint(x: poleX + flagWidth * t, y: y))
                    }
                    for step in (0...18).reversed() {
                        let t = Double(step) / 18
                        let y = top + flagHeight + sin(phase + t * 7 + 1.2) * size.height * 0.018
                        flag.addLine(to: CGPoint(x: poleX + flagWidth * t, y: y))
                    }
                    flag.closeSubpath()
                    context.fill(flag, with: .color(color))
                    let label = Text(stage == "start" ? "START" : (index == 0 ? "P" : "I"))
                        .font(.system(size: compact ? 8 : 16, weight: .bold, design: .rounded))
                        .foregroundColor(stage == "start" && index == 1 ? .black : .white)
                    context.draw(label, at: CGPoint(x: poleX + flagWidth * 0.52, y: top + flagHeight * 0.53))
                }
            }
        }
        .accessibilityLabel(stage == "start" ? "スタート旗" : stage == "one-minute" ? "1分前の旗" : stage == "preparatory" ? "準備信号旗" : stage == "warning" ? "予告信号旗" : "信号開始待ち")
    }
}

struct SignalTimerPanel: View {
    var compact = false
    @AppStorage("signalNtpOffset") private var ntpOffset = 0.0
    @AppStorage("signalNtpSynced") private var ntpSynced = false
    @AppStorage("signalEnd") private var endTime = 0.0
    @AppStorage("signalPaused") private var pausedSeconds = 0.0
    @AppStorage("signalMinutes") private var selectedMinutes = 5
    @AppStorage("signalHornSeconds") private var hornSeconds = 2
    @State private var syncStatus = "NICT時刻未同期"
    @State private var syncing = false
    @State private var announcedStart = false
    @State private var lastAnnouncedEvent = ""
    @State private var lastAnnouncedCountdown = 99

    private func synchronizeAndStart() {
        syncing = true
        syncStatus = "ntp.nict.jpに接続中…"
        SignalNtpSync.synchronize { result in
            syncing = false
            switch result {
            case .success(let offset):
                ntpOffset = offset
                ntpSynced = true
                syncStatus = String(format: "NICT同期済み（補正 %+.3f 秒）", offset)
                let reference = Date().timeIntervalSince1970 + offset
                endTime = (floor(reference / 60) + 1) * 60 + Double(selectedMinutes * 60)
                pausedSeconds = 0
                announcedStart = false
            case .failure(let error):
                syncStatus = "同期できません。手動ゼロ合わせを使用できます"
            }
        }
    }
    private func manualStart() {
        ntpOffset = 0
        ntpSynced = false
        syncStatus = "手動ゼロ合わせ：タップ時を基準に開始"
        let reference = Date().timeIntervalSince1970
        endTime = floor(reference / 60) * 60 + Double(selectedMinutes * 60)
        pausedSeconds = 0
        announcedStart = false
    }
    private func toggle(now: Double) {
        if endTime > now {
            pausedSeconds = max(1, ceil(endTime - now))
            endTime = 0
        } else if pausedSeconds > 0 {
            endTime = now + pausedSeconds
            pausedSeconds = 0
        }
    }
    private func reset() { endTime = 0; pausedSeconds = 0; announcedStart = false }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            let now = context.date.timeIntervalSince1970 + ntpOffset
            let running = endTime > now
            let paused = !running && pausedSeconds > 0
            let finished = endTime > 0 && !running && !paused
            let remaining = running ? endTime - now : pausedSeconds
            let duration = selectedMinutes * 60
            let plannedStart = (floor(now / 60) + 1 + Double(selectedMinutes)) * 60
            let seconds = running || paused ? max(0, Int(remaining.rounded(.up))) : max(0, Int((plannedStart - now).rounded(.up)))
            let warningAt = min(duration, 300)
            let prepAt = duration >= 300 ? 240 : max(0, duration - 60)
            let eventID: String = {
                if finished { return "start" }
                guard running || paused else { return "idle" }
                if seconds > warningAt { return "waiting" }
                if seconds > prepAt { return "warning" }
                if seconds > 60 { return "preparatory" }
                if seconds > 0 && duration > 120 { return "one-minute" }
                if seconds > 0 && duration > 60 { return "preparatory" }
                if seconds > 0 { return "warning" }
                return "start"
            }()
            let stage = eventID == "start" ? "スタート！" : eventID == "one-minute" ? "1分前" : eventID == "preparatory" ? "準備信号" : eventID == "warning" ? "予告信号" : paused ? "一時停止中" : eventID == "waiting" ? "最初の信号待ち" : "スタート時刻を設定"
            let untilNextFlag = eventID == "waiting" || eventID == "idle" ? max(0, seconds - warningAt) : eventID == "warning" ? seconds - prepAt : eventID == "preparatory" ? (duration > 120 ? seconds - 60 : seconds) : eventID == "one-minute" ? seconds : eventID == "start" ? 0 : warningAt
            let nextFlag = eventID == "waiting" || eventID == "idle" ? "予告信号" : eventID == "warning" ? "準備信号" : eventID == "preparatory" ? (duration > 120 ? "1分前の旗" : "スタート旗") : eventID == "one-minute" ? "スタート旗" : "スタート旗"
            VStack(spacing: compact ? 4 : 10) {
                Text("シグナル").font(compact ? .headline : .largeTitle.bold()).foregroundStyle(.orange)
                WavingSignalFlags(stage: eventID, compact: compact)
                    .frame(height: compact ? 70 : 190)
                Text(stage).font(compact ? .caption.bold() : .title2.bold()).foregroundStyle(.orange)
                Text("次に上げる旗：\(nextFlag) まで").font(compact ? .system(size: 9) : .headline).foregroundStyle(.white)
                Text(String(format: "%02d:%02d", untilNextFlag / 60, untilNextFlag % 60))
                    .font(.system(size: compact ? 22 : 38, weight: .semibold, design: .monospaced)).foregroundStyle(.orange)
                Text(finished ? "START" : String(format: "%02d:%02d", seconds / 60, seconds % 60))
                    .font(.system(size: compact ? 31 : 74, weight: .bold, design: .monospaced))
                    .minimumScaleFactor(0.55).lineLimit(1).foregroundStyle(finished ? .green : .white)
                Text(Date(timeIntervalSince1970: now).formatted(date: .omitted, time: .standard) + (ntpSynced ? " · NICT" : " · 端末時刻"))
                    .font(compact ? .system(size: 9, design: .monospaced) : .title3.monospacedDigit())
                Text(syncStatus).font(compact ? .system(size: 8) : .caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                HStack(spacing: compact ? 7 : 14) {
                    Button("−") { selectedMinutes = max(1, selectedMinutes - 1); if !running { reset() } }.buttonStyle(.bordered).tint(.orange)
                    Text("\(selectedMinutes)分").font(compact ? .caption : .headline).monospacedDigit()
                    Button("＋") { selectedMinutes = min(60, selectedMinutes + 1); if !running { reset() } }.buttonStyle(.bordered).tint(.orange)
                }
                if !compact {
                    VStack(spacing: 2) {
                        Text("ホーン長：\(hornSeconds)秒").font(.caption).foregroundStyle(.secondary)
                        Slider(value: Binding(get: { Double(hornSeconds) }, set: { hornSeconds = Int($0.rounded()) }), in: 1...10, step: 1).tint(.orange)
                    }
                }
                HStack(spacing: compact ? 4 : 10) {
                    Button(syncing ? "同期中…" : "NICT同期して開始") { synchronizeAndStart() }.disabled(syncing)
                        .buttonStyle(.borderedProminent).tint(.orange)
                    Button("手動ゼロ合わせ") { manualStart() }.buttonStyle(.bordered).tint(.orange)
                }.font(compact ? .system(size: 9) : .body)
                HStack(spacing: compact ? 6 : 12) {
                    Button(running ? "一時停止" : paused ? "再開" : "停止") { toggle(now: now) }.buttonStyle(.bordered).tint(.green)
                    Button("リセット") { reset() }.buttonStyle(.bordered).tint(.orange)
                }.font(compact ? .system(size: 9) : .body)
                if !running && !paused && !finished {
                    Button("NICT時刻を同期") {
                        syncing = true
                        syncStatus = "ntp.nict.jpに接続中…"
                        SignalNtpSync.synchronize { result in
                            syncing = false
                            switch result {
                            case .success(let offset): ntpOffset = offset; ntpSynced = true; syncStatus = String(format: "NICT同期済み（補正 %+.3f 秒）", offset)
                            case .failure: syncStatus = "同期できません。手動ゼロ合わせを使用できます"
                            }
                        }
                    }.buttonStyle(.bordered).tint(.gray).font(compact ? .system(size: 8) : .caption)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(compact ? 3 : 12)
            .background(Color.black)
            .preferredColorScheme(.dark)
            .onChange(of: eventID) { _, value in
                guard running || finished else { lastAnnouncedEvent = ""; return }
                guard value != lastAnnouncedEvent else { return }
                if value == "waiting" { lastAnnouncedEvent = value; return }
                lastAnnouncedEvent = value
                let phrase = value == "start" ? "スタート" : value == "one-minute" ? "1分前" : value == "preparatory" ? "準備信号" : "予告信号"
                StartTimerVoice.speak(phrase)
                #if os(iOS)
                SignalHorn.play(seconds: hornSeconds)
                #endif
                if value == "start" { announcedStart = true }
            }
            .onChange(of: seconds) { _, value in
                guard running, (1...10).contains(value), value != lastAnnouncedCountdown else { return }
                lastAnnouncedCountdown = value
                StartTimerVoice.speak(String(value))
            }
            .onChange(of: running) { _, value in
                if !value { lastAnnouncedCountdown = 99; if !finished { lastAnnouncedEvent = "" } }
            }
        }
    }
}
