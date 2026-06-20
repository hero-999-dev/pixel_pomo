# Pixel Pomo — Animated Live Wallpaper (Android) Design

**Date:** 2026-06-20
**Status:** approved (brainstorming) — ready for implementation plan
**Feature:** the long-deferred true animated Android live wallpaper. A native `WallpaperService`
renders the user's actual garden, at the camera angle they framed, gently animated, on their home screen.

## Goal

One sentence: **let the user frame the garden at any angle in camera mode and set *that* view as a real,
animated Android live wallpaper that reflects the garden they planted.**

## Decisions (locked in brainstorming)

- **Fidelity:** the wallpaper shows the user's *real* garden (reads the same saved data) and is *animated*
  (swaying plants, drifting critters, parallax) — not a generic scene, not a frozen snapshot.
- **Render approach: A1 — native Kotlin Canvas.** A `WallpaperService` re-renders a calm version of the
  garden in pure Android Canvas. We do **not** embed a Flutter engine (no supported API for rendering into a
  wallpaper surface; fragile across the moving `stable` channel; heavy in a background process; untestable here).
- **Honors the chosen angle:** the wallpaper reproduces the **yaw + zoom + pan** the user framed in camera
  mode (so the native renderer ports the projection math, including yaw — more than a fixed-framing version).
- **Entry point:** **camera mode** in the Garden screen. Bottom actions become **SET LIVE WALLPAPER ·
  CAPTURE · CANCEL**. SET LIVE WALLPAPER uses the current framing; CAPTURE stays for the frozen Save/Share still.
- **Retire the static wallpaper:** remove `wallpaper_manager_flutter`, `setPhoneWallpaper`, and the static
  "SET AS LIVE WALLPAPER" option in the post-CAPTURE dialog.
- **Android-only:** iOS has no live-wallpaper API; the SET LIVE WALLPAPER action is hidden on iOS (which keeps
  Save/Share). The no-Mac CI is unaffected (native code is Android-only and restored after `flutter create`).

## Global constraints (copied from the project)

- CI (`.github/workflows/build-flutter.yml`, macOS runner) regenerates `android/` + `ios/` with
  `flutter create`, then `git checkout -- pubspec.yaml lib` restores committed Dart. **`android/` is
  gitignored**, so native files must live in a committed overlay and be copied/patched in by a CI step.
- Flutter 3.44.2 / Dart 3.12.2; `flutter analyze` + `flutter test` gate the build.
- App id `com.pixelpomo.pixel_pomo`; Kotlin sources under
  `android/app/src/main/kotlin/com/pixelpomo/pixel_pomo/`.
- Pure logic stays framework-free in `lib/logic.dart`. No `Co-Authored-By` trailer. English throughout.

## Architecture

```
 Garden screen (camera mode)                 Android system
 ───────────────────────────                 ──────────────
 frame angle (yaw/zoom/pan)
        │ tap SET LIVE WALLPAPER
        ▼
 AppStore.setWallpaperCamera(...)  ──►  SharedPreferences  ◄──┐ (same file)
        │  persists framing + (garden, theme already there)   │
        ▼                                                      │
 MethodChannel "pixel_pomo/wallpaper".setLiveWallpaper         │
        │                                                      │
        ▼                                                      │
 MainActivity (native): fire ACTION_CHANGE_LIVE_WALLPAPER ─► system preview ─► user confirms
                                                               │
                                                               ▼
                                              GardenWallpaperService.Engine
                                                - reads garden + theme + framing  ─┘
                                                - loads sprite PNGs from assets
                                                - Choreographer render loop (paused when hidden)
                                                - parallax on onOffsetsChanged
```

**Data bridge (no duplication of state or art):**
- The app already persists the garden codec under pref key `garden` and theme under `theme_id`
  (`lib/store.dart`). Flutter's `shared_preferences` on Android writes the `FlutterSharedPreferences` XML with
  a `flutter.` prefix, so native reads `flutter.garden`, `flutter.theme_id`, and the new `flutter.wallpaper_cam`.
- Sprite PNGs are bundled Flutter assets, reachable natively via
  `AssetManager.open("flutter_assets/assets/objects/<id>.png")`.

## Components

### Native (committed in `flutter/android_overlay/`, copied into `android/` by CI)

- **`kotlin/.../GardenWallpaperService.kt`** — `WallpaperService` + inner `Engine`. Owns the Choreographer
  render loop, visibility gating (stop when hidden — battery), parallax offset from `onOffsetsChanged`, and
  re-reads the saved garden/theme/framing in `onVisibilityChanged(true)`. Draws each frame to the locked
  `Canvas`.
- **`kotlin/.../GardenRenderer.kt`** — pure-ish drawing: a Kotlin port of the *simplified* projection
  (oblique + `kVy` squash + **yaw** + zoom + pan, mirroring `Projector`/`GardenCamera` math — no 3D fence
  mesh) and the scene paint order: forest floor → bounded forest border props → grass clearing → roads (flat)
  → planted flowers as swaying billboards (depth-sorted, contact-shadowed) → 1–2 drifting critters. Fences
  render as simple flat thumbnail billboards (not the 3D mesh).
