#!/usr/bin/env python3
"""Copy the committed native files into the (gitignored, CI-regenerated) android/
tree, idempotently patch AndroidManifest.xml to declare the wallpaper service, and
pin the release build to a stable debug keystore (so every CI build is
signed identically and in-place APK updates don't break with "package conflicts
with an existing package", #v30.2 — a fresh debug key was being auto-generated on
every ephemeral CI runner otherwise). That key is NOT in the repo — the repo is
public — so CI writes it from the ANDROID_DEBUG_KEYSTORE_B64 secret before this
runs; a local build without it falls back to Gradle's own per-machine debug key.
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


def copy_keystore():
    """Returns whether the shared key was there. Absent is normal on a machine
    that isn't CI: the build still runs, it just gets a per-machine key, which
    only matters for an APK meant to install over an existing one."""
    src = os.path.join(HERE, "debug.keystore")
    if not os.path.exists(src):
        print("no debug.keystore — Gradle will use its own per-machine debug key")
        return False
    dst = os.path.join(HERE, "..", "android", "app", "debug.keystore")
    shutil.copy2(src, dst)
    print("copied debug.keystore")
    return True


def patch_build_gradle():
    """Point the auto-generated `debug` signingConfig at our committed keystore
    (same standard alias/passwords Android tooling itself uses) instead of
    whatever debug.keystore Gradle would otherwise auto-generate per-machine —
    `buildTypes.release` already signs with `signingConfigs.debug`, so this is
    the only change needed for release builds to sign consistently."""
    path = os.path.join(HERE, "..", "android", "app", "build.gradle.kts")
    with open(path, "r", encoding="utf-8") as fh:
        kts = fh.read()
    if "debug.keystore" in kts:
        print("build.gradle.kts already patched (signing)")
        return
    marker = "    buildTypes {"
    if marker not in kts:
        raise SystemExit("apply_overlay: could not find buildTypes block to patch signing config")
    signing = (
        "    signingConfigs {\n"
        '        getByName("debug") {\n'
        "            storeFile = file(\"debug.keystore\")\n"
        '            storePassword = "android"\n'
        '            keyAlias = "androiddebugkey"\n'
        '            keyPassword = "android"\n'
        "        }\n"
        "    }\n\n"
    )
    kts = kts.replace(marker, signing + marker, 1)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(kts)
    print("patched build.gradle.kts: stable debug signing key")


PKG_NAME = "com.pixelpomo.pixel_pomo"


def patch_manifest(path=None):
    """Every component the overlay ships is declared by its FULL
    `com.pixelpomo.pixel_pomo.*` class name, never a relative `.Name` — the Kotlin
    files under `kotlin/` hardcode `package com.pixelpomo.pixel_pomo` regardless of
    which app they get copied into. A relative name resolves against the INSTALLED
    app's own applicationId, which only equals `com.pixelpomo.pixel_pomo` for the
    real app; for "Test Pixel Pomo" (applicationId `com.pixelpomo.test.pixel_pomo`)
    it names a class that doesn't exist there.

    That bit twice. #v31.19 fixed the three SERVICES. It missed the ACTIVITY —
    which `flutter create` emits as `.MainActivity`, so the test build launched
    the stock activity it generated at `com.pixelpomo.test.pixel_pomo.MainActivity`
    instead of ours. That stock activity registers no MethodChannel, so the
    wallpaper, blocker and timer channels were ALL dead on the test build while
    working on the real one — our MainActivity was compiled into the APK and
    simply never started (#v34.2).

    [path] is for the tests; production patches the generated tree.
    """
    if path is None:
        path = os.path.join(ANDROID, "AndroidManifest.xml")
    with open(path, "r", encoding="utf-8") as fh:
        xml = fh.read()
    if "    </application>" not in xml:
        raise SystemExit("apply_overlay: could not find </application> to patch")
    orig = xml

    # --- the launcher activity (#v34.2) ---
    if f'android:name="{PKG_NAME}.MainActivity"' not in xml:
        if 'android:name=".MainActivity"' not in xml:
            raise SystemExit("apply_overlay: could not find the .MainActivity declaration to patch")
        xml = xml.replace('android:name=".MainActivity"',
                          f'android:name="{PKG_NAME}.MainActivity"', 1)

    # --- live wallpaper service (#v15) ---
    if "GardenWallpaperService" not in xml:
        service = (
            '        <service\n'
            '            android:name="com.pixelpomo.pixel_pomo.GardenWallpaperService"\n'
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
        xml = xml.replace("    </application>", service + "    </application>", 1)
    feature = ('    <uses-feature android:name="android.software.live_wallpaper" '
               'android:required="false" />\n')
    if "android.software.live_wallpaper" not in xml:
        xml = xml.replace("    <application", feature + "    <application", 1)

    # --- app blocker accessibility service + permissions (#v23) ---
    if "AppBlockerService" not in xml:
        svc = (
            '        <service\n'
            '            android:name="com.pixelpomo.pixel_pomo.AppBlockerService"\n'
            '            android:exported="false"\n'
            '            android:label="Pixel Pomo App Blocker"\n'
            '            android:permission="android.permission.BIND_ACCESSIBILITY_SERVICE">\n'
            '            <intent-filter>\n'
            '                <action android:name="android.accessibilityservice.AccessibilityService" />\n'
            '            </intent-filter>\n'
            '            <meta-data\n'
            '                android:name="android.accessibilityservice"\n'
            '                android:resource="@xml/app_blocker_accessibility" />\n'
            '        </service>\n'
        )
        xml = xml.replace("    </application>", svc + "    </application>", 1)

    # --- focus-timer foreground service (#v23 fb) ---
    if "TimerService" not in xml:
        svc = (
            '        <service\n'
            '            android:name="com.pixelpomo.pixel_pomo.TimerService"\n'
            '            android:exported="false"\n'
            '            android:foregroundServiceType="specialUse">\n'
            '            <property\n'
            '                android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"\n'
            '                android:value="pomodoro_focus_timer" />\n'
            '        </service>\n'
        )
        xml = xml.replace("    </application>", svc + "    </application>", 1)
    for perm in ("android.permission.SYSTEM_ALERT_WINDOW", "android.permission.QUERY_ALL_PACKAGES",
                 "android.permission.POST_NOTIFICATIONS", "android.permission.FOREGROUND_SERVICE",
                 "android.permission.FOREGROUND_SERVICE_SPECIAL_USE"):
        if f'"{perm}"' not in xml:
            xml = xml.replace(
                "    <application",
                f'    <uses-permission android:name="{perm}" />\n    <application', 1)

    if xml != orig:
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(xml)
        print("patched manifest: wallpaper + app blocker")
    else:
        print("manifest already patched")


IOS_PLIST = os.path.join(HERE, "..", "ios", "Runner", "Info.plist")

# image_picker (the home wallpaper, #v32.4) reads the photo library; iOS kills an
# app that asks without a purpose string. Info.plist is generated by
# `flutter create` and never committed, so it has to be patched here like the
# Android manifest is.
PHOTO_PERMISSION = """	<key>NSPhotoLibraryUsageDescription</key>
	<string>Pick a photo to use as your Pixel Pomo home screen wallpaper.</string>
"""


def patch_ios_plist():
    """Add the photo-library purpose string. No-op off macOS, where there is no ios/."""
    if not os.path.exists(IOS_PLIST):
        print("no ios/Runner/Info.plist — skipping (android-only run)")
        return
    with open(IOS_PLIST, encoding="utf-8") as f:
        plist = f.read()
    if "NSPhotoLibraryUsageDescription" in plist:
        print("Info.plist already patched")
        return
    close = plist.rindex("</dict>")
    with open(IOS_PLIST, "w", encoding="utf-8") as f:
        f.write(plist[:close] + PHOTO_PERMISSION + plist[close:])
    print("patched Info.plist with NSPhotoLibraryUsageDescription")


def main():
    copy_tree(PKG)
    copy_tree(os.path.join("res", "xml"))
    copy_tree(os.path.join("res", "drawable"))
    has_keystore = copy_keystore()
    patch_manifest()
    if has_keystore:
        patch_build_gradle()
    patch_ios_plist()


if __name__ == "__main__":
    main()
