# 📓 Change Log

A running record of what changed in each prompt / iteration. Newest entries on top.
Each entry notes the **prompt** (what you asked for) and the **changes** made.

---

## v0.1.1 — Edge-case tests + logic refactor
**Date:** 2026-06-14

**Prompt:** Do edge testing after every change, create a testing doc, and fix any bugs.

**Changes:**
- Extracted all timer logic into a pure, framework-free **`PomodoroEngine`** state
  machine; `MainActivity` now only drives `CountDownTimer` and renders engine state.
- Added **13 JUnit edge-case unit tests** (`PomodoroEngineTest`), all passing —
  start/pause/reset/switch, phase-finish + round counting, time formatting
  (round-up, zero-pad), and progress/time clamping.
- **Hardening surfaced by the tests:** `start()` no-ops at 0; `setTimeLeft()` clamps
  to `[0, duration]`; `progressPercent()` clamps to `0..100`; the old timer is
  cancelled before a new one starts (no double timers).
- **CI now runs the unit tests before building** — a failing test blocks the APK —
  and uploads the test report as an artifact.
- Added **`TESTING.md`** (strategy, covered cases, known gaps, per-change checklist).
  Bumped to versionCode 2 / versionName 0.1.1.

**APK:** Releases → "Latest debug build" (rebuilt only after tests pass).

**Notes:** Known gaps to tackle later — Activity-recreation state restore, true
background timing (foreground service), instrumented UI tests.

---

## v0.1.0 — Initial scaffold
**Date:** 2026-06-14

**Prompt:** Create a private repo `pixel_pomo`. Build a pixel-style Pomodoro app for
Android. Add a change log, a recreation prompt, and a README describing the structure.
After every change, produce a downloadable APK for testing on Android.

**Changes:**
- Created the full native-Android (Kotlin) project skeleton.
- Implemented the first working timer screen (`MainActivity.kt` + `activity_main.xml`):
  - WORK (25:00) / BREAK (5:00) phases.
  - START / PAUSE / RESET controls and a manual **SWITCH MODE** button.
  - Round counter; auto-switch + toast when a phase finishes.
- Pixel-art styling: bundled the **Press Start 2P** font, retro color palette
  (`colors.xml`), hard-edged drop-shadow buttons and a chunky progress bar
  (`drawable/*.xml`), and a blocky pixel-tomato adaptive launcher icon.
- Set up **GitHub Actions** (`.github/workflows/build-apk.yml`) to build a debug APK
  on every push and publish it to the **`latest`** release for easy phone download.
- Added `README.md` (structure + how to grab the APK), this `log.md`, and `prompt.md`
  (a self-contained spec to recreate the project elsewhere).
- Generated the **Gradle wrapper** (committed) and **verified the debug APK builds
  locally** (~5.5 MB) before the first push.

**APK:** Available from the repo's **Releases → "Latest debug build" → `pixel_pomo-debug.apk`**
once the first GitHub Actions run finishes.

**Notes / next ideas:**
- Sound + vibration on phase end (needs `VIBRATE` permission).
- Adjustable durations and long-break-every-4-rounds.
- Settings screen and a persistent foreground-service timer so it survives backgrounding.
- Nicer hand-drawn pixel launcher icon.

---

<!--
Template for new entries — copy this above when we make changes:

## vX.Y.Z — Short title
**Date:** YYYY-MM-DD

**Prompt:** (what was requested)

**Changes:**
- ...

**APK:** Releases → "Latest debug build".
-->
