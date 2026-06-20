#!/usr/bin/env python3
"""Copy the committed native files into the (gitignored, CI-regenerated) android/
tree and idempotently patch AndroidManifest.xml to declare the wallpaper service.
Run from flutter/ after `flutter create`. Safe to run repeatedly."""
import os
import shutil

HERE = os.path.dirname(os.path.abspath(__file__))
ANDROID = os.path.join(HERE, "..", "android", "app", "src", "main")
PKG = os.path.join("kotlin", "com", "pixelpomo", "pixel_pomo")


def copy_tree(rel):
    src = os.path.join(HERE, rel)
    dst = os.path.join(ANDROID, rel)
    for root, _dirs, files in os.walk(src):
        for f in files:
            s = os.path.join(root, f)
            d = os.path.join(dst, os.path.relpath(s, src))
            os.makedirs(os.path.dirname(d), exist_ok=True)
            shutil.copy2(s, d)
            print("copied", os.path.relpath(d, ANDROID))


def patch_manifest():
    path = os.path.join(ANDROID, "AndroidManifest.xml")
    with open(path, "r", encoding="utf-8") as fh:
        xml = fh.read()
    if "GardenWallpaperService" in xml:
        print("manifest already patched")
        return
    service = (
        '        <service\n'
        '            android:name=".GardenWallpaperService"\n'
        '            android:exported="true"\n'
        '            android:label="Pixel Pomo Garden"\n'
        '            android:permission="android.permission.BIND_WALLPAPER">\n'
        '            <intent-filter>\n'
        '                <action android:name="android.service.wallpaper.WallpaperService" />\n'
        '            </intent-filter>\n'
        '            <meta-data\n'
        '                android:name="android.service.wallpaper"\n'
        '                android:resource="@xml/garden_wallpaper" />\n'
        '        </service>\n'
    )
    if "    </application>" not in xml:
        raise SystemExit("apply_overlay: could not find </application> to patch")
    xml = xml.replace("    </application>", service + "    </application>", 1)
    feature = ('    <uses-feature android:name="android.software.live_wallpaper" '
               'android:required="false" />\n')
    if "android.software.live_wallpaper" not in xml:
        xml = xml.replace("    <application", feature + "    <application", 1)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(xml)
    print("patched manifest: wallpaper service + live_wallpaper feature")


def main():
    copy_tree(PKG)
    copy_tree(os.path.join("res", "xml"))
    copy_tree(os.path.join("res", "drawable"))
    patch_manifest()


if __name__ == "__main__":
    main()
