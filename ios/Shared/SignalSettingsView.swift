import SwiftUI

#if os(iOS)
import AudioToolbox
import AVFoundation

private struct SignalStartAction: Identifiable, Codable, Hashable {
    var id = UUID()
    var flagID = "class-4"
    var minute = 5
    var second = 0
    var raised = true
    var enabled = true
    var horn = "short"

    var title: String {
        "\(SignalSequence.flag(flagID).name)を\(raised ? "掲揚" : "降下")"
    }
}

private struct SignalFleetPreset: Identifiable, Codable, Hashable {
    var id = UUID()
    var name = "OP Au Bp"
    var sequence = "standard-start"
    var startRule = "P"
    var classFlagID = "class-4"
    var prepFlagID = "P"
    var raceDelayEnabled = false
    var raceDelayMinutes = 0
    var timeLimitEnabled = false
    var raceLimitMinutes = 50
    var finishWindowMinutes = 20
    var rule42Override = false
    var orangeEnabled = true
    var orangeDisplayedMinutes = 5
    var orangeRemovedMinutes = 4
    var starts: [SignalStartAction] = [
        SignalStartAction(flagID: "class-4", minute: 5, raised: true, horn: "short")
    ]

    static let starter = SignalFleetPreset()
    static func load(from value: String) -> [SignalFleetPreset] {
        guard let data = value.data(using: .utf8),
              let saved = try? JSONDecoder().decode([SignalFleetPreset].self, from: data),
              !saved.isEmpty else { return [.starter] }
        return saved.map { preset in
            var migrated = preset
            migrated.sequence = "standard-start"
            migrated.prepFlagID = SignalSequence.preparationFlagID(forStartRule: migrated.startRule)
            return migrated
        }
    }
    static func encode(_ value: [SignalFleetPreset]) -> String {
        guard let data = try? JSONEncoder().encode(value) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}

private struct SignalCustomFlag: Identifiable, Codable, Hashable {
    var id = UUID()
    var name = ""
    var style = "text"
    var layout = "solid"
    var flagColor = "#FFFFFF"
    var text = ""
    var textColor = "#111111"
    var logoID = "class-4"
    var internationalFlag = "Alpha"
}

private struct SignalColorChoice: Identifiable {
    let name: String
    let color: Color
    let hex: String
    var id: String { name }
}

private struct SignalFlagChoice: Identifiable, Hashable {
    let id: String
    let name: String
    let category: String
    var symbol: String { id.hasPrefix("class-") ? String(id.dropFirst(6)) : name }
}

private struct SignalFlagSwatch: View {
    let flagID: String
    private var flag: SignalSequence.Flag { SignalSequence.flag(flagID) }
    private var fill: Color {
        let value = flag.colors.first ?? 0xFFFFFF
        return Color(red: Double((value >> 16) & 0xFF) / 255,
                     green: Double((value >> 8) & 0xFF) / 255,
                     blue: Double(value & 0xFF) / 255)
    }
    var body: some View {
        Group {
            if flag.style == "internationalFlag" {
                SignalInternationalFlagArtwork(name: flag.artworkName ?? flag.name)
            } else if flagID.hasPrefix("class-") {
                SignalClassLogoMark(name: String(flagID.dropFirst(6)))
            } else {
                ZStack {
                    fill
                    Text(flag.symbol.isEmpty ? flag.name : flag.symbol)
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(fill == .white ? .black : .white)
                        .minimumScaleFactor(0.5)
                }
            }
        }
        .frame(width: 44, height: 30)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

struct SignalSettingsView: View {
    @AppStorage("signalMinimumTimeToFirstAction") private var minimumTime = 15
    @AppStorage("signalVoiceName") private var voiceName = "Kyoko (Enhanced)"
    @AppStorage("signalRadioFriendly") private var radioFriendly = true
    @AppStorage("signalClockOffset") private var clockOffset = 0.0
    @AppStorage("signalClockAlignmentMode") private var clockAlignmentMode = "manual"
    @AppStorage("signalExternalDisplayEnabled") private var externalDisplay = true
    @AppStorage("signalRemoteFlagsEnabled") private var remoteFlags = false
    @AppStorage("signalBuoyZoneLinked") private var buoyZoneLinked = false
    @AppStorage("signalLogEnabled") private var logEnabled = true
    @State private var timeSyncMessage = ""
    @State private var isSyncingTime = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Mode", value: "Fleet")
                }
                Section("General Settings") {
                    Stepper(value: $minimumTime, in: 0...120, step: 5) {
                        VStack(alignment: .leading) {
                            LabeledContent("次の分00秒までの最短時間", value: "\(minimumTime)秒")
                            Text("開始ボタンから実時間の次の分00秒までに確保する最短間隔です。各信号はシーケンスのn分00秒で動作します。AP・N旗は時刻を固定せず手動で掲揚します。").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Picker("Voice", selection: $voiceName) {
                        Text("Kyoko (Enhanced)").tag("Kyoko (Enhanced)")
                        Text("Siri Japanese").tag("Siri Japanese")
                        Text("端末の標準音声").tag("端末の標準音声")
                    }
                    NavigationLink("Notifications") { SignalNotificationsView() }
                    Picker("時間合わせ", selection: $clockAlignmentMode) {
                        Text("端末時刻で0秒合わせ").tag("manual")
                        Text("ntp.nict.jpと同期").tag("nict")
                    }
                    .onChange(of: clockAlignmentMode) { _, mode in
                        if mode == "manual" {
                            clockOffset = 0
                            timeSyncMessage = "端末の実時刻を基準にします"
                        } else {
                            Task { await syncTime() }
                        }
                    }
                    if clockAlignmentMode == "nict" {
                        Button {
                            Task { await syncTime() }
                        } label: {
                            HStack {
                                Text(timeSyncMessage.isEmpty
                                     ? (clockOffset == 0 ? "未同期" : "同期済み（差 \(String(format: "%+.3f", clockOffset)) 秒）")
                                     : timeSyncMessage)
                                Spacer()
                                if isSyncingTime { ProgressView() } else { Text("今すぐ同期").foregroundStyle(.blue) }
                            }
                        }.disabled(isSyncingTime)
                    } else {
                        Text("各信号は端末の実時刻のn分00秒を基準に動作します。開始時は設定した最短時間を確保して、次の分00秒に合わせます。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    NavigationLink("Horn") { SignalHornSettingsView() }
                    Toggle("Remote Flags", isOn: $remoteFlags)
                    Toggle("BuoyZoneと連携", isOn: $buoyZoneLinked)
                    Toggle("External Display", isOn: $externalDisplay)
                    NavigationLink("Log") { SignalLogSettingsView(enabled: $logEnabled) }
                }
                Section("Fleet Start Sequences") {
                    NavigationLink("フリート手順を管理") { SignalFleetSequencesView() }
                }
                Section("旗の設定") {
                    NavigationLink("クラス旗を編集") { SignalClassFlagSettingsView() }
                    NavigationLink("国際信号旗") { SignalInternationalFlagGallery() }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") { dismiss() }.tint(.orange)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    @MainActor
    private func syncTime() async {
        isSyncingTime = true
        defer { isSyncingTime = false }
        do {
            let serverTime = try await NICTClock.query()
            clockOffset = serverTime.timeIntervalSinceNow
            timeSyncMessage = "同期済み（差 \(String(format: "%+.3f", clockOffset)) 秒）"
        } catch {
            clockOffset = 0
            timeSyncMessage = "同期失敗・端末時刻を使用中"
        }
    }
}

private struct SignalLogSettingsView: View {
    @Binding var enabled: Bool
    @AppStorage("signalLogRetentionDays") private var retentionDays = 14
    var body: some View {
        Form {
            Toggle("ログを保存", isOn: $enabled)
            Stepper("保存期間：\(retentionDays)日", value: $retentionDays, in: 1...90)
            Text("記録した信号、操作、同期状態を端末内に保存します。")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .navigationTitle("Log")
        .preferredColorScheme(.dark)
    }
}

private struct SignalFleetSequencesView: View {
    @AppStorage("signalFleetPresetsJSON") private var savedJSON = ""
    @State private var presets: [SignalFleetPreset] = [.starter]
    @State private var loaded = false

    var body: some View {
        List {
            ForEach($presets) { $preset in
                NavigationLink {
                    SignalFleetPresetEditor(preset: $preset)
                } label: {
                    HStack {
                        Image(systemName: "circle")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading) {
                            Text(preset.name)
                            Text("\(preset.starts.count) signal actions")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onDelete { presets.remove(atOffsets: $0); save() }
            Button {
                var next = SignalFleetPreset()
                next.name = "Fleet Start \(presets.count + 1)"
                presets.append(next)
                save()
            } label: {
                Label("フリート手順を追加", systemImage: "plus.circle.fill")
            }
        }
        .navigationTitle("Fleet Start Sequences")
        .toolbar { EditButton() }
        .onAppear {
            guard !loaded else { return }
            presets = SignalFleetPreset.load(from: savedJSON)
            loaded = true
        }
        .onChange(of: presets) { _, _ in save() }
        .preferredColorScheme(.dark)
    }

    private func save() { savedJSON = SignalFleetPreset.encode(presets) }
}

private struct SignalFleetPresetEditor: View {
    @Binding var preset: SignalFleetPreset
    @AppStorage("signalFlagProfile") private var activeSequence = "standard-start"
    @AppStorage("signalCustomClassFlag") private var activeClassFlag = "class-4"
    @AppStorage("signalCustomPrepFlag") private var activePrepFlag = "P"
    @AppStorage("signalOrangeEnabled") private var activeOrangeEnabled = true
    @AppStorage("signalOrangeDisplayedMinutes") private var activeOrangeDisplayed = 5
    @AppStorage("signalOrangeRemovedAfterMinutes") private var activeOrangeRemoval = 4
    @AppStorage("signalActiveStartActionsJSON") private var activeStartActionsJSON = "[]"
    @AppStorage("signalRaceDelayEnabled") private var activeRaceDelayEnabled = false
    @AppStorage("signalRaceDelayMinutes") private var activeRaceDelayMinutes = 0
    @Environment(\.dismiss) private var dismiss
    @State private var showingAddFlag = false

    private let rules = ["P", "I", "U", "Z", "Black", "Default"]

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $preset.name)
            }
            Section("Defaults") {
                LabeledContent("Start Sequence", value: "Rule 26 · 5 min")
                Picker("スタートルール／準備信号", selection: $preset.startRule) {
                    ForEach(rules, id: \.self) { Text($0).tag($0) }
                }
                NavigationLink {
                    SignalClassPicker(selection: $preset.classFlagID)
                } label: {
                    HStack {
                        Text("Classes")
                        Spacer()
                        Text(SignalSequence.flag(preset.classFlagID).name).foregroundStyle(.secondary)
                    }
                }
                Stepper("Time between races：\(preset.raceDelayMinutes)分", value: $preset.raceDelayMinutes, in: 0...60)
            }
            Section("Time Limits") {
                Toggle("Enable", isOn: $preset.timeLimitEnabled)
                Stepper("Race Limit：\(preset.raceLimitMinutes):00", value: $preset.raceLimitMinutes, in: 1...300)
                    .disabled(!preset.timeLimitEnabled)
                Stepper("Finish Window：\(preset.finishWindowMinutes):00", value: $preset.finishWindowMinutes, in: 1...120)
                    .disabled(!preset.timeLimitEnabled)
            }
            Section("Rule 42 Override") { Toggle("Enable", isOn: $preset.rule42Override) }
            Section("橙旗") {
                Toggle("シーケンスに橙旗を含める", isOn: $preset.orangeEnabled)
                Stepper("橙旗掲揚から予告信号まで：\(preset.orangeDisplayedMinutes)分", value: $preset.orangeDisplayedMinutes, in: 0...30)
                    .disabled(!preset.orangeEnabled)
                Stepper("スタート後、橙旗を降下するまで：\(preset.orangeRemovedMinutes)分", value: $preset.orangeRemovedMinutes, in: 0...30)
                    .disabled(!preset.orangeEnabled)
                Text("シーケンス前は橙旗を降下します。手動で掲揚した場合はその時刻を記録し、指定間隔が経過した時点でクラス旗の手順に進みます。降下も手動で操作できます。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Starts") {
                ForEach($preset.starts) { $start in
                    HStack(spacing: 8) {
                        Button(role: .destructive) {
                            preset.starts.removeAll { $0.id == start.id }
                        } label: { Image(systemName: "minus.circle.fill") }
                        SignalFlagSwatch(flagID: start.flagID)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(start.title)
                            HStack(spacing: 4) {
                                TextField("分", value: $start.minute, format: .number).keyboardType(.numberPad).frame(width: 36)
                                Text(":")
                                TextField("秒", value: $start.second, format: .number).keyboardType(.numberPad).frame(width: 36)
                            }.font(.caption).monospacedDigit()
                        }
                        Spacer()
                        Toggle("有効", isOn: $start.enabled).labelsHidden()
                        Menu {
                            Button("掲揚") { start.raised = true }
                            Button("降下") { start.raised = false }
                            Divider()
                            Button("短音") { start.horn = "short" }
                            Button("長音") { start.horn = "long" }
                            Button("音なし") { start.horn = "none" }
                        } label: { Image(systemName: "line.3.horizontal") }
                    }
                }
                Button { showingAddFlag = true } label: {
                    Label("Add Start…", systemImage: "plus.circle.fill")
                }
            }
        }
        .onChange(of: preset.startRule) { _, value in
            preset.prepFlagID = SignalSequence.preparationFlagID(forStartRule: value)
        }
        .navigationTitle("Fleet Start")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    activeSequence = "standard-start"
                    activeClassFlag = preset.classFlagID
                    activePrepFlag = SignalSequence.preparationFlagID(forStartRule: preset.startRule)
                    activeOrangeEnabled = preset.orangeEnabled
                    activeOrangeDisplayed = preset.orangeDisplayedMinutes
                    activeOrangeRemoval = preset.orangeRemovedMinutes
                    activeRaceDelayEnabled = preset.raceDelayMinutes > 0
                    activeRaceDelayMinutes = preset.raceDelayMinutes
                    // A fleet preset has one selected class flag. Apply it to
                    // every class-flag action, including presets previously
                    // saved with a different class, so subsequent changes do
                    // not leave stale logo IDs in the live timeline.
                    var runtimeStarts = preset.starts
                    for index in runtimeStarts.indices where runtimeStarts[index].flagID.hasPrefix("class-") {
                        runtimeStarts[index].flagID = preset.classFlagID
                    }
                    if let encoded = try? JSONEncoder().encode(runtimeStarts) {
                        activeStartActionsJSON = String(data: encoded, encoding: .utf8) ?? "[]"
                    }
                    dismiss()
                }.tint(.orange)
            }
        }
        .sheet(isPresented: $showingAddFlag) {
            NavigationStack {
                SignalClassPicker(selection: Binding(
                    get: { preset.classFlagID },
                    set: { value in
                        preset.starts.append(SignalStartAction(flagID: value, minute: 5, raised: true, horn: "short"))
                    }
                ))
                .navigationTitle("Classes")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完了") { showingAddFlag = false } } }
            }
        }
        .preferredColorScheme(.dark)
    }

}

struct SignalClassPicker: View {
    @Binding var selection: String
    private let categories = ["クラスロゴ"]
    private let classFlags: [SignalFlagChoice] = SignalClassLogoAssets.availableClassNames.map {
        SignalFlagChoice(id: "class-\($0)", name: $0, category: "クラスロゴ")
    }

    var body: some View {
        List {
            ForEach(categories, id: \.self) { category in
                Section(category) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 12)], spacing: 12) {
                        ForEach(classFlags.filter { $0.category == category }) { flag in
                            Button { selection = flag.id } label: {
                                VStack(spacing: 7) {
                                    SignalClassLogoMark(name: flag.name)
                                        .overlay(selection == flag.id ? RoundedRectangle(cornerRadius: 5).stroke(Color.orange, lineWidth: 3) : nil)
                                    Text(flag.name).font(.caption).lineLimit(2).multilineTextAlignment(.center)
                                }
                            }.buttonStyle(.plain)
                        }
                    }.padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Classes")
        .preferredColorScheme(.dark)
    }
}

private struct SignalClassFlagSettingsView: View {
    @AppStorage("signalUserFlagsJSON") private var savedJSON = "[]"
    @State private var flags: [SignalCustomFlag] = []
    @State private var loaded = false

    var body: some View {
        List {
            ForEach($flags) { $flag in
                NavigationLink {
                    SignalCustomFlagEditor(flag: $flag)
                } label: {
                    HStack {
                        SignalFlagPreview(flag: flag).frame(width: 44, height: 30)
                        Text(flag.name.isEmpty ? "Class Flag" : flag.name)
                    }
                }
            }.onDelete { flags.remove(atOffsets: $0); save() }
            Button {
                flags.append(SignalCustomFlag())
            } label: { Label("クラス旗を追加", systemImage: "plus.circle.fill") }
            NavigationLink("国際信号旗一覧") { SignalInternationalFlagGallery() }
        }
        .navigationTitle("Class Flags")
        .toolbar { EditButton() }
        .onAppear {
            guard !loaded else { return }
            if let data = savedJSON.data(using: .utf8),
               let value = try? JSONDecoder().decode([SignalCustomFlag].self, from: data) { flags = value }
            loaded = true
        }
        .onChange(of: flags) { _, _ in save() }
        .preferredColorScheme(.dark)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(flags) else { return }
        savedJSON = String(data: data, encoding: .utf8) ?? "[]"
    }
}

private struct SignalCustomFlagEditor: View {
    @Binding var flag: SignalCustomFlag
    @AppStorage("signalCustomClassFlag") private var activeClassFlag = "class-4"
    @AppStorage("signalActiveStartActionsJSON") private var activeStartActionsJSON = "[]"
    @AppStorage("signalClassLogoTextColor") private var activeLogoColor = "#111111"
    @AppStorage("signalClassLogoBackgroundColor") private var activeLogoBackground = "#FFFFFF"
    @Environment(\.dismiss) private var dismiss
    private let layouts = ["solid", "horizontal", "vertical", "diagonal", "reverseDiagonal"]
    private let colors: [SignalColorChoice] = [
        SignalColorChoice(name: "White", color: .white, hex: "#FFFFFF"),
        SignalColorChoice(name: "Black", color: .black, hex: "#111111"),
        SignalColorChoice(name: "Red", color: .red, hex: "#E32636"),
        SignalColorChoice(name: "Yellow", color: .yellow, hex: "#F5D328"),
        SignalColorChoice(name: "Blue", color: .blue, hex: "#1769FF"),
        SignalColorChoice(name: "Green", color: .green, hex: "#00B83F"),
        SignalColorChoice(name: "Orange", color: .orange, hex: "#F58A00"),
        SignalColorChoice(name: "Purple", color: .purple, hex: "#7A35A8")
    ]

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $flag.name)
                Picker("表示形式", selection: $flag.style) {
                    Text("Logo").tag("logo")
                    Text("Text").tag("text")
                    Text("International Flag").tag("international")
                }.pickerStyle(.segmented)
            }
            Section("Background Layout") {
                Picker("Layout", selection: $flag.layout) {
                    Text("全面").tag("solid")
                    Text("上下").tag("horizontal")
                    Text("左右").tag("vertical")
                    Text("斜め").tag("diagonal")
                    Text("逆斜め").tag("reverseDiagonal")
                }.pickerStyle(.segmented)
            }
            Section("Flag Color") {
                colorPicker("旗の色", selection: $flag.flagColor)
            }
            if flag.style == "text" {
                Section("Text") {
                    TextField("表示する文字", text: $flag.text)
                    colorPicker("文字色", selection: $flag.textColor)
                }
            } else if flag.style == "international" {
                Section("International Flag") {
                    NavigationLink("信号旗を選択") { SignalInternationalFlagGallery(selection: $flag.internationalFlag) }
                    Text("国際信号旗の一覧から表示する旗を選びます。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                Section("Logo") {
                    NavigationLink("クラスのロゴを選択") { SignalClassPicker(selection: $flag.logoID) }
                    colorPicker("ロゴ色", selection: $flag.textColor)
                }
            }
            Section("Preview") {
                SignalFlagPreview(flag: flag).frame(height: 110).frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(flag.name.isEmpty ? "Class Flag" : flag.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("この旗を使用") {
                    switch flag.style {
                    case "logo":
                        activeClassFlag = flag.logoID
                        activeLogoColor = flag.textColor
                        activeLogoBackground = flag.flagColor
                    case "international": activeClassFlag = "intl:\(flag.internationalFlag)"
                    default: activeClassFlag = "text:\(flag.text.isEmpty ? flag.name : flag.text)"
                    }
                    // The live sequence uses its saved action rows in
                    // preference to the standalone class flag setting. Keep
                    // those rows in sync when this editor activates a logo.
                    if activeClassFlag.hasPrefix("class-"),
                       let data = activeStartActionsJSON.data(using: .utf8),
                       var actions = try? JSONDecoder().decode([SignalStartAction].self, from: data) {
                        for index in actions.indices where actions[index].flagID.hasPrefix("class-") {
                            actions[index].flagID = activeClassFlag
                        }
                        if let updated = try? JSONEncoder().encode(actions) {
                            activeStartActionsJSON = String(data: updated, encoding: .utf8) ?? "[]"
                        }
                    }
                    dismiss()
                }.tint(.orange)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func colorPicker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            ForEach(colors) { item in
                HStack { Circle().fill(item.color).frame(width: 20, height: 20); Text(item.name) }.tag(item.hex)
            }
        }.pickerStyle(.menu)
    }
}

private struct SignalFlagPreview: View {
    let flag: SignalCustomFlag
    var body: some View {
        GeometryReader { geo in
            ZStack {
                if flag.style == "international" {
                    SignalInternationalFlagArtwork(name: flag.internationalFlag)
                } else {
                    Color(hex: flag.flagColor)
                    if flag.layout == "horizontal" {
                        VStack(spacing: 0) { Color(hex: flag.flagColor); Color.white }
                    } else if flag.layout == "vertical" {
                        HStack(spacing: 0) { Color(hex: flag.flagColor); Color.white }
                    } else if flag.layout == "diagonal" || flag.layout == "reverseDiagonal" {
                        Canvas { context, size in
                            let path = Path { p in
                                p.move(to: .zero); p.addLine(to: CGPoint(x: size.width, y: 0))
                                p.addLine(to: CGPoint(x: size.width, y: size.height)); p.closeSubpath()
                            }
                            context.fill(path, with: .color(.white))
                        }
                    }
                    if flag.style == "text" {
                        Text(flag.text).font(.system(size: geo.size.height * 0.55, weight: .bold))
                            .foregroundStyle(Color(hex: flag.textColor))
                    } else {
                        SignalClassLogoMark(name: flag.text.isEmpty ? flag.logoID.replacingOccurrences(of: "class-", with: "") : flag.text,
                                            color: Color(hex: flag.textColor),
                                            backgroundColor: Color(hex: flag.flagColor))
                    }
                }
            }.frame(width: geo.size.width, height: geo.size.height)
        }.clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

private struct SignalInternationalFlagGallery: View {
    @AppStorage("signalSelectedInternationalFlag") private var storedSelection = "Alpha"
    private let selection: Binding<String>?
    init(selection: Binding<String>? = nil) { self.selection = selection }
    private var selectedFlag: Binding<String> { selection ?? $storedSelection }
    private let flags = ["Alpha","Bravo","Charlie","Delta","Echo","Foxtrot","Golf","Hotel","India","Juliett","Kilo","Lima","Mike","November","Oscar","Papa","Quebec","Romeo","Sierra","Tango","Uniform","Victor","Whiskey","X-Ray","Yankee","Zulu","Pennant 0","Pennant 1","Pennant 2","Pennant 3","Pennant 4","Pennant 5","Pennant 6","Pennant 7","Pennant 8","Pennant 9","Answering Pennant","First Substitute","Second Substitute","Third Substitute"]

    var body: some View {
        List {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 10)], spacing: 14) {
                ForEach(flags, id: \.self) { name in
                    Button { selectedFlag.wrappedValue = name } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                SignalInternationalFlagArtwork(name: name)
                                if selectedFlag.wrappedValue == name {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                                }
                            }.frame(height: 48)
                            Text(name).font(.caption2).lineLimit(2).multilineTextAlignment(.center)
                        }
                    }.buttonStyle(.plain)
                }
            }.padding(.vertical)
        }
        .navigationTitle("Flag")
        .preferredColorScheme(.dark)
    }
}

