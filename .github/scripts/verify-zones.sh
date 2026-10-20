#!/usr/bin/env bash
set -euo pipefail
APP=com.goldenfalcons.sailinggps
mkdir -p screenshots
trap 'adb logcat -d > screenshots/all-runtime.log; adb shell dumpsys location > screenshots/location-state.txt; adb shell dumpsys notification --noredact > screenshots/notifications.txt; adb shell dumpsys activity activities > screenshots/activities.txt; adb shell run-as "$APP" cat shared_prefs/display.xml > screenshots/display.xml; adb shell run-as "$APP" cat shared_prefs/waypoints.xml > screenshots/waypoints.xml; adb exec-out screencap -p > screenshots/zone-final.png' EXIT
adb install -g apk/*.apk
adb shell cmd location set-location-enabled true
adb shell am force-stop com.android.launcher3
adb shell run-as "$APP" mkdir -p shared_prefs
python3 - <<'PY'
import xml.etree.ElementTree as E,json
root=E.Element('map')
E.SubElement(root,'string',name='items').text='[]'
E.SubElement(root,'string',name='library').text=json.dumps({'groups':[],'features':[{'id':'zone-test','name':'TEST ZONE','kind':'circle','radius':200,'coordinates':[[35.318,139.467]]}]})
E.ElementTree(root).write('zone-waypoints.xml',encoding='utf-8',xml_declaration=True)
root=E.Element('map')
for key,value in [('zoneEnabled',True),('zoneEnter',True),('zoneExit',True)]: E.SubElement(root,'boolean',name=key,value=str(value).lower())
E.SubElement(root,'string',name='zoneSelected').text='zone-test'
E.ElementTree(root).write('zone-display.xml',encoding='utf-8',xml_declaration=True)
PY
adb shell run-as "$APP" sh -c "'cat > shared_prefs/waypoints.xml'" < zone-waypoints.xml
adb shell run-as "$APP" sh -c "'cat > shared_prefs/display.xml'" < zone-display.xml
adb logcat -c
adb emu geo fix 139.477 35.318
adb shell am start -W -n "$APP/.MainActivity"
sleep 3
for sample in 1 2 3 4 5 6 7 8; do adb emu geo fix 139.477 35.318; sleep 1; done
adb logcat -d -s SailingZoneAlert > screenshots/zone-baseline.log
if grep -q 'POST id=zone-test' screenshots/zone-baseline.log; then echo 'Unexpected initial alert'; exit 1; fi
for sample in 1 2 3 4 5 6 7 8; do adb emu geo fix 139.467 35.318; sleep 1; done
adb logcat -d -s SailingZoneAlert > screenshots/zone-enter.log
grep -q 'POST id=zone-test entered=true' screenshots/zone-enter.log
adb shell am start-foreground-service -n "$APP/.GpsLoggingService" -a com.goldenfalcons.sailinggps.START
sleep 2
adb shell input keyevent 3
for sample in 1 2 3 4 5 6 7 8; do adb emu geo fix 139.477 35.318; sleep 1; done
adb logcat -d -s SailingZoneAlert > screenshots/zone-service-exit.log
grep -q 'POST id=zone-test entered=false' screenshots/zone-service-exit.log
adb shell dumpsys notification --noredact > screenshots/zone-notifications.txt
grep -q 'zone-zone-test' screenshots/zone-notifications.txt
adb shell am startservice -n "$APP/.GpsLoggingService" -a com.goldenfalcons.sailinggps.STOP
printf '%s\n' 'PASS: initial baseline is silent; foreground entry and background recording exit post notifications.' > screenshots/zone-result.txt
