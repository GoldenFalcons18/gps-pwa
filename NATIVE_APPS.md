# Sailing GPS Logger native apps

既存のWeb版を維持し、`android/` と `ios/` にネイティブ版を追加しています。

## Android

Android Studioで `android/` を開いてください。SDK 36、AGP 8.13.2、アプリID `com.goldenfalcons.sailinggps`。バージョン1.1.0（4）。
スピードメーター／地図モード、磁気コンパス／GPS方位、ウェイポイント、GPX、Foreground ServiceによるGPS記録、デバッグログを備えます。

起動時に最大1日1回、または「更新を確認」ボタンで `GoldenFalcons18/gps-pwa` の公開リリースを調べます。`android-v1.1.0` のようなタグと `android-update.json`、対応APKが必要です。草稿・プレリリース・別パッケージ・古い版は通知しません。自動インストールは行いません。ダウンロード後、Androidのインストール画面で操作します。

新しい版では `android/gradle.properties` の appVersionCode を必ず増やし、appVersionName も変更します。過去にインストールした版と同じ署名キーを使います。デバッグ署名APKは既存の正式署名アプリに上書きできません。削除すると記録が消えるため、先にGPXを保存してください。

### GitHubで署名済みAPKの配布準備

Actions の Android build and signed release draft は通常はデバッグビルドとテストだけを実行します。署名して配布する場合はリポジトリのActions secretsに次を登録します（チャットやソースコードに貼り付けないでください）。

- SAILING_KEYSTORE_BASE64: 既存署名キーストアのBase64
- SAILING_KEYSTORE_PASSWORD
- SAILING_KEY_ALIAS
- SAILING_KEY_PASSWORD

手動実行で signed_release を有効にすると、署名APKと更新メタデータを添付した**草稿**リリースができます。実機で記録・画面OFF・GPX・旧版からの上書きを確認してから公開してください。Secretsが未設定なら署名リリースは作成できません。
ローカルで署名したAPKからメタデータを作る場合、ルートで `python scripts/release-metadata.py <APKのパス>` を実行してください。メタデータのSHA256は配布ファイル確認用で、アプリ内でダウンロードAPKのハッシュ検証をする機能ではありません。Androidが署名と更新の整合性を確認します。

## iPhone（開発版）

SwiftUI / CoreLocation / MapKitを使用し、iOS 17以降を対象にしています。2表示モード、SOG、GPS／磁気方位、円形方位計、地図と航跡、複数ウェイポイント、GPX共有、バックグラウンド位置記録を実装しています。Androidと同じ機能・表示がすべて移植済みという意味ではありません。iPhone実機テストは未実施です。

MacではXcodeとXcodeGenを準備し、`ios/` で `xcodegen generate` を実行して生成されたプロジェクトを開きます。署名チームは自分のApple Developerアカウントに設定します。GitHub Actions の iPhone compile check でMac上のコンパイル確認を行えます。取得できる成果物は**シミュレーター用**で、そのままiPhoneにインストールするIPAではありません。

記録は前面で開始してください。位置情報許可とバックグラウンドlocation設定を使い、画面OFF中も継続する設計です。強制終了・OSによる終了後の自動再開は保証しません。記録とウェイポイントはアプリ内Documents、エラーや開始停止はdebug.logに保存します。GPX共有は記録中も可能です。地図はAppleのネットワークサービスを使用します。

### 日本でのApp Store以外の配布

2026-10-09時点、iOS 26.2以降の日本では認可済み代替マーケットプレイス経由で配布できます。ただし一般アプリのGitHubからのIPA直接インストールとは異なります。Apple Developer Program加入、App Store Connectでの手続き、公証、対応マーケットプレイスへの登録・受け入れが必要です。App Store公開を避けても開発者登録費用は残ります。Macを所有しなくてもクラウドMacでビルドする構成は可能ですが、署名と実機テストは別途必要です。

公式情報:
- https://developer.apple.com/support/app-distribution-in-japan/
- https://developer.apple.com/programs/enroll/

## 検証

Android: 更新メタデータの単体テストおよびデバッグAPKビルド成功。エミュレーターと実機での今回変更の動作確認は未完了。
iPhone: 初期ソースを作成。GitHubのMacビルド結果と実機での画面OFF記録・GPS方位・GPXの確認が必要。

署名キー、パスワード、位置記録、ローカルSDK設定、ビルドキャッシュはリポジトリに含めません。