private struct SignalNotificationsView: View {
    @AppStorage("signalRadioFriendly") private var radioFriendly = true
    @AppStorage("signalNotificationPreferencesJSON") private var saved = ""
    @State private var values: [String: String] = [:]
    @State private var loaded = false

    private let actionRows = ["ASAP", "Every minute*", "1 minute", "30 seconds", "20 seconds", "Countdown", "On Time"]
    private let raceRows = ["Every minute", "Every 5 minutes", "Time Limit"]
    private let choices = ["Time", "Full", "Sound", "None"]

    var body: some View {
        Form {
            Section {
                Toggle("Radio Friendly", isOn: $radioFriendly)
                Text("信号名ではなく、操作内容を読み上げます。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("TO ACTION") {
                ForEach(actionRows, id: \.self) { row in
                    notificationPicker(row)
                }
            }
            Section("Race") {
                ForEach(raceRows, id: \.self) { row in
                    notificationPicker(row)
                }
            }
            Section("Other") {
                notificationPicker("GPS status")
                notificationPicker("Zone alerts")
            }
        }
        .navigationTitle("Notifications")
        .onAppear { load() }
        .onChange(of: values) { _, _ in persist() }
        .preferredColorScheme(.dark)
    }

    private func notificationPicker(_ title: String) -> some View {
        Picker(title, selection: Binding(
            get: { values[title] ?? (title == "ASAP" ? "Full" : "None") },
            set: { values[title] = $0 }
        )) {
            ForEach(choices, id: \.self) { Text($0).tag($0) }
        }.pickerStyle(.menu)
    }
    private func load() {
        guard !loaded else { return }
        if let data = saved.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) { values = decoded }
        loaded = true
    }
    private func persist() {
        guard loaded, let data = try? JSONEncoder().encode(values) else { return }
        saved = String(data: data, encoding: .utf8) ?? "{}"
    }
}