- **`kotlin/.../GardenData.kt`** — reads `FlutterSharedPreferences` (`flutter.garden`, `flutter.theme_id`,
  `flutter.wallpaper_cam`), parses the garden codec (a Kotlin mirror of `Garden.decode`: `cols×rows`, index
  `r*cols+c`, `ground`/`prop` layers, `road+fence` composite), maps theme id → colors, and lazily decodes
  sprite `Bitmap`s from `flutter_assets`.
- **`kotlin/.../MainActivity.kt`** — overwrites the generated `MainActivity`; in `configureFlutterEngine`
  registers `MethodChannel("pixel_pomo/wallpaper")` with `setLiveWallpaper` (fires
  `WallpaperManager.ACTION_CHANGE_LIVE_WALLPAPER` with `EXTRA_LIVE_WALLPAPER_COMPONENT` =
  `ComponentName(this, GardenWallpaperService::class.java)`; falls back to `ACTION_LIVE_WALLPAPER_CHOOSER`)
  and `isActive` (is our service the current wallpaper).
- **`res/xml/garden_wallpaper.xml`** — wallpaper descriptor (thumbnail, literal label/description; no settings
  activity in v1).
- **`res/drawable/wallpaper_thumb.png`** — chooser thumbnail; reuse the existing launcher tomato
  (`assets/icon/app_icon.png`) to avoid new art.
- **`apply_overlay.py`** — copies the overlay files into the generated `android/` tree and **idempotently
  patches** `AndroidManifest.xml` (inserts the `<service …BIND_WALLPAPER>` + `<meta-data>` before
  `</application>` only if absent; adds `<uses-feature android:name="android.software.live_wallpaper"
  android:required="false"/>`). Patching (not overwriting) so it coexists with `flutter create` + the
  launcher-icon step.

### Dart

- **`lib/camera.dart`** — add `Future<void> setLiveWallpaper()` (invokes the `pixel_pomo/wallpaper` channel,
  Android only). **Remove** `setPhoneWallpaper` + the `wallpaper_manager_flutter` import.
- **`lib/store.dart`** — add `setWallpaperCamera(double yaw, double zoom, double panXFrac, double panYFrac)`
  persisting `wallpaper_cam` (a compact `"yaw,zoom,panXFrac,panYFrac"` string; pan stored normalized so it
  reproduces across the camera-preview vs. wallpaper surface sizes). New pref key `_kWallpaperCam`.
- **`lib/engine/garden_view.dart`** — let the parent read the live camera framing: accept an optional
  parent-owned `GardenCamera camera` (use it instead of creating an internal one when provided), so
  `_GardenScreenState` can read `yaw/zoom/pan` at the moment SET LIVE WALLPAPER is tapped.
- **`lib/main.dart`** (`_GardenScreenState`) — camera-mode bottom bar becomes **SET LIVE WALLPAPER ·
  CAPTURE · CANCEL** (SET LIVE WALLPAPER hidden on iOS). The handler reads the framing, calls
  `s.setWallpaperCamera(...)`, then `setLiveWallpaper()`. The post-CAPTURE dialog drops the static-wallpaper
  option (Save/Share only).
