#!/usr/bin/env bash
set -euo pipefail
APP=com.goldenfalcons.sailinggps
mkdir -p upgrade-results
adb root
adb wait-for-device
adb install -g signed/upgrade-fixture.apk | tee upgrade-results/install-previous.log
adb shell am start -W -n "$APP/.MainActivity"
sleep 4
adb shell am force-stop "$APP"
# Seed realistic saved waypoints and a private-file marker, using emulator root only.
printf '%s' '<map><string name="items">[{"id":"upgrade-marker","name":"UPDATE_KEEP","lat":35.318,"lon":139.467,"group":"港一覧"}]</string><string name="activeId">upgrade-marker</string><string name="library">{"groups":["港一覧","航路"],"features":[{"id":"migration-area","name":"保存済みエリア","kind":"circle","coordinates":[[35.318,139.467]],"radius":200,"group":"航路"}]}</string></map>' > upgrade-results/waypoints-before.xml
printf '%s' 'preserve-private-files-across-update' > upgrade-results/marker-before.txt
printf '%s' '<map><string name="mainWaypointFolder">港一覧</string><boolean name="metricUnits" value="true"/><boolean name="navigator" value="true"/></map>' > upgrade-results/display-before.xml
APP_UID=$(adb shell stat -c %u "/data/user/0/$APP" | tr -d '\r')
adb shell mkdir -p "/data/user/0/$APP/shared_prefs" "/data/user/0/$APP/files"
adb push upgrade-results/waypoints-before.xml "/data/user/0/$APP/shared_prefs/waypoints.xml"
adb push upgrade-results/display-before.xml "/data/user/0/$APP/shared_prefs/display.xml"
adb push upgrade-results/marker-before.txt "/data/user/0/$APP/files/update-preservation.txt"
adb shell chown "$APP_UID:$APP_UID" "/data/user/0/$APP/shared_prefs/waypoints.xml" "/data/user/0/$APP/shared_prefs/display.xml" "/data/user/0/$APP/files/update-preservation.txt"
adb shell restorecon -R "/data/user/0/$APP"
# -r updates the existing package; no uninstall / clear-data occurs.
adb install -r -g signed/dist/*.apk | tee upgrade-results/install-update.log
adb shell am start -W -n "$APP/.MainActivity"
sleep 5
adb exec-out cat "/data/user/0/$APP/shared_prefs/waypoints.xml" > upgrade-results/waypoints-after.xml
adb exec-out cat "/data/user/0/$APP/files/update-preservation.txt" > upgrade-results/marker-after.txt
adb exec-out cat "/data/user/0/$APP/shared_prefs/display.xml" > upgrade-results/display-after.xml
python3 - <<'PY'
import pathlib,xml.etree.ElementTree as E,json
p=pathlib.Path('upgrade-results')
assert (p/'marker-before.txt').read_bytes()==(p/'marker-after.txt').read_bytes()
root=E.parse(p/'waypoints-after.xml').getroot()
values={n.get('name'):n.text for n in root}
assert values['activeId']=='upgrade-marker'
assert any(i['id']=='upgrade-marker' and i['name']=='UPDATE_KEEP' for i in json.loads(values['items']))
items=json.loads(values['items'])
assert next(i for i in items if i['id']=='upgrade-marker')['group']=='港一覧'
library=json.loads(values['library'])
assert set(library['groups'])=={'港一覧','航路'}
assert any(f['id']=='migration-area' for f in library['features'])
display=E.parse(p/'display-after.xml').getroot()
assert next(n.text for n in display if n.get('name')=='mainWaypointFolder')=='港一覧'
assert any(n.get('name')=='metricUnits' and n.get('value')=='true' for n in display)
print('PASS: same-signature update installed; active waypoint, folders, area, settings and private files preserved.')
(p/'result.txt').write_text('PASS: same-signature update installed; active waypoint, folders, area, settings and private files preserved.\n')
PY
adb shell dumpsys package "$APP" | grep -E 'versionCode=|versionName=' > upgrade-results/installed-version.txt
CODE=$(sed -n 's/^appVersionCode=//p' android/gradle.properties | tr -d '\r')
grep -q "versionCode=$CODE " upgrade-results/installed-version.txt
adb exec-out screencap -p > upgrade-results/updated-app.png
adb logcat -d -s AndroidRuntime > upgrade-results/runtime.log
if grep -q 'FATAL EXCEPTION' upgrade-results/runtime.log; then exit 1; fi
