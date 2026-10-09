#!/usr/bin/env bash
set -euo pipefail
APP=com.goldenfalcons.sailinggps
# The emulator launcher can show a background ANR after cold boot. It is not the app under test.
adb shell am force-stop com.android.launcher3
adb install -g apk/*.apk
adb shell run-as "$APP" mkdir -p shared_prefs
python3 - <<'PY'
import xml.etree.ElementTree as E, json
root=E.Element('map')
E.SubElement(root,'string',name='items').text=json.dumps([{'id':'test-a','name':'TEST A','lat':35.317433,'lon':139.4661},{'id':'test-b','name':'TEST B','lat':35.320,'lon':139.470}])
E.SubElement(root,'string',name='activeId').text='test-a'
E.ElementTree(root).write('waypoints.xml',encoding='utf-8',xml_declaration=True)
PY
adb shell run-as "$APP" sh -c "'cat > shared_prefs/waypoints.xml'" < waypoints.xml
mkdir -p screenshots
adb emu geo fix 139.467 35.318
adb shell am start -n "$APP/.MainActivity"
sleep 5
adb exec-out screencap -p > screenshots/Android-speed.png
adb shell am force-stop "$APP"
printf '%s' '<map><boolean name="navigator" value="true" /></map>' | adb shell run-as "$APP" sh -c "'cat > shared_prefs/display.xml'"
adb shell am start -n "$APP/.MainActivity"
sleep 12
adb exec-out screencap -p > screenshots/Android-map.png
adb logcat -d -s AndroidRuntime > screenshots/runtime.log
if grep -q 'FATAL EXCEPTION' screenshots/runtime.log; then exit 1; fi

# Exercise the current-location action with recording stopped; verify persisted data.
adb shell am force-stop com.android.launcher3
adb shell uiautomator dump /sdcard/quick-wp-ui.xml
adb pull /sdcard/quick-wp-ui.xml quick-wp-ui.xml
cp quick-wp-ui.xml screenshots/quick-wp-ui.xml
COORDS=$(python3 - <<'PY'
import xml.etree.ElementTree as E,re
node=next(n for n in E.parse('quick-wp-ui.xml').iter('node') if n.get('resource-id')=='com.goldenfalcons.sailinggps:id/btnCurrentWp')
x1,y1,x2,y2=map(int,re.findall(r'\d+',node.get('bounds')))
print((x1+x2)//2,(y1+y2)//2)
PY
)
adb emu geo fix 139.467 35.318
sleep 3
adb shell input tap $COORDS
for counter in 1 2 3 4 5; do
  adb emu geo fix 139.467 35.318
  sleep 1
done
adb shell run-as "$APP" cat shared_prefs/waypoints.xml > quick-waypoints.xml
python3 - <<'PY'
import xml.etree.ElementTree as E,json
root=E.parse('quick-waypoints.xml').getroot()
items=json.loads(next(n.text for n in root if n.get('name')=='items'))
assert len(items)==3,items
point=items[-1]
assert abs(point['lat']-35.318)<0.0001 and abs(point['lon']-139.467)<0.0001,point
assert next(n.text for n in root if n.get('name')=='activeId')==point['id']
print('One-tap current waypoint saved and selected with recording stopped')
PY
adb shell run-as "$APP" sh -c "'test ! -s files/track_points.csv'"
adb logcat -d -s SailingGpsLogger > screenshots/gps-preview.log
if ! grep -q 'GPS preview started' screenshots/gps-preview.log; then exit 1; fi
adb exec-out screencap -p > screenshots/Android-current-waypoint.png
adb logcat -d -s AndroidRuntime > screenshots/runtime.log
if grep -q 'FATAL EXCEPTION' screenshots/runtime.log; then exit 1; fi

