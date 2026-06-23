# v23 — App Blocker (Android) — Design

**Date:** 2026-06-23
**Version:** 0.23.0 (+24) → new `flutter-v23` release (local Android APK; macOS CI minutes still out → no iOS this round).
**Platform:** **Android only.** iOS has no public app-blocking API → the whole feature is hidden on iOS (`Platform.isAndroid`).

## Goal
Block a user-chosen set of apps during focus (WORK) sessions: opening a distracting app shows a full-screen
"stay focused" overlay instead of the app.

## Behaviour (decided via brainstorming)
- **Settings toggle "APP BLOCKER" (ON/OFF)** — applies live (like AUTO-START BREAK; no Save needed). Android-only.
- **Active window:** blocks only while a **WORK session timer is running** —
  `appBlockerEnabled && engine.isRunning && engine.mode == work && !engine.isFinished`. Inactive during BREAK, while
  paused, and when finished.
- **Block UX:** opening a blocked app raises a **full-screen overlay** (theme-coloured) reading "STAY FOCUSED" + a
  single **"BACK TO PIXEL POMO"** button that returns to the app. **Hard block** — no bypass on the overlay; to
  unblock, the user stops/RESETs the timer in-app or the session ends. Reopening the blocked app re-shows the overlay.
- **Never blocked:** Pixel Pomo itself and the device launcher (so "back" works and the phone stays usable).
- **Enable flow (per the user):** flipping the toggle ON **requests permission first**; once granted the blocker is on.
- **App picker (per the user):** Settings shows a **"BLOCKED APPS"** row; tapping it **opens a new screen** listing
  installed (launchable) apps (icon + label), each with a toggle; the chosen set persists.

## Architecture

### Flutter
- `AppStore` (store.dart):
  - `bool appBlockerEnabled` — persisted (key `app_blocker`).
  - `Set<String> blockedApps` — persisted (key `blocked_apps`, csv of package names).
  - `bool get blockerActive => appBlockerEnabled && engine.isRunning && engine.mode == Mode.work && !engine.isFinished;`
    (pure-derivable → unit-testable).
  - Whenever `blockerActive` / `blockedApps` change (session start/stop/pause, mode→break, settings), **publish to
    native**: write `blocker_active` (bool), `blocked_apps` (csv), `block_until` (epoch ms = the running WORK session's
    wall-clock end — a safety so a killed app can't block forever) to `SharedPreferences` (the Accessibility service
    reads them cross-process, like the wallpaper) and call the channel so a foreground service can react immediately.
  - Methods `setAppBlocker(bool)`, `setBlocked(String pkg, bool)` — called live from the UI.
- `lib/app_blocker.dart` — `MethodChannel('pixel_pomo/blocker')`:
  - `Future<List<AppInfo>> installedApps()` → `{package, label, iconPng?}` (icon optional/lazy).
  - `Future<bool> hasAccessibility()` · `Future<void> openAccessibilitySettings()`.
  - `Future<bool> hasOverlay()` · `Future<void> openOverlaySettings()`.
  - `Future<void> pushState(bool active, String blockedCsv, int blockUntil)`.
  - All wrapped in try/catch so iOS / MissingPlugin returns safe defaults (host-unit-testable).
- Settings (main.dart): an **Android-only** `APP BLOCKER` ON/OFF row (reuse the auto-break toggle widget) + a
  **`BLOCKED APPS`** `secondaryBtn` → `openPanel(... AppPickerScreen)`. Flipping ON runs the permission flow.
- `AppPickerScreen`: `FutureBuilder<List<AppInfo>>` over `installedApps()` → scrollable rows `[icon | label | toggle]`,
  toggling updates `blockedApps` live. (No search box in v1 — YAGNI; alphabetical list.)

