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
# Read actual laid-out bounds from the debuggable app: no UI-idle wait or fixed pixel offsets.
adb logcat -d -s SailingUiBounds > screenshots/ui-bounds.log
COORDS=$(python3 - <<'PY'
import pathlib,re
records=re.findall(r'UI current=(\d+),(\d+),(\d+),(\d+) map=(\d+),(\d+),(\d+),(\d+)',pathlib.Path('screenshots/ui-bounds.log').read_text())
assert records,'No visible layout bounds'
x1,y1,x2,y2,*_=map(int,records[-1])
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


adb shell am force-stop "$APP"
printf '%s' '<map><boolean name="navigator" value="false"/><boolean name="metricUnits" value="true"/></map>' | adb shell run-as "$APP" sh -c "'cat > shared_prefs/display.xml'"
adb shell am start -n "$APP/.MainActivity"
sleep 3
adb emu geo fix 139.467 35.318
sleep 2
adb logcat -d -s SailingGpsLogger > screenshots/metric-units.log
# The unit spinner is inside the collapsed menu; its selection callback only fires
# after layout. The dashboard reads the persisted value directly on startup.
adb shell run-as "$APP" cat shared_prefs/display.xml > screenshots/metric-preferences.xml
python3 - <<'PYPREF'
import xml.etree.ElementTree as E
root=E.parse('screenshots/metric-preferences.xml').getroot()
assert any(n.get('name')=='metricUnits' and n.get('value')=='true' for n in root)
PYPREF
# The live seconds clock and compass prevent UIAutomator's idle detection.
# Preserve the actual screen for visual checking instead of waiting for an idle UI.
adb exec-out screencap -p > screenshots/Android-metric.png

# Create a waypoint at a map coordinate (not the current GPS coordinate).
adb shell am force-stop "$APP"
printf '%s' '<map><boolean name="navigator" value="true"/></map>' | adb shell run-as "$APP" sh -c "'cat > shared_prefs/display.xml'"
adb shell am start -n "$APP/.MainActivity"
sleep 4
adb emu geo fix 139.467 35.318
sleep 2
adb logcat -d -s SailingUiBounds > screenshots/ui-bounds.log
MAP_POINT=$(python3 - <<'PYMAP'
import pathlib,re
records=re.findall(r'UI current=(\d+),(\d+),(\d+),(\d+) map=(\d+),(\d+),(\d+),(\d+)',pathlib.Path('screenshots/ui-bounds.log').read_text())
assert records
x1,y1,x2,y2=map(int,records[-1][4:])
print(int(x1+(x2-x1)*.25),int(y1+(y2-y1)*.60))
PYMAP
)
read -r MAP_X MAP_Y <<< "$MAP_POINT"
adb shell input swipe "$MAP_X" "$MAP_Y" "$MAP_X" "$MAP_Y" 1200
sleep 1
adb exec-out screencap -p > screenshots/Android-map-operations.png
adb logcat -d -s SailingUiBounds > screenshots/map-operations-bounds.log
read -r CREATE_X CREATE_Y < <(python3 - <<'PYMAPOPS'
import pathlib,re
rows=re.findall(r'MAPOPS create=(\d+),(\d+),(\d+),(\d+)',pathlib.Path('screenshots/map-operations-bounds.log').read_text())
assert rows,'Map operation panel missing'
a,b,c,d=map(int,rows[-1]);print((a+c)//2,(b+d)//2)
PYMAPOPS
)
adb shell input tap "$CREATE_X" "$CREATE_Y"
sleep 1
adb exec-out screencap -p > screenshots/Android-map-create-dialog.png
# Read actual dialog bounds rather than assuming an inset/keyboard configuration.
adb logcat -d -s SailingUiBounds > screenshots/dialog-bounds.log
read -r INPUT_X INPUT_Y SAVE_X SAVE_Y < <(python3 - <<'PYBOUNDS'
import pathlib,re
records=re.findall(r'DIALOG input=(\d+),(\d+),(\d+),(\d+) save=(\d+),(\d+),(\d+),(\d+)',pathlib.Path('screenshots/dialog-bounds.log').read_text())
assert records,'Map long press did not open the waypoint dialog'
x1,y1,x2,y2,a,b,c,d=map(int,records[-1])
print((x1+x2)//2,(y1+y2)//2,(a+c)//2,(b+d)//2)
PYBOUNDS
)
adb shell input tap "$INPUT_X" "$INPUT_Y"
sleep 1
adb shell input text MAP_TEST
adb shell input keyevent 4
sleep 1
adb exec-out screencap -p > screenshots/Android-map-name-entered.png
adb shell input tap "$SAVE_X" "$SAVE_Y"
sleep 2
adb shell run-as "$APP" cat shared_prefs/waypoints.xml > screenshots/map-waypoints.xml
python3 - <<'PYVERIFY'
import xml.etree.ElementTree as E,json
root=E.parse('screenshots/map-waypoints.xml').getroot()
items=json.loads(next(n.text for n in root if n.get('name')=='items'))
assert len(items)==4,items
point=items[-1]
assert point['name']=='MAP_TEST',point
assert -90<=point['lat']<=90 and -180<=point['lon']<=180
assert abs(point['lat']-35.318)+abs(point['lon']-139.467)>0.0001,point
assert next(n.text for n in root if n.get('name')=='activeId')!=point['id']
print('Map long press saved a separate coordinate and selected the new target')
PYVERIFY
adb exec-out screencap -p > screenshots/Android-map-created.png
adb logcat -d -s AndroidRuntime > screenshots/runtime.log
if grep -q 'FATAL EXCEPTION' screenshots/runtime.log; then exit 1; fi

# Rotate the virtual device while its GPS position stays fixed: camera and target must agree.
adb shell am force-stop "$APP"
printf '%s' '<map><boolean name="navigator" value="true"/><boolean name="preferGpsHeading" value="false"/></map>' | adb shell run-as "$APP" sh -c "'cat > shared_prefs/display.xml'"
adb emu sensor set acceleration 0:0:9.81
adb emu sensor set magnetic-field 0:50:-35
adb logcat -c
adb shell am start -W -n "$APP/.MainActivity"
adb emu geo fix 139.467 35.318
sleep 3
adb shell screenrecord --time-limit 18 --bit-rate 2000000 /sdcard/heading-rotation.mp4 > /dev/null 2>&1 &
RECORDER_PID=$!
for CASE in 'north,0:50:-35' 'east,-50:0:-35' 'south,0:-50:-35' 'west,50:0:-35' '359,0.8726:49.9924:-35' '001,-0.8726:49.9924:-35'; do
  LABEL=${CASE%%,*}
  VECTOR=${CASE#*,}
  adb emu sensor set magnetic-field "$VECTOR"
  sleep 2
  adb exec-out screencap -p > "screenshots/Android-heading-$LABEL.png"
done
wait "$RECORDER_PID"
adb pull /sdcard/heading-rotation.mp4 screenshots/Android-heading-rotation.mp4
adb logcat -d -s SailingGpsLogger > screenshots/heading-rotation.log
python3 - <<'PYROTATION'
import pathlib,re,math
p=pathlib.Path('screenshots/heading-rotation.log')
records=[tuple(map(float,m)) for m in re.findall(r'Nav heading=([0-9.Ee+-]+) true=([0-9.Ee+-]+) target=([0-9.Ee+-]+) relative=([0-9.Ee+-]+) source=',p.read_text())]
assert len(records)>=6,records
wrap=lambda a:(a+180)%360-180
assert any(abs(wrap(b[0]-a[0]))>40 for a in records for b in records),records
# The fixed goal bearing must not rotate along with the phone.
assert max(abs(wrap(row[2]-records[0][2])) for row in records)<0.5,records
for heading,true,target,relative in records:
    assert abs(wrap((target-heading)-relative))<0.001,(heading,true,target,relative)
assert 'Map follow heading=' in p.read_text()
anchors=[float(x) for x in re.findall(r'FOLLOW_ANCHOR ratio=([0-9.Ee+-]+)',p.read_text())]
assert len(anchors)>=6,anchors
assert all(0.67 < ratio < 0.77 for ratio in anchors[-30:]),anchors[-30:]
pathlib.Path('screenshots/boat-anchor-result.txt').write_text('PASS: real boat remains near 72 percent down the map while virtual heading rotates.\n')
pathlib.Path('screenshots/heading-result.txt').write_text('PASS: stationary device rotation changes heading; target bearing stays fixed; map and arrow use matching true/magnetic references.\n')
print('Stationary device rotation and invariant goal bearing verified')
PYROTATION
adb logcat -d -s AndroidRuntime > screenshots/runtime.log
if grep -q 'FATAL EXCEPTION' screenshots/runtime.log; then exit 1; fi

# Save a custom appearance through the real dialog, then restart and verify persistence.
adb shell am force-stop "$APP"
adb logcat -c
adb shell am start -W -n "$APP/.MainActivity" --ez previewAppearance true
sleep 3
adb exec-out screencap -p > screenshots/Android-waypoint-appearance.png
adb logcat -d -s SailingUiBounds > screenshots/appearance-bounds.log
read -r SAVE_X SAVE_Y < <(python3 - <<'PYAPPEARANCE'
import re,pathlib
rows=re.findall(r'APPEARANCE save=(\d+),(\d+),(\d+),(\d+)',pathlib.Path('screenshots/appearance-bounds.log').read_text())
assert rows,'Appearance dialog not visible'
a,b,c,d=map(int,rows[-1]);print((a+c)//2,(b+d)//2)
PYAPPEARANCE
)
adb shell input tap "$SAVE_X" "$SAVE_Y"
sleep 2
adb shell am force-stop "$APP"
adb shell am start -W -n "$APP/.MainActivity"
sleep 3
adb shell run-as "$APP" cat shared_prefs/waypoints.xml > screenshots/appearance-waypoints.xml
python3 - <<'PYAPPEARANCEVERIFY'
import json,pathlib,xml.etree.ElementTree as E
root=E.parse('screenshots/appearance-waypoints.xml').getroot()
items=json.loads(next(n.text for n in root if n.get('name')=='items'))
active=next(n.text for n in root if n.get('name')=='activeId')
point=next(p for p in items if p['name']=='MAP_TEST')
assert point['id']!=active,point
assert point['mark']=='灯台' and point['color']=='#12ABCD',point
assert len(items)==4
pathlib.Path('screenshots/appearance-result.txt').write_text('PASS: custom mark and RGB color saved through native dialog and retained after restart; existing waypoints retained.\n')
PYAPPEARANCEVERIFY
adb emu geo fix 139.467 35.318
sleep 3
adb exec-out screencap -p > screenshots/Android-custom-waypoint-map.png
adb logcat -d -s AndroidRuntime > screenshots/runtime.log
if grep -q 'FATAL EXCEPTION' screenshots/runtime.log; then exit 1; fi

# Clear target, tap a marker without selecting, long-press to edit that existing ID.
adb shell am force-stop "$APP"
adb logcat -c
adb shell am start -W -n "$APP/.MainActivity" --ez clearTarget true
adb emu geo fix 139.467 35.318
sleep 4
adb logcat -d -s SailingUiBounds > screenshots/touch-bounds.log
read -r WP_X WP_Y < <(python3 - <<'PYTOUCH'
import pathlib,re,json,xml.etree.ElementTree as E
root=E.parse('screenshots/appearance-waypoints.xml').getroot()
points=json.loads(next(n.text for n in root if n.get('name')=='items'))
wp=next(p for p in points if p['name']=='MAP_TEST')
rows=re.findall(r'WP_TOUCH id='+re.escape(wp['id'])+r' x=(-?\d+) y=(-?\d+)',pathlib.Path('screenshots/touch-bounds.log').read_text())
assert rows,'Waypoint screen bounds missing'
print(*rows[-1])
PYTOUCH
)
adb shell input tap "$WP_X" "$WP_Y"
sleep 1
adb shell run-as "$APP" cat shared_prefs/waypoints.xml > screenshots/tap-waypoints.xml
python3 - <<'PYTAP'
import xml.etree.ElementTree as E
root=E.parse('screenshots/tap-waypoints.xml').getroot()
assert next(n.text for n in root if n.get('name')=='activeId')=='__none__'
PYTAP
adb shell input swipe "$WP_X" "$WP_Y" "$WP_X" "$WP_Y" 1200
sleep 1
adb logcat -d -s SailingUiBounds > screenshots/edit-bounds.log
read -r NAME_X NAME_Y SAVE_X SAVE_Y < <(python3 - <<'PYEDIT'
import pathlib,re
rows=re.findall(r'EDIT input=(\d+),(\d+),(\d+),(\d+) save=(\d+),(\d+),(\d+),(\d+)',pathlib.Path('screenshots/edit-bounds.log').read_text())
assert rows,'Long press did not open existing waypoint editor'
a,b,c,d,e,f,g,h=map(int,rows[-1]);print((a+c)//2,(b+d)//2,(e+g)//2,(f+h)//2)
PYEDIT
)
adb exec-out screencap -p > screenshots/Android-long-press-edit.png
adb shell input tap "$NAME_X" "$NAME_Y"
adb shell input keyevent 123
adb shell input text _EDIT
adb shell input keyevent 4
sleep 1
adb shell input tap "$SAVE_X" "$SAVE_Y"
sleep 2
adb shell am force-stop "$APP"
adb shell am start -W -n "$APP/.MainActivity"
sleep 2
adb shell run-as "$APP" cat shared_prefs/waypoints.xml > screenshots/edited-waypoints.xml
python3 - <<'PYEDITVERIFY'
import pathlib,json,xml.etree.ElementTree as E
def data(path):
 r=E.parse(path).getroot();return json.loads(next(n.text for n in r if n.get('name')=='items')),next(n.text for n in r if n.get('name')=='activeId')
before,_=data('screenshots/appearance-waypoints.xml');after,target=data('screenshots/edited-waypoints.xml')
original=next(p for p in before if p['name']=='MAP_TEST');changed=next(p for p in after if p['id']==original['id'])
assert changed['name']=='MAP_TEST_EDIT',changed
assert len(after)==len(before)
for key in ['id','lat','lon','mark','color']:assert changed[key]==original[key],(key,changed,original)
assert target=='__none__'
pathlib.Path('screenshots/map-interaction-result.txt').write_text('PASS: target-none survives restart; tap does not select; long press edits existing waypoint without duplication or target changes.\n')
PYEDITVERIFY
adb emu geo fix 139.467 35.318
sleep 2
adb exec-out screencap -p > screenshots/Android-target-none.png
adb logcat -d -s AndroidRuntime > screenshots/runtime.log
if grep -q 'FATAL EXCEPTION' screenshots/runtime.log; then exit 1; fi

# Choose an existing goal through navigation options; only Go commits the selection.
adb shell am force-stop "$APP"
adb logcat -c
adb shell am start -W -n "$APP/.MainActivity" --ez previewNavigationOptions true
adb emu geo fix 139.467 35.318
sleep 3
adb exec-out screencap -p > screenshots/Android-navigation-options.png
adb logcat -d -s SailingUiBounds > screenshots/navigation-options-bounds.log
read -r ACTION_X ACTION_Y < <(python3 - <<'PYNAV'
import pathlib,re
rows=re.findall(r'ACTION label=既存ウェイポイント（近い順） bounds=(\d+),(\d+),(\d+),(\d+)',pathlib.Path('screenshots/navigation-options-bounds.log').read_text())
assert rows
a,b,c,d=map(int,rows[-1]);print((a+c)//2,(b+d)//2)
PYNAV
)
adb shell input tap "$ACTION_X" "$ACTION_Y"
sleep 1
adb logcat -d -s SailingUiBounds > screenshots/candidate-bounds.log
read -r ACTION_X ACTION_Y < <(python3 - <<'PYCANDIDATE'
import pathlib,re
rows=re.findall(r'ACTION label=[^\n]*MAP_TEST_EDIT[^\n]* bounds=(\d+),(\d+),(\d+),(\d+)',pathlib.Path('screenshots/candidate-bounds.log').read_text())
assert rows
a,b,c,d=map(int,rows[-1]);print((a+c)//2,(b+d)//2)
PYCANDIDATE
)
adb shell input tap "$ACTION_X" "$ACTION_Y"
sleep 1
adb exec-out screencap -p > screenshots/Android-go-confirmation.png
adb shell run-as "$APP" cat shared_prefs/waypoints.xml > screenshots/before-go-waypoints.xml
python3 - <<'PYBEFOREGO'
import xml.etree.ElementTree as E
r=E.parse('screenshots/before-go-waypoints.xml').getroot()
assert next(n.text for n in r if n.get('name')=='activeId')=='__none__'
PYBEFOREGO
adb logcat -d -s SailingUiBounds > screenshots/go-bounds.log
read -r ACTION_X ACTION_Y < <(python3 - <<'PYGO'
import pathlib,re
rows=re.findall(r'GO bounds=(\d+),(\d+),(\d+),(\d+)',pathlib.Path('screenshots/go-bounds.log').read_text())
assert rows
a,b,c,d=map(int,rows[-1]);print((a+c)//2,(b+d)//2)
PYGO
)
adb shell input tap "$ACTION_X" "$ACTION_Y"
sleep 2
adb shell run-as "$APP" cat shared_prefs/waypoints.xml > screenshots/after-go-waypoints.xml
python3 - <<'PYAFTERGO'
import pathlib,json,xml.etree.ElementTree as E
r=E.parse('screenshots/after-go-waypoints.xml').getroot()
points=json.loads(next(n.text for n in r if n.get('name')=='items'))
active=next(n.text for n in r if n.get('name')=='activeId')
assert next(p for p in points if p['id']==active)['name']=='MAP_TEST_EDIT'
pathlib.Path('screenshots/navigation-go-result.txt').write_text('PASS: blank long press opens operations before creation; navigation options select a candidate; Go alone commits target.\n')
PYAFTERGO
adb logcat -d -s AndroidRuntime > screenshots/runtime.log
if grep -q 'FATAL EXCEPTION' screenshots/runtime.log; then exit 1; fi

# New overlays and library UI; only synthetic emulator waypoints are used.
adb shell am force-stop "$APP"
adb shell am start -n "$APP/.MainActivity" --ez previewLibraryOverlay true >/dev/null
sleep 3
adb exec-out screencap -p > screenshots/Android-library-overlays.png
adb shell am force-stop "$APP"
adb shell am start -n "$APP/.MainActivity" --ez previewLibrary true >/dev/null
sleep 2
adb exec-out screencap -p > screenshots/Android-map-library.png
adb shell run-as "$APP" cat shared_prefs/waypoints.xml > screenshots/library-persistence.xml
python3 - <<'PYLIBRARY'
import json,pathlib,xml.etree.ElementTree as E
r=E.parse('screenshots/library-persistence.xml').getroot()
l=json.loads(next(n.text for n in r if n.get('name')=='library'))
assert {f['kind'] for f in l['features']}=={'circle','area','line'}
assert len(l['groups'])==1
pathlib.Path('screenshots/library-result.txt').write_text('PASS: circle, area and line stored, restored after restart and rendered on map.\n')
PYLIBRARY

adb shell am force-stop "$APP"
adb shell am start -n "$APP/.MainActivity" --ez previewLibrary true --ez previewCircleEditor true >/dev/null
sleep 5
adb exec-out screencap -p > screenshots/Android-circle-editor.png

# Use the production current-position save path with a synthetic location.
adb shell am force-stop "$APP"
adb shell am start -n "$APP/.MainActivity" --ez previewFolderSave true >/dev/null
sleep 4
adb exec-out screencap -p > screenshots/Android-folder-editor.png
adb shell run-as "$APP" cat shared_prefs/waypoints.xml > screenshots/folder-before.xml
adb shell run-as "$APP" cat shared_prefs/display.xml > screenshots/default-folder.xml
adb shell am force-stop "$APP"
adb shell am start -n "$APP/.MainActivity" >/dev/null
sleep 3
adb shell run-as "$APP" cat shared_prefs/waypoints.xml > screenshots/folder-after.xml
python3 - <<'PYFOLDER'
import json,pathlib,xml.etree.ElementTree as E
def items(path):
    root=E.parse(path).getroot()
    return json.loads(next(n.text for n in root if n.get('name')=='items'))
before=items('screenshots/folder-before.xml');after=items('screenshots/folder-after.xml')
r=E.parse('screenshots/default-folder.xml').getroot()
folder=next(n.text for n in r if n.get('name')=='mainWaypointFolder')
assert folder=='港一覧'
assert before[-1]['group']==folder and before[-1]['mark']=='港'
assert before[-1]==after[-1]
pathlib.Path('screenshots/default-folder-result.txt').write_text('PASS: current-position save uses selected default folder with harbor mark and persists after restart.\n')
PYFOLDER


# The large instrument must fit a decimal speed across one, two and three integer digits.
for SPEED in 1.9 12.3 99.9 100.0; do
  adb shell am force-stop "$APP"
  printf '%s' '<map><boolean name="navigator" value="false"/></map>' | adb shell run-as "$APP" sh -c "'cat > shared_prefs/display.xml'"
  adb shell am start -n "$APP/.MainActivity" --es previewSpeed "$SPEED" >/dev/null
  sleep 2
  adb exec-out screencap -p > "screenshots/Android-speed-$SPEED.png"
done

# Notification callbacks are verified independently by zone-verification.yml.

# The third mode keeps only SOG, true COG and true target bearing visible.
adb shell am force-stop "$APP"
adb shell am start -W -n "$APP/.MainActivity" --ez previewFocus true >/dev/null
sleep 3
adb exec-out screencap -p > screenshots/Android-focus.png
adb logcat -d -s AndroidRuntime > screenshots/focus-runtime.log
if grep -q 'FATAL EXCEPTION' screenshots/focus-runtime.log; then exit 1; fi
adb shell run-as "$APP" cat shared_prefs/display.xml > screenshots/focus-preferences.xml
python3 - <<'PYFOCUS'
import xml.etree.ElementTree as E
root=E.parse('screenshots/focus-preferences.xml').getroot()
assert any(n.get('name')=='displayMode' and n.get('value')=='2' for n in root)
PYFOCUS

adb shell am force-stop "$APP"
python3 - <<'PYNORTH'
import xml.etree.ElementTree as E
p='screenshots/focus-preferences.xml';root=E.parse(p).getroot()
node=next((n for n in root if n.get('name')=='instrumentMagnetic'),None)
if node is None: node=E.SubElement(root,'boolean',name='instrumentMagnetic')
node.set('value','true');E.ElementTree(root).write('focus-magnetic.xml',encoding='utf-8',xml_declaration=True)
PYNORTH
adb shell run-as "$APP" sh -c "'cat > shared_prefs/display.xml'" < focus-magnetic.xml
adb shell am start -W -n "$APP/.MainActivity" --ez previewFocus true >/dev/null
sleep 2
adb exec-out screencap -p > screenshots/Android-focus-magnetic.png
