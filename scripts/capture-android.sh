#!/usr/bin/env bash
set -euo pipefail
APP=com.goldenfalcons.sailinggps
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
