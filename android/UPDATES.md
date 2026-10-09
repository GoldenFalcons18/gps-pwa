# Android継続更新

初回の固定署名版: 1.5.1 (versionCode 10)。公開先: GoldenFalcons18/gps-pwa の Releases。

利用者は最初に1.5.1以降の固定署名版をインストールする。旧1.5.0デバッグ版との署名互換性はない。旧版を削除する前にGPX保存とウェイポイントの控えを行う。

以後はアンインストールせず、アプリの通知でダウンロードページを開き、APKを上書きインストールする。通知は約24時間ごと、手動確認も可能。初回はダウンロードに使ったブラウザー等へのインストール許可が必要。記録を止めGPX保存してから更新する。

## 開発者の公開手順

1. android/gradle.properties の appVersionCode を必ず増やす。appVersionNameも更新する。
2. android/RELEASE_NOTES.md を書き直してコミット・プッシュする。
3. GitHub Actionsの「Android fixed-signature release」を実行する。
4. 単体テスト、固定証明書の照合、エミュレーター上書き・データ保持チェックが通った後にだけドラフトが作られる。
5. ドラフトのAPKとandroid-update.jsonを確認して公開する。通常リリースとし、タグはandroid-v<versionName>にする。

ワークフローはGitHub SecretsのSAILING_KEYSTORE_BASE64/SAILING_KEYSTORE_PASSWORD/SAILING_KEY_ALIAS/SAILING_KEY_PASSWORDを使う。秘密鍵を再生成・変更しない。鍵が失われると同じアプリへ上書きできなくなる。リポジトリ内には公開証明書のSHA256指紋だけを保存し、意図しない鍵変更をビルド時に拒否する。秘密鍵・パスワードをGitや公開成果物へ含めない。

Proton Driveのcodex/private/android-signingは秘密鍵の保管場所。password.dpapiはこのWindowsアカウントで暗号化されているため、PC変更前に安全な方法で復元可能なバックアップを用意する。

公開APKはreleaseビルド。debugビルドや旧1.5.0は継続配布に使用しない。上書き検証は現在コードを1つ小さいversionCodeでビルドした検証専用APKから行い、実際の利用者の旧デバッグ版からの移行を保証するものではない。
