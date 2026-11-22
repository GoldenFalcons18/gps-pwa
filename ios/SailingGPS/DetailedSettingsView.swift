import SwiftUI
import UserNotifications

struct DetailedSettingsView: View {
    @ObservedObject var gps:GPSRecorder
    @AppStorage("largeDecimal") private var largeDecimal=true
    @AppStorage("coordinateFormat") private var coordinateFormat="dm"
    @AppStorage("twelveHourClock") private var twelveHourClock=false
    @AppStorage("keepScreenAwake") private var keepScreenAwake=false
    @AppStorage("zeroSpeedThreshold") private var zeroSpeedThreshold=0.0
    @AppStorage("arrivalUsesAverage") private var arrivalUsesAverage=false
    @AppStorage("showETA") private var showETA=false
    @AppStorage("showCourseLine") private var showCourse=true
    @AppStorage("courseLineLengthMeters") private var courseLineLengthMeters=500
    @AppStorage("courseMarkIntervalMeters") private var courseMarkIntervalMeters=100
    @AppStorage("mapProvider") private var mapProvider="apple"
    @AppStorage("zoneEnabled") private var zoneEnabled=false
    @AppStorage("zoneSelected") private var zoneSelected=""
    @AppStorage("zoneEnter") private var zoneEnter=true
    @AppStorage("zoneExit") private var zoneExit=true
    @AppStorage("zoneSound") private var zoneSound=true
    @AppStorage("zoneHaptic") private var zoneHaptic=true
    @AppStorage("zoneAccuracy") private var zoneAccuracy=50.0
    @AppStorage("zoneMargin") private var zoneMargin=10.0
    @AppStorage("zoneConfirmations") private var zoneConfirmations=3
    @State private var notificationStatus="確認中"
    private var areas:[MapFeature] { gps.library.features.filter{["circle","area"].contains($0.kind)} }
    private func selected(_ id:UUID)->Binding<Bool> {
        Binding(get:{zoneSelected.split(separator:",").contains(Substring(id.uuidString))},set:{ enabled in
            var ids=Set(zoneSelected.split(separator:",").map(String.init));if enabled { ids.insert(id.uuidString) } else { ids.remove(id.uuidString) };zoneSelected=ids.sorted().joined(separator:",")
        })
    }
    var body:some View {
        Section("詳細設定") {
            NavigationLink("速度・座標・時刻") {
                Form {
                    Section("スピードメーター") {
                        Toggle("小数点を大きく表示",isOn:$largeDecimal)
                        Picker("ゼロ速度として表示",selection:$zeroSpeedThreshold) {
                            Text("補正なし").tag(0.0);Text("0.5 knot未満").tag(0.5/1.943844);Text("1.0 knot未満").tag(1.0/1.943844)
                        }
                        Text("低速補正は画面の速度表示だけに適用します。記録値は変更しません。").font(.caption)
                    }
                    Section("表示形式") {
                        Picker("座標",selection:$coordinateFormat) { Text("度分（35°19.0000′N）").tag("dm");Text("度（35.316667°N）").tag("dd");Text("度分秒（35°19′00.0″N）").tag("dms") }
                        Toggle("12時間表示",isOn:$twelveHourClock)
                        Toggle("画面を自動ロックしない",isOn:$keepScreenAwake)
                    }
                }.navigationTitle("速度・座標・時刻")
            }
            NavigationLink("ナビゲーション") {
                Form {
                    Picker("予想時間の計算",selection:$arrivalUsesAverage) { Text("現在の速度").tag(false);Text("記録中の平均速度").tag(true) }
                    Picker("時間の表示",selection:$showETA) { Text("所要時間（ETE）").tag(false);Text("到着時刻（ETA）").tag(true) }
                    Text("目的地までの直線距離で計算します。平均速度は記録距離÷記録時間です。速度未取得・低速時は予想を表示しません。").font(.caption)
                }.navigationTitle("ナビゲーション")
            }
            NavigationLink("地図") {
                Form {
                    Picker("地図サービス",selection:$mapProvider) {
                        Text("Appleマップ").tag("apple")
                        Text("OpenFreeMap（OSM）").tag("openfreemap")
                    }
                    Toggle("進路ライン・距離目盛りを表示",isOn:$showCourse)
                    Picker("進路ラインの長さ",selection:$courseLineLengthMeters) {
                        Text("250 m").tag(250);Text("500 m").tag(500);Text("1 km").tag(1000);Text("2.5 km").tag(2500);Text("5 km").tag(5000)
                    }
                    Picker("距離目盛りの間隔",selection:$courseMarkIntervalMeters) {
                        Text("25 m").tag(25);Text("50 m").tag(50);Text("100 m").tag(100);Text("250 m").tag(250);Text("500 m").tag(500)
                    }
                    Text("ラインと目盛りはAppleマップ・OpenFreeMapで同じ長さと間隔を使います。").font(.caption)
                    OfflineMapSettingsAction()
                    Text(mapProvider == "openfreemap" ? "OpenFreeMapを端末に保存すると、通信がない場所でも表示できます。保存範囲は地図画面で別に選びます。" : "オフライン保存にはOpenFreeMapを使用します。").font(.caption)
                }.navigationTitle("地図")
            }
            NavigationLink("ゾーンアラート") {
                Form {
                    Section("動作") {
                        Toggle("ゾーンアラートを有効にする",isOn:$zoneEnabled).onChange(of:zoneEnabled) { _, enabled in if enabled { ZoneAlerts.shared.requestPermission() } }
                        Text("画面表示中、またはGPS記録中に検知します。アプリ終了・記録停止中のバックグラウンドでは監視しません。最初の位置は基準として登録し、通知しません。").font(.caption)
                        Toggle("エリアに入ったら通知",isOn:$zoneEnter)
                        Toggle("エリアから出たら通知",isOn:$zoneExit)
                        Toggle("通知音",isOn:$zoneSound)
                        Toggle("画面表示中の触覚通知",isOn:$zoneHaptic)
                        Text("通知の許可："+notificationStatus).font(.caption)
                        Button("通知設定を確認") { if let url=URL(string:UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                    }
                    Section("監視するエリア") {
                        if areas.isEmpty { Text("地図ライブラリで円または多角形エリアを作成してください。線は対象外です。") }
                        ForEach(areas) { area in Toggle(area.name + (area.group.isEmpty ? "":"（\(area.group)）"),isOn:selected(area.id)) }
                    }
                    Section("誤通知を抑える設定") {
                        Picker("使用するGPS精度",selection:$zoneAccuracy) { Text("±20m以内").tag(20.0);Text("±50m以内").tag(50.0);Text("±100m以内").tag(100.0) }
                        Picker("境界からの余裕",selection:$zoneMargin) { Text("5m").tag(5.0);Text("10m").tag(10.0);Text("20m").tag(20.0) }
                        Picker("連続確認回数",selection:$zoneConfirmations) { Text("2回").tag(2);Text("3回").tag(3);Text("5回").tag(5) }
                        Text("GPS精度：設定した誤差以内の測位だけを判定に使います。誤差が大きい位置は判定を保留します。").font(.caption)
                        Text("境界からの余裕：境界から、この距離またはGPS誤差の大きい方より離れるまで判定を保留します。").font(.caption)
                        Text("連続確認回数：同じ側の測位が指定回数続いた時に通知します。回数を増やすと誤通知を抑えやすくなりますが、通知は遅くなります。").font(.caption)
                    }
                }.navigationTitle("ゾーンアラート").task {
                    let value=await UNUserNotificationCenter.current().notificationSettings()
                    notificationStatus=value.authorizationStatus == .authorized ? "許可済み":(value.authorizationStatus == .notDetermined ? "未設定":"端末の設定を確認")
                }
            }
        }
    }
}
