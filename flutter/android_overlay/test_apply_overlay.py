"""Tests for the manifest patching in apply_overlay.py.

Run:  python -m unittest discover -s android_overlay -p 'test_*.py'   (from flutter/)

There is no Gradle/JUnit harness for the native side, so every earlier native
round was device-verified only — which is how the same class of bug shipped
three times. `patch_manifest` is plain Python, so it can be tested here, and the
thing it must guarantee is exactly what kept breaking: **every component the
overlay ships must resolve to the class the overlay actually copies in, for BOTH
applicationIds.**

The fixture is the real `flutter create` manifest, not a hand-written
approximation — the bug lives in what the generator emits.
"""
import os
import re
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import apply_overlay  # noqa: E402

# The class package hardcoded at the top of every Kotlin file under kotlin/.
PKG = "com.pixelpomo.pixel_pomo"

# Trimmed from the actual output of
#   flutter create --org <org> --project-name pixel_pomo --platforms=android .
# The `.MainActivity` is the point: a RELATIVE name, resolved by Android against
# the app's own applicationId.
GENERATED_MANIFEST = """<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="pixel_pomo"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
</manifest>
"""


def patched(manifest=GENERATED_MANIFEST):
    """Run the real patch_manifest over a throwaway copy and return the result."""
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "AndroidManifest.xml")
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(manifest)
        apply_overlay.patch_manifest(path)
        with open(path, encoding="utf-8") as fh:
            return fh.read()


class ComponentNamesAreAbsolute(unittest.TestCase):
    """A relative name resolves against the INSTALLED app's applicationId, which
    is `com.pixelpomo.pixel_pomo` for the real app and `com.pixelpomo.test.pixel_pomo`
    for Test Pixel Pomo. The Kotlin files are the same in both APKs and always
    declare `package com.pixelpomo.pixel_pomo`, so anything left relative points
    at a class that does not exist in the test build."""

    def test_the_launcher_activity_is_the_one_the_overlay_ships(self):
        # THE #v34.2 BUG. `.MainActivity` resolved to
        # com.pixelpomo.test.pixel_pomo.MainActivity in the test app — the stock
        # activity flutter create wrote, which registers no MethodChannel. Our
        # MainActivity was compiled into the APK and never launched, so the
        # wallpaper, blocker and timer channels were all dead there.
        xml = patched()
        self.assertNotIn('android:name=".MainActivity"', xml,
                         "the activity is still relative — the test build launches the stock one")
        self.assertIn(f'android:name="{PKG}.MainActivity"', xml)

    def test_every_service_is_absolute_too(self):
        # #v31.19 fixed these; nothing pinned them afterwards.
        xml = patched()
        for svc in ("GardenWallpaperService", "AppBlockerService", "TimerService"):
            self.assertIn(f'android:name="{PKG}.{svc}"', xml, f"{svc} is not absolute")
        self.assertNotRegex(xml, r'android:name="\.\w+Service"')

    def test_no_component_anywhere_is_left_relative(self):
        # The general rule, so a component added later cannot regress quietly.
        xml = patched()
        relative = re.findall(r'android:name="(\.[^"]+)"', xml)
        self.assertEqual(relative, [], f"relative component names left in manifest: {relative}")


class PatchingIsSafeToRepeat(unittest.TestCase):
    """CI runs apply_overlay once, but it is documented as safe to re-run, and a
    local run after a `flutter create` is the normal repair path."""

    def test_running_twice_changes_nothing_the_second_time(self):
        once = patched()
        twice = patched(once)
        self.assertEqual(once, twice)

    def test_exactly_one_activity_and_three_services(self):
        xml = patched(patched())
        self.assertEqual(xml.count("<activity"), 1)
        self.assertEqual(xml.count("<service"), 3)

    def test_the_launcher_intent_filter_survives(self):
        # Rewriting the activity name must not disturb what makes it launchable.
        xml = patched()
        self.assertIn("android.intent.action.MAIN", xml)
        self.assertIn("android.intent.category.LAUNCHER", xml)


if __name__ == "__main__":
    unittest.main()
