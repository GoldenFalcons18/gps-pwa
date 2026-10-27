import SwiftUI
import AVFoundation

/// Race-start signal presentation styled after the supplied video: animated mast,
/// prominent current signal/countdown, and a highlighted vertical flag sequence.
struct SignalTimerPanel: View {
    var compact = false
    @AppStorage("signalStartAt") private var startAt = 0.0
    @AppStorage("signalPausedSeconds") private var pausedSeconds = 0.0
    @AppStorage("signalDurationMinutes") private var durationMinutes = 5
    @AppStorage("signalClockOffset") private var clockOffset = 0.0
    @AppStorage("signalHornSeconds") private var hornSeconds = 0.7
    @AppStorage("signalHornCount") private var hornCount = 1
    @AppStorage("signalFlagProfile") private var flagProfile = "class-p"
    @State private var syncing = false
    @State private var syncMessage = ""
    @State private var hornPlayer: AVAudioPlayer?

    private var duration: Double { Double(max(1, durationMinutes) * 60) }
    private func remaining(at date: Date) -> Double {
        startAt > 0 ? startAt - (date.timeIntervalSince1970 + clockOffset) : (pausedSeconds > 0 ? pausedSeconds : duration)
    }
    private func begin(at date: Date) {
        let timestamp = date.timeIntervalSince1970 + clockOffset
        if startAt > timestamp {
            pausedSeconds = max(1, startAt - timestamp)
            startAt = 0
        } else {
            let resuming = pausedSeconds > 0
            startAt = timestamp + (pausedSeconds > 0 ? pausedSeconds : duration)
            pausedSeconds = 0
            if !resuming { playHorn() }
        }
    }
    private func zero(at date: Date) {
        // Manual zero alignment: the operator taps exactly when the start signal is given.
        startAt = date.timeIntervalSince1970 + clockOffset
        pausedSeconds = 0
        playHorn()
    }
    private func reset() { startAt = 0; pausedSeconds = 0 }
    private func flagColor(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
    private func countdown(_ value: Double) -> String {
        let seconds = Int(ceil(abs(value)))
        let sign = value < 0 ? "+" : "−"
        return seconds >= 60 ? String(format: "%@%d:%02d", sign, seconds / 60, seconds % 60) : String(format: "%@%02d", sign, seconds)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let left = remaining(at: now)
            let events = SignalSequence.events(durationMinutes: durationMinutes, profileID: flagProfile)
            let active = SignalSequence.nextEventIndex(secondsUntilStart: left, durationMinutes: durationMinutes, profileID: flagProfile)
            let next = events[active]
            let phaseSeconds = SignalSequence.secondsUntilNextEvent(secondsUntilStart: left, index: active, durationMinutes: durationMinutes, profileID: flagProfile)
            let running = startAt > now.timeIntervalSince1970 + clockOffset
            let completed = startAt > 0 && !running
            VStack(spacing: compact ? 5 : 9) {
                HStack {
                    Text(SignalSequence.clockText(now, offset: clockOffset))
                        .font(.system(size: compact ? 12 : 18, weight: .semibold, design: .monospaced))
                    Spacer()
                    if !compact {
                        Button(syncing ? "同期中…" : "NTP同期") { Task { await syncClock() } }
                            .font(.caption).buttonStyle(.bordered).tint(.blue).disabled(syncing)
                    }
                }
                HStack(spacing: compact ? 7 : 14) {
                    mast(event: next, animating: running && !completed && phaseSeconds <= 10 && phaseSeconds > 0)
                        .frame(width: compact ? 58 : 118, height: compact ? 84 : 168)
                    VStack(alignment: .leading, spacing: compact ? 1 : 4) {
                        Text(next.title).font(compact ? .caption.bold() : .title2.bold()).lineLimit(1).minimumScaleFactor(0.55)
                        Text(countdown(Double(phaseSeconds)))
                            .font(.system(size: compact ? 34 : 76, weight: .bold, design: .rounded))
                            .monospacedDigit().minimumScaleFactor(0.45).lineLimit(1)
                        Text(completed ? "スタート信号" : "次の信号まで")
                            .font(compact ? .system(size: 9) : .subheadline).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .center)
                }
                VStack(spacing: 2) {
                    ForEach(events) { event in
                        let isActive = event.id == active
                        HStack(spacing: 8) {
                            Image(systemName: event.raised ? "arrow.up" : "arrow.down")
                                .font(.system(size: compact ? 10 : 15, weight: .bold)).frame(width: compact ? 18 : 26)
                            flagSwatch(event: event, compact: compact)
                            Text(event.title).font(compact ? .system(size: 10, weight: .medium) : .subheadline.bold())
                                .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            Text(event.secondsBeforeStart == 0 ? "00:00" : String(format: "%02d:%02d", event.secondsBeforeStart / 60, event.secondsBeforeStart % 60))
                                .font(.system(size: compact ? 9 : 12, weight: .medium, design: .monospaced))
                        }
                        .padding(.horizontal, compact ? 4 : 9).padding(.vertical, compact ? 2 : 5)
                        .background(isActive ? Color.green.opacity(0.58) : Color.white.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .animation(.easeInOut(duration: 0.25), value: isActive)
                    }
                }
                if !compact { Text("旗の順序は大会の帆走指示書に合わせてください").font(.system(size: 10)).foregroundStyle(.secondary) }
                if !syncMessage.isEmpty { Text(syncMessage).font(.caption2).foregroundStyle(.secondary) }
                if !compact { Picker("旗シーケンス", selection: $flagProfile) { ForEach(SignalSequence.profiles) { profile in Text(profile.name).tag(profile.id) } }.pickerStyle(.menu).tint(.orange)
                HStack(spacing: 6) {
                    Text("ホーン \(String(format: "%.1f", hornSeconds))秒").font(.caption)
                    Slider(value: $hornSeconds, in: 0.1...3.0, step: 0.1).tint(.orange)
                }.frame(maxWidth: 340)
                Picker("ホーン回数", selection: $hornCount) { Text("1回").tag(1); Text("2回").tag(2); Text("3回").tag(3) }.pickerStyle(.segmented).tint(.orange) }
                HStack(spacing: compact ? 3 : 7) {
                    ForEach([1, 3, 5, 10], id: \.self) { minute in
                        Button("\(minute)分") { durationMinutes = minute; reset() }
                            .font(compact ? .system(size: 9) : .caption).buttonStyle(.bordered)
                            .tint(durationMinutes == minute ? .green : .orange)
                    }
                    Button("0秒合わせ") { zero(at: now) }
                        .font(compact ? .system(size: 9) : .caption).buttonStyle(.bordered).tint(.orange)
                }
                HStack(spacing: 8) {
                    Button(running ? "一時停止" : "開始／再開") { begin(at: now) }
                        .buttonStyle(.borderedProminent).tint(running ? .orange : .green)
                    Button("リセット") { reset() }.buttonStyle(.bordered).tint(.gray)
                }
            }
            .padding(compact ? 4 : 10).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black).foregroundStyle(.white).preferredColorScheme(.dark)
            .onChange(of: active) { oldValue, newValue in if oldValue != newValue && running { playHorn() } }
        }
    }

