import SwiftUI

/// Three large sailing readings with target bearing and range sharing one row.
struct FocusDashboardView: View {
    let speed: String
    let course: Double?
    let isCompass: Bool
    let targetBearing: Double?
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

    private func card(_ label: String, _ value: String, _ color: Color) -> some View {
        GeometryReader { bounds in
            VStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.gray)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(value)
                    .font(.system(size: min(bounds.size.width * 0.24, bounds.size.height * 0.58),
                                  weight: .bold, design: .monospaced))
                    .minimumScaleFactor(0.45)
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
        ["スピードメーター", "ナビゲーション", "セーリング", "タイマー", "シグナル"][min(max(mode, 0), 4)]
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

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button { mode = (mode + 1) % 5 } label: {
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
            HStack(spacing: 8) {
                card("SOG / " + unit, speed, .green)
                card((isCompass ? "コンパス方位" : "COG") + (magnetic ? "（磁北）" : "（真北）"),
                     course.map { String(format: "%.0f°", $0.rounded().truncatingRemainder(dividingBy: 360)) } ?? "—",
                     .white)
            }
            .frame(height: 150)
            HStack(spacing: 8) {
                Button(action: chooseTarget) {
                    card("目標方位" + (magnetic ? "（磁北）" : "（真北）"),
                         targetBearing.map { String(format: "%.0f°", $0.rounded().truncatingRemainder(dividingBy: 360)) } ?? "—",
                         .orange)
                }
                .buttonStyle(.plain)
                .accessibilityHint("タップして目標地点を変更")
                card("目標距離", targetDistance, .white)
            }
            .frame(height: 92)
        }
        .padding(8)
        .background(.black)
        .preferredColorScheme(.dark)
    }
}
