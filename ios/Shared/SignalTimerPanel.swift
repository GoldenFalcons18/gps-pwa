import SwiftUI
import AVFoundation

// Rebuild trigger for logo color controls

/// Signal timer with the two elapsed-time sequences transcribed from the supplied videos.
struct SignalTimerPanel: View {
    var compact = false
    @AppStorage("signalVideoStartAt") private var startAt = 0.0
    @AppStorage("signalVideoPausedSeconds") private var pausedSeconds = 0.0
    @AppStorage("signalVideoPausedAt") private var pausedAt = 0.0
    @AppStorage("signalVideoStarted") private var hasStarted = false
    @AppStorage("signalRunEventsJSON") private var runEventsJSON = ""
    @AppStorage("signalClockOffset") private var clockOffset = 0.0
    @AppStorage("signalMinimumTimeToFirstAction") private var minimumTimeToFirstAction = 15
    @AppStorage("signalHornSeconds") private var hornSeconds = 5.1
    @AppStorage("signalShortHornSeconds") private var shortHornSeconds = 3.1
    @AppStorage("signalHornGapSeconds") private var hornGapSeconds = 1.1
    @AppStorage("signalHornTimingPresetMigrated") private var hornTimingPresetMigrated = false
    @AppStorage("signalHornVolume") private var hornVolume = 0.8
    @AppStorage("signalHornEnabled") private var hornEnabled = true
    @AppStorage("signalFlagProfile") private var flagProfile = "standard-start"
    @AppStorage("signalSequenceTimingVersion") private var sequenceTimingVersion = 0
    @AppStorage("signalCustomClassFlag") private var classFlagID = "class-4"
    @AppStorage("signalCustomPrepFlag") private var prepFlagID = "P"
    @AppStorage("signalActiveStartActionsJSON") private var activeStartActionsJSON = "[]"
    @AppStorage("signalOrangeEnabled") private var orangeEnabled = true
    @AppStorage("signalOrangeDisplayedMinutes") private var orangeDisplayedMinutes = 5
    @AppStorage("signalOrangeRemovedAfterMinutes") private var orangeRemovedMinutes = 4
    @AppStorage("signalRaceDelayEnabled") private var raceDelayEnabled = false
    @AppStorage("signalRaceDelayMinutes") private var raceDelayMinutes = 0
    @AppStorage("signalIndividualRecallFlagUp") private var individualRecallFlagUp = false
    @AppStorage("signalAbandonFlagUp") private var abandonFlagUp = false
    @AppStorage("signalSkipFinalEvent") private var skipFinalEvent = false
    @AppStorage("signalGeneralRecallFlagUp") private var generalRecallFlagUp = false
    @AppStorage("signalPostponementFlagUp") private var postponementFlagUp = false
    @AppStorage("signalOrangeManualOverride") private var orangeManualOverride = false
    @AppStorage("signalOrangeManualUp") private var orangeManualUp = false
    @AppStorage("signalOrangeRaisedAt") private var orangeRaisedAt = 0.0
    @AppStorage("signalRestartWarningAt") private var restartWarningAt = 0.0
    @AppStorage("signalPostponementLowerAt") private var postponementLowerAt = 0.0
    @AppStorage("signalPostponementWarningAt") private var postponementWarningAt = 0.0
    @State private var hornPlayer: AVAudioPlayer?
    @State private var showSettings = false
    @State private var showInterruptOptions = false
    @State private var showSchedule = false
    @State private var scheduledDate = SignalSequence.defaultScheduledDate()
    @State private var scheduleMode = 0
    @State private var scheduleValidationMessage = ""

