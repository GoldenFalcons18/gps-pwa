import SwiftUI
import AVFoundation

/// Signal timer with the two elapsed-time sequences transcribed from the supplied videos.
struct SignalTimerPanel: View {
    var compact = false
    @AppStorage("signalVideoStartAt") private var startAt = 0.0
    @AppStorage("signalVideoPausedSeconds") private var pausedSeconds = 0.0
    @AppStorage("signalVideoStarted") private var hasStarted = false
    @AppStorage("signalClockOffset") private var clockOffset = 0.0
    @AppStorage("signalMinimumTimeToFirstAction") private var minimumTimeToFirstAction = 15
    @AppStorage("signalHornSeconds") private var hornSeconds = 0.7
    @AppStorage("signalShortHornSeconds") private var shortHornSeconds = 0.22
    @AppStorage("signalHornGapSeconds") private var hornGapSeconds = 0.18
    @AppStorage("signalHornVolume") private var hornVolume = 0.8
    @AppStorage("signalHornEnabled") private var hornEnabled = true
    @AppStorage("signalFlagProfile") private var flagProfile = "standard-start"
    @AppStorage("signalSequenceTimingVersion") private var sequenceTimingVersion = 0
    @AppStorage("signalCustomClassFlag") private var classFlagID = "class-4"
    @AppStorage("signalCustomPrepFlag") private var prepFlagID = "P"
    @AppStorage("signalIndividualRecallFlagUp") private var individualRecallFlagUp = false
    @AppStorage("signalGeneralRecallFlagUp") private var generalRecallFlagUp = false
    @AppStorage("signalPostponementFlagUp") private var postponementFlagUp = false
    @AppStorage("signalOrangeManualOverride") private var orangeManualOverride = false
    @AppStorage("signalOrangeManualUp") private var orangeManualUp = false
    @AppStorage("signalRestartWarningAt") private var restartWarningAt = 0.0
    @State private var syncing = false
    @State private var syncMessage = ""
    @State private var hornPlayer: AVAudioPlayer?
    @State private var showSettings = false

