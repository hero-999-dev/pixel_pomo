# 📓 Change Log

A running record of what changed in each prompt / iteration. Newest entries on top.
Each entry notes the **prompt** (what you asked for) and the **changes** made.

---

## iOS step — Flutter cross-platform port (v0.5.0 parity)
**Date:** 2026-06-15

**Prompt:** "do the next step for ios."

**What landed:** a new **`flutter/`** project — a single **Dart codebase** that builds **both** an
Android APK and an **unsigned iOS `.ipa`**, finally covering iPhone. Faithful port of v0.5.0:
- `lib/logic.dart` — pure port of `PomodoroEngine`, `Themes` (5), `Flowers` (10, 6-lang names),
  `Economy`, `Garden`, `Labels`, `LabelColors`, `Stats*`, `TestData` (shares the Kotlin edge cases).
- `lib/strings.dart` — the six UI languages (en/tr/pl/de/ko/it) + localized month names.
- `lib/store.dart` — `AppStore` (`ChangeNotifier`): all state, `shared_preferences` persistence,
  and a wall-clock countdown; first-launch test fixture (+1000 coins + sample history).
- `lib/pixel.dart` — pixel button / progress / swatch widgets, flower-sprite + **bar/line/pie**
  chart painters. `lib/main.dart` — timer screen + theme/garden/stats/settings/shop/label overlays.
- `test/logic_test.dart` — Dart edge tests that gate the Flutter CI.

**CI:** new **`.github/workflows/build-flutter.yml`** runs on a **macOS runner**: it `flutter
create`s the `ios/`+`android/` scaffolding (those aren't committed — only the portable
`lib/`/`pubspec`/`assets`/`test` are), restores our files, runs tests, builds the APK and an
**`flutter build ios --no-codesign`**, zips an unsigned **`.ipa`**, and publishes both to a
**`latest-flutter`** prerelease. The iOS `.ipa` is **sideloaded via SideStore/AltStore** (signs
on-device — no Mac needed by the user). The Flutter Android app uses app id
`com.pixelpomo.pixel_pomo`, so it coexists with the native `com.pixelpomo.app` build for A/B
testing on the phone. The native Android pipeline (`0v0X_pixelpomo` on `latest`) is unchanged.

**Note:** Flutter isn't installed locally, so the macOS CI run is the first real compile/build —
expect to iterate on any build errors via the workflow logs.

---

## v0.5.0 — Garden, 6 languages, stats charts, label colors
**Date:** 2026-06-15

**Prompt (v4 follow-up, items #9–#10):** v4 missed things — add the **garden** (a 2D square
map, free 4×4, left-corner upgrade) and a **garden section** at the top; seed **1000 test
coins** + example study data so the mechanics can be tested; finish **languages** (en/tr/pl/de/
ko/it) and make **flower names** localized (not one language); after every prompt make a new
version then an iOS version (iOS = Flutter port, deferred to next turn — see below). Also: move
the **coin icon to the right corner with the count beside it at the settings-icon height**; in
**stats**, put **bar / line / pie charts** above the numbers with a **per-option chart-style
picker** and a **month selector** to trace back through past months/years; seed specific study
totals (today 360, week 700, month 1000, plus 2025 + earlier 2026 months); and let users
**choose a color per label** that drives the **graph colors**.

