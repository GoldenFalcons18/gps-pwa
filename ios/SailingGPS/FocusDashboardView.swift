import SwiftUI

/// Three large sailing readings with target bearing and range sharing one row.
struct FocusDashboardView: View {
    let speed: String
    let speedColor: Color
    let course: Double?
    let isCompass: Bool
    let targetBearing: Double?
    let targetRelativeAngle: Double?
    let targetDistance: String
    let unit: String
    @Binding var mode: Int
    @Binding var magnetic: Bool
    let recording: Bool
    let recordingPaused: Bool
    let startRecording: () -> Void
    let pauseRecording: () -> Void
    let resumeRecording: () -> Void
    let stopRecording: () -> Void
    let chooseTarget: () -> Void
    let openMenu: () -> Void
    @State private var smoothedRelativeAngle: Double?

    private func card(_ label: String, _ value: String, _ color: Color, valueScale: CGFloat = 0.42) -> some View {
        GeometryReader { bounds in
            VStack(spacing: 4) {
                if !label.isEmpty {
                    Text(label)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Text(value)
                    .font(.system(size: min((bounds.size.width - 16) * valueScale, bounds.size.height * 0.62),
                                  weight: .bold, design: .monospaced))
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .foregroundStyle(color)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.gray))
        }
    }

    private var modeName: String {
        ["スピードメーター", "ナビゲーション", "セーリング", "タイマー", "シグナル", "風・マーク記録"][min(max(mode, 0), 5)]
    }

    private func relativeTargetLabel(for angle: Double?) -> String {
        guard let angle else { return "—° · —時方向" }
        let signed = angle > 180 ? angle - 360 : angle
        let degrees = Int(abs(signed).rounded())
        let relative = degrees == 0 ? "正面 0°" : degrees == 180 ? "後方 180°" : "\(signed > 0 ? "右" : "左") \(degrees)°"
        let halfHourIndex = Int(floor((angle + 7.5) / 15)) % 24
        let hour = (halfHourIndex / 2) % 12
        let clock = "\(hour == 0 ? 12 : hour)時\(halfHourIndex % 2 == 1 ? "半" : "")方向"
        return "\(relative) · \(clock)"
    }

    private var recordingControls: some View {
        HStack(spacing: 8) {
            if recording {
                Button(action: pauseRecording) {
                    Image(systemName: "pause.circle.fill").foregroundStyle(.orange)
                }.accessibilityLabel("GPS記録を一時停止")
                Button(action: stopRecording) {
                    Image(systemName: "stop.circle.fill").foregroundStyle(.red)
                }.accessibilityLabel("GPS記録を終了")
            } else if recordingPaused {
                Button(action: resumeRecording) {
                    Image(systemName: "play.circle.fill").foregroundStyle(.green)
                }.accessibilityLabel("GPS記録を再開")
                Button(action: stopRecording) {
                    Image(systemName: "stop.circle.fill").foregroundStyle(.red)
                }.accessibilityLabel("GPS記録を終了")
            } else {
                Button(action: startRecording) {
                    Image(systemName: "record.circle").foregroundStyle(.red)
                }.accessibilityLabel("新しいGPS記録を開始")
            }
        }.buttonStyle(.plain)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            Button { mode = mode < 3 ? mode + 1 : 0 } label: {
                Text(modeName)
                    .font(.system(size: 27, weight: .medium))
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("モード切替")
            HStack(spacing: 4) {
                Circle()
                    .fill(recording ? Color.green : (recordingPaused ? Color.orange : Color.gray))
                    .frame(width: 8, height: 8)
                Text(recording ? "記録中" : (recordingPaused ? "一時停止" : "停止中"))
                    .font(.caption2)
                    .foregroundStyle(recording ? Color.green : (recordingPaused ? Color.orange : Color.secondary))
            }
            .accessibilityElement(children: .combine)
            recordingControls
            Button(action: openMenu) {
                Image(systemName: "line.3.horizontal").foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("メニュー")
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let contentHeight = max(0, geometry.size.height - 16)
            let gap = min(8, max(4, contentHeight * 0.01))
            let headerHeight = min(48, max(36, contentHeight * 0.08))
            let cardHeight = max(72, (contentHeight - headerHeight - gap * 3) / 3)

            VStack(spacing: gap) {
                header.frame(height: headerHeight)
                card("SOG / " + unit, speed, speedColor, valueScale: 0.54)
                    .frame(height: cardHeight)
                card((isCompass ? "コンパス方位" : "COG") + (magnetic ? "（磁北）" : "（真北）"),
                     course.map { String(format: "%.0f°", $0.rounded().truncatingRemainder(dividingBy: 360)) } ?? "—",
                     .white, valueScale: 0.54)
                    .frame(height: cardHeight)
                HStack(spacing: 8) {
                    Button(action: chooseTarget) {
                        VStack(spacing: 3) {
                            Text("目標方位" + (magnetic ? "（磁北）" : "（真北）"))
                                .font(.system(size: 15, weight: .medium)).foregroundStyle(.gray).lineLimit(1).minimumScaleFactor(0.7)
                            Text(targetBearing.map { String(format: "%.0f°", $0.rounded().truncatingRemainder(dividingBy: 360)) } ?? "—")
                                .font(.system(size: 46, weight: .bold, design: .monospaced)).foregroundStyle(.orange)
                                .lineLimit(1).minimumScaleFactor(0.55)
                            Text(relativeTargetLabel(for: smoothedRelativeAngle))
                                .font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
                                .lineLimit(1).minimumScaleFactor(0.55)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(6)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.gray))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("タップして目標地点を変更")
                    card("", targetDistance, .white, valueScale: 0.34)
                }
                .frame(height: cardHeight)
            }
            .padding(8)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(.black)
        .preferredColorScheme(.dark)
        .onAppear { smoothedRelativeAngle = targetRelativeAngle }
        .onChange(of: targetRelativeAngle) { _, value in
            guard let value else { smoothedRelativeAngle = nil; return }
            smoothedRelativeAngle = InstrumentHeading.smooth(previous: smoothedRelativeAngle, target: value, weight: 0.45)
        }
        .animation(.easeOut(duration: 0.2), value: smoothedRelativeAngle)
    }
}
