#!/usr/bin/env bash
set -euo pipefail
: "${KEYSTORE_BASE64:?Missing persistent signing key}"
: "${SAILING_KEYSTORE_PASSWORD:?Missing signing password}"
: "${SAILING_KEY_ALIAS:?Missing signing alias}"
: "${SAILING_KEY_PASSWORD:?Missing key password}"
trap 'rm -f "$SAILING_KEYSTORE_FILE"' EXIT
printf '%s' "$KEYSTORE_BASE64" | base64 --decode > "$SAILING_KEYSTORE_FILE"
chmod 600 "$SAILING_KEYSTORE_FILE"
VERSION=$(sed -n 's/^appVersionName=//p' android/gradle.properties | tr -d '\r')
CODE=$(sed -n 's/^appVersionCode=//p' android/gradle.properties | tr -d '\r')
test "$CODE" -gt 1
# Same key, previous versionCode: verify Android accepts an update and retains data.
gradle -p android :app:assembleRelease -PappVersionCode="$((CODE - 1))" -PappVersionName=1.5.0 --no-daemon
cp android/app/build/outputs/apk/release/app-release.apk upgrade-fixture.apk
gradle -p android :app:testDebugUnitTest :app:assembleRelease --no-daemon
mkdir -p dist
APK="dist/SailingGpsLogger-$VERSION.apk"
cp android/app/build/outputs/apk/release/app-release.apk "$APK"
SIGNER="$ANDROID_HOME/build-tools/36.0.0/apksigner"
for FILE in upgrade-fixture.apk "$APK"; do
  "$SIGNER" verify --verbose --print-certs "$FILE" > "$RUNNER_TEMP/cert-info.txt"
  ACTUAL=$(sed -n 's/^Signer #1 certificate SHA-256 digest: //p' "$RUNNER_TEMP/cert-info.txt" | tr -d '\r')
  EXPECTED=$(tr -d '\r\n' < android/signing-certificate-sha256.txt)
  test "$ACTUAL" = "$EXPECTED"
done
python3 scripts/release-metadata.py "$APK"
(cd dist; sha256sum *.apk android-update.json > SHA256SUMS.txt)
echo 'Both APKs verified with the pinned persistent signing certificate.'
