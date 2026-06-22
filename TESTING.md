# 🧪 Testing

This project does **edge testing after every change**. The timer logic lives in a
pure, framework-free class (`PomodoroEngine`) precisely so it can be unit-tested on
the JVM — fast, deterministic, no emulator. Tests run locally and **gate every CI
build**: if a test fails, the workflow stops and **no APK is published**.

## How to run

```bash
# locally (needs JDK + Android SDK)
./gradlew testDebugUnitTest

# the exact command CI runs before building the APK
./gradlew testDebugUnitTest --no-daemon --stacktrace
```

HTML report after a run: `app/build/reports/tests/testDebugUnitTest/index.html`.
In CI it's uploaded as the **`unit-test-report`** artifact (even on failure).

## What's covered

**72 JUnit tests, all passing** as of v0.5.0, across ten pure classes:

### `PomodoroEngineTest.kt` (16) — timer state machine

| Area | Edge cases checked |
|------|--------------------|
| Initial state | WORK, full time, not running, session 1, `totalSessions`, 100% progress, `00:10` format |
| start | sets running; **no-op when time left is 0**; **no-op when the run is finished** |
| pause | stops but **keeps remaining time** (so START resumes) |
| reset | restarts the **whole run** → session 1 / WORK / full time, clears finished |
| switch mode | toggles WORK↔BREAK, reloads that phase's time, stops, **clears finished**, keeps session |
| finish WORK | → BREAK, session **not** advanced |
| finish BREAK | → WORK, session **+1** |
| final break | last session's break sets **`isFinished`**, session **never overflows** `totalSessions` |
| custom durations | injected study/break minutes are honored (`50:00` / `10:00`) |
| setTimeLeft | **clamps** negative → 0 and over-duration → duration |
| progress % | 100 / 50 / 0 across the range; **never leaves 0..100** (incl. negative & `Long.MAX_VALUE`) |
| time format | rounds **up** (`1ms`→`00:01`), zero-pads, `25:00` at full, `00:00` at zero |

### `LabelsTest.kt` (10) — focus-label rules

| Area | Edge cases checked |
|------|--------------------|
| normalize | upper-cases + trims; collapses inner whitespace; **strips disallowed chars** incl. `,` and newline (codec safety); inner separators (`-`) → space; edge symbols trimmed |
| normalize cap | caps at **12 chars** and re-trims a tail that lands on a space |
| normalize reject | empty / whitespace-only / symbol-only → `null` |
| add | appends a valid label; **ignores case-insensitive duplicates**; ignores invalid input |
| remove | drops a match but **never empties** the list; missing label is a no-op |
| seed | seed set contains the `STUDY` default |

### `StatsTest.kt` (9) — recording & aggregation

| Area | Edge cases checked |
|------|--------------------|
| aggregate | splits minutes across **today / week / month / year / all**; empty → all zero |
| week boundary | **Monday-start** week includes this Monday, excludes the Sunday before |
| negatives | negative minutes clamp to 0 |
| by-label | sums per label, **sorted descending** |
| format | `0m` / `5m` / `1h` / `1h 30m` / `2h 5m`; negative → `0m` |
| codec | **round-trips** (labels with spaces survive); decode **skips blank/malformed lines**; null/blank → empty |

### `EconomyTest.kt` (6) — coins & inventory

| Area | Edge cases checked |
|------|--------------------|
| coinsFor | 1 coin / 5 min, **rounds down** (4→0, 5→1, 25→5, 50→10, 30→6); negative → 0 |
| upgradeCost | new-tile count `2n+1` (4→9, 5→11, 6→13) |
| inventory codec | round-trips; **drops zero/negative** counts; **skips malformed/blank** lines; null/blank → empty |

### `FlowersTest.kt` (4) — flower catalog

| Area | Edge cases checked |
|------|--------------------|
| catalog | exactly **10 flowers**, **unique ids**; `byId` resolves known + returns null for unknown/null |
| grid integrity | every grid is **rectangular**, uses only `P/C/S/L/.`, and has **at least one petal** |

