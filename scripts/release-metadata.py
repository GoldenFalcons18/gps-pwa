"""Create metadata for a signed APK. Signing credentials never enter this script."""
import hashlib
import json
import pathlib
import re
import sys

apk = pathlib.Path(sys.argv[1]).resolve()
properties = dict(re.findall(r'^(appVersion\w+)=(.+)$', pathlib.Path('android/gradle.properties').read_text(), re.M))
version = properties['appVersionName'].strip()
assert re.fullmatch(r'\d+\.\d+\.\d+', version)
assert apk.is_file() and apk.suffix == '.apk'
metadata = dict(schemaVersion=1, packageName='com.goldenfalcons.sailinggps',
                versionCode=int(properties['appVersionCode']), versionName=version,
                minSdk=26, apkFile=apk.name, sha256=hashlib.file_digest(apk.open('rb'), 'sha256').hexdigest())
apk.with_name('android-update.json').write_text(json.dumps(metadata, indent=2) + '\n', encoding='utf-8')
print('Release tag: android-v' + version)
