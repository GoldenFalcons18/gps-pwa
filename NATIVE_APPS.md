# Sailing GPS Logger native apps

既存のWeb版を維持し、`android/` と `ios/` にネイティブ版を追加しています。

## Android

Android Studioで `android/` を開いてください。SDK 36、AGP 8.13.2、アプリID `com.goldenfalcons.sailinggps`。バージョン1.2.0（5）。
スピードメーター／地図モード、磁気コンパス／GPS方位、ウェイポイント、GPX、Foreground ServiceによるGPS記録、デバッグログを備えます。

起動時に最大1日1回、または「更新を確認」ボタンで `GoldenFalcons18/gps-pwa` の公開リリースを調べます。`android-v1.1.0` のようなタグと `android-update.json`、対応APKが必要です。草稿・プレリリース・別パッケージ・古い版は通知しません。自動インストールは行いません。ダウンロード後、Androidのインストール画面で操作します。

旧V3にはこの機能がないため、今回の更新通知対応版だけは手動でインストールしてください。その後の新しい公開版から通知できます。

新しい版では `android/gradle.properties` の appVersionCode を必ず増やし、appVersionName も変更します。過去にインストールした版と同じ署名キーを使います。デバッグ署名APKは既存の正式署名アプリに上書きできません。削除すると記録が消えるため、先にGPXを保存してください。

### GitHubで署名済みAPKの配布準備

Actions の Android build and signed release draft は通常はデバッグビルドとテストだけを実行します。署名して配布する場合はリポジトリのActions secretsに次を登録します（チャットやソースコードに貼り付けないでください）。

- SAILING_KEYSTORE_BASE64: 既存署名キーストアのBase64
- SAILING_KEYSTORE_PASSWORD
- SAILING_KEY_ALIAS
- SAILING_KEY_PASSWORD

手動実行で signed_release を有効にすると、署名APKと更新メタデータを添付した**草稿**リリースができます。実機で記録・画面OFF・GPX・旧版からの上書きを確認してから公開してください。Secretsが未設定なら署名リリースは作成できません。
ローカルで署名したAPKからメタデータを作る場合、ルートで `python scripts/release-metadata.py <APKのパス>` を実行してください。メタデータのSHA256は配布ファイル確認用で、アプリ内でダウンロードAPKのハッシュ検証をする機能ではありません。Androidが署名と更新の整合性を確認します。

Windowsでローカル署名する補助ツールは `scripts/build-signed-android.ps1` です。JavaとPython 3.11以降を準備して実行すると、既存キーのパスとエイリアス、非表示のパスワード入力を求めます。秘密はファイルに保存せず、終了時に環境変数を消去します。Android Studioの「Generate Signed App Bundle / APK」からAPKを作成し、上記メタデータ作成手順を使うこともできます。

## iPhone（開発版）

SwiftUI / CoreLocation / MapKitを使用し、iOS 17以降を対象にしています。2表示モード、SOG、GPS／磁気方位、円形方位計、地図と航跡、複数ウェイポイント、GPX共有、バックグラウンド位置記録を実装しています。Androidと同じ機能・表示がすべて移植済みという意味ではありません。旧版1.1.0はiPhoneで起動確認済みです。画面OFF記録の実機確認は未完了です。

iPhone版1.2.0（6）ではウェイポイントをAndroidと同じ度・分とN/S・E/Wで入力します。既存のウェイポイント保存形式は維持しています。座標変換・範囲チェックは `swift test --package-path ios` で検証します。

MacではXcodeとXcodeGenを準備し、`ios/` で `xcodegen generate` を実行して生成されたプロジェクトを開きます。署名チームは自分のApple Developerアカウントに設定します。GitHub Actions の iPhone compile check でMac上のコンパイル確認を行えます。シミュレーター用アプリに加え、個人署名用の未署名IPAを生成します。

記録は前面で開始してください。位置情報許可とバックグラウンドlocation設定を使い、画面OFF中も継続する設計です。強制終了・OSによる終了後の自動再開は保証しません。記録とウェイポイントはアプリ内Documents、エラーや開始停止はdebug.logに保存します。GPX共有は記録中も可能です。地図はAppleのネットワークサービスを使用します。

### 日本でのApp Store以外の配布

2026-10-09時点、iOS 26.2以降の日本では認可済み代替マーケットプレイス経由で配布できます。ただし一般アプリのGitHubからのIPA直接インストールとは異なります。Apple Developer Program加入、App Store Connectでの手続き、公証、対応マーケットプレイスへの登録・受け入れが必要です。App Store公開を避けても開発者登録費用は残ります。Macを所有しなくてもクラウドMacでビルドする構成は可能ですが、署名と実機テストは別途必要です。

公式情報:
- https://developer.apple.com/support/app-distribution-in-japan/
- https://developer.apple.com/programs/enroll/

対応マーケットプレイスの具体例は AltStore PAL です。日本でも利用でき、公証後の配布パッケージとソースJSONを準備して配布します。手順: https://faq.altstore.io/developers/distribute-with-altstore-pal

### Macも有料登録もない場合の個人テスト

AltStore ClassicとWindows版AltServerは無料Appleアカウントで個人署名・インストールする方法です。これは日本の新制度による一般配布とは別の方式です。アプリは7日で期限切れとなるため、Windows PCのAltServerと接続して期限内に更新してください。無料アカウントでは同時に3アプリまで等の制限があります。

1. GitHub Actionsの `iPhone compile check` が成功したら、成果物 `iPhone-unsigned-IPA-requires-AltStore-Classic-signing` をダウンロードして展開します。
2. 公式手順でWindows版AltServerとiPhoneのAltStore Classicを設定します。Appleアカウントの入力はご自身で行い、チャットには送らないでください。
3. `SailingGPS-unsigned.ipa` をiPhoneへ移し、AltStore ClassicのMy Appsの追加操作から署名してインストールします。直接タップするだけではインストールできません。
4. 位置情報を許可し、記録開始後に画面をOFFにして実機で確認します。旧版はAltServerからの個人署名インストールと起動を確認済みです。画面OFF記録は実機検証が必要です。更新時はアプリを削除せず、同じAppleアカウントで上書きしてください。

公式手順: https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows
制限: https://faq.altstore.io/altstore-classic/your-altstore

## 検証

Android: 更新メタデータの単体テストおよびデバッグAPKビルド成功。エミュレーターと実機での今回変更の動作確認は未完了。
iPhone: 初期ソースを作成。GitHubのMacビルド結果と実機での画面OFF記録・GPS方位・GPXの確認が必要。

署名キー、パスワード、位置記録、ローカルSDK設定、ビルドキャッシュはリポジトリに含めません。

## 1.2.0 の画面配置と地図

両OSで上段は大型速度表示／地図、次に目標情報・中央方位計・設定目標、モード名、計器情報、下段に方位と緯度経度を配置します。ウェイポイント編集と設定はメニューから開きます。地図では保存済み地点の名前を表示し、タップで目標を選択できます。「全ウェイポイント」で表示範囲を戻せます。画像の平均速度・MAX・日照など、未実装の計器値は架空表示しません。