### `LabelColorsTest.kt` (6) — per-label color rules (v0.5.0)

| Area | Edge cases checked |
|------|--------------------|
| default | **stable** per name, case/whitespace-insensitive, always a real palette swatch |
| colorFor | prefers the user's chosen color, else a palette default |
| codec | round-trips; **skips malformed/blank**, null/blank → empty |
| palette | no duplicate swatches |

### `GardenTest.kt` (8) — garden grid model (v0.5.0)

| Area | Edge cases checked |
|------|--------------------|
| init | free **4×4**, 16 tiles, empty |
| plant/clear | place + remove by index; **bad index / blank id are no-ops** |
| grow | size+1, **plantings keep their (row,col)** under the new flat index |
| countPlanted | counts per flower (so we don't over-plant inventory) |
| codec | round-trips; **drops out-of-range tiles**, **clamps size up to the base 4**, null/blank → default |

### `StatsMonthTest.kt` (5) — month-scoped stats (v0.5.0)

| Area | Edge cases checked |
|------|--------------------|
| monthTotal | only that calendar **month+year**; other month/year excluded |
| byLabelInMonth | sums per label **sorted desc**, **drops empty** |
| dailySeries | array length = days in month, **bucketed by day-of-month** |
| negatives | negative minutes clamp to 0 in both views |

### `FlowersLocalizationTest.kt` (3) — localized names (v0.5.0)

| Area | Edge cases checked |
|------|--------------------|
| names | every flower has all **six** language names |
| nameIn | resolves a language; **falls back to English** for an unknown tag |
| langs | the six tags `en/tr/pl/de/ko/it` are registered |

### `TestDataTest.kt` (5) — seeded fixture (v0.5.0)

| Area | Edge cases checked |
|------|--------------------|
| buckets | TODAY **360**, THIS WEEK **700**, THIS MONTH **1000** (for a mid-week "today") |
| history | the **previous year (2025)** is seeded; fixture labels are all present |
| coins | grants **1000** coins |

## Flutter port (`flutter/`) — iOS + Android cross-platform build

The Dart port carries its own tests, gating the **`build-flutter.yml`** macOS pipeline
(`flutter test` blocks the APK/IPA build on failure). Validated locally on Flutter
**3.44.2 / Dart 3.12.2** and green in CI.

```bash
cd flutter && flutter analyze && flutter test   # 55 tests
```

**v21:** count stays **55**. The **TREND/line chart** no longer draws the highlighted (red) selected-bucket label on
top of the fixed gray label at the **first/last** tick — the highlighted label is skipped when the selected bucket is
an endpoint (`s != 0 && s != n-1`), so the ends keep one fixed number while every middle bucket still shows the
highlighted one on tap (the vertical highlight line + data callout still draw at the ends). Render-only — the headless
`toImage` golden render hangs here, so the chart is **device-verified**; the 55-test gate + the boot/overlay smoke
test guard against regressions. (v21 also releases the 2026-06-22 v20 follow-up below: centered wallpaper preview,
multiple wallpaper critters, v19 coin.)

**v20:** count stays **55** (visual/native). The wallpaper is the **native `GardenRenderer`** (a `FlutterEngine`-
hosted variant that ran the actual `GardenView` was tried for a 1:1 match but black-screened on device — an
unsupported path — so it was reverted and the native renderer improved): **real road sprites** (were gray
squares), **low-poly 3D fence meshes** (posts + linking rails, ported from the app's `boxCorners`/`_paintFenceRails`
— were flat billboard cards), and a **single-shape bee** that no longer morphs with the camera — all **device-verified**. The
**no-wind** flowers, **flat white daisies** (app painter + native renderer), **single-shape critters**, and the
redrawn **coin** are visual too.

**v20 follow-up (device feedback):** the live-wallpaper **preview** no longer sits left-shifted —
`GardenWallpaperService` forces the centered offset when `isPreview` (the preview pane reports `xOffset≈0`, which
the renderer's parallax turned into a ~0.75-tile left slide; the *applied* wallpaper was already centered, matching
the in-app capture). The wallpaper now shows **multiple critter types** (bee/butterfly/ladybug) via `CritterSim`, a
faithful port of the in-app `CritterSystem`, not a lone bee. The **coin** is back to the **v19** sprite
(byte-identical). All three are visual/native → **device-verified**; the 55-test gate is unchanged (no Dart logic
touched — the changes are in Kotlin + the sprite generator).

**v19:** count stays **55**; the garden **grow** + `atLeast` tests were updated for the new **taller growth**
(`grow()` adds +2 cols / +4 rows). Device-verified: the **ClipRect** that keeps the zoomed garden off the HUD,
the garden-mode **SESSION** line + **light-theme** over-garden text, the new **MATCHA** theme, the redrawn
**coin**, the **sparse white daisies**, and the native wallpaper **bee lifecycle** (spawn → visit → leave →
gap). The all-time year clamp (≥2025) and the TREND callout de-dup are covered by the seeded fixture / visual.

**v18 additions:** `logic_test` gained a **portrait base + pad-independent `atLeast`** test (a legacy *wide*
10×16 plot pads to **10×20** without widening) and a **daily-trend-non-empty** test (the seeded data now carries
timestamps so the DAILY curve renders). `engine_test`'s forest group is now **screen-filling + roam clamp**:
`isGardenTile` classification, **`visibleTileBounds` spans beyond the plot** (forest fills the screen), and the
**roam-radius clamp** (bounded, no infinite roam); the `Projector.fit` test asserts the **plot-based** fit fills
most of the screen. The **menu icons** (extracted from the user's sheet by `tools/extract_icons.py`), the
**portrait garden / screen-filling forest**, and the **grass flowers** are **device-verified** (Pillow runs
locally only; CI ships the committed PNGs and never runs it).

**v17:** no new tests (count stays **53**). Two **native `GardenRenderer`** fixes, **device-verified**: forest
props rendered as **only shadows** because `isFlower()` mis-classified `tree_/bush_/rock_` ids and looked them
up as the nonexistent `flower_tree_NN.png` — fixed by excluding those prefixes; and the screen-space sine **bee**
was replaced with a garden-space flower-visiting bee (`frameForAngle` facing) like the in-app `CritterSystem`.
These are pure-Kotlin wallpaper rendering, outside the `flutter test` (Dart) gate.

**v16:** no new tests (count stays **53**). The live-wallpaper **picker fix** (native `MainActivity` now calls
`startActivity` in a try/catch instead of guarding with `resolveActivity`, which returns null on Android 11+
under package visibility) is **device-verified**, and moving **SET LIVE WALLPAPER** from the camera bar into the
**CAPTURE** save/share sheet is a UI change to an Android-only option that the host widget test can't render.

**v15 additions:** `logic_test` gained a **`WallpaperCam` framing codec** group (encode 4 fields +
round-trip; tolerant decode of null/garbage — the live-wallpaper framing the native side reads). New
**`test/wallpaper_channel_test.dart`** mocks `MethodChannel('pixel_pomo/wallpaper')` and asserts
`setLiveWallpaper()` invokes the `setLiveWallpaper` method. The **native live wallpaper is device-verified**:
the macOS CI runs `flutter test` only (Dart), not Gradle/JUnit, so the Kotlin `WallpaperService` /
`GardenRenderer` / `GardenData` (which mirror `Garden.decode` / `Placeables.split` / `Projector` / `forestPropAt`)
and the on-device wallpaper-set are verified on the user's phone. The existing **garden-codec round-trip** tests
pin the format the Kotlin `GardenData` parser mirrors. The camera-mode **SET LIVE WALLPAPER** button is
Android-only (`Platform.isAndroid`), so it doesn't render in the host widget test — device-verified too.

**v14 additions:** `logic_test` gained a **`SessionRecord` timestamp codec** group (the 4-field encode +
**backward-compatible** decode of legacy 3-field rows — #2) and a **`StatsAggregator` trend** group
(`dailyCumulative` 7-point hourly cumulative + `periodStats` → **current/average/best** bucketed per period —
#2). `engine_test` gained a **`bounded forest world`** group (`worldOf` adds the fixed `kForestBorder` ring;
`isGardenTile` classifies plot vs. border; `GardenCamera.clamp` keeps pan inside the world edge — #4), and the
`Projector.fit` test now asserts the plot is **framed inside the bounded world** (not most of the screen). The
smoke test taps **TREND** and asserts the **CURRENT/AVG/BEST** block, and still taps every top-bar icon — now
backed by **`Image.asset`** transparent icons rather than the deleted sheet slicer. The **generated transparent
icons**, the **TREND line + clamped callout**, the **bounded forest framing**, the **SESSION-in-top-bar** layout,
and the **calmer grass** are **visual / device-verified**.

**v13 additions:** `logic_test` gained **`StatsAggregator.anchorFor` + offset** (browse previous
day/week/month/year, never the future — #1), **`Economy.elapsedFocusMinutes`** (spent-time payout on cancel —
#6), and the **garden base 10×16 + `Garden.atLeast`** migration that grows older saves to the bigger base
keeping plantings centred (#7). `engine_test` gained **`forestPropAt`** (deterministic, in-range, weighted
trees>bushes>rocks with grass gaps — #5). The smoke test now taps the **stats ◀ history navigator**, asserts
**FOCUS** + the **AUTO-START BREAK** toggle, taps the **store** icon and the **OUTER DECOR** tab, and uses the
new top-bar **icon keys** (`themeButton`/`gardenButton`/`statsButton`/`settingsButton`/`storeButton`). The bar
minutes, pie/line label layout, daily legend, custom pixel icons (sliced from the sheets), bigger garden, varied
forest, garden-mode layout, and the auto-break dialog are **visual / device-verified**.

**v12 additions:** `logic_test` gained the **theme system-bar brightness** group (`isLightColor`,
`systemOverlayFor` color the bars to the theme bg with contrasting icons — #2), the **stats period
aggregators** group (`byLabelInWindow`/`seriesFor`/`labelSeriesFor` for daily/weekly/monthly/yearly/all-time
windows + per-bucket by-label, #10/#11), and **`Labels.rename`** (normalize, reject empty/dupe/missing, #8).
`engine_test` gained **`Projector.gridAt`/`visibleTileBounds`** (the forest-fill visible-range math, #1) and a
**critter max-lifetime despawn** test (#3); the old `WorldGrid` group was removed with the class. The smoke test
now also taps the **stats period + chart types** and **long-press label rename**. Pie separators, the line
callout, the screen-filling forest, themed system bars/HUD, the un-dimmed backdrop, and the Android wallpaper
set are **visual / device-verified** (the wallpaper call is Android-only and isn't invoked in tests).

- **`test/logic_test.dart` (39)** — pure-logic parity with the Kotlin edge suite:
  `PomodoroEngine` state machine + progress clamp + `1ms→00:01` round-up; `Economy`
  `coinsFor`/`upgradeCost`; `Garden` plant/grow + codec round-trip; `Labels` normalize (strip +
  cap 12), dedup, keep ≥1; `LabelColors` default + codec; `Stats` monthTotal / byLabelInMonth /
  dailySeries + minute formatting; `TestData` fixture buckets to **360 / 700 / 1000** + 2025 + 1000 coins.
  **v11 rectangular garden:** `Garden` is now **cols×rows, starting 4×6** (`tileCount=24`); `grow()`
  adds a **centered ring** (4×6 → 6×8, a tile drifts +1/+1), index = `r*cols+c`, **no cap** (10 EXPANDs);
  `Economy.upgradeCost(cols,rows) = 2*(cols+rows)+1` (4×6 → 21); `decode` **migrates a legacy `size:`
  square** and drops out-of-range tiles. `Placeables` catalogue **4 roads + 3 fences (7 objects)** by
  `isRoad`/`isFence`; `costOf` = **5** objects / **10** flowers; ids round-trip. **Tile-layering (#2):**
  a fence stands on a road (`groundAt`=road + `propAt`=fence survive the codec); a road slides under a
  fence but clears a flower; a flower refuses to plant on a road.
- **`test/engine_test.dart` (10)** — low-poly 3D geometry + rectangular/forest math (TDD).
  `Projector.projectElevated` raises a point **straight up by `e·t`, no horizontal shift, identical across
  five yaws** (sun-free vertical); `boxCorners` returns **8 corners**, top directly above base by `height·t`,
  **real footprint width from every angle** (fixes the "fence → thin antenna" bug). The **rectangular
  `Projector` tile mapping** round-trips `tileAt(projectGrid(gridOf(c,r))) == r*cols+c` for a **non-square 4×6
  plot across four yaws**, and `Projector.fit` frames the plot **inside the bounded world**. `gridAt` inverts
  `ground` for fractional coords at several yaws. **v14 bounded world:** `worldOf` adds the fixed
  `kForestBorder` ring, `isGardenTile` classifies plot vs. border, and `GardenCamera.clamp` keeps pan inside
  the world edge. **Critters:** a critter **always despawns within `Critter.maxLife`** (stepped 200s past
  spawn) — no more stuck bugs (#3).
- **`test/widget_smoke_test.dart` (1)** — boots the **real** app via `PixelPomoApp(store)`
  and opens **every** overlay (settings, garden, stats, theme, labels, **and the shop via the
  gold-coin button keyed `shopButton`**), asserting `START` renders, each panel shows, closes
  cleanly, and there are **no exceptions or layout overflow**. The **garden runs a live ticker**, so
  that screen is driven with fixed `pump(Duration)` steps; the sprite PNGs decode via real async, so the
  test uses **`tester.runAsync(gardenSprites)`** to resolve the `FutureBuilder` before asserting.
  **v11 interactions:** it taps the **peek button** (`peekButton`) to hide all HUD (the `GARDEN` title
  disappears) and restores it; enters **camera mode** (`cameraButton`) and confirms `CAPTURE`/`CANCEL`
  (without tapping CAPTURE — its `toImage` hangs headless); and toggles **Settings → HOME SCREEN
  `GARDEN`→`CLEAN`** (`ensureVisible` first, so the tap really lands and leaves no live-backdrop ticker running).

**Garden engine note (visual, partly unit-tested):** the renderer math in `lib/engine/garden_engine.dart`
— `Projector` fit + yaw + tile↔screen inverse (`projectGrid`/`tileAt`/`gridAt`), `GardenCamera.clamp`
world-edge bounding, **garden-space** `CritterSystem`, the low-poly 3D fence primitives `projectElevated` +
`boxCorners`, and the **bounded-world** helpers (`worldOf`/`isGardenTile`) — are covered by `engine_test.dart`.
**v14 bounded forest (#4):** the projector is sized to the **whole world** (garden + a fixed `kForestBorder`
ring), the painter stamps varied forest props (`tree/bush/rock_NN`) on the **border ring only** (depth-sorted,
contact-shadowed) over a dark forest floor, and pan is **clamped to the world edge** — a framed garden with a
defined forest edge, no infinite roam. (Superseded v12's screen-filling infinite forest + v11's fixed
`WorldGrid`, both deleted.) Lighting is flat sky-ambient; **flowers are single billboards**, **only critters**
use an 8-frame atlas. The **themed system bars / no-splash** (#2/#12), **themed HUD chips** + **full-bleed peek**
(#4/#5), **pie separators** (#9), **tappable line + daily multi-line** (#10), **period selector** (#11),
**un-dimmed home backdrop** (#7), **peek/camera**, **static backdrop**, and the **Android live-wallpaper set**
(#6, `wallpaper_manager_flutter`, Android-only) are **visual**, verified by eye on-device / `flutter run`.
*(An offscreen golden harness was tried but `toImage` hangs headlessly here; the rendered world / charts / camera
are previewed on-device, and the geometry + aggregators underneath are unit-pinned.)*

**Known gap:** no on-device iOS UI automation (the runner builds an *unsigned* `.ipa`; it
isn't booted in a simulator). The widget test exercises the same screens on the Flutter
engine, so logic/layout regressions are caught; platform-channel/iOS-chrome issues aren't.

## Notes for v0.5.0 (garden, languages, charts, label colors)

- **All new logic is pure + unit-tested** (`Garden`, `LabelColors`, `TestData`, the new
  `StatsAggregator` month views, `Flowers` localization). The Android glue is manual per the
  checklist: the garden overlay (build/plant/clear/upgrade + persistence), the `ChartView`
  rendering, the language switch (locale wrap + recreate), the color-picker dialog, and the
  coin-icon sizing.
- **`ChartView`** is purely presentational (canvas drawing), untested by design — the data that
  feeds it (`byLabelInMonth` / `dailySeries` / `LabelColors`) is what's covered.
- **Test fixture seeds once** (guarded by `test_seeded_v5`) and **adds** to any existing data,
  so the first v0.5.0 launch shows the example history + 1000 coins. The documented week split
  (700) assumes a mid-week "today"; on a Monday the week equals today (the extras still land in
  the month and charts).
- **Locale + font:** `LocaleManager` wraps the context locale in `attachBaseContext`; Korean
  swaps to the system font (`retypeface`) because Press Start 2P has no Hangul. Some
  Latin-Extended diacritics may render imperfectly in the pixel font (cosmetic).

## Notes for v0.4.0 (label UX, coins, shop, theme trim)

- **Label deletion is now guarded.** Tap a label = select (and stay on the page); the **🗑**
  per row triggers a yes/no `AlertDialog` before `Labels.remove` (which still keeps ≥1). The
  pure rules were unchanged, so `LabelsTest` still covers them; the dialog/stay-on-page glue
  is checked manually.
- **Coins/shop logic is pure + tested** (`Economy`, `Inventory`, `Flowers`). The Android glue
  (coin counter, shop overlay, `PixelArt` rendering, buy flow) is manual per the checklist. A
  WORK completion awards `coinsFor(studyMinutes)`; BUY is blocked + dimmed below 10 coins.
- **`PixelArt`** renders flowers to non-antialiased bitmaps from the `Flowers` grids — purely
  presentational, untested by design (the grid *data* is validated by `FlowersTest`).
- **Theme change is data-only** (Macchiato removed; Latte → cream). A stale saved id falls
  back to Dark via `Themes.byId`.

## Notes for v0.3.0 (limits, themes, labels, stats)

- **Higher limits are presentation-only.** The steppers now allow study 5–300, break 1–120,
  sessions 1–24; `PomodoroEngine` already accepted arbitrary durations/sessions, so
  `customDurationsAreHonored` still covers the engine side. No new engine cases needed.
- **Theme change is data-only.** Recoloring DARK/LIGHT and DARK's accent doesn't touch logic.
- **Labels & stats logic is pure and unit-tested** (`Labels`, `StatsAggregator`, `StatsCodec`).
  The Android glue (`SharedPreferences` persistence, the two overlays, recording a block on
  WORK completion) is verified manually per the checklist — a completed WORK phase appends
  one record `(today, studyMinutes, currentLabel)`; SWITCH/PAUSE/RESET do **not** record.
- **`java.time`** (`LocalDate`) is used for date bucketing — available natively on minSdk 26.

## Notes for v0.2.0 (settings, sessions, themes)

- **"Round" became "Session."** A session is one WORK+BREAK pair; the user picks how
  many via Settings. After the final session's break the engine is **`isFinished`**
  (timer stops, screen shows **ALL DONE!**) until RESET or SWITCH MODE.
- **Configurable durations.** Study minutes, break minutes and session count are
  injected into `PomodoroEngine` and persisted in `SharedPreferences`. `customDurationsAreHonored`
  guards that the engine respects whatever durations it's built with.
- **Themes are presentation-only** — the six pixel themes (mirroring the ClaWus
  widget: Dark, Light, Mocha, Macchiato, Frappe, Latte) tint views/drawables at
  runtime and don't touch `PomodoroEngine`, so the logic tests are unaffected.

## Bugs fixed / behavior hardened (v0.1.1)

Surfaced while writing the edge tests:

- **`start()` guarded** — does nothing when there's no time left (avoids spawning a
  zero-length countdown).
- **`setTimeLeft()` clamped** to `[0, duration]` — a stray/overshooting tick can no
  longer show negative or above-max time.
- **`progressPercent()` clamped** to `0..100` — the progress bar can't overflow or
  go negative.
- **Old timer cancelled before a new one starts** — prevents two `CountDownTimer`s
  running at once if start is ever triggered while running.

## Known gaps (not yet covered)

These are limitations to address in future changes, tracked here so they aren't
forgotten:

1. **State loss on Activity recreation.** The screen is portrait-locked so rotation
   won't recreate it, but a system theme/locale change or multi-window resize would
   reset the timer to WORK 25:00. Fix later via `onSaveInstanceState`/`ViewModel`.
2. **Background timing.** `CountDownTimer` is tied to the Activity; if the process is
   killed the countdown stops. True background timing needs a foreground service.
3. **No instrumented UI tests yet.** Button clicks → view updates are currently
   verified manually (see checklist). Espresso tests could automate this once an
   emulator/device is wired into CI.
4. **Stats grow unbounded.** One line per completed WORK block is appended forever. Fine
   for normal use; a future change could roll old records up into daily totals.

## Per-change checklist

Every time the app changes:

1. Add/adjust unit tests for any logic touched, then `./gradlew testDebugUnitTest`.
2. Manually sanity-check on a device (install the APK from the latest release):
   START counts down · PAUSE freezes · START resumes · RESET restarts the run · SWITCH
   MODE flips WORK/BREAK · timer hits 00:00 → toast + auto-switch · SESSION increments
   after a break · run ends at ALL DONE! after the last session · Settings steppers
   change study/break/sessions (up to 300/120/24) and persist · each theme re-tints the
   whole screen live and DARK/LIGHT/LATTE look distinct (Latte is cream; Macchiato is gone) ·
   the label chip opens the picker, tapping a label selects it **and stays on the page**, ADD
   creates a label and stays, **🗑 asks yes/no** before deleting · finishing a WORK block
   bumps the STATS totals and the per-label breakdown · finishing a WORK block also **adds
   coins** (studyMin / 5) to the top-right counter · tapping coins opens the **SHOP**, BUY is
   dimmed/blocked under 10 coins, buying deducts 10 and raises the OWNED count · the **GARDEN**
   icon opens the 4×4 map, CUSTOMIZE → tile plants/clears an owned flower, UPGRADE deducts the
   right coins and grows the grid · the stats **month ◀ ▶** navigates (not past this month) and
   the **BAR/LINE/PIE** picker redraws the chart · a label's **● swatch** opens the palette and
   recolors its chart series · the **LANGUAGE** picker re-renders the whole UI (incl. flower
   names) in the chosen language.
3. Update `log.md`, and `prompt.md` if behavior changed.
4. Push — CI runs the tests, and only then builds & publishes the APK.
