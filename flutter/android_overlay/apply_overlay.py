#!/usr/bin/env python3
"""Copy the committed native files into the (gitignored, CI-regenerated) android/
tree, idempotently patch AndroidManifest.xml to declare the wallpaper service, and
pin the release build to a stable, committed debug keystore (so every CI build is
signed identically and in-place APK updates don't break with "package conflicts
with an existing package", #v30.2 — a fresh debug key was being auto-generated on
every ephemeral CI runner otherwise).
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
    src = os.path.join(HERE, "debug.keystore")
    dst = os.path.join(HERE, "..", "android", "app", "debug.keystore")
    shutil.copy2(src, dst)
    print("copied debug.keystore")


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


def patch_manifest():
    """All three services below are declared by their FULL `com.pixelpomo.pixel_pomo.*`
    class name, never a relative `.ServiceName` — the Kotlin files under `kotlin/`
    hardcode `package com.pixelpomo.pixel_pomo` regardless of which app they get
    copied into. A relative name resolves against the CALLING app's own manifest
    `package`, which only equals `com.pixelpomo.pixel_pomo` for the real app; for
    "Test Pixel Pomo" (applicationId `com.pixelpomo.test.pixel_pomo`) it resolved to
    a class that doesn't exist, so the service could never be found — the live
    wallpaper (and app blocker, and the timer notification) silently failed to set
    on the Test build while working fine on the real one (#v31.19)."""
    path = os.path.join(ANDROID, "AndroidManifest.xml")
    with open(path, "r", encoding="utf-8") as fh:
        xml = fh.read()
    if "    </application>" not in xml:
        raise SystemExit("apply_overlay: could not find </application> to patch")
    orig = xml

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


def main():
    copy_tree(PKG)
    copy_tree(os.path.join("res", "xml"))
    copy_tree(os.path.join("res", "drawable"))
    copy_keystore()
    patch_manifest()
    patch_build_gradle()


if __name__ == "__main__":
    main()
