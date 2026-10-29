import SwiftUI
import AVFoundation

/// Signal timer matching the supplied video: elapsed-time sequence, mast panel, signal list and start controls.
struct SignalTimerPanel: View {
    var compact = false
    @AppStorage("signalVideoStartAt") private var startAt = 0.0
    @AppStorage("signalVideoPausedSeconds") private var pausedSeconds = 0.0
    @AppStorage("signalVideoStarted") private var hasStarted = false
    @AppStorage("signalClockOffset") private var clockOffset = 0.0
    @AppStorage("signalHornSeconds") private var hornSeconds = 0.7
    @AppStorage("signalFlagProfile") private var flagProfile = "video-20"
    @State private var syncing = false
    @State private var syncMessage = ""
    @State private var hornPlayer: AVAudioPlayer?

    private let durationMinutes = 20
    private var events: [SignalSequence.Event] { SignalSequence.events(durationMinutes: durationMinutes, profileID: flagProfile) }
    private func elapsed(at date: Date) -> Double {
        if startAt > 0 { return max(0, date.timeIntervalSince1970 + clockOffset - startAt) }
        return hasStarted ? max(0, pausedSeconds) : 0
    }
    private func running(at date: Date) -> Bool {
        startAt > 0 && elapsed(at: date) < Double(events.last?.secondsAfterStart ?? 1200)
    }
    private func startOrPause(at date: Date) {
        let value = elapsed(at: date)
        if running(at: date) {
            pausedSeconds = value
            startAt = 0
            hasStarted = true
        } else {
            let completed = hasStarted && value >= Double(events.last?.secondsAfterStart ?? 1200)
            let wasPaused = hasStarted && !completed
            if completed { pausedSeconds = 0 }
            startAt = date.timeIntervalSince1970 + clockOffset - (wasPaused ? pausedSeconds : 0)
            if !wasPaused {
                pausedSeconds = 0
                hasStarted = true
                playHorn(pulses: events.first?.hornPulses ?? [])
            }
        }
    }
    private func reset() {
        startAt = 0
        pausedSeconds = 0
        hasStarted = false
    }
    private func flagColor(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
    private func elapsedText(_ seconds: Double) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let spent = elapsed(at: now)
            let active = hasStarted ? SignalSequence.activeEventIndex(elapsed: spent, durationMinutes: durationMinutes, profileID: flagProfile) : SignalSequence.initialEventIndex(durationMinutes: durationMinutes, profileID: flagProfile)
            let current = events[active]
            let isRunning = running(at: now)
            let raisedFlags = SignalSequence.flags(elapsed: spent, durationMinutes: durationMinutes, profileID: flagProfile)
            VStack(spacing: compact ? 4 : 8) {
                HStack(spacing: 5) {
                    Text("⚑").foregroundStyle(.purple)
                    Spacer()
                    Text(SignalSequence.clockText(now, offset: clockOffset))
                        .font(.system(size: compact ? 14 : 22, weight: .medium, design: .monospaced))
                    Spacer()
                    if !compact {
                        Button(syncing ? "…" : "◉") { Task { await syncClock() } }
                            .buttonStyle(.plain).foregroundStyle(.blue)
                    }
                }
                MastBoard(flags: raisedFlags, compact: compact)
                    .frame(height: compact ? 60 : 112)
                HStack {
                    Text("Start at").foregroundStyle(.black)
                    Spacer()
                    Text(hasStarted
                         ? SignalSequence.clockText(Date(timeIntervalSince1970: startAt > 0 ? startAt : now.timeIntervalSince1970 + clockOffset - pausedSeconds))
                         : "TBD")
                        .font(.system(.body, design: .monospaced)).foregroundStyle(.black)
                }
                .font(.system(size: compact ? 12 : 16, weight: .medium))
                HStack(spacing: 8) {
                    Text(current.raised ? "↑" : "↓").font(.title3.bold()).foregroundStyle(.black)
                    Text(current.title).font(.caption).lineLimit(1)
                    Spacer()
                    Text(hasStarted ? elapsedText(spent) : "--:--")
                        .font(.system(size: compact ? 28 : 38, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                    Circle().fill(Color.gray.opacity(0.65)).frame(width: compact ? 28 : 42, height: compact ? 28 : 42)
                        .overlay(Image(systemName: "timer").foregroundStyle(.white))
                }
                .foregroundStyle(.black)
                VStack(spacing: 1) {
                    ForEach(events) { event in
                        let isActive = event.id == active
                        HStack(spacing: 5) {
                            Text(event.raised ? "↑" : "↓").frame(width: 14)
                            Rectangle().fill(flagColor(event.colorHex))
                                .frame(width: 17, height: 16)
                                .overlay { if event.flag == "青" { Rectangle().fill(.white).frame(width: 6, height: 6) } }
                            Circle().fill(.black).frame(width: 6, height: 6)
                            Text(event.title).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            Text(String(format: "%02d:%02d", event.secondsAfterStart / 60, event.secondsAfterStart % 60))
                                .font(.system(size: compact ? 10 : 12, design: .monospaced))
                            Text(event.hornPulses.map { $0 == 0 ? "●" : "━" }.joined())
                                .font(.system(size: compact ? 9 : 11, weight: .bold)).frame(width: 22)
                        }
                        .font(.system(size: compact ? 9 : 12))
                        .padding(.horizontal, 3).padding(.vertical, compact ? 1 : 2)
                        .background(isActive ? Color.green.opacity(0.65) : Color.white)
                        .foregroundStyle(.black)
                    }
                }
                HStack(spacing: compact ? 8 : 22) {
                    Button("Interrupt…") { if isRunning { startOrPause(at: now) } }
                        .disabled(!isRunning).foregroundStyle(.gray)
                    Button(isRunning ? "Pause" : (hasStarted && spent < Double(events.last?.secondsAfterStart ?? 1200) ? "Resume" : "Start")) { startOrPause(at: now) }
                        .foregroundStyle(.blue).fontWeight(.semibold)
                    Button { reset() } label: { Image(systemName: "stopwatch").foregroundStyle(.blue) }
                }
                .font(.system(size: compact ? 12 : 16))
                #if os(iOS)
                if !compact {
                    let hornLengthText = String(format: "%.1f", hornSeconds)
                    HStack(spacing: 6) {
                        Picker("信号", selection: $flagProfile) {
                            ForEach(SignalSequence.profiles) { Text($0.name).tag($0.id) }
                        }.pickerStyle(.menu)
                        Text("長音 " + hornLengthText + "秒").font(.caption2)
                        Slider(value: $hornSeconds, in: 0.1...3.0, step: 0.1).frame(maxWidth: 100)
                    }
                    if !syncMessage.isEmpty { Text(syncMessage).font(.caption2).foregroundStyle(.secondary) }
                }
                #endif
            }
            .padding(compact ? 4 : 8)
            .background(Color.white)
            .foregroundStyle(.black)
            .onChange(of: active) { oldValue, newValue in
                guard isRunning, newValue > oldValue else { return }
                for index in (oldValue + 1)...newValue where events.indices.contains(index) {
                    playHorn(pulses: events[index].hornPulses)
                }
            }
        }
    }

    private func playHorn(pulses: [Int]) {
        guard !pulses.isEmpty else { return }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        let rate = 22_050.0
        let pulseDurations = pulses.map { $0 == 0 ? 0.22 : hornSeconds }
        let gapSamples = Int(rate * 0.18)
        var samples = Data(capacity: (pulseDurations.reduce(0) { $0 + Int(rate * $1) } + gapSamples * max(0, pulseDurations.count - 1)) * 2)
        for (burst, pulseDuration) in pulseDurations.enumerated() {
            let count = max(1, Int(rate * pulseDuration))
            for index in 0..<count {
                let fade = min(1, Double(index) / 160) * min(1, Double(count - index) / 1200)
                var sample = Int16(sin(2 * Double.pi * 660 * Double(index) / rate) * 0.42 * fade * Double(Int16.max)).littleEndian
                withUnsafeBytes(of: &sample) { samples.append(contentsOf: $0) }
            }
            if burst < pulseDurations.count - 1 { samples.append(Data(repeating: 0, count: gapSamples * 2)) }
        }
        var wav = Data("RIFF".utf8)
        func append32(_ value: UInt32) { var value = value.littleEndian; withUnsafeBytes(of: &value) { wav.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { var value = value.littleEndian; withUnsafeBytes(of: &value) { wav.append(contentsOf: $0) } }
        append32(UInt32(36 + samples.count)); wav.append(Data("WAVEfmt ".utf8)); append32(16); append16(1); append16(1)
        append32(UInt32(rate)); append32(UInt32(rate) * 2); append16(2); append16(16)
        wav.append(Data("data".utf8)); append32(UInt32(samples.count)); wav.append(samples)
        hornPlayer = try? AVAudioPlayer(data: wav)
        hornPlayer?.play()
    }

    @MainActor private func syncClock() async {
        syncing = true
        defer { syncing = false }
        do {
            let data = try await NICTClock.query()
            clockOffset = data.timeIntervalSinceNow
            syncMessage = "ntp.nict.jp 同期済み（差 \(String(format: "%+.3f", clockOffset)) 秒）"
        } catch {
            syncMessage = "NTP同期できません。端末時刻を使用します"
        }
    }
}

private struct MastBoard: View {
    let flags: [SignalSequence.Event]
    let compact: Bool

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .bottom, spacing: proxy.size.width * 0.10) {
                ForEach(0..<5, id: \.self) { poleIndex in
                    MastPole(poleIndex: poleIndex, flags: flags, height: proxy.size.height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.horizontal, proxy.size.width * 0.04)
            .background(Color(red: 0.39, green: 0.78, blue: 0.94))
            .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}

private struct MastPole: View {
    let poleIndex: Int
    let flags: [SignalSequence.Event]
    let height: CGFloat

    private func color(_ hex: UInt32) -> Color {
        let red = Double((hex >> 16) & 255) / 255
        let green = Double((hex >> 8) & 255) / 255
        let blue = Double(hex & 255) / 255
        return Color(red: red, green: green, blue: blue)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(poleIndex == 1 ? Color.orange : Color.gray.opacity(0.85))
                .frame(width: 2, height: height * 0.94)
            ForEach(flags.indices, id: \.self) { flagIndex in
                let event = flags[flagIndex]
                let assignedPole = [1, 3, 2, 4, 0][event.id % 5]
                if assignedPole == poleIndex {
                    HStack(spacing: 0) {
                        color(event.colorHex)
                        if event.flag == "青" {
                            Rectangle().fill(Color.white).frame(width: 7, height: 7)
                        }
                    }
                    .frame(width: 25, height: 18)
                    .offset(x: 2, y: CGFloat(flagIndex % 3) * 20 + 8)
                    .animation(.easeInOut(duration: 0.45), value: flags.map(\.id))
                }
            }
        }
        .frame(width: 28, height: height, alignment: .topLeading)
    }
}