private struct SignalHornSettingsView: View {
    @AppStorage("signalHornEnabled") private var enabled = true
    @AppStorage("signalHornVolume") private var volume = 0.8
    @AppStorage("signalShortHornSeconds") private var shortSound = 3.1
    @AppStorage("signalHornSeconds") private var longSound = 5.1
    @AppStorage("signalHornGapSeconds") private var gap = 1.1

    var body: some View {
        Form {
            Section("Mode") {
                Picker("Mode", selection: Binding(
                    get: { enabled ? "Virtual" : "Disabled" },
                    set: { enabled = $0 == "Virtual" }
                )) {
                    Text("Disabled").tag("Disabled")
                    Text("Virtual").tag("Virtual")
                    Text("Remote").tag("Remote")
                }.pickerStyle(.segmented)
            }
            Section("General") { Toggle("Horn for first finisher", isOn: .constant(false)) }
            Section("Virtual Horn") {
                slider("Volume", value: $volume, range: 0...1, step: 0.05, suffix: "%", multiplier: 100)
            }
            Section("Remote Settings") {
                slider("Short Sound", value: $shortSound, range: 0.1...10, step: 0.1, suffix: "s")
                slider("Long Sound", value: $longSound, range: 0.1...10, step: 0.1, suffix: "s")
                slider("Gap", value: $gap, range: 0.1...3, step: 0.1, suffix: "s")
            }
            Section("Preview") {
                Button("短音を試す") { SignalSettingsSound.preview(seconds: shortSound, volume: volume) }
                Button("長音を試す") { SignalSettingsSound.preview(seconds: longSound, volume: volume) }
            }
        }
        .navigationTitle("Remote Horn")
        .preferredColorScheme(.dark)
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, suffix: String, multiplier: Double = 1) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.1f%@", value.wrappedValue * multiplier, suffix))
                    .foregroundStyle(.secondary).monospacedDigit()
            }
            Slider(value: value, in: range, step: step)
        }
    }
}