### Native (`flutter/android_overlay/`)
- `AppBlockerService.kt` (`AccessibilityService`): on `TYPE_WINDOW_STATE_CHANGED`, read `event.packageName`; if
  `BlockerData.shouldBlock(pkg)` → show the overlay, else hide it. A periodic `Handler` tick also drops the overlay
  when the session ends (`block_until` passed or `active=false`) even if no new window event fires.
- `BlockerData.kt`: reads `app_blocker` / `blocked_apps` / `blocker_active` / `block_until` from
  `getSharedPreferences("FlutterSharedPreferences")` (the `flutter.` prefix, like `GardenData`).
  `shouldBlock(pkg) = active && now < blockUntil && pkg ∈ blockedSet && pkg != ourPackage && pkg != currentLauncher`.
- `BlockOverlayView`: a `TYPE_APPLICATION_OVERLAY` full-screen `WindowManager` view (Android views/Canvas, no Flutter):
  theme-coloured bg + "STAY FOCUSED" + a "BACK TO PIXEL POMO" button (launches `MainActivity`). Reads the theme colour
  from `flutter.theme_id` for consistency.
- `MainActivity.kt`: extend the existing channel setup with `pixel_pomo/blocker`: `installedApps` (PackageManager
  `queryIntentActivities` for LAUNCHER → package + label + small icon PNG), `hasAccessibility`,
  `openAccessibilitySettings`, `hasOverlay`, `openOverlaySettings`, `pushState`.
- `res/xml/app_blocker_accessibility.xml`: service config (`typeWindowStateChanged`, `feedbackGeneric`).
- `apply_overlay.py`: copy the new Kotlin + res; idempotently patch `AndroidManifest.xml` to add the
  `<service ...BIND_ACCESSIBILITY_SERVICE>` (+ its config meta-data), `SYSTEM_ALERT_WINDOW` and `QUERY_ALL_PACKAGES`
  uses-permission (sideloaded → QUERY_ALL_PACKAGES is fine). Mirror the existing wallpaper-patch style.

## Data flow
1. APP BLOCKER ON → check perms → if missing, prompt (open system settings) → once granted `appBlockerEnabled=true`,
   persist, `pushState`.
2. BLOCKED APPS → pick apps → `blockedApps` persist + `pushState`.
3. WORK session starts → `blockerActive=true`, `block_until = end ms` → `pushState`.
4. User opens a blocked app → `AppBlockerService` → `shouldBlock` true → overlay. "BACK TO PIXEL POMO" → MainActivity.
5. Session ends / break / pause / reset → `blockerActive=false` → `pushState`; service hides the overlay (or
   `block_until` elapses if the app was killed).

## Permissions / onboarding
- Required: **BIND_ACCESSIBILITY_SERVICE** (user enables the service in system Accessibility settings),
  **SYSTEM_ALERT_WINDOW** (draw over apps), **QUERY_ALL_PACKAGES** (list apps).
- Enable-time dialog: explains why each is needed + a button to open each settings page + a re-check. The toggle shows
  "needs permission" until both Accessibility + overlay are granted.

## Testing
- Pure Dart (CI gate): `blockerActive` derivation across engine states (running/paused × work/break × finished ×
  enabled/disabled); blocked-apps csv codec round-trip; `shouldBlock`-style never-block of own package/launcher (pure
  helper mirrored in Dart for the test).
- `app_blocker.dart` channel test (mock the channel, like `wallpaper_channel_test`).
- Smoke: Settings shows the APP BLOCKER toggle (Android path); tapping BLOCKED APPS opens the picker (mocked
  `installedApps`).
- Native (service / overlay / permissions / app list) → **device-verified** by the user (CI runs only `flutter test`).

## Out of scope (deferred)
- iOS blocking (no API). Scheduled hours / always-on / manual mode. Per-app time limits / usage insights.
- Removing the Settings SAVE button (toggles already apply live; the steppers keep Save).

## Delivery
- Version → **0.23.0+24**. Branch `v23-app-blocker` → main. Build release APK locally → upload to a new
  **`flutter-v23`** release. No iOS (macOS CI minutes out).
