import SwiftUI
import CoreLocation

struct WaypointEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @State var waypoint: Waypoint
    @State private var format = 1
    @State private var latitudeSelected = true
    let save: (Waypoint) -> Void
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
                    row("カラー") {
                        HStack(spacing: 7) {
                            ForEach(["orange", "red", "green", "blue", "purple", "cyan"], id: \.self) { color in
                                Button { waypoint.colorName = color } label: {
                                    RoundedRectangle(cornerRadius: 4).fill(waypointColor(color)).frame(width: 25, height: 25)
                                        .overlay(RoundedRectangle(cornerRadius: 4).stroke((waypoint.colorName ?? "orange") == color ? Color.white : .clear, lineWidth: 2))
                                }.accessibilityLabel(color)
                            }
                        }
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
            pickerView.bounds.width / CGFloat(numberOfComponents(in: pickerView))
        }
        func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
            let label = (view as? UILabel) ?? UILabel(); label.textAlignment = .center; label.textColor = .white
            label.font = .monospacedDigitSystemFont(ofSize: 23, weight: .medium)
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