private enum SignalSettingsSound {
    private static var player: AVAudioPlayer?

    static func preview(seconds: Double, volume: Double) {
        let rate = 22_050.0
        let duration = max(0.1, seconds)
        let count = max(1, Int(rate * duration))
        var samples = Data(capacity: count * 2)
        for index in 0..<count {
            let t = Double(index) / rate
            let envelope = min(min(1, t / 0.08), min(1, (duration - t) / 0.18))
            let frequency = 218.0 - 7.0 * (t / duration)
            let fundamental = sin(2 * Double.pi * frequency * t)
            let harmonics = 0.48 * sin(2 * Double.pi * frequency * 2 * t)
                + 0.24 * sin(2 * Double.pi * frequency * 3 * t)
                + 0.12 * sin(2 * Double.pi * frequency * 4 * t)
                + 0.12 * sin(2 * Double.pi * (frequency + 3.5) * t)
            var sample = Int16((fundamental * 0.68 + harmonics) * envelope * volume * 0.52 * Double(Int16.max)).littleEndian
            withUnsafeBytes(of: &sample) { samples.append(contentsOf: $0) }
        }
        var wav = Data("RIFF".utf8)
        func append32(_ value: UInt32) { var value = value.littleEndian; withUnsafeBytes(of: &value) { wav.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { var value = value.littleEndian; withUnsafeBytes(of: &value) { wav.append(contentsOf: $0) } }
        append32(UInt32(36 + samples.count)); wav.append(Data("WAVEfmt ".utf8)); append32(16); append16(1); append16(1)
        append32(UInt32(rate)); append32(UInt32(rate) * 2); append16(2); append16(16)
        wav.append(Data("data".utf8)); append32(UInt32(samples.count)); wav.append(samples)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        player = try? AVAudioPlayer(data: wav)
        player?.play()
    }
}

private extension Color {
    init(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let value = UInt64(digits, radix: 16) ?? 0xFFFFFF
        self.init(.sRGB,
                  red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255,
                  opacity: 1)
    }
}

#endif