    private let durationMinutes = 20
    private var configuredEvents: [SignalSequence.Event] {
        let base = SignalSequence.events(durationMinutes: durationMinutes, profileID: flagProfile, classFlagID: classFlagID, prepFlagID: prepFlagID)
        let all = SignalSequence.configuredStartEvents(
            json: activeStartActionsJSON,
            profileID: flagProfile,
            prepFlagID: prepFlagID,
            orangeEnabled: orangeEnabled,
            orangeDisplayedMinutes: orangeDisplayedMinutes,
            orangeRemovedMinutes: orangeRemovedMinutes,
            raceDelayEnabled: raceDelayEnabled,
            raceDelayMinutes: raceDelayMinutes
        ) ?? base
        return skipFinalEvent && all.count > 1 ? Array(all.dropLast()) : all
    }
    private var events: [SignalSequence.Event] {
        if hasStarted, let data = runEventsJSON.data(using: .utf8),
           let frozen = try? JSONDecoder().decode([SignalSequence.Event].self, from: data), !frozen.isEmpty {
            return frozen
        }
        return configuredEvents
    }
    private func freezeConfiguredEvents() {
        guard let data = try? JSONEncoder().encode(configuredEvents),
              let value = String(data: data, encoding: .utf8) else { return }
        runEventsJSON = value
    }
    private func manualOrangeAnchoredRun(at correctedNow: Double) -> (start: Double, events: [SignalSequence.Event])? {
        guard orangeManualOverride, orangeManualUp, orangeRaisedAt > 0,
              let rebased = SignalSequence.eventsStartingAtFirstClassWarning(configuredEvents),
              let data = try? JSONEncoder().encode(rebased),
              let value = String(data: data, encoding: .utf8) else { return nil }
        runEventsJSON = value
        let start = SignalSequence.startAfterOrangeRaise(
            now: correctedNow,
            orangeRaisedAt: orangeRaisedAt,
            intervalMinutes: orangeDisplayedMinutes,
            minimumLeadSeconds: minimumTimeToFirstAction
        )
        return (start, rebased)
    }
    private var recallRestartEvents: [SignalSequence.Event] {
        SignalSequence.recallRestartEvents(classFlagID: classFlagID, prepFlagID: prepFlagID, orangeEnabled: orangeEnabled, orangeRemovedMinutes: orangeRemovedMinutes)
    }
    private func orangeRaiseTime(at date: Date) -> Double? {
        if orangeManualOverride { return orangeManualUp && orangeRaisedAt > 0 ? orangeRaisedAt : nil }
        let correctedNow = date.timeIntervalSince1970 + clockOffset
        let restart = restartWarningAt > 0
        let base = restart ? restartWarningAt : (startAt > 0 ? startAt : (hasStarted ? pausedAt - pausedSeconds : 0))
        guard base > 0 else { return nil }
        if !restart && startAt > correctedNow { return nil }
        let elapsed = restart ? max(0, correctedNow - restartWarningAt) : elapsed(at: date)
        let timeline = restart ? recallRestartEvents : events
        return SignalSequence.raisedFlagTime(events: timeline, flagID: "orange", elapsed: elapsed, baseTime: base)
    }
    private func pauseForManualSignal(at date: Date) {
        if startAt > 0 {
            pausedAt = max(startAt, date.timeIntervalSince1970 + clockOffset)
            pausedSeconds = elapsed(at: date)
            startAt = 0
        }
        if startAt > 0 || hasStarted { hasStarted = true }
    }
    private func toggleAbandon(at date: Date) {
        if !abandonFlagUp && !canOperateRaceSignals(at: date) { return }
        if abandonFlagUp {
            abandonFlagUp = false
            playHorn(pulses: SignalSequence.abandonLower.hornPulses)
            restartWarningAt = SignalSequence.restartWarningTime(loweredAt: date.timeIntervalSince1970 + clockOffset)
        } else {
            pauseForManualSignal(at: date)
            individualRecallFlagUp = false
            generalRecallFlagUp = false
            postponementFlagUp = false
            abandonFlagUp = true
            playHorn(pulses: SignalSequence.abandonRaise.hornPulses)
        }
    }
    private func toggleIndividualRecall(at date: Date) {
        if !individualRecallFlagUp && !canOperateRaceSignals(at: date) { return }
        if !individualRecallFlagUp && (generalRecallFlagUp || postponementFlagUp || abandonFlagUp) { return }
        if individualRecallFlagUp {
            individualRecallFlagUp = false
        } else {
            individualRecallFlagUp = true
            playHorn(pulses: SignalSequence.individualRecallRaise.hornPulses)
        }
    }
    private func toggleGeneralRecall(at date: Date) {
        if !generalRecallFlagUp && !canOperateRaceSignals(at: date) { return }
        if !generalRecallFlagUp && abandonFlagUp { return }
        if generalRecallFlagUp {
            generalRecallFlagUp = false
            playHorn(pulses: SignalSequence.generalRecallLower.hornPulses)
            restartWarningAt = SignalSequence.restartWarningTime(loweredAt: date.timeIntervalSince1970 + clockOffset)
        } else {
            pauseForManualSignal(at: date)
            individualRecallFlagUp = false
            postponementFlagUp = false
            abandonFlagUp = false
            restartWarningAt = 0
            generalRecallFlagUp = true
            playHorn(pulses: SignalSequence.generalRecallRaise.hornPulses)
        }
    }
    private func togglePostponement(at date: Date) {
        if !postponementFlagUp && (generalRecallFlagUp || abandonFlagUp) { return }
        if postponementFlagUp {
            // A second tap cancels a scheduled restart while leaving AP raised.
            if postponementLowerAt > 0 {
                postponementLowerAt = 0
                postponementWarningAt = 0
                restartWarningAt = 0
                return
            }

            let now = date.timeIntervalSince1970 + clockOffset
            var orangeAt = orangeRaiseTime(at: date)
            let raiseOrangeNow = orangeEnabled && orangeAt == nil
            if raiseOrangeNow {
                orangeAt = now
                orangeManualOverride = true
                orangeManualUp = true
                orangeRaisedAt = now
                playHorn(pulses: [0])
            }
            let warningAt = SignalSequence.postponementRestartWarningTime(
                loweredAt: now,
                orangeRaisedAt: orangeAt,
                orangeDisplayedMinutes: orangeDisplayedMinutes,
                orangeEnabled: orangeEnabled
            )
            postponementWarningAt = warningAt
            postponementLowerAt = SignalSequence.postponementLowerTime(warningAt: warningAt)
            restartWarningAt = warningAt
            if postponementLowerAt <= now { processPostponementSchedule(at: now) }
        } else {
            let orangeAt = orangeRaiseTime(at: date)
            pauseForManualSignal(at: date)
            if let orangeAt {
                orangeManualOverride = true
                orangeManualUp = true
                orangeRaisedAt = orangeAt
            }
            individualRecallFlagUp = false
            generalRecallFlagUp = false
            restartWarningAt = 0
            postponementLowerAt = 0
            postponementWarningAt = 0
            postponementFlagUp = true
            playHorn(pulses: SignalSequence.postponementRaise.hornPulses)
        }
    }