    private let durationMinutes = 20
    private var events: [SignalSequence.Event] {
        SignalSequence.events(durationMinutes: durationMinutes, profileID: flagProfile, classFlagID: classFlagID, prepFlagID: prepFlagID)
    }
    private var recallRestartEvents: [SignalSequence.Event] {
        SignalSequence.recallRestartEvents(classFlagID: classFlagID, prepFlagID: prepFlagID)
    }
    private func pauseForManualSignal(at date: Date) {
        if startAt > 0 {
            pausedSeconds = elapsed(at: date)
            startAt = 0
        }
        hasStarted = true
    }
    private func toggleIndividualRecall(at date: Date) {
        if individualRecallFlagUp {
            individualRecallFlagUp = false
        } else {
            individualRecallFlagUp = true
            playHorn(pulses: SignalSequence.individualRecallRaise.hornPulses)
        }
    }
    private func toggleGeneralRecall(at date: Date) {
        if generalRecallFlagUp {
            generalRecallFlagUp = false
            playHorn(pulses: SignalSequence.generalRecallLower.hornPulses)
            restartWarningAt = date.timeIntervalSince1970 + clockOffset + 60
        } else {
            pauseForManualSignal(at: date)
            individualRecallFlagUp = false
            postponementFlagUp = false
            restartWarningAt = 0
            generalRecallFlagUp = true
            playHorn(pulses: SignalSequence.generalRecallRaise.hornPulses)
        }
    }
    private func togglePostponement(at date: Date) {
        if postponementFlagUp {
            postponementFlagUp = false
            playHorn(pulses: SignalSequence.postponementLower.hornPulses)
            restartWarningAt = date.timeIntervalSince1970 + clockOffset + 60
        } else {
            pauseForManualSignal(at: date)
            individualRecallFlagUp = false
            generalRecallFlagUp = false
            restartWarningAt = 0
            postponementFlagUp = true
            playHorn(pulses: SignalSequence.postponementRaise.hornPulses)
        }
    }
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
            let correctedNow = date.timeIntervalSince1970 + clockOffset
            startAt = wasPaused && pausedSeconds > 0
                ? correctedNow - pausedSeconds
                : SignalSequence.nextMinuteBoundary(at: correctedNow, minimumLeadSeconds: minimumTimeToFirstAction)
            if !wasPaused {
                pausedSeconds = 0
                hasStarted = true
            }
        }
    }
    private func reset() {
        startAt = 0
        pausedSeconds = 0
        hasStarted = false
        individualRecallFlagUp = false
        generalRecallFlagUp = false
        postponementFlagUp = false
        restartWarningAt = 0
        orangeManualOverride = false
        orangeManualUp = false
    }
    private func elapsedText(_ seconds: Double) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
    private func countdownText(_ seconds: Double) -> String {
        let value = SignalSequence.countdownSeconds(seconds)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    private func eventTimeText(_ event: SignalSequence.Event, restart: Bool = false) -> String {
        guard flagProfile == "standard-start" || restart else {
            return String(format: "%02d:%02d", event.secondsAfterStart / 60, event.secondsAfterStart % 60)
        }
        let startOffset = restart ? 300 : 600
        let offset = event.secondsAfterStart - startOffset
        let time = String(format: "%02d:%02d", abs(offset) / 60, abs(offset) % 60)
        if offset == 0 { return "T+00:00" }
        return offset < 0 ? "T−\(time)" : "T+\(time)"
    }

    private func activeEventIndex(retryPending: Bool, useRetrySequence: Bool, waitingForFirstSignal: Bool, sequenceEvents: [SignalSequence.Event], sequenceElapsed: Double, spent: Double) -> Int {
        if retryPending { return 0 }
        if waitingForFirstSignal { return -1 }
        if useRetrySequence {
            return sequenceEvents.lastIndex { Double($0.secondsAfterStart) <= sequenceElapsed } ?? 0
        }
        if hasStarted {
            return SignalSequence.activeEventIndex(elapsed: spent, durationMinutes: durationMinutes, profileID: flagProfile, classFlagID: classFlagID, prepFlagID: prepFlagID)
        }
        return -1
    }

    private func displayedFlags(retryPending: Bool, useRetrySequence: Bool, waitingForFirstSignal: Bool, sequenceEvents: [SignalSequence.Event], sequenceElapsed: Double) -> [SignalSequence.Flag] {
        var visible = retryPending
            ? [SignalSequence.flag("orange")]
            : ((hasStarted || useRetrySequence) && !waitingForFirstSignal
                ? SignalSequence.raisedFlags(events: sequenceEvents, elapsed: sequenceElapsed)
                : [])
        if useRetrySequence && sequenceElapsed < 540 {
            visible.append(SignalSequence.flag("orange"))
        }
        if generalRecallFlagUp {
            visible = [SignalSequence.flag("orange"), SignalSequence.flag("first-sub")]
        } else if postponementFlagUp {
            visible = [SignalSequence.flag("orange"), SignalSequence.flag("AP")]
        } else if individualRecallFlagUp {
            visible.append(SignalSequence.flag("X"))
        }
        if orangeManualOverride {
            visible.removeAll { $0.id == "orange" }
            if orangeManualUp { visible.append(SignalSequence.flag("orange")) }
        }
        var unique: [String: SignalSequence.Flag] = [:]
        for flag in visible { unique[flag.id] = flag }
        return unique.values.sorted { $0.id < $1.id }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let spent = elapsed(at: now)
            let correctedNow = now.timeIntervalSince1970 + clockOffset
            let retryPending = restartWarningAt > correctedNow
            let useRetrySequence = restartWarningAt > 0 && !retryPending
            let waitingForFirstSignal = !useRetrySequence && startAt > correctedNow
            let sequenceEvents = useRetrySequence ? recallRestartEvents : events
            let sequenceElapsed = retryPending ? 0 : (useRetrySequence ? max(0, correctedNow - restartWarningAt) : spent)
            let active = activeEventIndex(retryPending: retryPending, useRetrySequence: useRetrySequence, waitingForFirstSignal: waitingForFirstSignal, sequenceEvents: sequenceEvents, sequenceElapsed: sequenceElapsed, spent: spent)
            let current = sequenceEvents[max(0, active)]
            let isRunning = useRetrySequence
                ? sequenceElapsed < Double(sequenceEvents.last?.secondsAfterStart ?? 540)
                : running(at: now)
            let displaySeconds = retryPending ? max(0, restartWarningAt - correctedNow) : (waitingForFirstSignal ? max(0, startAt - correctedNow) : sequenceElapsed)
            let raisedFlags = displayedFlags(retryPending: retryPending, useRetrySequence: useRetrySequence, waitingForFirstSignal: waitingForFirstSignal, sequenceEvents: sequenceEvents, sequenceElapsed: sequenceElapsed)
            VStack(spacing: compact ? 4 : 8) {
                HStack(spacing: 5) {
                    Text("⚑").foregroundStyle(.purple)
                    Spacer()
                    Text(SignalSequence.clockText(now, offset: clockOffset))
                        .font(.system(size: compact ? 14 : 22, weight: .medium, design: .monospaced))
                    Spacer()
                    if !compact {
                        #if os(iOS)
                        Button { showSettings = true } label: { Image(systemName: "gearshape.fill") }
                            .buttonStyle(.plain).foregroundStyle(.orange)
                        #endif
                        Button(syncing ? "…" : "◉") { Task { await syncClock() } }
                            .buttonStyle(.plain).foregroundStyle(.blue)
                    }
                }
                MastBoard(flags: raisedFlags, compact: compact)
                    .frame(height: compact ? 60 : 112)
                HStack {
                    Text(retryPending ? "次の予告信号まで" : (waitingForFirstSignal ? "次の分00秒まで" : (useRetrySequence ? "再予告信号時刻" : "オレンジ旗を上げる時刻"))).foregroundStyle(.black)
                    Spacer()
                    Text(retryPending
                         ? countdownText(displaySeconds)
                         : (hasStarted
                            ? SignalSequence.clockText(Date(timeIntervalSince1970: useRetrySequence ? restartWarningAt : (startAt > 0 ? startAt : now.timeIntervalSince1970 + clockOffset - pausedSeconds)))
                            : "TBD"))
                        .font(.system(.body, design: .monospaced)).foregroundStyle(.black)
                }
                .font(.system(size: compact ? 12 : 16, weight: .medium))
                HStack(spacing: 8) {
                    Text(waitingForFirstSignal ? "◷" : (current.raised ? "↑" : "↓")).font(.title3.bold()).foregroundStyle(.black)
                    Text(waitingForFirstSignal ? "分00秒待ち · " + current.title : current.title).font(.caption).lineLimit(1)
                    Spacer()
                    Text((hasStarted || restartWarningAt > 0) ? ((waitingForFirstSignal || retryPending) ? countdownText(displaySeconds) : elapsedText(displaySeconds)) : "--:--")
                        .font(.system(size: compact ? 28 : 38, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                    Circle().fill(Color.gray.opacity(0.65)).frame(width: compact ? 28 : 42, height: compact ? 28 : 42)
                        .overlay(Image(systemName: "timer").foregroundStyle(.white))
                }
                .foregroundStyle(.black)
                VStack(spacing: 1) {
                    ForEach(sequenceEvents) { event in
                        let isActive = event.id == active
                        HStack(spacing: 5) {
                            Text(event.raised ? "↑" : "↓").frame(width: 14)
                            HStack(spacing: 2) {
                                ForEach(event.flags) { flag in
                                    SignalFlagView(flag: flag)
                                        .frame(width: compact ? 16 : 22, height: compact ? 12 : 16)
                                }
                            }
                            Circle().fill(.black).frame(width: 6, height: 6)
                            Text(event.title).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            Text(eventTimeText(event, restart: useRetrySequence))
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
                    Button("中断") { if isRunning { startOrPause(at: now) } }
                        .disabled(!isRunning || restartWarningAt > 0).foregroundStyle(.gray)
                    Button(waitingForFirstSignal ? "分00秒合わせ中（取消）" : (isRunning ? "一時停止" : (hasStarted && spent < Double(events.last?.secondsAfterStart ?? 1200) ? "再開" : "開始"))) { startOrPause(at: now) }
                        .disabled(restartWarningAt > 0 || generalRecallFlagUp || postponementFlagUp)
                        .foregroundStyle(.blue).fontWeight(.semibold)
                    Button { reset() } label: { Image(systemName: "stopwatch").foregroundStyle(.blue) }
                }
                .font(.system(size: compact ? 12 : 16))
                HStack(spacing: compact ? 4 : 10) {
                    Button(raisedFlags.contains(where: { $0.id == "orange" }) ? "橙旗 降下" : "橙旗 掲揚") {
                        orangeManualUp = !raisedFlags.contains(where: { $0.id == "orange" })
                        orangeManualOverride = true
                    }
                    Button(individualRecallFlagUp ? "X旗 降下" : "個別リコール X旗") { toggleIndividualRecall(at: now) }
                        .disabled(!["P", "I"].contains(prepFlagID) || generalRecallFlagUp || postponementFlagUp)
                    Button(generalRecallFlagUp ? "第一代表旗 降下" : "ゼネラルリコール") { toggleGeneralRecall(at: now) }
                        .disabled(postponementFlagUp)
                    Button(postponementFlagUp ? "AP 降下" : "AP 掲揚") { togglePostponement(at: now) }
                        .disabled(generalRecallFlagUp)
                }
                .font(.system(size: compact ? 9 : 12, weight: .semibold))
                .buttonStyle(.bordered)
                #if os(iOS)
                if !compact {
                    VStack(spacing: 4) {
                        Picker("スタート手順", selection: $flagProfile) {
                            ForEach(SignalSequence.profiles.filter { !["class-p", "class-i"].contains($0.id) }) { Text($0.name).tag($0.id) }
                        }.pickerStyle(.menu)
                        if flagProfile == "custom-five" || flagProfile == "standard-start" {
                            HStack(spacing: 8) {
                                Picker("クラス旗", selection: $classFlagID) {
                                    ForEach(SignalSequence.flagCatalog.filter { $0.id.hasPrefix("class-") }) { Text($0.name).tag($0.id) }
                                }.pickerStyle(.menu)
                                Picker("準備旗", selection: $prepFlagID) {
                                    ForEach(SignalSequence.flagCatalog.filter { ["P", "I", "U", "Z", "black"].contains($0.id) }) { Text($0.name).tag($0.id) }
                                }.pickerStyle(.menu)
                            }
                        }
                        DisclosureGroup("ホーン設定") {
                            Toggle("仮想ホーンを有効にする", isOn: $hornEnabled)
                            signalSlider("音量", value: $hornVolume, range: 0...1, step: 0.05, format: "%.0f%%", scale: 100)
                            signalSlider("短音", value: $shortHornSeconds, range: 0.1...1.0, step: 0.05, format: "%.2f秒", scale: 1)
                            signalSlider("長音", value: $hornSeconds, range: 0.1...5.0, step: 0.1, format: "%.1f秒", scale: 1)
                            signalSlider("連発間隔", value: $hornGapSeconds, range: 0.1...2.0, step: 0.05, format: "%.2f秒", scale: 1)
                        }
                        .font(.caption)
                    }
                    if !syncMessage.isEmpty { Text(syncMessage).font(.caption2).foregroundStyle(.secondary) }
                }
                #endif
            }
            .padding(compact ? 4 : 8)
            .background(Color.white)
            .foregroundStyle(.black)
            #if os(iOS)
            .sheet(isPresented: $showSettings) { SignalSettingsView() }
            #endif
            .onAppear {
                if sequenceTimingVersion < 2 {
                    flagProfile = "standard-start"
                    sequenceTimingVersion = 2
                }
                if flagProfile == "class-p" || flagProfile == "class-i" {
                    prepFlagID = flagProfile == "class-p" ? "P" : "I"
                    classFlagID = "class-1"
                    flagProfile = "custom-five"
                }
            }
            .onChange(of: useRetrySequence) { oldValue, newValue in
                guard !oldValue, newValue else { return }
                playHorn(pulses: sequenceEvents.first?.hornPulses ?? [0])
            }
            .onChange(of: active) { oldValue, newValue in
                guard newValue > oldValue else { return }
                let crossed = (oldValue + 1)...newValue
                if crossed.contains(where: { sequenceEvents.indices.contains($0) && sequenceEvents[$0].flags.contains(where: { $0.id == "orange" }) }) {
                    orangeManualOverride = false
                    orangeManualUp = false
                }
                guard isRunning else { return }
                for index in crossed where sequenceEvents.indices.contains(index) {
                    playHorn(pulses: sequenceEvents[index].hornPulses)
                }
            }
        }
    }

    private func signalSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, format: String, scale: Double) -> some View {
        HStack(spacing: 6) {
            Text(title).frame(width: 72, alignment: .leading)
            Slider(value: value, in: range, step: step)
            Text(String(format: format, value.wrappedValue * scale))
                .font(.system(.caption2, design: .monospaced)).frame(width: 48, alignment: .trailing)
        }
    }

    private func playHorn(pulses: [Int]) {
        guard hornEnabled, !pulses.isEmpty else { return }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        let rate = 22_050.0
        let pulseDurations = pulses.map { $0 == 0 ? shortHornSeconds : hornSeconds }
        let gapSamples = Int(rate * hornGapSeconds)
        var samples = Data(capacity: (pulseDurations.reduce(0) { $0 + Int(rate * $1) } + gapSamples * max(0, pulseDurations.count - 1)) * 2)
        for (burst, pulseDuration) in pulseDurations.enumerated() {
            let count = max(1, Int(rate * pulseDuration))
            for index in 0..<count {
                let fade = min(1, Double(index) / 160) * min(1, Double(count - index) / 1200)
                var sample = Int16(sin(2 * Double.pi * 660 * Double(index) / rate) * 0.42 * hornVolume * fade * Double(Int16.max)).littleEndian
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
    let flags: [SignalSequence.Flag]
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
    let flags: [SignalSequence.Flag]
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(poleIndex == 1 ? Color.orange : Color.gray.opacity(0.85))
                .frame(width: 2, height: height * 0.94)
            ForEach(flags.indices, id: \.self) { flagIndex in
                if [1, 3, 2, 4, 0][flagIndex % 5] == poleIndex {
                    SignalFlagView(flag: flags[flagIndex])
                        .frame(width: 25, height: 18)
                        .offset(x: 2, y: CGFloat(flagIndex / 5) * 20 + 8)
                        .animation(.easeInOut(duration: 0.45), value: flags.map(\.id))
                }
            }
        }
        .frame(width: 28, height: height, alignment: .topLeading)
    }
}

private struct SignalFlagView: View {
    let flag: SignalSequence.Flag

    private func color(_ index: Int) -> Color {
        let hex = flag.colors[min(index, flag.colors.count - 1)]
        return Color(red: Double((hex >> 16) & 255) / 255,
                     green: Double((hex >> 8) & 255) / 255,
                     blue: Double(hex & 255) / 255)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            ZStack {
                switch flag.style {
                case "diagonal":
                    color(0)
                    Path { path in
                        path.move(to: .zero); path.addLine(to: CGPoint(x: width, y: .zero))
                        path.addLine(to: CGPoint(x: .zero, y: height)); path.closeSubpath()
                    }.fill(color(1))
                case "checker", "nFlag", "uFlag":
                    VStack(spacing: 0) {
                        HStack(spacing: 0) { color(0); color(1) }
                        HStack(spacing: 0) { color(1); color(0) }
                    }
                case "blueSquare", "pFlag":
                    color(0)
                    Rectangle().fill(color(1)).frame(width: width * 0.42, height: height * 0.42)
                case "iFlag":
                    color(0)
                    Circle().fill(color(1)).frame(width: height * 0.50, height: height * 0.50)
                case "zFlag", "lFlag":
                    color(0)
                    VStack(spacing: 0) { color(1); color(0); color(1) }.frame(height: height * 0.62)
                case "apFlag", "hFlag":
                    HStack(spacing: 0) { color(0); color(1) }
                case "firstSub":
                    color(0)
                    Path { path in
                        path.move(to: .zero); path.addLine(to: CGPoint(x: width, y: height))
                        path.addLine(to: CGPoint(x: width, y: .zero)); path.closeSubpath()
                    }.fill(color(1))
                case "xFlag":
                    color(0)
                    Rectangle().fill(color(1)).frame(width: width * 0.22, height: height)
                    Rectangle().fill(color(1)).frame(width: width, height: height * 0.22)
                case "classLogo":
                    Color.white
                    Circle().fill(color(1)).frame(width: height * 0.64, height: height * 0.64)
                default:
                    color(0)
                }
                if !flag.symbol.isEmpty {
                    Text(flag.symbol)
                        .font(.system(size: max(6, height * 0.58), weight: .black, design: .rounded))
                        .foregroundStyle(["black", "I", "Z", "L"].contains(flag.id) ? Color.white : Color.black)
                        .minimumScaleFactor(0.45)
                        .lineLimit(1)
                        .shadow(color: .white.opacity(0.5), radius: 0.5)
                }
            }
            .overlay(Rectangle().stroke(Color.black.opacity(0.7), lineWidth: 0.6))
        }
        .clipShape(Rectangle())
    }
}