- **`pubspec.yaml`** — drop `wallpaper_manager_flutter`.
- **`lib/strings.dart`** — repurpose/keep `setLiveWallpaper` label; add any new strings (e.g. a "framing
  saved" / chooser hint) in all six languages.

## What the wallpaper renders (the simplified scene)

A fixed, calm, ambient view — *not* an interactive copy of the engine:
- **Forest floor** base fill, then the **bounded forest world** (the `kForestBorder` ring of tree/bush/rock
  props from `forestPropAt`) framing the **grass clearing**, then the user's **planted flowers** as upright
  billboards that sway with a slow sine, depth-sorted back-to-front, each with a soft contact shadow.
- **Roads** drawn flat on the ground; **fences** drawn as flat thumbnail billboards (no 3D mesh in v1).
- **1–2 critters** (bee/butterfly) drift across slowly.
- **Camera:** reproduces the saved `yaw/zoom/pan` (and `kVy` tilt) so it matches the angle the user framed.
- **Parallax:** `onOffsetsChanged` nudges the scene horizontally as the user swipes home screens.
- **Performance:** ~30 fps cap; the loop **stops entirely when the wallpaper isn't visible**; bitmaps decoded
  once and cached.

## Data flow (set + render)

1. Camera mode: user frames an angle. Taps **SET LIVE WALLPAPER**.
2. `_GardenScreenState` reads the live `GardenCamera` (yaw/zoom/pan), calls `s.setWallpaperCamera(...)`
   (persists `wallpaper_cam`), then `setLiveWallpaper()`.
3. Native `MainActivity` fires `ACTION_CHANGE_LIVE_WALLPAPER` for `GardenWallpaperService` → system preview.
4. User confirms → system binds the service, creates an `Engine`.
5. `Engine` loads sprites (once), reads `garden`/`theme_id`/`wallpaper_cam`, builds the scene, starts the loop.
6. `onVisibilityChanged(true)` → re-read prefs (pick up new plantings / re-framing) + resume; `(false)` → stop.
7. `onOffsetsChanged` → store the parallax offset for the next frame.

## Error handling / edge cases

- **No saved garden / parse failure** → render an empty grass clearing + forest at the base size; never crash
  the wallpaper.
- **Missing `wallpaper_cam`** → use a sensible default framing (centered, no yaw, fit zoom).
- **Missing sprite** → skip that prop.
- **`ACTION_CHANGE_LIVE_WALLPAPER` unsupported** (rare OEM) → fall back to `ACTION_LIVE_WALLPAPER_CHOOSER`;
  if that also fails, the channel returns an error and Dart shows a localized "couldn't open wallpaper picker".
- **Preview engine** (`isPreview`) → render normally; ignore parallax.
- **Theme id unknown** → default theme colors.
- No runtime permission is needed (the system chooser handles consent; the `<service>` declares
  `BIND_WALLPAPER` so only the system binds it).

## CI / build integration

- New committed dir `flutter/android_overlay/` (the files above) + `apply_overlay.py`.
- New workflow step in `build-flutter.yml`, **after** "Scaffold platform projects": run
  `python android_overlay/apply_overlay.py` (working-directory `flutter`). It copies the Kotlin/res files and
  patches the manifest. Idempotent, so local runs are safe too.
- The launcher-icon step is unaffected (it edits res/mipmap + the `<application android:icon>` attr; our patch
  only inserts a `<service>`).
- Locally: `android/` persists between builds, so `apply_overlay.py` is run once (or re-run after a fresh
  `flutter create`); the debug APK then carries the wallpaper.

## Testing

- The render is **visual / device-verified** (same as the whole garden; headless `toImage` hangs here).
- **Gate-able (Dart, in `flutter test`):**
  - `camera.setLiveWallpaper()` invokes the `pixel_pomo/wallpaper` channel with method `setLiveWallpaper`
    (mock the `MethodChannel`; assert the call). Android-only guard covered.
  - `store.setWallpaperCamera(...)` persists a well-formed `wallpaper_cam` string and round-trips
    (parse back to the same 4 values).
  - The existing **garden codec** round-trip tests pin the exact format the Kotlin `GardenData` parser mirrors
    (the contract the native side depends on) — note this dependency in `TESTING.md`.
  - The widget **smoke test** stays green: camera mode now has three actions; assert SET LIVE WALLPAPER
    renders (the tap itself opens a system intent, so the test asserts presence, not the intent).
- **Not gated (documented):** the native Kotlin renderer/codec mirror and the on-device wallpaper-set flow are
  verified on the user's phone (the no-Mac CI runs `flutter test` only, not Gradle/JUnit).

## Scope / explicitly out (YAGNI)

- **No iOS** (no API). **No per-wallpaper settings screen.** **No 3D fence meshes / day-night / weather** in
  the wallpaper v1 — a calm ambient scene at the chosen angle is the deliverable.
- No lock-screen-specific handling beyond what the system chooser offers.
- No live "push" from app to wallpaper — the wallpaper re-reads prefs on visibility, which is enough.

## File summary

**Create (committed overlay + script):**
- `flutter/android_overlay/kotlin/com/pixelpomo/pixel_pomo/GardenWallpaperService.kt`
- `flutter/android_overlay/kotlin/com/pixelpomo/pixel_pomo/GardenRenderer.kt`
- `flutter/android_overlay/kotlin/com/pixelpomo/pixel_pomo/GardenData.kt`
- `flutter/android_overlay/kotlin/com/pixelpomo/pixel_pomo/MainActivity.kt`
- `flutter/android_overlay/res/xml/garden_wallpaper.xml`
- `flutter/android_overlay/res/drawable/wallpaper_thumb.png`
- `flutter/android_overlay/apply_overlay.py`

**Modify:**
- `flutter/lib/camera.dart` (add `setLiveWallpaper`, remove `setPhoneWallpaper`)
- `flutter/lib/store.dart` (`setWallpaperCamera` + `_kWallpaperCam`)
- `flutter/lib/engine/garden_view.dart` (optional parent-owned `GardenCamera`)
- `flutter/lib/main.dart` (camera-mode actions; drop static-wallpaper dialog option)
- `flutter/lib/strings.dart` (labels, 6 languages)
- `flutter/pubspec.yaml` (drop `wallpaper_manager_flutter`)
- `.github/workflows/build-flutter.yml` (apply-overlay step)
- docs: `log.md`, `prompt.md`, `README.md`, `flutter/README.md`, `TESTING.md`

**Delete:** the `wallpaper_manager_flutter` dependency and `setPhoneWallpaper`.
