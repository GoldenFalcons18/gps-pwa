import SwiftUI
import CoreLocation

struct WaypointEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @State var waypoint: Waypoint
    @State private var format = 1
    @State private var latitudeSelected = true
    let save: (Waypoint) -> Void
    private let symbols = ["flag.fill", "mappin", "star.fill", "circle.fill", "triangle.fill", "square.fill", "diamond.fill", "sailboat.fill", "ferry.fill", "house.fill", "sun.max.fill", "moon.fill", "exclamationmark.triangle.fill", "fish.fill", "binoculars.fill", "light.beacon.max.fill"]
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
                    save(waypoint); dismiss()
                }.font(.headline)
            }.foregroundStyle(.orange).padding().background(Color(white: 0.09))
            ScrollView {
                VStack(spacing: 1) {
                    row("名前") { TextField("名前", text: $waypoint.name).accessibilityIdentifier("waypointName") }
                    row("注記") { TextField("注記", text: Binding(get: { waypoint.note ?? "" }, set: { waypoint.note = $0 })) }
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
                                ForEach(symbols, id: \.self) { symbol in
                                    Button { waypoint.markSymbol = symbol; waypoint.markText = nil } label: {
                                        Image(systemName: symbol).font(.title2).frame(width: 38, height: 36)
                                            .foregroundStyle(selectedColor.wrappedValue)
                                            .background((waypoint.markText ?? "").isEmpty && (waypoint.markSymbol ?? "flag.fill") == symbol ? Color.white.opacity(0.2) : .clear)
                                    }.accessibilityLabel(symbol)
                                }
                            }
                            TextField("絵文字・文字も入力できます", text: Binding(get: { waypoint.markText ?? "" }, set: { waypoint.markText = String($0.prefix(2)) }))
                                .textFieldStyle(.roundedBorder).accessibilityLabel("自由なマーク")
                        }
                    }
                    row("カラー") { ColorPicker("自由に選ぶ", selection: selectedColor, supportsOpacity: false) }
                    row("プレビュー") {
                        HStack {
                            if let text = waypoint.markText, !text.isEmpty { Text(text).font(.title) }
                            else { Image(systemName: waypoint.markSymbol ?? "flag.fill").font(.title) }
                            Text(waypoint.name).lineLimit(1)
                        }.foregroundStyle(selectedColor.wrappedValue)
                    }
                    row("マップ") { Text("保存後、地図に表示します").font(.caption) }
                    row("操作") {
                        Button("保存してナビゲート") { save(waypoint); dismiss() }.buttonStyle(.borderedProminent).tint(.orange).foregroundStyle(.black)
                    }
                }
            }
        }.background(.black).foregroundStyle(.white).preferredColorScheme(.dark)
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