    private func processPostponementSchedule(at correctedNow: Double) {
        guard postponementFlagUp, postponementLowerAt > 0, correctedNow >= postponementLowerAt else { return }
        postponementFlagUp = false
        postponementLowerAt = 0
        playHorn(pulses: SignalSequence.postponementLower.hornPulses)
    }
    private func elapsed(at date: Date) -> Double {
        if startAt > 0 { return max(0, date.timeIntervalSince1970 + clockOffset - startAt) }
        return hasStarted ? max(0, pausedSeconds) : 0
    }
    private func canOperateRaceSignals(at date: Date) -> Bool {
        let correctedNow = date.timeIntervalSince1970 + clockOffset
        let sequenceHasStarted = self.hasStarted || startAt > 0 || pausedAt > 0 || restartWarningAt > 0
        let sequenceEvents = restartWarningAt > 0 ? recallRestartEvents : events
        let raceStartOffset = Double(sequenceEvents[SignalSequence.raceStartEventIndex(in: sequenceEvents) ?? 0].secondsAfterStart)
        let sequenceBaseTime = restartWarningAt > 0
            ? restartWarningAt
            : (startAt > 0 ? startAt : (sequenceHasStarted ? pausedAt - pausedSeconds : 0))
        let raceStartPending = sequenceBaseTime > 0 && sequenceBaseTime + raceStartOffset > correctedNow
        return SignalSequence.canOperateRaceSignals(
            hasStarted: sequenceHasStarted,
            firstActionPending: startAt > correctedNow || raceStartPending,
            restartPending: restartWarningAt > correctedNow
        )
    }
    private func running(at date: Date) -> Bool {
        startAt > 0 && elapsed(at: date) < Double(events.last?.secondsAfterStart ?? 1200)
    }
    private func startOrPause(at date: Date) {
        let correctedNow = date.timeIntervalSince1970 + clockOffset
        let retryEnd = restartWarningAt + Double(recallRestartEvents.last?.secondsAfterStart ?? 300)
        if restartWarningAt > 0 && correctedNow >= retryEnd {
            reset()
            freezeConfiguredEvents()
            startAt = SignalSequence.nextMinuteBoundary(at: correctedNow, minimumLeadSeconds: minimumTimeToFirstAction)
            hasStarted = true
            return
        }
        if startAt > correctedNow {
            reset()
            return
        }
        let value = elapsed(at: date)
        if running(at: date) {
            pausedSeconds = value
            pausedAt = correctedNow
            startAt = 0
            hasStarted = true
        } else {
            let completed = hasStarted && value >= Double(events.last?.secondsAfterStart ?? 1200)
            let wasPaused = hasStarted && !completed
            if completed { pausedSeconds = 0 }
            if !wasPaused {
                if let orangeRun = manualOrangeAnchoredRun(at: correctedNow) {
                    startAt = orangeRun.start
                } else {
                    freezeConfiguredEvents()
                    startAt = SignalSequence.nextMinuteBoundary(at: correctedNow, minimumLeadSeconds: minimumTimeToFirstAction)
                    orangeRaisedAt = 0
                }
            } else {
                startAt = pausedSeconds > 0
                    ? correctedNow - pausedSeconds
                    : SignalSequence.nextMinuteBoundary(at: correctedNow, minimumLeadSeconds: minimumTimeToFirstAction)
            }
            if startAt > 0 { pausedAt = 0 }
            if !wasPaused {
                pausedSeconds = 0
                hasStarted = true
            }
        }
    }
    private func reset() {
        startAt = 0
        pausedSeconds = 0
        pausedAt = 0
        hasStarted = false
        runEventsJSON = ""
        orangeRaisedAt = 0
        individualRecallFlagUp = false
        generalRecallFlagUp = false
        postponementFlagUp = false
        abandonFlagUp = false
        restartWarningAt = 0
        postponementLowerAt = 0
        postponementWarningAt = 0
        orangeManualOverride = false
        orangeManualUp = false
        skipFinalEvent = false
    }
    private func elapsedText(_ seconds: Double) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
    private func countdownText(_ seconds: Double) -> String {
        let value = SignalSequence.countdownSeconds(seconds)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    private func raceCountdownText(_ secondsUntilStart: Double) -> String {
        if abs(secondsUntilStart) < 1 {
            return "00:00"
        }
        let seconds = secondsUntilStart > 0
            ? SignalSequence.countdownSeconds(secondsUntilStart)
            : Int(floor(-secondsUntilStart))
        let prefix = secondsUntilStart > 0 ? "−" : "+"
        return prefix + String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func eventTimeText(_ event: SignalSequence.Event, baseTime: Double?, sequenceEvents: [SignalSequence.Event], restart: Bool = false) -> String {
        if let baseTime {
            return SignalSequence.clockText(Date(timeIntervalSince1970: baseTime + Double(event.secondsAfterStart)))
        }
        let zero = restart ? 300 : Double(sequenceEvents[SignalSequence.raceStartEventIndex(in: sequenceEvents) ?? 0].secondsAfterStart)
        let offset = event.secondsAfterStart - Int(zero)
        let time = String(format: "%02d:%02d", abs(offset) / 60, abs(offset) % 60)
        return offset == 0 ? "T+00:00" : (offset < 0 ? "T−" : "T+") + time
    }

    private func activeEventIndex(retryPending: Bool, useRetrySequence: Bool, waitingForFirstSignal: Bool, sequenceEvents: [SignalSequence.Event], sequenceElapsed: Double, spent: Double) -> Int {
        if retryPending { return 0 }
        if waitingForFirstSignal { return -1 }
        if useRetrySequence {
            return sequenceEvents.lastIndex { Double($0.secondsAfterStart) <= sequenceElapsed } ?? 0
        }
        if hasStarted {
            return sequenceEvents.lastIndex { Double($0.secondsAfterStart) <= spent } ?? -1
        }
        return -1
    }

    private func displayedFlags(retryPending: Bool, useRetrySequence: Bool, waitingForFirstSignal: Bool, sequenceEvents: [SignalSequence.Event], sequenceElapsed: Double) -> [SignalSequence.Flag] {
        // During AP/N/first-substitute restart delay and the restarted warning
        // sequence, the orange flag stays down unless the user raises it manually.
        var visible = retryPending
            ? []
            : ((hasStarted || useRetrySequence) && !waitingForFirstSignal
                ? SignalSequence.raisedFlags(events: sequenceEvents, elapsed: sequenceElapsed)
                : [])
        if generalRecallFlagUp {
            visible = [SignalSequence.flag("first-sub")]
        } else if postponementFlagUp {
            visible = [SignalSequence.flag("AP")]
        } else if abandonFlagUp {
            visible = [SignalSequence.flag("N")]
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
        TimelineView(.periodic(from: SignalSequence.nextAlignedTickDate(after: .now, clockOffset: clockOffset), by: 1)) { context in
            let now = context.date
            let spent = elapsed(at: now)
            let correctedNow = now.timeIntervalSince1970 + clockOffset
            let retryTimeline = restartWarningAt > 0
            let retryPending = retryTimeline && restartWarningAt > correctedNow
            let useRetrySequence = retryTimeline && !retryPending
            let waitingForFirstSignal = !retryTimeline && startAt > correctedNow
            let sequenceEvents = retryTimeline ? recallRestartEvents : events
            let sequenceElapsed = retryPending ? 0 : (useRetrySequence ? max(0, correctedNow - restartWarningAt) : spent)
            let active = activeEventIndex(retryPending: retryPending, useRetrySequence: useRetrySequence, waitingForFirstSignal: waitingForFirstSignal, sequenceEvents: sequenceEvents, sequenceElapsed: sequenceElapsed, spent: spent)
            let retrySequenceComplete = useRetrySequence && sequenceElapsed >= Double(sequenceEvents.last?.secondsAfterStart ?? 300)
            let raceStartIndex = SignalSequence.raceStartEventIndex(in: sequenceEvents)
            let raceStartEvent = raceStartIndex.flatMap { sequenceEvents.indices.contains($0) ? sequenceEvents[$0] : nil }
            let raceStartOffset = Double(raceStartEvent?.secondsAfterStart ?? 0)
            let runBaseTime: Double? = retryTimeline ? restartWarningAt : (startAt > 0 ? startAt : (hasStarted ? pausedAt - spent : nil))
            let raceStartTime = raceStartEvent.flatMap { _ in runBaseTime.map { $0 + raceStartOffset } }
            let secondsUntilRaceStart = raceStartTime.map { $0 - correctedNow }
            let raceStartPending = secondsUntilRaceStart.map { $0 > 0 } ?? false
            let initialTarget = raceStartIndex ?? SignalSequence.initialEventIndex(durationMinutes: durationMinutes, profileID: flagProfile)
            let highlighted = retryPending ? active : ((raceStartPending || !hasStarted) ? initialTarget : active)
            let current = sequenceEvents[max(0, active)]
            let isRunning = useRetrySequence
                ? sequenceElapsed < Double(sequenceEvents.last?.secondsAfterStart ?? 540)
                : running(at: now)
            let raceCountdown = secondsUntilRaceStart.map(raceCountdownText)
            let raisedFlags = displayedFlags(retryPending: retryPending, useRetrySequence: useRetrySequence, waitingForFirstSignal: waitingForFirstSignal, sequenceEvents: sequenceEvents, sequenceElapsed: sequenceElapsed)
            let raisedFlagIDs = Set(raisedFlags.map(\.id))
            let highlightedEventID = sequenceEvents.indices.contains(highlighted) ? sequenceEvents[highlighted].id : nil
            let raceSignalControlsEnabled = SignalSequence.canOperateRaceSignals(
                hasStarted: hasStarted,
                firstActionPending: waitingForFirstSignal || raceStartPending,
                restartPending: retryPending
            )
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
                    }
                }
                MastBoard(flags: raisedFlags, compact: compact)
                    .frame(height: compact ? 60 : 112)
                HStack {
                    Text(raceStartEvent.map { "\($0.flags.first?.name ?? "") スタート時刻" } ?? (retryPending ? "次の予告信号まで" : (waitingForFirstSignal ? "クラス旗掲揚待ち" : (useRetrySequence ? "再予告信号時刻" : "スタート時刻")))).foregroundStyle(.black)
                    Spacer()
                    Text(raceStartTime.map { SignalSequence.clockText(Date(timeIntervalSince1970: $0)) } ?? "TBD")
                        .font(.system(.body, design: .monospaced)).foregroundStyle(.black)
                }
                .font(.system(size: compact ? 12 : 16, weight: .medium))
                HStack(spacing: 8) {
                    Text(raceStartPending && raceStartEvent != nil ? "↓" : (waitingForFirstSignal ? "◷" : (current.raised ? "↑" : "↓"))).font(.title3.bold()).foregroundStyle(.black)
                    Text(raceStartPending && raceStartEvent != nil ? "スタートまで" : (waitingForFirstSignal ? "クラス旗掲揚待ち · " + current.title : current.title)).font(.caption).lineLimit(1)
                    Spacer()
                    Text((raceStartTime != nil || restartWarningAt > 0) ? (raceCountdown ?? "--:--") : "--:--")
                        .font(.system(size: compact ? 28 : 38, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                    Circle().fill(Color.gray.opacity(0.65)).frame(width: compact ? 28 : 42, height: compact ? 28 : 42)
                        .overlay(Image(systemName: "timer").foregroundStyle(.white))
                }
                .foregroundStyle(.black)
                VStack(spacing: 1) {
                    ForEach(sequenceEvents.filter { !($0.raised && $0.flags.contains(where: { $0.id == "orange" }) && raisedFlagIDs.contains("orange")) }) { event in
                        let isActive = event.id == highlightedEventID
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
                            Text(eventTimeText(event, baseTime: runBaseTime, sequenceEvents: sequenceEvents, restart: retryTimeline))
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
                    if hasStarted || restartWarningAt > 0 {
                        Button("中断…") { showInterruptOptions = true }
                            .foregroundStyle(.gray)
                        Button("停止", role: .destructive) { reset() }
                    }
                    let canStartSequence = !retryPending && !(useRetrySequence && !retrySequenceComplete) && !generalRecallFlagUp && !postponementFlagUp
                    if canStartSequence {
                        Button(waitingForFirstSignal ? "クラス旗待ち（取消）" : (retrySequenceComplete ? "開始" : (isRunning ? "一時停止" : (hasStarted && spent < Double(events.last?.secondsAfterStart ?? 1200) ? "再開" : "開始")))) { startOrPause(at: now) }
                            .foregroundStyle(.blue).fontWeight(.semibold)
                    }
                    #if os(iOS)
                    Button { scheduledDate = SignalSequence.defaultScheduledDate(); scheduleValidationMessage = ""; showSchedule = true } label: { Image(systemName: "clock").foregroundStyle(.blue) }
                    #else
                    Button { reset() } label: { Image(systemName: "stopwatch").foregroundStyle(.blue) }
                    #endif
                }
                .font(.system(size: compact ? 12 : 16))
                HStack(spacing: compact ? 4 : 10) {
                    Button(raisedFlags.contains(where: { $0.id == "orange" }) ? "橙旗 降下" : "橙旗 掲揚") {
                        let raise = !raisedFlags.contains(where: { $0.id == "orange" })
                        orangeManualUp = raise
                        orangeManualOverride = true
                        orangeRaisedAt = raise ? now.timeIntervalSince1970 + clockOffset : 0
                        if raise { playHorn(pulses: [0]) }
                    }
                    if individualRecallFlagUp || (raceSignalControlsEnabled && ["P", "I"].contains(prepFlagID) && !generalRecallFlagUp && !postponementFlagUp && !abandonFlagUp) {
                        Button(individualRecallFlagUp ? "X旗 降下" : "個別リコール X旗") { toggleIndividualRecall(at: now) }
                    }
                    if generalRecallFlagUp || (raceSignalControlsEnabled && !postponementFlagUp && !abandonFlagUp) {
                        Button(generalRecallFlagUp ? "第一代表旗 降下" : "ゼネラルリコール") { toggleGeneralRecall(at: now) }
                    }
                    if postponementFlagUp || (!generalRecallFlagUp && !abandonFlagUp) {
                        Button(postponementFlagUp ? (postponementLowerAt > 0 ? "AP降下予約中（取消）" : "AP降下手順を開始") : "AP 掲揚") { togglePostponement(at: now) }
                    }
                    if abandonFlagUp || raceSignalControlsEnabled {
                        Button(abandonFlagUp ? "N旗 降下" : "すべて中止 N旗") { toggleAbandon(at: now) }
                    }
                }
                .font(.system(size: compact ? 9 : 12, weight: .semibold))
                .buttonStyle(.bordered)
                #if os(iOS)
                if !compact {
                    VStack(spacing: 4) {
                        DisclosureGroup("ホーン設定") {
                            Toggle("仮想ホーンを有効にする", isOn: $hornEnabled)
                            signalSlider("音量", value: $hornVolume, range: 0...1, step: 0.05, format: "%.0f%%", scale: 100)
                            signalSlider("短音", value: $shortHornSeconds, range: 0.1...10.0, step: 0.1, format: "%.1f秒", scale: 1)
                            signalSlider("長音", value: $hornSeconds, range: 0.1...10.0, step: 0.1, format: "%.1f秒", scale: 1)
                            signalSlider("連発間隔", value: $hornGapSeconds, range: 0.1...3.0, step: 0.1, format: "%.1f秒", scale: 1)
                        }
                        .font(.caption)
                    }
                }
                #endif
            }
            .padding(compact ? 4 : 8)
            .background(Color.white)
            .foregroundStyle(.black)
            #if os(iOS)
            .sheet(isPresented: $showSettings) { SignalSettingsView() }
            .sheet(isPresented: $showSchedule) {
                NavigationStack {
                    Form {
                        Picker("設定する時刻", selection: $scheduleMode) {
                            Text("シーケンス開始").tag(0)
                            Text("スタート信号").tag(1)
                        }.pickerStyle(.segmented)
                            .onChange(of: scheduleMode) { _, _ in scheduleValidationMessage = "" }
                        DatePicker(scheduleMode == 0 ? "シーケンス開始時刻" : "スタート時刻", selection: $scheduledDate, displayedComponents: [.date, .hourAndMinute])
                            .onChange(of: scheduledDate) { _, _ in scheduleValidationMessage = "" }
                        Text("時刻は分単位で予約し、秒は00秒に揃えます。スタート時刻を選ぶと、選択中のシーケンスに必要な先行時間を差し引きます。").font(.footnote).foregroundStyle(.secondary)
                        if !scheduleValidationMessage.isEmpty {
                            Text(scheduleValidationMessage).font(.footnote).foregroundStyle(.red)
                        }
                    }
                    .navigationTitle("開始時刻を予約")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { showSchedule = false } }
                        ToolbarItem(placement: .confirmationAction) { Button("予約") { scheduleSignalStart() } }
                    }
                }.preferredColorScheme(.dark)
            }
            .confirmationDialog("中断", isPresented: $showInterruptOptions, titleVisibility: .visible) {
                Button("停止（待機状態へ戻る）", role: .destructive) { reset() }
                Button("延期（AP旗）") { togglePostponement(at: Date()) }
                Button("最後のスタートを再実施（N旗）") { toggleAbandon(at: Date()) }
                Button("中止したスタートを再実施（N旗）") { toggleAbandon(at: Date()) }
                Button("レースを続行") { if !isRunning && !waitingForFirstSignal { startOrPause(at: Date()) } }
                Button("キャンセル", role: .cancel) {}
            }
            #endif
            .onChange(of: now) { _, current in
                processPostponementSchedule(at: current.timeIntervalSince1970 + clockOffset)
            }
            .onAppear {
                processPostponementSchedule(at: Date().timeIntervalSince1970 + clockOffset)
                if !hornTimingPresetMigrated {
                    if abs(hornSeconds - 0.7) < 0.001 { hornSeconds = 5.1 }
                    if abs(shortHornSeconds - 0.22) < 0.001 { shortHornSeconds = 3.1 }
                    if abs(hornGapSeconds - 0.18) < 0.001 { hornGapSeconds = 1.1 }
                    hornTimingPresetMigrated = true
                }
                if sequenceTimingVersion < 2 {
                    flagProfile = "standard-start"
                    sequenceTimingVersion = 2
                }
                if flagProfile == "class-p" || flagProfile == "class-i" {
                    prepFlagID = flagProfile == "class-p" ? "P" : "I"
                    flagProfile = "standard-start"
                }
                if !hasStarted && !isRunning { flagProfile = "standard-start" }
            }
            .onChange(of: useRetrySequence) { oldValue, newValue in
                guard !oldValue, newValue else { return }
                playHorn(pulses: sequenceEvents.first(where: { !$0.hornPulses.isEmpty })?.hornPulses ?? [])
            }
            .onChange(of: active) { oldValue, newValue in
                guard newValue > oldValue else { return }
                let crossed = (oldValue + 1)...newValue
                if crossed.contains(where: { sequenceEvents.indices.contains($0) && sequenceEvents[$0].flags.contains(where: { $0.id == "orange" }) }) {
                    orangeManualOverride = false
                    orangeManualUp = false
                    orangeRaisedAt = 0
                }
                guard isRunning else { return }
                for index in crossed where sequenceEvents.indices.contains(index) {
                    playHorn(pulses: sequenceEvents[index].hornPulses)
                }
            }
        }
    }

    private func scheduleSignalStart() {
        let scheduledStart = SignalSequence.scheduledSequenceStart(
            selectedDate: scheduledDate,
            clockOffset: clockOffset,
            scheduleAtRaceStart: scheduleMode == 1,
            profileID: flagProfile
        )
        guard scheduledStart.timeIntervalSince1970 > Date().timeIntervalSince1970 + clockOffset else {
            scheduleValidationMessage = "選択した時刻は過ぎているか、シーケンス開始に必要な先行時間がありません。未来の時刻を選んでください。"
            return
        }
        skipFinalEvent = false
        freezeConfiguredEvents()
        startAt = scheduledStart.timeIntervalSince1970
        pausedSeconds = 0
        pausedAt = 0
        hasStarted = true
        restartWarningAt = 0
        individualRecallFlagUp = false
        generalRecallFlagUp = false
        postponementFlagUp = false
        abandonFlagUp = false
        orangeManualOverride = false
        orangeManualUp = false
        showSchedule = false
    }

    private func signalSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, format: String, scale: Double) -> some View {
        HStack(spacing: 6) {
            Text(title).frame(width: 72, alignment: .leading)
            Slider(value: value, in: range, step: step)
            Text(String(format: format, value.wrappedValue * scale))
                .font(.system(.caption2, design: .monospaced)).frame(width: 54, alignment: .trailing)
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
                let t = Double(index) / rate
                let duration = Double(count) / rate
                let envelope = min(min(1, t / 0.08), min(1, (duration - t) / 0.18))
                // Two detuned horn tones with harmonics create the brassy air-horn timbre.
                let lower = 370.0 - 9.0 * (t / duration)
                let upper = 440.0 - 11.0 * (t / duration)
                let horn = 0.50 * sin(2 * Double.pi * lower * t)
                    + 0.42 * sin(2 * Double.pi * upper * t)
                    + 0.22 * sin(2 * Double.pi * lower * 2 * t)
                    + 0.18 * sin(2 * Double.pi * upper * 2 * t)
                    + 0.10 * sin(2 * Double.pi * lower * 3 * t)
                    + 0.08 * sin(2 * Double.pi * upper * 3 * t)
                var sample = Int16(horn * envelope * hornVolume * 0.62 * Double(Int16.max)).littleEndian
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

    private func assignedPole(for flagIndex: Int) -> Int {
        let flag = flags[flagIndex]
        let ordinal = flags.prefix(flagIndex).filter { $0.id != "orange" }.count
        return SignalSequence.mastPoleIndex(flagID: flag.id, otherFlagOrdinal: ordinal)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(poleIndex == 1 ? Color.orange : Color.gray.opacity(0.85))
                .frame(width: 2, height: height * 0.94)
            ForEach(flags.indices, id: \.self) { flagIndex in
                if assignedPole(for: flagIndex) == poleIndex {
                    let stack = flags.indices.filter { $0 < flagIndex && assignedPole(for: $0) == poleIndex }.count
                    SignalFlagView(flag: flags[flagIndex])
                        .frame(width: 25, height: 18)
                        .offset(x: 2, y: 8 + CGFloat(stack) * 13)
                        .animation(.easeInOut(duration: 0.45), value: flags.map(\.id))
                }
            }
        }
        .frame(width: 28, height: height, alignment: .topLeading)
    }
}

private struct SignalFlagView: View {
    let flag: SignalSequence.Flag
    @AppStorage("signalClassLogoTextColor") private var logoColorHex = "#111111"
    @AppStorage("signalClassLogoBackgroundColor") private var logoBackgroundHex = "#FFFFFF"

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
                    SignalClassLogoMark(name: flag.id.replacingOccurrences(of: "class-", with: ""),
                                        color: signalDisplayColor(logoColorHex),
                                        backgroundColor: signalDisplayColor(logoBackgroundHex))
                case "internationalFlag":
                    SignalInternationalFlagArtwork(name: flag.artworkName ?? flag.name)
                default:
                    color(0)
                }
                if !flag.symbol.isEmpty && flag.style != "classLogo" && flag.style != "internationalFlag" {
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


private func signalDisplayColor(_ hex: String) -> Color {
        let digits = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let value = UInt64(digits, radix: 16) ?? 0xFFFFFF
        return Color(.sRGB, red: Double((value >> 16) & 0xFF) / 255,
                     green: Double((value >> 8) & 0xFF) / 255,
                     blue: Double(value & 0xFF) / 255, opacity: 1)
}

