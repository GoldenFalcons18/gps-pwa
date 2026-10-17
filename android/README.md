# Sailing GPS Logger Android V3 — Google Play 公開準備版

V2でAQUOS sense7 / Android 14の実機動作とバックグラウンドGPS記録を確認した構成をベースに、Google Play公開用の設定を追加した版です。

## V3の変更点

- `compileSdk = 36`
- `targetSdk = 36`（Android 16 / API 36）
- Android Gradle Plugin 8.13.2
- `versionCode = 3`, `versionName = 1.0.0`
- ランチャーアイコン設定を追加
- バックアップを無効化（GPSログ等をOSバックアップ対象から除外）
- Google Play Console入力用資料を `store_assets/` に追加
- AAB作成・署名手順を追加

## 重要

Google Playで一度公開した `applicationId` は原則変更できません。このプロジェクトは以下を使用します。

`com.goldenfalcons.sailinggps`

公開前にこのIDで問題ないことを確認してください。

## Android Studioで開く

1. ZIPを展開
2. Android Studio → Open
3. `SailingGpsLoggerAndroidV3` フォルダを選択
4. Gradle Syncを待つ
5. SDK 36が未導入なら Android Studio の SDK Manager から Android 16 / API 36 をインストール
6. AQUOS sense7を接続してRunし、V2同様にGPS記録を再確認

## Google Play用AABを作る

Android Studioで以下を実行します。

1. Build → Generate Signed App Bundle or APK
2. Android App Bundle を選択
3. Next
4. Create new... でアップロードキー（keystore）を作成
5. keystoreファイルとパスワードを安全な場所に保管
6. release を選択
7. Create

生成された `.aab` をGoogle Play Consoleにアップロードします。

**keystoreを紛失しないでください。GitHub等にも絶対に公開しないでください。**

## Play Console用資料

`store_assets/` 内を参照してください。

- `privacy_policy_ja.md` — プライバシーポリシー雛形
- `play_console_notes_ja.md` — 権限・Foreground Service・Data safety回答の下書き
- `store_listing_ja.md` — ストア説明文の下書き
- `release_checklist_ja.md` — 公開前チェックリスト
- `icon_512.png` — Playストア用512×512アイコン候補

スクリーンショットとフィーチャーグラフィックは、実際のアプリ画面を使って公開前に用意してください。
