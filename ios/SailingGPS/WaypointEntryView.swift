import SwiftUI
import CoreLocation

struct WaypointEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @State var waypoint: Waypoint
    @State private var format = 1
    @State private var latitudeSelected = true
    @State private var rgbRed="255"
    @State private var rgbGreen="170"
    @State private var rgbBlue="0"
    let folders: [String]
    let defaultFolder: String
    let folderColors: [String: String]
    private var folderOptions:[String] { let values=Array(Set(folders + [waypoint.group ?? "",defaultFolder])).filter{!$0.isEmpty}.sorted();return values.isEmpty ? ["メインフォルダ"] : values }
    let save: (Waypoint, Bool) -> Void
    private let symbols = MarineMarks.choices
    private var folderSelection:some View {
        Picker("保存フォルダ",selection:Binding(get:{DefaultWaypointFolder.destination(explicit:waypoint.group,defaultFolder:defaultFolder)},set:{waypoint.group=$0;waypoint.colorName=folderColors[$0] ?? WaypointFolderColors.fallback})) {
            ForEach(folderOptions,id:\.self){Text($0 + ($0==defaultFolder ? " ★デフォルト" : "")).tag($0)}
        }.labelsHidden().accessibilityIdentifier("waypointFolder")
    }
    private var selectedColor: Binding<Color> {
        Binding(get: { waypointColor(waypoint.colorName) }, set: { color in
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            if UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
                waypoint.colorName = String(format: "#%02X%02X%02X", Int((red*255).rounded()), Int((green*255).rounded()), Int((blue*255).rounded()))
            }
        })
    }
    private var coordinate: Binding<Double> {
        latitudeSelected ? $waypoint.latitude : $waypoint.longitude
    }
    private func setColor(_ hex:String) {
        waypoint.colorName=hex
        let value=hex.hasPrefix("#") ? String(hex.dropFirst()):hex
        if let number=UInt32(value,radix:16),value.count==6 { rgbRed=String((number>>16)&255);rgbGreen=String((number>>8)&255);rgbBlue=String(number&255) }
    }
    private func applyRGB() {
        let values=[rgbRed,rgbGreen,rgbBlue].compactMap(Int.init)
        guard values.count==3,values.allSatisfy({(0...255).contains($0)}) else{return}
        setColor(String(format:"#%02X%02X%02X",values[0],values[1],values[2]))
    }
    private func formatted(_ value: Double, latitude: Bool) -> String {
        let suffix = latitude ? (value.sign == .minus ? "S" : "N") : (value.sign == .minus ? "W" : "E")
        let absolute = abs(value)
        if format == 0 { return String(format: "%.6f°%@", absolute, suffix) }
        if format == 1 { return CoordinateInput.format(value, isLatitude: latitude) }
        let total = Int((absolute * 360000).rounded())
        return String(format: "%d°%02d′%05.2f″%@", total / 360000, total / 6000 % 60, Double(total % 6000) / 100, suffix)
    }
    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 0) {
            Text(label).font(.headline).foregroundStyle(.orange).frame(width: 100, alignment: .leading).padding(8).frame(maxHeight: .infinity).background(Color(white: 0.18))
            content().padding(8).frame(maxWidth: .infinity, alignment: .leading).background(Color(white: 0.28))
        }.frame(minHeight: 45).background(Color(white: 0.28))
    }
    var body: some View {
        VStack(spacing: 1) {
            HStack {
                Button { dismiss() } label: { Image(systemName: "xmark").font(.title2) }.accessibilityLabel("キャンセル")
                Text("ウェイポイント").font(.title3.bold())
                Spacer()
                Button("完了") {
                    if waypoint.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { waypoint.name = "ウェイポイント" }
                    save(waypoint, false); dismiss()
                }.font(.headline)
            }.foregroundStyle(.orange).padding().background(Color(white: 0.09))
            ScrollView {
                VStack(spacing: 1) {
                    row("名前") { TextField("名前（改行可）", text: $waypoint.name, axis: .vertical).lineLimit(1...4).accessibilityIdentifier("waypointName") }
                    row("注記") { TextField("注記", text: Binding(get: { waypoint.note ?? "" }, set: { waypoint.note = $0 })) }
                    row("保存フォルダ") { folderSelection }
                    row("緯度/経度") { Text(formatted(waypoint.latitude, latitude: true) + ", " + formatted(waypoint.longitude, latitude: false)).font(.caption.monospacedDigit()).minimumScaleFactor(0.5).lineLimit(1) }
                    Picker("座標形式", selection: $format) { Text("度").tag(0); Text("度分").tag(1); Text("度分秒").tag(2) }.pickerStyle(.segmented).padding(6)
                    HStack(spacing: 0) {
                        axisButton(true)
                        axisButton(false)
                    }
                    CoordinateWheel(value: coordinate, latitude: latitudeSelected, format: format)
                        .id("\(latitudeSelected)-\(format)").frame(height: 210).background(Color(white: 0.11))
                    row("マーク") {
                        VStack(alignment: .leading, spacing: 10) {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
                                ForEach(symbols, id: \.0) { symbol, title in
                                    Button { waypoint.markSymbol = symbol; waypoint.markText = nil } label: {
                                        VStack(spacing: 3) { WaypointMarkIcon(symbol: symbol); Text(title).font(.caption2) }.frame(minWidth: 38, minHeight: 48)
                                            .foregroundStyle(selectedColor.wrappedValue)
                                            .background((waypoint.markText ?? "").isEmpty && (waypoint.markSymbol ?? "flag.fill") == symbol ? Color.white.opacity(0.2) : .clear)
                                    }.accessibilityLabel(title)
                                }
                            }
                            TextField("絵文字・文字も入力できます", text: Binding(get: { waypoint.markText ?? "" }, set: { waypoint.markText = String($0.prefix(2)) }))
                                .textFieldStyle(.roundedBorder).accessibilityLabel("自由なマーク")
                        }
                    }
                    row("カラー") {
                        VStack(alignment:.leading,spacing:8) {
                            ColorPicker("自由に選ぶ", selection: selectedColor, supportsOpacity: false)
                            Menu("色を選択") { ForEach(WaypointFolderColors.palette){item in Button { setColor(item.hex) } label:{Label(item.name,systemImage:"circle.fill").tint(waypointColor(item.hex))} } }
                            HStack(spacing:5) {
                                TextField("R",text:$rgbRed).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                                TextField("G",text:$rgbGreen).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                                TextField("B",text:$rgbBlue).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                                Button("適用",action:applyRGB).buttonStyle(.bordered)
                            }
                            Text("RGB各0〜255").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    row("プレビュー") {
                        HStack {
                            if let text = waypoint.markText, !text.isEmpty { Text(text).font(.title) }
                            else { WaypointMarkIcon(symbol: waypoint.markSymbol ?? "flag.fill") }
                            Text(waypoint.name).lineLimit(1)
                        }.foregroundStyle(selectedColor.wrappedValue)
                    }
                    row("マップ") { Text("保存後、地図に表示します").font(.caption) }
                    row("操作") {
                        Button("保存してナビゲート") { save(waypoint, true); dismiss() }.buttonStyle(.borderedProminent).tint(.orange).foregroundStyle(.black)
                    }
                }
            }
        }.onAppear { if (waypoint.group ?? "").isEmpty { waypoint.group=defaultFolder };if waypoint.colorName == nil { waypoint.colorName=folderColors[waypoint.group ?? defaultFolder] ?? WaypointFolderColors.fallback };setColor(waypoint.colorName ?? WaypointFolderColors.fallback) }.onChange(of:waypoint.colorName){_,value in if let value{setColor(value)}}.background(.black).foregroundStyle(.white).preferredColorScheme(.dark)
    }
    private func axisButton(_ latitude: Bool) -> some View {
        Button { latitudeSelected = latitude } label: {
            VStack(alignment: latitude ? .leading : .trailing, spacing: 3) {
                Text(formatted(latitude ? waypoint.latitude : waypoint.longitude, latitude: latitude)).font(.system(size: 23, weight: .bold, design: .monospaced)).minimumScaleFactor(0.5).lineLimit(1).foregroundStyle(.orange)
                Text(latitude ? "緯度" : "経度").font(.caption).foregroundStyle(.white)
            }.padding(8).frame(maxWidth: .infinity).background(latitudeSelected == latitude ? Color(white: 0.16) : .black)
        }
    }
}

