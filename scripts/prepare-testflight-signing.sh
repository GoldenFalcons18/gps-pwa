#!/usr/bin/env bash
set -euo pipefail
umask 077
python3 - <<'PY'
import base64, os, pathlib
root = pathlib.Path(os.environ['RUNNER_TEMP'])
for name, filename in [('IOS_DISTRIBUTION_P12_BASE64','distribution.p12'), ('IOS_APPSTORE_PROFILE_BASE64','appstore.mobileprovision')]:
    (root/filename).write_bytes(base64.b64decode(os.environ[name], validate=True))
key_id = os.environ['APPSTORE_KEY_ID']
if not key_id.isalnum(): raise SystemExit('Invalid API key ID')
keys = pathlib.Path.home()/'private_keys'
keys.mkdir(exist_ok=True)
(keys/('AuthKey_'+key_id+'.p8')).write_bytes(base64.b64decode(os.environ['APPSTORE_PRIVATE_KEY_BASE64'], validate=True))
PY
security cms -D -i "$RUNNER_TEMP/appstore.mobileprovision" > "$RUNNER_TEMP/profile.plist"
python3 - <<'PY'
import os, pathlib, plistlib, datetime
root = pathlib.Path(os.environ['RUNNER_TEMP'])
p = plistlib.loads((root/'profile.plist').read_bytes())
team = os.environ['APPLE_TEAM_ID']
bundle = 'com.goldenfalcons.sailinggps'
ent = p['Entitlements']
assert team in p['TeamIdentifier'], 'Profile belongs to a different team'
assert ent['application-identifier'] == p['ApplicationIdentifierPrefix'][0]+'.'+bundle, 'Profile has wrong bundle ID'
assert not ent.get('get-task-allow', False), 'Development profile cannot be used'
assert not p.get('ProvisionedDevices') and not p.get('ProvisionsAllDevices'), 'Use App Store Connect distribution profile'
assert p['ExpirationDate'] > datetime.datetime.utcnow(), 'Profile expired'
uuid = p['UUID']
assert all(c.isalnum() or c == '-' for c in uuid), 'Invalid profile UUID'
profiles = pathlib.Path.home()/'Library/MobileDevice/Provisioning Profiles'
profiles.mkdir(parents=True, exist_ok=True)
(profiles/(uuid+'.mobileprovision')).write_bytes((root/'appstore.mobileprovision').read_bytes())
options = {'method':'app-store-connect', 'teamID':team, 'signingStyle':'manual', 'signingCertificate':'Apple Distribution', 'provisioningProfiles':{bundle:uuid}, 'manageAppVersionAndBuildNumber':False, 'uploadSymbols':True}
(root/'ExportOptions.plist').write_bytes(plistlib.dumps(options))
with open(os.environ['GITHUB_ENV'],'a') as f: f.write('PROFILE_UUID='+uuid+'\n')
PY
SIGNING_KEYCHAIN="$RUNNER_TEMP/testflight-signing.keychain-db"
KEYCHAIN_PASSWORD=$(openssl rand -hex 24)
echo "::add-mask::$KEYCHAIN_PASSWORD"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$SIGNING_KEYCHAIN"
security set-keychain-settings -lut 21600 "$SIGNING_KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$SIGNING_KEYCHAIN"
security import "$RUNNER_TEMP/distribution.p12" -P "$IOS_DISTRIBUTION_P12_PASSWORD" -A -t cert -f pkcs12 -k "$SIGNING_KEYCHAIN" >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$SIGNING_KEYCHAIN" >/dev/null
security list-keychains -d user -s "$SIGNING_KEYCHAIN" "$HOME/Library/Keychains/login.keychain-db"
DISTRIBUTION_IDENTITY=$(security find-identity -v -p codesigning "$SIGNING_KEYCHAIN" | awk '/Apple Distribution:/{print $2; exit}')
if [ -z "$DISTRIBUTION_IDENTITY" ]; then echo 'No valid Apple Distribution identity in P12'; exit 1; fi
printf 'SIGNING_KEYCHAIN=%s\nDISTRIBUTION_IDENTITY=%s\n' "$SIGNING_KEYCHAIN" "$DISTRIBUTION_IDENTITY" >> "$GITHUB_ENV"
