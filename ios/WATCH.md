# Apple Watch 目標ナビ・スピード

watchOS 10以降。WatchプロセスのCore Locationで現在地・速度・進行方位・コンパスを取得し、iPhoneのGPS数値を代用しません。位置情報源のハードウェア選択はwatchOSが管理します。

- ナビ：緑の目標矢印と回転方位盤、目標方位、目標距離、Watchの現在方位。磁北方位が得られるときは真北との差を補正します。
- 速度：SOG（knot / km/h）、COG（真北基準）。GPS未取得・15秒以上古い値は非表示、0.5m/s未満のCOGは非表示。
- 目標：iPhoneの保存地点をフォルダ別に同期。Watchで選択・目標なしにでき、iPhoneへ反映します。未接続時も同期済み地点を選べ、再接続で同期。競合時は新しい選択を優先。新しい地点の作成はiPhoneで行います。
- 単位：iPhone設定を引き継ぎます。

Watchアプリを表示中にセンサーを取得します。バックグラウンドの連続測位は今回の対象外です。コンパス非対応のWatchや真北が得られない場合は方向矢印を表示しません。

配布前に実機でGPS権限、Watchの回転、SOG/COG、iPhoneとの選択同期、未接続時の操作を確認してください。Watch App IDは com.goldenfalcons.sailinggps.watchkitapp。両ターゲットの署名設定と ITSAppUsesNonExemptEncryption=false を維持します。