func waypointColor(_ name: String?) -> Color {
    if let name, name.hasPrefix("#"), name.count == 7, let rgb = UInt32(name.dropFirst(), radix: 16) {
        return Color(.sRGB, red: Double((rgb >> 16) & 255)/255, green: Double((rgb >> 8) & 255)/255, blue: Double(rgb & 255)/255, opacity: 1)
    }
    switch name { case "red": return .red; case "green": return .green; case "blue": return .blue; case "purple": return .purple; case "cyan": return .cyan; default: return .orange }
}

/// A single native picker prevents adjacent SwiftUI wheels from stealing touches.
struct CoordinateWheel: UIViewRepresentable {
    @Binding var value: Double
    let latitude: Bool
    let format: Int
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIPickerView {
        let picker = UIPickerView(); picker.dataSource = context.coordinator; picker.delegate = context.coordinator
        picker.accessibilityLabel = latitude ? "緯度ホイール" : "経度ホイール"
        return picker
    }
    func updateUIView(_ picker: UIPickerView, context: Context) {
        context.coordinator.parent = self
        let rows = context.coordinator.rows
        picker.reloadAllComponents()
        for (component, row) in rows.enumerated() { picker.selectRow(row, inComponent: component, animated: false) }
    }
    final class Coordinator: NSObject, UIPickerViewDataSource, UIPickerViewDelegate {
        var parent: CoordinateWheel
        init(_ parent: CoordinateWheel) { self.parent = parent }
        var maximum: Int { parent.latitude ? 90 : 180 }
        var rows: [Int] { CoordinateInput.wheelRows(parent.value, latitude: parent.latitude, format: parent.format) }
        func numberOfComponents(in pickerView: UIPickerView) -> Int { parent.format == 0 ? 8 : 6 }
        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
            if component == 0 { return maximum + 1 }
            if component == numberOfComponents(in: pickerView)-1 { return 2 }
            if parent.format != 0 && component == 1 { return 60 }
            if parent.format == 2 && component == 2 { return 60 }
            return 10
        }
        func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
            max(24, pickerView.bounds.width / CGFloat(numberOfComponents(in: pickerView)) - 12)
        }
        func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
            let label = (view as? UILabel) ?? UILabel(); label.textAlignment = .center; label.textColor = .white
            label.font = .monospacedDigitSystemFont(ofSize: 23, weight: .medium)
            label.adjustsFontSizeToFitWidth = true; label.minimumScaleFactor = 0.6
            if component == numberOfComponents(in: pickerView)-1 { label.text = parent.latitude ? (row == 0 ? "N" : "S") : (row == 0 ? "E" : "W") }
            else if component == 0 { label.text = "\(row)°" }
            else if parent.format != 0 && component == 1 { label.text = "\(row)" + (parent.format == 1 ? "." : "′") }
            else if parent.format == 2 && component == 2 { label.text = "\(row)." }
            else { label.text = String(row) }
            return label
        }
        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            let count = numberOfComponents(in: pickerView)
            let values = (0..<count).map { pickerView.selectedRow(inComponent: $0) }
            parent.value = CoordinateInput.wheelValue(values, latitude: parent.latitude, format: parent.format)
        }
    }
}