**Changes:**
- **Garden (#7, #9):** new **GARDEN** overlay (top-left flower icon) showing a square grid —
  free **4×4** for everyone. **CUSTOMIZE** mode lets you tap a tile to **plant** a flower you
  own (picker lists remaining count) or **clear** it; planted flowers render as pixel sprites on
  the map. The **UPGRADE** button (top-left of the garden) grows the grid one ring for the
  new-tile count in coins (`Economy.upgradeCost`: 5×5 = 9, 6×6 = 11, … capped at 8×8). Pure
  model in **`Garden.kt`** (immutable `plant`/`clear`/`grow` + `GardenCodec`), persisted.
- **Languages (#6):** a **LANGUAGE** picker in Settings — **English / Türkçe / Polski / Deutsch /
  한국어 / Italiano** — applied instantly via **`LocaleManager`** (wraps the context locale in
  `attachBaseContext`; selecting recreates the Activity). Full translated `values-tr/pl/de/ko/it`
  string sets. Korean falls back to the system font (the pixel font has no Hangul glyphs).
- **Localized flowers (#9):** `Flower.names` now carries all six languages; the shop and garden
  show `flower.nameIn(lang)` (rose/gül/róża/rose/장미/rosa, …).
- **Stats charts + month nav (#10):** above the totals, a **month navigator** (◀ ▶, won't browse
  the future) and a **BAR / LINE / PIE** style picker drive a custom **`ChartView`** — BAR/PIE
  plot per-label minutes (in each label's color), LINE plots the month's per-day minutes. The
  **by-label** breakdown is now **per selected month**, each row with a color swatch. New
  month-scoped helpers in `Stats.kt` (`monthTotal`, `byLabelInMonth`, `dailySeries`).
- **Label colors (#10):** each label row gains a **● color swatch** opening a palette dialog;
  the choice (**`LabelColors`** + codec, persisted) recolors the chip list, the per-label rows,
  and every chart series.
- **Coin counter (#10):** icon bumped to the **settings-icon height (32dp)** with the count right
  beside it, still in the far-right corner.
- **Test fixture (#9, #10):** first v0.5.0 launch seeds **+1000 coins** and example history via
  pure **`TestData`** — TODAY 360 (math 60 / history 100 / english 40 / coding 160), THIS WEEK
  700 (+ science 100 / english 40 / math 200), THIS MONTH 1000 (+ turkish 300), plus earlier
  2026 months and 2025, and unions those subjects into the label list. (Note: the week split
  reads 700 only when "today" is at least mid-week; on a Monday the week equals today — the data
  still exists for the month/graphs.)
- **iOS (#9, #3):** confirmed plan — **Flutter** single-codebase port (Android APK + iOS `.ipa`
  via a GitHub macOS runner) executed as **one clean pass next turn**, now that the feature set
  has stabilized; logic is already pure to make that port mechanical.
- **Style:** new code keeps the **ponytail** data-driven style (one `ChartView` + data rows,
  shared `swatchView`/`listButton` builders, pure models with codecs).
- **Tests:** added **`LabelColorsTest` (6)**, **`GardenTest` (8)**, **`StatsMonthTest` (5)**,
  **`FlowersLocalizationTest` (3)**, **`TestDataTest` (5)** → **72 JUnit tests**, all passing and
  still gating CI. versionCode 6 / versionName **0.5.0** → APK **`0v05_pixelpomo`**.

**APK:** Releases → "Latest debug build (v0.5.0)" → **`0v05_pixelpomo.apk`** (after tests pass).

**Notes / known gaps:** Korean uses the system font for glyph coverage (pixel font is Latin-only);
some Latin-Extended diacritics (e.g. Polish ł/ż) may render imperfectly in the pixel font. Same
prior gaps stand (Activity-recreation timer restore beyond locale change, background-service
timing, instrumented UI tests, unbounded stats growth).

---

## v0.4.0 — Label bin + confirm, coins & shop, theme trim
**Date:** 2026-06-15

**Prompt (v3 follow-up):** Labels: tapping shouldn't delete — put a 🗑 next to each label
that asks yes/no before removing; adding a label should **stay** on the label page. Add a
**coin system** (5 focus min = 1 coin, 25 min = 5; a flower = 10 coins) with coins in the
top-right corner that open a **shop** of 2D-pixel flowers (Turkish names: gül, papatya,
lale, kaktüs, kasımpatı, menekşe, nilüfer, orkide, begonya, kamelya). **Remove Macchiato**
(too close to the others) and give **Latte a cream background** (was too close to Light).
Pick the right iOS path; code in the concise "ponytail" style. Keep docs + edge tests current.

**Changes:**
- **Labels — bin + confirm (#1) & stay-on-page (#2):** each label row is now
  `[ name | 🗑 ]`; the 🗑 opens a **yes/no confirm dialog** before deleting (long-press
  delete removed). Selecting a label now **keeps you on the label page** (close via
  CLOSE/back) instead of jumping back to the timer.
- **Themes (#8):** **Macchiato removed** (`Themes.ALL` is now Dark/Light/Mocha/Frappe/Latte);
  **Latte** switched to a warm **cream** background (`#F7EFDD`) so it no longer looks like the
  cool-neutral Light theme. A previously-saved "macchiato" selection safely falls back to Dark.
- **Coins (#5):** a gold **coin counter sits in the top-right corner**; completing a WORK
  block awards `studyMinutes / 5` coins (`Economy.coinsFor`). Balance + owned flowers persist.
- **Shop (#5):** tapping the coins opens a **SHOP** overlay listing the **ten flowers**, each
  drawn as a **2D pixel sprite** (`Flowers.kt` grid data + `PixelArt.kt` canvas renderer),
  with its Turkish name, owned count, and a **BUY (10)** button (dimmed + blocked when you
  can't afford it). Buying deducts 10 coins and adds the flower to your inventory (ready for
  the garden).
- **Economy groundwork for the garden (#7):** `Economy.upgradeCost(n) = 2n+1` (4×4→5×5 = 9,
  5×5→6×6 = 11) and `BASE_GARDEN_SIZE = 4` are implemented + tested now, so next turn's garden
  just consumes them.
- **Style:** new code follows the **ponytail** "lazy senior" philosophy — data-driven flowers
  (one renderer + 10 data rows), reuse of `PixelStyle`, no new abstractions beyond what's used.
- **Tests:** added **`EconomyTest`** (6) and **`FlowersTest`** (4) → **45 JUnit tests**, all
  passing, still gating CI. versionCode 5 / versionName **0.4.0** → APK **`0v04_pixelpomo`**.

**Deferred to next turn (with reasons):** the **garden (#7)** depends on owning flowers, so
the shop had to land first; **languages (#6)** is a 6-locale translation pass best done once
these new screens' strings settle. **iOS (#3):** decision recorded — **Flutter** (one Dart
codebase → both platforms; CI can build the iOS `.ipa` on a cloud macOS runner, no Mac
needed), executed as a single clean port **once the game design stabilizes** rather than
re-porting a target that changes every prompt. See `README.md` roadmap.

**APK:** Releases → "Latest debug build (v0.4.0)" → **`0v04_pixelpomo.apk`** (after tests pass).

**Notes:** stats + owned-inventory persist in `SharedPreferences`; same known gaps as before
(Activity-recreation restore, background-service timing, instrumented UI tests, unbounded
stats growth).

---

## v0.3.0 — Higher limits, distinct themes, labels, and stats
**Date:** 2026-06-15

**Prompt (v3 notes):** Raise the ceilings (study → 300, break → 120, sessions → 24).
The themes look too alike — DARK blends into Mocha/Macchiato/Frappe and LIGHT into
Latte; change the red used in DARK (style cues from catppuccin.com / the ClaWus widget).
Add a **label** next to WORK (custom labels like MATH, CODING; "STUDY" as the template;
tap to switch). **Record sessions** — daily, weekly, monthly, yearly, all-time. Keep the
logic portable for a future iOS/cross-platform build, and keep the docs + edge tests current.

**Changes:**
- **Raised limits** (`MainActivity` steppers): **STUDY 5–300** (×5), **BREAK 1–120** (×1),
  **SESSIONS 1–24** (×1). Engine/persistence already handled arbitrary values.
- **Theme redesign** (`PixelTheme.kt`): **DARK** and **LIGHT** are now **neutral grayscale**
  so they no longer blend into the four blue/purple Catppuccin flavors (the core of the
  "not much difference" complaint). DARK's crimson accent **`#E43B44` → coral `#FF5A5F`**
  (a clearly different hue from Catppuccin pink `#F38BA8`); LIGHT's accent → `#E5484D` with
  near-black neutral text vs Latte's lavender text. Mocha/Macchiato/Frappe/Latte stay
  canonical Catppuccin (intentionally a close family; the fix was getting DARK/LIGHT out of
  their lane).
- **Focus labels** (`Labels.kt` + label overlay): a **tappable chip** under the mode label
  shows the current label and opens a picker. Seeded with **STUDY / MATH / CODING / READING**;
  **add** your own (normalized: upper-cased, A–Z/0–9/space, ≤12 chars, deduped) and
  **long-press to delete** (never empties the list). Selection + list persist in
  `SharedPreferences`.
- **Session recording & stats** (`Stats.kt` + stats overlay, new bar-chart icon): each
  **completed WORK block** is recorded (today's date + study minutes + current label).
  A **STATS** screen shows **TODAY / THIS WEEK (Mon-start) / THIS MONTH / THIS YEAR /
  ALL TIME** totals plus an **all-time per-label** breakdown, formatted as `Xh Ym`.
  Records persist as compact `epochDay,minutes,label` lines (defensive decode skips
  malformed lines).
- **Logic kept portable:** all new logic lives in pure, Android-free classes
  (`Labels`, `StatsAggregator`, `StatsCodec`) alongside `PomodoroEngine`, so the same core
  can back a future iOS/cross-platform UI. See the roadmap note in `README.md`.
- **Tests:** added **`LabelsTest`** (10) and **`StatsTest`** (9) — normalization/add/remove
  edge cases and window/per-label/format/codec edge cases — bringing the suite to
  **35 JUnit tests**, all passing and still gating CI. Bumped to versionCode 4 /
  versionName **0.3.0** → APK **`0v03_pixelpomo`**.

**APK:** Releases → "Latest debug build (v0.3.0)" → **`0v03_pixelpomo.apk`** (built only
after tests pass).

**Notes:** Stats grow unbounded over time (one line per completed WORK block) — fine for
now, prune/rollup later. Known gaps from v0.2.0 (Activity-recreation state restore,
background-service timing, instrumented UI tests) still stand.

---

## v0.2.0 — Settings, configurable sessions, and themes
**Date:** 2026-06-14

**Prompt:** Add a settings section with a classic gear icon in the top-right and a
theme icon in the top-left. Add themes mirroring the ClaWus widget's color style,
adapted to pixel. In the timer, remove "round" and use "session"; let the user change
study time, break time, and how many sessions they want. Rename the APK to
`0v01_pixelpomo`, with the next release as `0v02_pixelpomo`.

**Changes:**
- **Top bar:** added a **theme/palette icon (top-left)** and a **classic settings gear
  (top-right)** — `ic_palette.xml` / `ic_settings.xml`, tinted to the active theme.
- **Settings overlay:** three pixel **steppers** (`row_stepper.xml`) for **STUDY (min)**,
  **BREAK (min)** and **SESSIONS**, each `-`/`+` clamped to a sensible range
  (study 5–90 ×5, break 1–30 ×1, sessions 1–12 ×1). Values are edited as a draft and
  committed on **SAVE**, persisted in `SharedPreferences`, and rebuild the engine.
- **"Round" → "Session".** `PomodoroEngine` now takes `totalSessions`, tracks the
  1-based `session`, and sets **`isFinished`** after the final session's break; the UI
  shows **`SESSION n / N`** and **`ALL DONE!`** at the end (START after that restarts).
- **Themes:** six pixel themes mirroring the **ClaWus** widget — **Dark, Light, Mocha,
  Macchiato, Frappe, Latte** (Catppuccin palette adapted to the retro look) in
  `PixelTheme.kt`. A **theme overlay** lists them; tapping one re-tints every view live.
- **Runtime-themed drawables:** replaced the static `btn_pixel*.xml` / `progress_pixel.xml`
  with `PixelStyle.kt`, which builds the drop-shadow buttons and progress bar in code so
  their colors come from the active theme.
- **Tests:** expanded to **16 JUnit edge-case tests** — session advance, final-break
  `isFinished` (no session overflow), start-when-finished no-op, reset-restarts-run,
  switch-clears-finished, and custom-duration honoring. All passing; CI still gates on them.
- **APK naming:** the workflow now derives the name from `versionName` —
  `0.1.x → 0v01_pixelpomo`, **`0.2.0 → 0v02_pixelpomo`** — and titles the `latest`
  release with the version. Bumped to versionCode 3 / versionName 0.2.0.

**APK:** Releases → "Latest debug build (v0.2.0)" → **`0v02_pixelpomo.apk`** (built only
after tests pass).

**Notes:** Themes/sessions are persisted; known gaps from v0.1.1 (Activity-recreation
state restore, background-service timing, instrumented UI tests) still stand.

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
