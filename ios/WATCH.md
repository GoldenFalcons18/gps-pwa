# Apple Watch 目標ナビ

watchOS 10以降のiPhone連携アプリです。目標名、真北基準の方位、距離（iPhoneの単位設定）を表示します。

iPhoneのGPS値を受信します。記録前はiPhoneのアプリ表示中、画面を消した運用ではiPhoneで航跡記録を開始してください。GPS時刻から30秒以上経った情報は警告表示します。Watch単独GPSや手首の向きに合わせた矢印は未実装です。

## 配布前
Apple側のWatch App ID `com.goldenfalcons.sailinggps.watchkitapp` と配布プロファイルを追加し、両アプリの署名設定が必要です。Apple管理画面の操作はユーザーが行います。ビルドと実機の通信、目標なし、単位変更、切断と再接続を確認してください。

暗号化申告 ITSAppUsesNonExemptEncryption=false は両ターゲットで維持します。
