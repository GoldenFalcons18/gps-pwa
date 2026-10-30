import SwiftUI

#if os(iOS)
import AudioToolbox

#if os(iOS)
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
    var orangeDisplayedMinutes = 4
    var orangeRemovedMinutes = 4
    var starts: [SignalStartAction] = [
        SignalStartAction(flagID: "class-4", minute: 5, raised: true, horn: "short")
    ]

    static let starter = SignalFleetPreset()
    static func load(from value: String) -> [SignalFleetPreset] {
        guard let data = value.data(using: .utf8),
              let saved = try? JSONDecoder().decode([SignalFleetPreset].self, from: data),
              !saved.isEmpty else { return [.starter] }
        return saved
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
}

private struct SignalSequenceChoice: Identifiable { let id: String; let name: String }
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

struct SignalSettingsView: View {
    @AppStorage("signalMinimumTimeToFirstAction") private var minimumTime = 15
    @AppStorage("signalVoiceName") private var voiceName = "Kyoko (Enhanced)"
    @AppStorage("signalRadioFriendly") private var radioFriendly = true
    @AppStorage("signalClockOffset") private var clockOffset = 0.0
    @AppStorage("signalExternalDisplayEnabled") private var externalDisplay = true
    @AppStorage("signalRemoteFlagsEnabled") private var remoteFlags = false
    @AppStorage("signalBuoyZoneLinked") private var buoyZoneLinked = false
    @AppStorage("signalLogEnabled") private var logEnabled = true
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
                            LabeledContent("最初の信号までの最短時間", value: "\(minimumTime)秒")
                            Text("レース管理モード").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Picker("Voice", selection: $voiceName) {
                        Text("Kyoko (Enhanced)").tag("Kyoko (Enhanced)")
                        Text("Siri Japanese").tag("Siri Japanese")
                        Text("端末の標準音声").tag("端末の標準音声")
                    }
                    NavigationLink("Notifications") { SignalNotificationsView() }
                    LabeledContent("Time Sync", value: String(format: "%.0f秒", clockOffset))
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
                            Text("\(preset.starts.count) starts · \(sequenceName(preset.sequence))")
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
    private func sequenceName(_ id: String) -> String {
        SignalSequence.profiles.first(where: { $0.id == id })?.name ?? "5分シーケンス"
    }
}

private struct SignalFleetPresetEditor: View {
    @Binding var preset: SignalFleetPreset
    @AppStorage("signalFlagProfile") private var activeSequence = "standard-start"
    @AppStorage("signalCustomClassFlag") private var activeClassFlag = "class-4"
    @AppStorage("signalCustomPrepFlag") private var activePrepFlag = "P"
    @AppStorage("signalOrangeEnabled") private var activeOrangeEnabled = true
    @AppStorage("signalOrangeRemovedAfterMinutes") private var activeOrangeRemoval = 4
    @Environment(\.dismiss) private var dismiss
    @State private var showingAddFlag = false

