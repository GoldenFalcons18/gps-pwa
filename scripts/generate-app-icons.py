"""Generate shared sailing/GPS launcher artwork. Requires Pillow."""
from pathlib import Path
from PIL import Image, ImageDraw
import json, math

ROOT = Path(__file__).resolve().parents[1]
NAVY = "#071B2B"

def artwork(size, transparent=False):
    scale = 3
    image = Image.new("RGBA", (1024 * scale, 1024 * scale), (0, 0, 0, 0) if transparent else NAVY)
    draw = ImageDraw.Draw(image)
    def box(values): return tuple(round(x * scale) for x in values)
    def polygon(points, color): draw.polygon([(int(x*scale), int(y*scale)) for x,y in points], fill=color)
    draw.ellipse(box((188,188,836,836)), outline="#3CC7F5", width=18*scale)
    draw.ellipse(box((733,210,797,274)), fill="#FFAA00")
    polygon([(500,286),(326,594),(500,594)], "#FFFFFF")
    polygon([(550,376),(690,594),(550,594)], "#3CC7F5")
    draw.line(box((524,270,524,632)), fill="#FFAA00", width=18*scale)
    polygon([(303,632),(721,632),(666,707),(366,707)], "#FFFFFF")
    wave=[(x,754+12*math.sin((x-302)*math.pi/104)) for x in range(302,723)]
    draw.polygon([(int(x*scale),int((y-8)*scale)) for x,y in wave] + [(int(x*scale),int((y+8)*scale)) for x,y in reversed(wave)], fill="#3CC7F5")
    return image.resize((size,size),Image.Resampling.LANCZOS)

def save(image,path):
    path.parent.mkdir(parents=True,exist_ok=True)
    image.save(path)

for density,size in [("mdpi",48),("hdpi",72),("xhdpi",96),("xxhdpi",144),("xxxhdpi",192)]:
    for name in ["ic_launcher","ic_launcher_round"]:
        save(artwork(size).convert("RGB"),ROOT/f"android/app/src/main/res/mipmap-{density}/{name}.png")
    save(artwork(round(size*108/48),True),ROOT/f"android/app/src/main/res/mipmap-{density}/ic_launcher_foreground.png")
for version in ["v26","v33"]:
    folder=ROOT/f"android/app/src/main/res/mipmap-anydpi-{version}"
    folder.mkdir(parents=True,exist_ok=True)
    mono='<monochrome android:drawable="@drawable/ic_launcher_monochrome" />' if version=="v33" else ''
    xml=f'''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    {mono}
</adaptive-icon>
'''
    for name in ["ic_launcher","ic_launcher_round"]: (folder/f"{name}.xml").write_text(xml,encoding="utf-8")
assets=ROOT/"ios/SailingGPS/Assets.xcassets"
assets.mkdir(parents=True,exist_ok=True)
(assets/"Contents.json").write_text(json.dumps({"info":{"author":"xcode","version":1}}),encoding="utf-8")
icon=assets/"AppIcon.appiconset"
save(artwork(1024).convert("RGB"),icon/"AppIcon.png")
(icon/"Contents.json").write_text(json.dumps({"images":[{"filename":"AppIcon.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}},indent=2),encoding="utf-8")