    private func mast(event: SignalSequence.Event, animating: Bool) -> some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            ZStack(alignment: .topLeading) {
                Rectangle().fill(.gray.opacity(0.85)).frame(width: 3, height: h * 0.94).offset(x: w * 0.16, y: h * 0.03)
                flagColor(event.colorHex)
                    .frame(width: w * 0.72, height: h * 0.34)
                    .overlay(alignment: .center) { Text(event.flag).font(.system(size: h * 0.12, weight: .bold)).foregroundStyle(.white) }
                    .rotationEffect(.degrees(animating ? -2 : 0), anchor: .leading)
                    .offset(x: w * 0.19, y: event.raised ? h * 0.05 : h * 0.60)
                    .animation(.easeInOut(duration: 0.45), value: event.id)
                Rectangle().fill(.gray.opacity(0.45)).frame(width: w * 0.86, height: 2).offset(x: w * 0.05, y: h * 0.96)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .background(Color(red: 0.24, green: 0.70, blue: 0.90))
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func flagSwatch(event: SignalSequence.Event, compact: Bool) -> some View {
        Rectangle().fill(flagColor(event.colorHex)).frame(width: compact ? 18 : 28, height: compact ? 13 : 20)
            .overlay { if event.flag == "青" { Rectangle().fill(.white).frame(width: compact ? 5 : 8, height: compact ? 5 : 8) } }
            .overlay(Rectangle().stroke(.black.opacity(0.45), lineWidth: 1))
    }

    private func playHorn() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        let rate = 22_050.0
        let burstSamples = max(1, Int(rate * hornSeconds)), gapSamples = Int(rate * 0.18)
        var samples = Data(capacity: (burstSamples * max(1, hornCount) + gapSamples * max(0, hornCount - 1)) * 2)
        for burst in 0..<max(1, hornCount) {
            for index in 0..<burstSamples {
                let fade = min(1, Double(index) / 160) * min(1, Double(burstSamples - index) / 1200)
                let sample = Int16(sin(2 * Double.pi * 660 * Double(index) / rate) * 0.42 * fade * Double(Int16.max))
                var little = sample.littleEndian
                withUnsafeBytes(of: &little) { samples.append(contentsOf: $0) }
            }
            if burst < hornCount - 1 { samples.append(Data(repeating: 0, count: gapSamples * 2)) }
        }
        var wav = Data("RIFF".utf8)
        func append32(_ value: UInt32) { var value = value.littleEndian; withUnsafeBytes(of: &value) { wav.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { var value = value.littleEndian; withUnsafeBytes(of: &value) { wav.append(contentsOf: $0) } }
        append32(UInt32(36 + samples.count)); wav.append(Data("WAVEfmt ".utf8)); append32(16); append16(1); append16(1)
        append32(UInt32(rate)); append32(UInt32(rate) * 2); append16(2); append16(16)
        wav.append(Data("data".utf8)); append32(UInt32(samples.count)); wav.append(samples)
        do { hornPlayer = try AVAudioPlayer(data: wav); hornPlayer?.play() }
        catch { syncMessage = "ホーンを再生できません" }
    }

    @MainActor private func syncClock() async {
        syncing = true
        defer { syncing = false }
        // NICT's public NTP endpoint uses UDP/123; URL time endpoints are avoided.
        do {
            let data = try await NICTClock.query()
            clockOffset = data.timeIntervalSinceNow
            syncMessage = "ntp.nict.jp 同期済み（差 \(String(format: "%+.3f", clockOffset)) 秒）"
        } catch {
            syncMessage = "NTP同期できません。端末時刻を使用します"
        }
    }
}