    private let sequences: [SignalSequenceChoice] = [
        SignalSequenceChoice(id: "standard-start", name: "Rule 26 · 5分"),
        SignalSequenceChoice(id: "video-20", name: "動画A · 20分"),
        SignalSequenceChoice(id: "video-13", name: "動画B · 13分"),
        SignalSequenceChoice(id: "custom-five", name: "カスタム · 5分")
    ]
    private let rules = ["P", "I", "U", "Z", "Black", "Default"]

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $preset.name)
            }
            Section("Defaults") {
                Picker("Start Sequence", selection: $preset.sequence) {
                    ForEach(sequences) { Text($0.name).tag($0.id) }
                }
                Picker("Start Rule", selection: $preset.startRule) {
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
                Picker("準備信号", selection: $preset.prepFlagID) {
                    ForEach(["P", "I", "U", "Z", "black"], id: \.self) { Text($0 == "black" ? "黒旗" : "\($0)旗").tag($0) }
                }
                Stepper("次のレースまで：\(preset.raceDelayMinutes)分", value: $preset.raceDelayMinutes, in: 0...60)
                Toggle("Custom Race Delay", isOn: $preset.raceDelayEnabled)
            }
            Section("Time Limits") {
                Toggle("Enable", isOn: $preset.timeLimitEnabled)
                Stepper("Race Limit：\(preset.raceLimitMinutes):00", value: $preset.raceLimitMinutes, in: 1...300)
                    .disabled(!preset.timeLimitEnabled)
                Stepper("Finish Window：\(preset.finishWindowMinutes):00", value: $preset.finishWindowMinutes, in: 1...120)
                    .disabled(!preset.timeLimitEnabled)
            }
            Section("Rule 42 Override") { Toggle("Enable", isOn: $preset.rule42Override) }
            Section("Orange Flag") {
                Toggle("Enable", isOn: $preset.orangeEnabled)
                Stepper("表示時間：\(preset.orangeDisplayedMinutes)分", value: $preset.orangeDisplayedMinutes, in: 1...30)
                    .disabled(!preset.orangeEnabled)
                Stepper("スタート後に降下：\(preset.orangeRemovedMinutes)分", value: $preset.orangeRemovedMinutes, in: 0...30)
                    .disabled(!preset.orangeEnabled)
                Text("シーケンス開始前は降下状態です。開始時に掲揚し、設定した時間後に降下します。")
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
                            TextField("時刻（分）", value: $start.minute, format: .number)
                                .keyboardType(.numberPad)
                                .font(.caption)
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
        .navigationTitle("Fleet Start")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    activeSequence = preset.sequence
                    activeClassFlag = preset.classFlagID
                    activePrepFlag = ["P", "I", "U", "Z"].contains(preset.startRule)
                        ? preset.startRule
                        : (preset.startRule == "Black" ? "black" : preset.prepFlagID)
                    activeOrangeEnabled = preset.orangeEnabled
                    activeOrangeRemoval = preset.orangeRemovedMinutes
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

private struct SignalClassPicker: View {
    @Binding var selection: String
    private let categories = ["Multihull", "Keelboat", "Board", "Centerboard"]
    private let classFlags: [SignalFlagChoice] =
        ["A-Cat","Dart 18","Formula 18","Hobie","Nacra","Nacra 15","Nacra 17","Paper Tiger","Tornado","Weta","Weta+"].map { SignalFlagChoice(id:"class-\($0)", name:$0, category:"Multihull") } +
        ["10mR","12mR","15mR","2.4mR","5.5mR","6mR","7mR","8mR","Albin Vega","Dragon","Etchells","Farr 1020","Flying Fifteen","H-Boat","IF-Boat","IOD","J/22","J/24","J/70","J/80","J/105","Melges 24","Monarch","Optimist","RS Aero","Snipe","Starling","Sunfish","Tasar","Topper","WASZP","Wayfarer","Zoom 8"].map { SignalFlagChoice(id:"class-\($0)", name:$0, category:"Keelboat") } +
        ["Formula Kite","IKA","iQFoil","RS:X","T293","Windsurfer","Wing Foil"].map { SignalFlagChoice(id:"class-\($0)", name:$0, category:"Board") } +
        ["29er","3.7","420","470","49er","49er FX","Albacore","B14","Cadet","Cherub","Cyclone 13","Europe","Finn","Firebug","Flying 11","Flying Ant","GP14","Hornet","ILCA","International 14","J14","Jollyboat","Laser","Laser Pico","Lightning","Luch","Moth","National 18","OK","Open Skiff","Pirate","RS Feva","Solo","Spiral","Splash","Squib","TP 52","Trias","Viper","X-79","X-99","Yngling"].map { SignalFlagChoice(id:"class-\($0)", name:$0, category:"Centerboard") }

    var body: some View {
        List {
            ForEach(categories, id: \.self) { category in
                Section(category) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 12)], spacing: 12) {
                        ForEach(classFlags.filter { $0.category == category }) { flag in
                            Button { selection = flag.id } label: {
                                VStack(spacing: 7) {
                                    Text(flag.symbol)
                                        .font(.system(size: 28, weight: .black, design: .rounded))
                                        .frame(maxWidth: .infinity, minHeight: 54)
                                        .background(selection == flag.id ? Color.orange.opacity(0.3) : Color.white)
                                        .foregroundStyle(selection == flag.id ? .orange : .black)
                                        .clipShape(RoundedRectangle(cornerRadius: 5))
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
                    NavigationLink("信号旗を選択") { SignalInternationalFlagGallery() }
                    Text("国際信号旗の一覧から表示する旗を選びます。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                Section("Logo") {
                    NavigationLink("クラスのロゴを選択") { SignalClassPicker(selection: $flag.logoID) }
                }
            }
            Section("Preview") {
                SignalFlagPreview(flag: flag).frame(height: 110).frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(flag.name.isEmpty ? "Class Flag" : flag.name)
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
    @AppStorage("signalSelectedInternationalFlag") private var selectedInternationalFlag = "Alpha"
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(hex: flag.flagColor)
                if flag.layout == "horizontal" {
                    VStack(spacing: 0) { Color(hex: flag.flagColor); Color.white }
                } else if flag.layout == "vertical" {
                    HStack(spacing: 0) { Color(hex: flag.flagColor); Color.white }
                } else if flag.layout == "diagonal" || flag.layout == "reverseDiagonal" {
                    Canvas { context, size in
                        let path = Path { p in
                            p.move(to: .zero); p.addLine(to: CGPoint(x: size.width, y: 0))
                            p.addLine(to: CGPoint(x: size.width, y: size.height)); p.close()
                        }
                        context.fill(path, with: .color(.white))
                    }
                }
                if flag.style == "text" {
                    Text(flag.text).font(.system(size: geo.size.height * 0.55, weight: .bold))
                        .foregroundStyle(Color(hex: flag.textColor))
                } else if flag.style == "international" {
                    Text(flag.text.isEmpty ? String(selectedInternationalFlag.prefix(1)) : flag.text).font(.system(size: geo.size.height * 0.55, weight: .black))
                        .foregroundStyle(Color(hex: flag.textColor))
                } else {
                    Text(flag.text.isEmpty ? String(flag.logoID.dropFirst("class-".count)) : flag.text).font(.system(size: geo.size.height * 0.55, weight: .black))
                        .foregroundStyle(Color(hex: flag.textColor))
                }
            }.frame(width: geo.size.width, height: geo.size.height)
        }.clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

private struct SignalInternationalFlagGallery: View {
    @AppStorage("signalSelectedInternationalFlag") private var selectedFlag = "Alpha"
    private let flags = ["Alpha","Bravo","Charlie","Delta","Echo","Foxtrot","Golf","Hotel","India","Juliett","Kilo","Lima","Mike","November","Oscar","Papa","Quebec","Romeo","Sierra","Tango","Uniform","Victor","Whiskey","X-Ray","Yankee","Zulu","Pennant 0","Pennant 1","Pennant 2","Pennant 3","Pennant 4","Pennant 5","Pennant 6","Pennant 7","Pennant 8","Pennant 9","Answering Pennant","First Substitute","Second Substitute","Third Substitute","Fourth Substitute","NATO 0","NATO 1","NATO 2","NATO 3","NATO 4","NATO 5","NATO 6","NATO 7","NATO 8","NATO 9"]

    var body: some View {
        List {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 10)], spacing: 14) {
                ForEach(flags, id: \.self) { name in
                    Button { selectedFlag = name } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                Rectangle().fill(flagColor(name))
                                Text(String(name.prefix(1))).font(.system(size: 24, weight: .black))
                                    .foregroundStyle(.white)
                                if selectedFlag == name {
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

    private func flagColor(_ name: String) -> Color {
        if ["Bravo","Hotel","Romeo"].contains(name) { return .red }
        if ["Alpha","Charlie","Echo","Juliett","Papa","Sierra","X-Ray"].contains(name) { return .blue }
        if ["Delta","Golf","India","Kilo","Quebec","Tango","Yankee"].contains(name) { return .yellow }
        return .orange
    }
}

private struct SignalFlagSwatch: View {
    let flagID: String
    var body: some View {
        let flag = SignalSequence.flag(flagID)
        RoundedRectangle(cornerRadius: 2).fill(Color.white)
            .overlay(Text(flag.symbol.isEmpty ? String(flag.name.prefix(1)) : flag.symbol)
                .font(.caption.bold()).foregroundStyle(.black))
            .frame(width: 34, height: 24)
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
    @AppStorage("signalShortHornSeconds") private var shortSound = 0.22
    @AppStorage("signalHornSeconds") private var longSound = 0.7
    @AppStorage("signalHornGapSeconds") private var gap = 0.18

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
                slider("Short Sound", value: $shortSound, range: 0.1...1, step: 0.05, suffix: "s")
                slider("Long Sound", value: $longSound, range: 0.1...5, step: 0.1, suffix: "s")
                slider("Gap", value: $gap, range: 0.1...2, step: 0.05, suffix: "s")
            }
            Section("Preview") {
                Button("短音を試す") { SignalSettingsSound.preview(seconds: shortSound) }
                Button("長音を試す") { SignalSettingsSound.preview(seconds: longSound) }
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
    static func preview(seconds: Double) {
        AudioServicesPlaySystemSound(1104)
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.1, seconds)) {
            AudioServicesPlaySystemSound(1104)
        }
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
