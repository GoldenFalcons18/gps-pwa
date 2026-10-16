# WindowsからTestFlightへ配布する

## 現在の状態

TestFlight用の手動実行ワークフローを用意しました。Apple Developer Program登録、証明書とAPIキーの設定、Appleへの初回提出はまだです。既存のAltStore用ビルドは利用できます。

## 最初に行うこと

1. iPhoneのApple Developerアプリ、または https://developer.apple.com/jp/programs/enroll/ からApple Developer Programへ登録します。支払い・本人確認は本人が操作します。購入画面の年額を確認してください。
2. 登録が有効になったら https://developer.apple.com/account/ でApp IDを作成します。Bundle IDは `com.goldenfalcons.sailinggps`。他のチームが取得済みの場合は、別IDへのソース変更が必要です。
3. https://appstoreconnect.apple.com/ でiOSアプリを新規作成し、このBundle IDを選びます。表示名はSailing GPS Logger、日本語、SKUは任意の一意な値にします。
4. Apple Distribution証明書とApp Store Connect配布用プロビジョニングプロファイルを作成します。証明書要求とP12変換はWindows上でも準備できます。秘密鍵はリポジトリ外の `private/ios-signing` に保管します。既存の他アプリの証明書は取り消さないでください。
5. App Store Connectの「ユーザとアクセス」→「統合」で、提出権限を持つチームAPIキーを作成します。Key ID、Issuer ID、ダウンロードしたP8秘密鍵を安全に保管します。P8は再ダウンロードできません。

登録後に証明書作成・秘密情報設定を続けます。秘密鍵・パスワードをチャット、Issues、ソース、公開成果物に貼り付けないでください。

## GitHubの設定

リポジトリのSettings → Environmentsに `testflight` を作り、以下をEnvironment secretsとして登録します。証明書やAPIキーをGitにコミットしません。

|Secret|内容|
|---|---|
|APPLE_TEAM_ID|AppleのTeam ID|
|IOS_DISTRIBUTION_P12_BASE64|Apple Distribution証明書と秘密鍵を含むP12のBase64|
|IOS_DISTRIBUTION_P12_PASSWORD|P12に設定した空ではないパスワード|
|IOS_APPSTORE_PROFILE_BASE64|このアプリのApp Store Connect配布プロファイルのBase64|
|APPSTORE_KEY_ID|API Key ID|
|APPSTORE_ISSUER_ID|API Issuer ID|
|APPSTORE_PRIVATE_KEY_BASE64|P8秘密鍵ファイルのBase64|

APIキーは提出に必要な権限だけ付与します。GitHub Environmentの保護設定は利用できる範囲で適用してください。

## 配布操作

1. GitHub Actionsで `iPhone TestFlight upload` → Run workflowを選択します。
2. ビルド番号は最初19、その後はAppleが受理した番号より大きくします。アプリバージョンはios/project.ymlに従います。
3. macOSランナー上でロジックテスト、配布署名付きアーカイブ、IPA書き出し、App Store Connectへのアップロードを行います。PCへのMacやXcodeのインストールは不要です。
4. Apple側で処理されたらApp Store ConnectのTestFlightでテスト情報・連絡先・輸出コンプライアンス回答を設定します。暗号化の質問には実際の機能に基づいて回答します。
5. 他の人は外部テスターとして追加し、必要なベータ審査を受けた後、招待リンクを共有します。招待メール送信や公開リンクの有効化は配布相手を確認してから行います。
6. 相手はApp StoreからTestFlightを入れ、招待を開いてアプリをインストールします。相手の有料登録・PC・AltServerは不要です。各ビルドは最大90日利用できます。

アップロード成功だけでは外部テスターへの配布は始まりません。App Storeへの一般公開も自動では行いません。

## テスト情報の下書き

説明: セーリング用GPSロガーです。速度・方位の表示、ウェイポイントと目標ナビゲーション、地図、航跡のバックグラウンド記録、GPX出力をテストします。

確認する項目: 現在地と方位の取得、地図の回転と下寄りの自船表示、ウェイポイント作成・長押し編集・目標解除、距離とETE、画面OFF中の記録、GPX出力、以前のデータの保持。

レビュー補足: アカウント作成やアプリ内ログインは不要です。位置情報の許可を求めます。バックグラウンド位置情報は、利用者が開始した航跡記録を画面OFF中にも続けるために使います。

フィードバックメールと審査担当者の連絡先は所有者本人の情報を登録してください。AltStore版からの移行時は署名やアプリIDが異なる可能性があるため、先にGPXなどを保存し、既存アプリを削除せず状態を確認します。全データの自動移行は未検証です。

## ログ・署名

ActionsのTestFlight-build-logs-*にビルド・書き出し・提出ログを14日保存します。P12・P8・プロファイル・一時キーチェーンはアップロード成果物に含めず、終了時に削除します。TestFlight署名工程は有料登録と秘密情報の設定後に実機検証が必要です。

公式資料:
- https://developer.apple.com/jp/programs/enroll/
- https://developer.apple.com/jp/help/app-store-connect/manage-builds/upload-builds
- https://developer.apple.com/jp/help/app-store-connect/test-a-beta-version/invite-external-testers/

## 暗号化輸出設定

project.yml の Info.plist 生成設定に ITSAppUsesNonExemptEncryption: false を設定済み。現在のアプリは独自暗号化を実装せず、依存するZIPFoundationもZIP圧縮・展開のみを使用します。暗号化機能や暗号化SDKを追加した更新では、Appleの説明に従って依存ライブラリを含めて再評価し、この値を見直してください。
https://developer.apple.com/jp/documentation/security/complying-with-encryption-export-regulations
