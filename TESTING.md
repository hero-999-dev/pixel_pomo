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
cd flutter && flutter analyze && flutter test   # 77 tests
```

**v22:** count rises to **60** (+5 pure tests for the flower **variant system**: `flowerBase` strips the `~N` suffix;
`variantsFor` (rose 3 / others 1); a variant prop is still a flower and not an object; planting stores `id~v`, counts
by base id, and survives the garden codec round-trip; a variant flower still refuses to sit on a road). The
boot/overlay smoke test loads the `flower_gul_0..2` sprites without error. Visual/native, device-verified: the
**wallpaper** tiles the real grass texture and draws flowers at the app's `1.05×0.9` size; the **rose variants**
render in-app + in the wallpaper. The headless `toImage` golden render still hangs, so the rose art + wallpaper are
eyeballed on-device.

**v22 polish (same release, still 0.22.0+23 — re-clobbers `flutter-v22`):** four device-feedback refinements; the
suite stays **60** (only the `variantsFor` assertion moved 4→3). **Korean** now uses **Galmuri11 as the primary
face** (its own metrics → aligned baseline, no "kayma") at **×1.15**, with Press Start 2P as the fallback — Latin
languages stay byte-identical (supersedes the first v22's "Press Start primary at normal size"). **Camera mode is
full-bleed** — the garden fills the screen edge-to-edge with CAPTURE/CANCEL floating over it (no black band /
system-bar strip). **Wallpaper critters scale with zoom** (`max(10, t*0.42)`, dropped the 30px cap; Dart + Kotlin
parity). **Rose remade to 3 reference-matched variants** (bud / spiral / open); `flower_gul_3.png` removed. All four
are visual/native → **device-verified**; the 60-test gate guards the variant logic.

**v22 (cont. — "22v" device feedback, still 0.22.0+23 — re-clobbers `flutter-v22`):** count rises to **65** (+5
`pixel_font_test.dart` tests for the **content-based font**: `hasHangul` flags Korean glyphs only; a Hangul string →
Galmuri11 primary, a Latin string → Press Start 2P primary even in the `ko` locale; no-text default → Latin primary;
no per-language size scale). Three on-device items, all device-verified: **(1)** Korean is no longer
Galmuri-everywhere-×1.15 — the font is chosen **per string by content** (Latin stays Press Start, only Hangul uses
Galmuri) so the Korean UI matches the other languages. **(2)** camera mode runs in `SystemUiMode.edgeToEdge`, so the
garden paints behind transparent status+nav bars — the leftover gray strip is gone (matches the live-wallpaper
preview). **(3)** the half-open **rose** (variant 2) was redrawn clean, and the stem leaves are now **left-first** on
the bloom & bud and **symmetric** on the half-open. The headless `toImage` render still hangs, so the rose art / camera
bars are eyeballed on-device.

**v22 (cont. 2 — Korean dropped, French added, rose 3rd remake):** suite stays **65** (no count change;
`pixel_font_test.dart`'s Hangul→Galmuri checks now guard the retained accent/Hangul **fallback** routing rather than a
live `ko` locale). Korean was removed as a UI language and **French** added (`strings.dart` `fr` set + months +
`['fr','Français']`; `AppStore.load` migrates an unknown saved language → `en`); the Galmuri font + content-based
`pixelStyle` stay (they render accented Latin for tr/pl/de/fr). The half-open **rose** (variant 2) was redrawn
simpler/bolder per the user's art guide, and each rose now has a **distinct leaf layout** (left-first / right-first /
symmetric). Rose art self-verified by rendering; the French strings + language swap are device-verified by the user.

**v22 (cont. 3 — rose→2 models, tulip + camellia, shop sprite icons):** suite stays **65** (the variant test now
asserts gul / lale / kamelya = 2 models, others = 1). The rose dropped to 2 models (full bloom + bud); **tulip
(`lale`) + camellia (`kamelya`)** got 2 hand-authored models each via the generalised modular pipeline
(`_FLOWER_BLOOMS` / `_FLOWER_PALS` in `gen_objects.py`); the shop + garden place-picker now render the garden **PNG
sprite** (`objectThumb`) instead of the char-grid `FlowerSprite`. New flower art is self-verified by rendering and
device-verified by the user; the other 7 species still use their single char-grid sprite (rollout pending).

**v23 (App Blocker, Android):** count rises to **72** (+7: `app_blocker_test.dart` — `AppBlocker.active` across engine
states, the blocked-apps csv codec, `shouldBlock` never-blocks-own-app/launcher; `app_blocker_channel_test.dart` —
`installedApps` mapping/sort + the permission getters/openers on a mocked `pixel_pomo/blocker` channel;
`store_blocker_test.dart` — `appBlockerEnabled`/`blockedApps` persist and `blockerActive` flips with a running WORK
session). The Accessibility service, the draw-over overlay, the installed-app list, and the permission grants are
**device-verified by the user** — host `flutter test` can't exercise Android services, and the Settings section is
`Platform.isAndroid`-gated (hidden on the test host).

**v23 follow-up (device feedback):** count rises to **74** (+2). Four fixes from on-device use:
**(1) overlay flicker** — `AppBlockerService` re-showed/hid in a loop because its own focusable overlay fired a
`WINDOW_STATE_CHANGED` for our package that hit `else hide()`, the blocked app returned to front, and we re-showed; it
now **ignores events from `packageName`** so the cover stays put (Kotlin, **device-verified** — outside the Dart gate).
**(2) overlay font/theme** — the cover now draws in **Press Start 2P** (loaded from `flutter_assets`) on the **active
PixelTheme** palette, which `_publishBlocker` hands the native service via `blocker_bg/ink/accent/on_accent/shadow`
prefs (and `selectTheme` re-publishes); `store_blocker_test.dart` asserts the palette is published **(+1)**, the native
render is device-verified. **(3) app-locker lag** — the picker was a `StatelessWidget` that re-ran `installedApps()`
(native enumerate + per-icon PNG) on **every rebuild** (i.e. every toggle, via `openPanel`'s `AnimatedBuilder`), and the
native call ran on the platform thread; it's now a `StatefulWidget` that **caches the future once** and the native
`installedApps` runs **off the platform thread**. `app_picker_widget_test.dart` asserts a single query survives a
toggle-driven rebuild **(+1)**. **(4) Settings SAVE removed** — the three steppers persist immediately (like the
language / auto-break / blocker toggles already did), so the SAVE button is gone; the smoke test now asserts the
**SETTINGS** title instead of the SAVE button.

**v23 follow-up 2 (device feedback):** count rises to **76** (+2).
- **Blocked apps float to the top:** the picker lists the selected (blocked) apps first, then a divider, then the rest
(`AppPickerScreen` partitions the already alpha-sorted list). `app_picker_widget_test.dart` asserts a newly-blocked app
jumps above an alphabetically-earlier one **(+1)**.
- **Ongoing focus-timer notification:** while a session runs and the app is backgrounded, a lock-screen-visible,
**ongoing** notification shows the live MM:SS countdown (`Notification.Builder` chronometer, ticked by the system) over
a new `pixel_pomo/timer` channel. It **can't be swiped away** until done and **self-clears at the deadline**
(`setTimeoutAfter`) or when the session is paused / reset / finished. `PixelPomoApp` is now a `WidgetsBindingObserver`
that calls `AppStore.onBackgrounded` on `paused`; `POST_NOTIFICATIONS` is requested on launch (Android 13+). **No
foreground service** — the countdown is system-driven, so it survives Android suspending the isolate in the background.
Device-verified (host `flutter test` can't post notifications); `timer_notif_test.dart` asserts the store drives
show-on-background / cancel-on-stop over the channel **(+1)**.
- **Overlay needed two BACK taps:** tapping the cover's BACK launched our app and hid the overlay, but hiding
re-exposed the blocked app for a beat → its window event re-showed the cover (the "our app to front" event that used to
hide it is now ignored by the flicker guard, so the spurious re-show stuck). Fixed: `backToApp` sets a ~1.5s
`suppressShowUntil` window so the transient re-focus during the BACK transition can't re-trigger the cover — one tap
leaves cleanly. Device-verified (accessibility service, outside the Dart gate).

**v23 follow-up 3 (device feedback):** count rises to **77** (+1). Seven tweaks; most are native/visual and
**device-verified** (host `flutter test` can't post notifications, draw the garden, or run the wallpaper):
- **Notification un-swipeable until done:** `setOngoing` alone is user-dismissible on Android 14+, so the countdown
moved to a **foreground service** (`TimerService`, `foregroundServiceType=specialUse`). It can't be swiped while
running; at the deadline it detaches (lingers, now swipeable) and stops; cancel-in-app removes it. The small/large icon
is now the **app's own icon**.
- **Round contact shadows removed** from every garden object (the `drawOval` under flowers/trees/rocks/fences) in both
the in-app painter and the native wallpaper renderer.
- **Fresh-install defaults**: clean home, auto-break **off**, app-blocker **off** — so a new install raises no
permission prompts until the user opts in. `store_blocker_test.dart` asserts the three defaults **(+1)**.
- **Garden starts smaller**: base `10×20 → 4×8` (keeps the 1:2 portrait; first upgrade cost `2*(c+r)+1` drops 61→25).
`logic_test` base assertion updated.
- **Wallpaper critters no longer crawl**: the per-step `dt` clamp was `0.05`, throttling motion at the wallpaper's lower
frame rate; raised to `0.1` (the outer cap) so they advance real-time down to ~10fps like the in-app garden.
- **Four new critters** in real-world colours — a yellow 22-spot ladybird, monarch (orange/black) and blue-morpho
butterflies, and a bumblebee (black/yellow) — added to `gen_objects.py` (palette swaps on the existing shapes) and
registered in both `CritterSystem.kinds` (Dart) and `CritterSim.kinds` (native); the low-bob check now covers ladybug
variants. 28 sprites total.

**v23 follow-up 4 (device feedback):** count stays **77** (the timer-channel test gained the phase-plan assertions).
All in the notification, **device-verified** (host `flutter test` can't post notifications):
- **App icon moved to the small/left mini-icon slot** — dropped `setLargeIcon` (it rendered the logo big on the right);
the app icon is now the `setSmallIcon`.
- **Fixed the count-past-zero bug:** at a phase deadline the service used to re-post the *same* counting chronometer
(`setWhen(pastDeadline)` → ticked negative) with the stale focus label, and the Dart isolate is frozen in the
background so nothing advanced the phase. The service now drives the transition from the plan handed to it up front:
**auto-break on → it rolls straight into the BREAK countdown; auto-break off → it settles on a static "FOCUS DONE!"**
(no chronometer, so no negative tick), then detaches (swipeable) and stops. `timer_notif_test.dart` asserts the plan in
the `show` payload (`nextMs`/`nextTitle`/`doneTitle`) for both auto-break states.

**v23 follow-up 5 (device feedback):** count stays **77** (both fixes are visual/native — no host-testable logic). Two
on-device items:
- **Wallpaper road at an angle** — the native `GardenRenderer.drawRoad` drew an **axis-aligned** rect at the projected
tile centre, so a path ignored the camera **yaw**: a wallpaper set from an angled capture didn't match it. It now draws
the road sprite as the **rotated/squashed tile quad** under the same garden→screen affine the grass uses (new
`gridMatrix()` helper, also reused by `fillClearing`), mirroring the in-app `_paintRoads`. The in-app capture was already
correct (it draws roads under the affine); only the native wallpaper was off. **Device-verified** (the Kotlin renderer is
outside the Dart gate; `toImage` hangs headless).
- **Peek (eye) button under the nav bar** — peek/camera run the garden **edge-to-edge** (`SafeArea(bottom:false)`), so
the on-scene chips at `bottom: 4` slid under the Android nav buttons. The three chips (peek / recenter / camera) now use
`bottom: 4 + navInset` (`MediaQuery.padding.bottom` — 0 in normal mode since the SafeArea consumed it; the nav-bar height
edge-to-edge). The smoke test already taps `peekButton`; the offset is visual, **device-verified**.

**v24.2 (daisy classic + bushy):** suite stays **77** — art-only change in `gen_objects.py` (Classic 8-petal + Bushy
3-head daisy models; sprites regenerated). No logic tests touched; garden/shop are **device-verified**.

**v24.2 (daisy classic + bushy):** suite stays **77** — art-only change in `gen_objects.py` (Classic 8-petal + Bushy
3-head daisy models; sprites regenerated). No logic tests touched; garden/shop are **device-verified**.

**v24 (all flowers redesigned):** suite stays **77** — the flower-variant test now iterates `Flowers.all` and
asserts **every** species has 2 models (`unknown` still defaults to 1; was rose/tulip/camellia-only). The rest is
pure art: all 9 non-rose species got 2 hand-pixelled models via the generalised modular pipeline in
`gen_objects.py` (each model a full self-contained grid), regenerated into `assets/objects/flower_*_0/1.png`. The
sprites are **visual** — verified by rendering a montage of all 20 models and eyeballing each against the user's
guide sheets (headless `toImage` can't preview them in a widget test); the garden/shop are device-verified.

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
