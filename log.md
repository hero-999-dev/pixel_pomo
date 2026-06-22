# 📓 Change Log

A running record of what changed in each prompt / iteration. Newest entries on top.
Each entry notes the **prompt** (what you asked for) and the **changes** made.

---

## v21 — wallpaper preview centered + multiple wallpaper critters + v19 coin + TREND end-label fix (Flutter, 0.21.0+22)
**Date:** 2026-06-22

**Prompt:** push as **v21**; and in the **line/TREND graph**, tapping a point shows the day/hour, but at the **ends**
(e.g. daily "1") the number shows **twice** — a gray fixed one and the red tapped one overlapping. Keep the **fixed
numbers at the start and end**, don't draw the red one *there*, but keep showing it on the **other** buckets.

**Changes:**
- **TREND end-label de-dup** — in `pixel.dart` `_line`, the fixed gray tick labels are drawn only at the first/last
  bucket, but the highlighted (red, `lineColor`) selected label was drawn for **every** selected bucket — so at the
  first/last bucket it landed exactly on top of the fixed one and the number appeared twice. The highlighted label is
  now **skipped when the selected bucket is the first or last** (`s != 0 && s != n - 1`): the ends keep their single
  fixed label, every middle bucket still shows the highlighted one on tap. The vertical highlight line + the data
  callout still draw at the ends, so tapping them still gives feedback.
- **Released as v21 (carries the 2026-06-22 v20 follow-up):** wallpaper **preview is force-centered** when `isPreview`
  (was parallax-shifted left in the picker), the wallpaper now shows **multiple critters** (bee/butterfly/ladybug via
  `CritterSim`, a faithful port of the in-app `CritterSystem`; adding a creature — incl. future pets/NPCs — is a small
  two-place edit), and the **coin reverted to the v19 sprite** (byte-identical). See the v20 follow-up below for detail.
- Version → **0.21.0+22**. `analyze` clean, **55 tests** pass. The TREND fix is render-only and the wallpaper changes
  are native → both **device-verified** (the headless `toImage` golden render hangs, so charts/wallpaper are eyeballed
  on-device; the boot/overlay smoke test guards against crashes).

## v20 — improved native live wallpaper + grass/coin/critter polish (Flutter, 0.20.0+21)
**Date:** 2026-06-21

**Prompt (device feedback):** (1) the live wallpaper renders poorly — outer decor (roads/fences) and bugs look
bad; (2) the flowers look like they're **moving** — remove the wind; (3) **"I want the live wallpaper to be the
same as the app"** — same structure, heavier power is fine; (4) the small flowers I added are wrong — I want
**flat 2D white daisies** baked into the grass like the examples (2.jpg/3.jpg/4.png), only ~5%; the coin example
is 1.png.

**Changes:**
- **(1+3) Wallpaper — tried the real app garden, fell back to an improved native renderer.** First attempted
  **A2**: a `FlutterEngine` hosted in `GardenWallpaperService` running a `wallpaperMain` entry point rendering the
  actual `GardenView` pointed at the wallpaper `Surface`. It compiled but showed a **persistent black screen** on
  device (the Flutter→wallpaper-surface path is unsupported and undebuggable without device logs — even after
  moving the entry point into `main.dart`'s root library, the surface attach never delivered frames). Per the
  user's choice, **reverted to the native `GardenRenderer`** and improved it instead: **roads now draw their real
  sprites** (were gray squares), **fences are real low-poly 3D meshes** (posts + linking rails, ported from the
  app's `boxCorners`/`_paintFenceRails` — were flat billboard cards), the **bug uses a single fixed facet** so it
  doesn't morph with the camera, plus the v20 polish below. (The exact-app-engine wallpaper is parked.)
- **(2) No wind** — flowers no longer sway (in-app `_paintBillboard` call + the native renderer's billboard loop).
- **(4) Flat grass daisies** — replaced the billboard blooms with small **flat pixel daisies** (white petals +
  yellow eye, squashed onto the ground by `kVy`), ~5% of empty tiles — matches the 2D flowered-grass examples
  (2.jpg) — in the app painter **and** the native wallpaper renderer.
- **Critters keep one shape** — `_paintCritters` uses a fixed atlas frame (was `frameForAngle(screen-velocity)`,
  which morphed the bug as the camera rotated); same fix in the native bee.
- **Coin** — `coin_grid` redrawn with a soft **upper-left diagonal highlight** (was a hard top/bottom split) to
  match `1.png`.
- **Tests: 55** (unchanged; visual/native). analyze clean; debug APK builds. Wallpaper + garden are
  **device-verified**. Version → **0.20.0+21**.

**Follow-up (device feedback, 2026-06-22):**

**Prompt:** (1) the **wallpaper preview** screen isn't the same as the in-app view — it shows a bit further **left** —
but once *set* as the wallpaper it's normal/centered like the capture; (coin) fix the coin the way I added it in **v19**;
(bugs) the wallpaper has only **one kind of bug** — I want several, **like the garden**; and (forward-looking) I'll add
**pets/NPCs with their own movement** later and want them to show up in the wallpaper too.

**Changes (still 0.20.0+21, no bump):**
- **(1) Preview left-shift fixed** — the live-wallpaper **preview pane** reports `xOffset≈0` (no home-screen paging
  context), so `GardenRenderer`'s parallax slid the garden ~0.75 tile left; the *applied* wallpaper (real launcher
  offsets) was already centered. `GardenWallpaperService` now **forces `xOffset=0.5` when `isPreview`** → the preview
  shows exactly the framing you set. (Confirmed against the v20 feedback screenshots: preview was left-shifted, in-app
  centered.)
- **(bugs) Multiple critter types in the wallpaper** — the native renderer drew a single bee; it now runs a faithful
  port of the in-app **`CritterSystem`** (new `CritterSim` in `GardenRenderer.kt`): up to 2 **bee/butterfly/ladybug**
  visitors that drift in from a random edge, visit a flower, hover, leave, and gap — the same variety as the garden.
- **(pets/NPCs, future-proofing)** — kinds come from a single list, so **adding a creature is data, not engine code**:
  drop the PNG in `assets/objects/` + add its id to `CritterSim.kinds` (Kotlin) AND `CritterSystem.kinds`
  (`garden_engine.dart`). A genuinely new *movement* (a pet that walks the ground, an NPC that follows a path) is one
  new `CState` branch per engine — bounded work, documented in the `CritterSim` doc-comment. (The wallpaper stays a
  separate native renderer — the real-Flutter-engine path was abandoned in v20 — so new entities are a small,
  deliberate two-place edit. YAGNI: no pet/NPC system is built until those entities exist.)
- **(coin) Reverted to the v19 coin** — `coin_grid` restored to the v19 **top/bottom bevel** (`FFDE73`/`E8B43A`, rim
  `d>5.2`); the regenerated `coin.png` is **byte-identical** to the v19 sprite. v20's diagonal upper-left highlight
  was undone per request.
- analyze clean, **55 tests** pass, debug APK builds. Preview centering + multi-critter are native/visual →
  **device-pending** your re-test.

## v19 — feedback round: garden growth, HUD clip, stats, themes, coin, daisies, wallpaper bee (Flutter, 0.19.0+20)
**Date:** 2026-06-21

**Prompt (device feedback, ~10 items):**
- **(1)** garden expands nicely horizontally but **too little vertically** → `grow()` now adds **+2 cols / +4 rows**
  (centred), so it gains height faster and stays portrait.
- **(2)** when zooming, the garden **bleeds over the HUD** → the `GardenView` scene is wrapped in a **`ClipRect`**
  so zoomed forest billboards can't paint over the GardenScreen title/buttons.
- **(3)** the live-wallpaper bug is **always on screen** → the native bee now has a **lifecycle**: a 5–14s gap with
  no bug, then it flies in from the top, visits 2–4 flowers, leaves off the top, and gaps again (like the in-app
  `CritterSystem`).
- **(4)** TREND line showed the bucket label **twice** (bottom axis + callout) → dropped it from the callout.
- **(5)** garden-mode **SESSION** overlapped the top-bar icons → moved it to its **own centred line** below the
  top bar (removed the crowded in-row `center`).
- **(6)** **light themes darkened** in garden mode → the over-garden timer/SESSION/coin text now uses a **light
  colour** (was `th.onSurface`, dark on light themes → unreadable on the dark garden).
- **(7a)** new green **MATCHA** theme matching the garden (Catppuccin-family palette: green base + `A6E3A1` accent).
- **(7b)** stats all-time chart now **starts at 2025** (clamp `minY`).
- **(8)** **coin redrawn** to match the user's example (clean gold disc: dark outline, gold rim, lighter inner
  face + bevel, top-left shine).
- **(9)** the multi-colour grass blooms → **sparse white daisies** (~8% of empty tiles, white petals + yellow eye),
  in-app and on the wallpaper.
- **Tests: 55** (grow + atLeast tests updated for the taller growth). analyze clean; debug APK builds. Garden/
  wallpaper/coin/icons are device-verified. Version → **0.19.0+20**.

## v18 — visual refinements: TREND daily, portrait garden + screen-filling forest, grass flowers, real icons (Flutter, 0.18.0+19)
**Date:** 2026-06-21

**Prompt (device feedback):** (1) **TREND / DAILY isn't working**; (2) there could be **a few flowers in the
grass**; (3) the **bounded forest doesn't cover the whole screen**, only the green area; (4) the **menu icons are
poor**, not the art I sent; (5) the **garden feels horizontal**, not a vertical garden for the phone, and still
doesn't expand right. **Decisions (AskUserQuestion):** use the **ChatGPT 'book' icon set**; make the **plot
taller + the forest fill the screen**.

**Changes:**
- **(1) TREND daily renders** — the daily curve only plots sessions with a per-session `minuteOfDay`, but the
  seeded demo data had none, so it was always empty. `TestData.records` now stamps timestamps; the curve shows.
- **(5) Portrait garden** — base plot **10×16 → 10×20**: with the 2.5D squash (`kVy=0.6`) a 10×16 plot projects
  ~10×9.6 (wider than tall); 10×20 projects ~10×12 (taller than wide). `Garden.atLeast` now **pads each axis
  independently** (centred) so a legacy *wide* plot gains rows to portrait without also widening (symmetric
  `grow()` couldn't). `Projector.fit` is **plot-based** again (`kFitMargin=2`), so the plot fills most of the
  screen.
- **(3) Screen-filling forest** — removed the v14 fixed-border world (`kForestBorder`/`worldOf`); restored
  `Projector.visibleTileBounds` and the painter draws forest on **every visible tile** around the plot, so it
  covers the whole portrait screen. `GardenCamera.clamp` is a bounded **roam radius** (wander a plot-size into
  the woods, but no infinite roam).
- **(2) Grass flowers** — `_paintGrassFlowers` scatters a few small deterministic decorative blooms (white/
  yellow/pink/purple, orange centre) on empty grass tiles, so the clearing isn't bare.
- **(4) Real menu icons** — replaced the v14 procedural icons with the **user's ChatGPT 'book' set** (open book /
  flower planter / scroll-chart / gear / blue-canopy stall). New local tool **`tools/extract_icons.py`** (Pillow)
  crops the 5 cells from the sheet and **flood-fills the navy background to transparent** from the borders (so blue
  *inside* an icon — the stall canopy — is kept); `gen_objects.py` no longer generates icons. CI stays
  dependency-free (the committed PNGs ship).
- **Wallpaper parity** — the native `GardenRenderer` mirrors the new fit (plot-based), **screen-filling forest**
  (visible-tile bounds via a native `gridAt`), and the **grass flowers** (64-bit hash so the same tiles bloom).
- **Tests: 55** (logic incl. the new portrait `atLeast` + `daily trend non-empty`; engine incl.
  `visibleTileBounds` + roam clamp). analyze clean; debug APK builds. Garden look + wallpaper are
  **device-verified**. Version → **0.18.0+19**.

## v17 — live wallpaper render fixes: forest shows + critter-like bee (Flutter, 0.17.0+18)
**Date:** 2026-06-21

**Prompt (device feedback on v16):** the wallpaper works, but (1) the **forest props don't show — only their
shadows**, and (2) there's a **bee randomly swinging around** that doesn't behave like the in-app critters.

**Changes (native `GardenRenderer.kt`):**
- **(1) Forest renders** — the bug was `isFlower()`: it only excluded `road_`/`fence_`, so forest ids
  (`tree_NN`/`bush_NN`/`rock_NN`) were treated as flowers and looked up as the **nonexistent
  `flower_tree_NN.png`** → null bitmap → only the contact shadow drew. `isFlower` now also excludes
  `tree_`/`bush_`/`rock_`, so forest props load by their own filename (the bee always worked because it loads
  `bee.png` directly).
- **(2) Critter-like bee** — replaced the screen-space sine sway with a bee that flies **between planted
  flowers in garden space** (projected through the same `Projector`), hovers at each, then picks the next
  (random garden point if no flowers), facing its heading via a `frameForAngle` mirror over the 8-frame `bee`
  atlas — the same feel as the in-app `CritterSystem`. Refactored `ground()` into `gridXY` + `projGrid` helpers.
- **Tests: 53** (unchanged; native render). analyze clean; debug APK builds. The render is **device-verified**.
  Version → **0.17.0+18**.

## v16 — live wallpaper fixes: picker opens + button moved into the capture sheet (Flutter, 0.16.0+17)
**Date:** 2026-06-21

**Prompt (device feedback on v15):** (1) "SET AS LIVE WALLPAPER says **couldn't open wallpaper picker**"; (2) its
**icon height/color don't match** the CAPTURE button; (3) **remove the SET LIVE WALLPAPER button** and put it
**in the CAPTURE sheet, below save/share**.

**Changes:**
- **(1) Picker now opens** — `MainActivity.openLiveWallpaperPicker` used to guard `startActivity` behind
  `Intent.resolveActivity(packageManager)`, which returns **null on Android 11+ under package visibility** even
  though the system picker handles the intent — so it always returned false → "couldn't open picker". Now it
  **calls `startActivity` directly in a try/catch** (`ACTION_CHANGE_LIVE_WALLPAPER` for our service, falling
  back to `ACTION_LIVE_WALLPAPER_CHOOSER`), returning false only if both throw.
- **(2)+(3) Button relocated** — removed the **SET LIVE WALLPAPER** button from the camera-mode bar (so the bar
  is back to **CAPTURE · CANCEL**, equal styling — fixes the height/color mismatch). **SET LIVE WALLPAPER** is now
  an option in the **CAPTURE** save/share sheet, **below Share** (Android only), still setting the wallpaper at
  the framing the user had in camera mode (`_setLiveWallpaper` reads `_wallpaperCam`).
- **Tests: 53** (unchanged; the Android-only button isn't host-testable). analyze clean; debug APK builds. The
  picker fix is **device-verified** (native intent). Version → **0.16.0+17**.

## v15 — true animated Android live wallpaper (Flutter, 0.15.0+16)
**Date:** 2026-06-20

**Prompt:** "do the live wallpaper update as we talked" — the long-deferred true animated Android live
wallpaper (a native `WallpaperService` rendering the garden), then continue refining the v14 visual details.
**Brainstorming decisions:** render approach **A1 — native Kotlin Canvas** (no embedded Flutter engine: there's
no supported API to draw into a wallpaper surface, it's fragile across the moving `stable` channel and heavy in
a background process). The wallpaper shows the user's **real** garden (reads the same saved data + sprites) and
reproduces the **angle the user frames in camera mode** (yaw/zoom/pan). Entry point: **camera mode** —
**SET LIVE WALLPAPER · CAPTURE · CANCEL**. The static `wallpaper_manager_flutter` path is retired. Android-only
(iOS has no API; keeps Save/Share).

**Changes (8 tasks):**
- **(T1) Framing model** — pure `WallpaperCam(yaw, zoom, panXFrac, panYFrac)` in `logic.dart` (encode/decode a
  compact string; pan stored as a fraction of the tile size so it reproduces across surface sizes);
  `AppStore.setWallpaperCamera(...)` persists pref `wallpaper_cam`.
- **(T2) Channel + cleanup** — `camera.dart` `setLiveWallpaper()` invokes `MethodChannel('pixel_pomo/wallpaper')`;
  removed `setPhoneWallpaper` and the **`wallpaper_manager_flutter`** dependency + its capture-dialog option.
- **(T3) Camera-mode UI** — `GardenView` now takes a parent-owned `GardenCamera` so `_GardenScreenState` can read
  the live framing; the camera-mode bar is **SET LIVE WALLPAPER · CAPTURE · CANCEL** (wallpaper button Android-only),
  whose handler normalizes pan by the projector tile size, persists the framing, and opens the picker.
- **(T4–T6) Native overlay** (`flutter/android_overlay/`, copied into the CI-regenerated `android/` by
  `apply_overlay.py`, which idempotently patches the manifest): `MainActivity.kt` (the channel fires
  `ACTION_CHANGE_LIVE_WALLPAPER` for our service / `isActive`), `GardenWallpaperService.kt` (Choreographer render
  loop, ~30 fps, **stops when not visible**, re-reads the garden on visibility, parallax via `onOffsetsChanged`),
  `GardenData.kt` (reads `flutter.garden`/`flutter.theme_id`/`flutter.wallpaper_cam` from `FlutterSharedPreferences`,
  mirrors `Garden.decode`/`Placeables.split`, loads sprites from `flutter_assets`), `GardenRenderer.kt` (ports the
  `Projector` math incl. yaw + a **64-bit `forestPropAt` mirror** so the forest border matches the in-app view;
  draws forest floor → bounded forest border → grass clearing → roads → swaying flower billboards → drifting bee).
- **(T7) CI** — `build-flutter.yml` runs `apply_overlay.py` after scaffolding (Android-only; CI stays green).
- **Tests: 53** (41 logic incl. `WallpaperCam`; 10 engine; new `wallpaper_channel_test`; smoke). analyze clean;
  debug APK builds with the patched manifest (`GardenWallpaperService` + `BIND_WALLPAPER` + `live_wallpaper`).
  The native render + on-device wallpaper-set are **device-verified** (CI runs `flutter test` only).
- **Docs:** TESTING.md, README.md, flutter/README.md, prompt.md updated; version → **0.15.0+16**.

## v14 — transparent icons, stats TREND, bounded forest world, calmer garden (Flutter, 0.14.0+15)
**Date:** 2026-06-20

**Prompt (Flutter, feedback in `feedback & guides/Feedback/Version 13v Feedback/`):** 7 items.
**(1)** the v13 menu icons render as **dark navy boxes** — the sheet slicer kept the sheet's non-transparent
background; generate proper **transparent 32×32 pixel icons** instead. **(2)** redesign the LINE chart into a
**TREND**: DAILY = the day filling up **hour by hour** (cumulative at 00,04,08,12,16,20,24); WEEKLY/MONTHLY/
YEARLY/ALL = per-bucket totals; replace the TODAY/WEEK/MONTH/YEAR/ALL block with period-contextual
**CURRENT / AVERAGE / BEST**; and fix the **callout text spilling outside the chart**. **(4)** the forest should
be **fixed/bounded** (not infinite), fill the portrait screen, with the garden growing toward its edges.
**(5)** the forest renders **over the top/bottom HUD text** (unreadable) — it should sit **under** them.
**(6)** **simplify the garden grass** (too patchwork/quilt-like). **(7)** remove the shop **FLOWERS-tab help text**.
**Decisions (AskUserQuestion):** add **per-session timestamps** so the daily trend is real hourly data;
CURRENT/AVG/BEST live **only on the TREND page**; a **bounded world** the garden grows into; **generate** clean
transparent icons procedurally. **Correction:** keep the home garden-mode **wallpaper** style (garden behind the
timer) — only move **SESSION into the top bar**, centered between the icon groups.

**Changes (8 tasks, all in `flutter/`):**
- **(#2) Session timestamps** — `SessionRecord.minuteOfDay`; `StatsCodec` encodes a 4th field and still decodes
  legacy 3-field rows (labels are comma-free, so part-count disambiguates); `store` stamps `minuteOfDay` on
  every recorded/cancelled session.
- **(#2) Trend aggregators** — `StatsAggregator.dailyCumulative(records, now, [offset])` (7 cumulative points at
  hours 0/4/8/12/16/20/24) and `periodStats(...) → (current, average, best)` bucketed by the period unit; pure,
  no `dart:math`.
- **(#2) Stats TREND UI** — LINE renders/labels as **TREND**; DAILY uses the cumulative series, other periods the
  per-bucket totals; the tap callout adds **FOCUS** + **AVG** rows and is **clamped fully inside the plot** so text
  never overflows; the totals block shows **CURRENT/AVG/BEST** in trend mode, the old today/week/month/year/all
  otherwise.
- **(#1) Transparent icons** — `gen_objects.py` builds 5 **transparent 32×32** menu icons (theme/garden/stats/
  settings/store) pixel-by-pixel on a blank canvas with a dark `outline()`; the top bar renders them via
  `Image.asset`. Deleted `lib/icons.dart` (`IconBank`/`MenuIcon`/`menuIcons`) and the broken `menu_sheet.png`/
  `store_sheet.png`.
- **(#4) Bounded forest world** — `kForestBorder=4`, `worldOf`, `isGardenTile`; `Projector.fit` sizes the whole
  world (garden + border ring) to the screen; the painter draws forest only on the fixed border ring; pan is
  **clamped to the world edge** (no infinite roam). Removed the now-dead `visibleTileBounds`.
- **(#3/#5) Garden HUD** — **SESSION** moved into the garden-mode **top bar**, centered between the icon groups;
  the coin count gets a hard pixel **shadow** over the wallpaper (matching the timer) for legibility. (The garden
  screen's HUD already sits on the themed background and the `GardenView` is clipped to its box, so no bleed.)
- **(#6) Calmer grass** — `grass_grid` is now one base green with only **sparse, low-contrast speckle** (no bright
  olive, no hard tufts); plants keep their dark outline to separate.
- **(#7) Shop cleanup** — dropped the FLOWERS-tab help line (`shopHelp` string kept, unused).
- **Tests: 50** (logic + engine `bounded forest world` + smoke `TREND`/`CURRENT`). analyze clean; debug APK builds.
- **Docs:** TESTING.md, README.md, flutter/README.md, prompt.md updated; version → **0.14.0+15**.

## v13 — stats polish, main-screen rework, store categories, bigger garden + forest (Flutter, 0.13.0+14)
**Date:** 2026-06-20

**Prompt (Flutter, feedback photos in `feedback & guides/Feedback/Version 12v Feedback/`):** 7 items.
**(1)** bar tops in minutes (not hours); pie labels full + right-aligned %; line-tap callout in the same
style with **TOTAL** on top and the day number moved to the bottom axis; a **history navigator** to browse
previous days/weeks/months/years. **(2)** daily line compares labels through the day (+ a legend like the
example). **(3)** use the **Main menu.png** pixel icons in the app (+ the store icon from Only Get Store.png).
**(4)** remove the backdrop option; **finish the live wallpaper** (deferred — see below); put **stats next to
garden** (3 icons left, 3 right); remove **SWITCH MODE** (auto-switch to break) + a settings toggle "auto-start
break" (off → ask "start the break?"); **WORK→FOCUS**. **(5)** in garden home-mode remove the colored area
blocking the garden, move the timer to the bottom + session to the top; add **forest variety** (20 trees, 10
bushes, 5 rocks) instead of one repeated tree. **(6)** pay out **spent minutes when a session is cancelled**;
add **store category tabs** (flowers / outer / inner / pets — last two empty). **(7)** make the garden a
**rectangular, screen-ratio-aware** plot (it looked optically small as a square on a tall phone).
**Decisions (AskUserQuestion):** v13 = all the Flutter polish; the **true animated live wallpaper is its own
v14** (native Android `WallpaperService`, iOS has no API). Garden = ratio-aware **10×16** (taller-than-wide in
tiles → near-square projected, fills portrait). Forest = ~20 trees + ~10 bushes + ~5 rocks, scattered.

**Changes (11 tasks, all in `flutter/`):**
- **(#1) Stats history navigator** — `StatsAggregator.anchorFor` + an `offset` param on
  `byLabelInWindow`/`seriesFor`/`labelSeriesFor`; `AppStore.statOffset`/`shiftStatOffset`; `StatsScreen` shows a
  **◀ [period label] ▶** row (day/week-range/month/year, localized; ▶ disabled at the present).
- **(#1/#2) Stats formatting** — bar tops show **total minutes**; the pie legend lists **full (≤12-char)
  labels left + `%` right-aligned**; the **line callout** is reformatted (`TOTAL` top, per-label right-aligned,
  the selected **tick number drawn at the bottom axis**); DAILY multi-line gets a **legend**.
- **(#3/#4) Custom icons + top bar** — new `lib/icons.dart` (`IconBank` decodes the two sheets, `MenuIcon`
  slices one icon column); top bar = **theme/garden/stats · settings/store/coin** with the user's pixel art; the
  **store** icon opens the shop.
- **(#4) Timer** — removed **SWITCH MODE**; `AppStore.autoBreak` + Settings **AUTO-START BREAK ON/OFF** (off →
  the home screen asks "**Start the break?** Y/N" via `awaitingBreakPrompt`); **WORK→FOCUS** strings.
- **(#5) Garden home-mode** — dropped the scrim box; **session up top**, **timer docked at the bottom** over the
  full-strength live garden (text shadows for legibility).
- **(#5) Forest variety** — `forestPropAt(c,r)` deterministically scatters **20 `tree_NN` + 10 `bush_NN` + 5
  `rock_NN`** (generated by `gen_objects.py`) with grass gaps; the painter draws the varied props.
- **(#6) Coins on cancel** — `Economy.elapsedFocusMinutes`; `AppStore.reset()` records the spent minutes +
  awards coins before resetting.
- **(#6) Store tabs** — `ShopScreen` is stateful: **FLOWERS / OUTER DECOR / INNER DECOR / PETS** (inner & pets
  show "coming soon").
- **(#7) Garden size** — `Economy.baseGardenCols/Rows` = **10/16** (was 4×6); `Garden.atLeast` migrates older
  saves to the bigger base, keeping plantings centred; `grow()` stays +2/+2.
- **(#4) Removed** the static garden backdrop (camera keeps SET AS LIVE WALLPAPER + SAVE/SHARE).
- **Tests: 46** (35 logic + 9 engine + smoke). analyze clean; debug APK builds.
- **Docs:** TESTING.md, README.md, flutter/README.md, prompt.md updated; version → **0.13.0+14**.

## v12 — screen-filling forest, theming polish, stats rework (Flutter, 0.12.0+13)
**Date:** 2026-06-19

**Prompt (Flutter, feedback photos in `feedback & guides/Feedback/Version 10-11v Feedback/`):** 12 items.
**(1)** drop the small 4×6-plot look — the forest should fill the *whole* screen (no dark void, trees not
floating); the garden is a clearing you roam. **(2)** the system status/nav bars don't match the theme
(top gray, bottom black). **(3)** a critter once got stuck among the trees — find & fix. **(4)** garden-section
icons don't recolor with the theme like the main menu. **(5)** when peeking, the top/bottom bars don't match
the map. **(6)** rename "SET AS BACKDROP" → "SET AS LIVE WALLPAPER" and actually set the phone wallpaper (with
a permission prompt). **(7)** in garden home-mode the theme color washes out the garden — make it transparent.
**(8)** add label renaming. **(9)** pie slices of the same color blend — add a separator line. **(10)** tapping
a line-chart point should show the day + minutes + which subjects. **(11)** add DAILY/WEEKLY/MONTHLY/YEARLY/
ALL-TIME above BAR/LINE/PIE to compare. **(12)** remove the white tap animation (or theme it). **Decisions
(AskUserQuestion):** forest fills the screen, garden is a clearing you grow into; live wallpaper = rename +
set the Android **static** phone wallpaper now (true *animated* live wallpaper is a future v13; iOS keeps
Save/Share, no wallpaper API); stats period = a time window all charts redraw for (replaces the ◀month▶
navigator); DAILY line = **per-label multi-line**; all 12 in one v12; ship APK + IPA.

**Changes (all in `flutter/`):**
- **(#1) Forest fills the screen** — the engine no longer uses a fixed `WorldGrid` margin (deleted). `Projector`
  gained `gridAt`/`gridOfD`/`visibleTileBounds`; the painter draws a tree billboard on **every visible tile
  outside the claimed plot** (depth-sorted, contact-shadowed), so the woods fill the screen at any pan/zoom.
  `Projector.fit` now leaves a forest margin (`kFitMargin`) so the plot reads as a clearing; pan clamp widened
  to a roam radius. Plot-sized projector again → taps map straight to the claimed tile.
- **(#2/#12) Theme polish** — `systemOverlayFor(theme)` + `isLightColor` (pixel.dart) drive `SystemChrome` via
  an `AnnotatedRegion`, so status+nav bars match the theme bg with contrasting icons. `MaterialApp` got a
  `ThemeData` with `NoSplash.splashFactory` + transparent splash/highlight → no white ripple.
- **(#3) Stuck critter** — `Critter.maxLife` (18s) hard-despawn regardless of state + `leave` always uses a
  nonzero heading; covered by an engine test that steps a critter past its lifetime.
- **(#4/#5) Garden HUD** — peek/camera/recenter icons sit on themed `panel` chips (recolor *and* stay visible
  on the dark scene); peeking goes full-bleed (`SafeArea(top/bottom:false)`) with transparent system bars.
- **(#6) Live wallpaper** — dialog action renamed **SET AS LIVE WALLPAPER**; new `camera.setPhoneWallpaper`
  sets the Android home-screen wallpaper via **`wallpaper_manager_flutter`** (new dep), behind
  `Platform.isAndroid` (option hidden on iOS; the in-app static backdrop + Save/Share stay).
- **(#7) Home backdrop** — dropped `Opacity(0.45)`; the live garden shows full-strength with a soft scrim only
  behind the timer block for legibility.
- **(#8) Label rename** — `Labels.rename` (pure) + `AppStore.renameLabel` migrates the color, current
  selection, **and past stat records**; long-press a label row opens a rename dialog.
- **(#9/#10/#11) Stats rework** — new pure aggregators `byLabelInWindow`/`seriesFor`/`labelSeriesFor` +
  `StatPeriod`; `StatsScreen` gained a 5-button **period selector** (replaces the month navigator) feeding
  bar/line/pie. Pie wedges now get a separator stroke. The line chart is **tappable** (callout: bucket +
  total + per-label). DAILY draws **one line per label** over the last 7 days.
- **Tests: 42** (28 logic + 8 engine + smoke); smoke exercises period/chart taps, label rename, peek/camera.
  `flutter analyze` clean; debug APK builds with the new plugin.
- **Docs:** TESTING.md, README.md, flutter/README.md, prompt.md updated; version → **0.12.0+13**.

## v11 — full-screen rectangular garden world + peek/camera/background (Flutter, 0.11.0+12)
**Date:** 2026-06-18

**Prompt (Flutter, regular v11 prompt):** three asks. **(1)** Stop making the garden a small rectangle on a
flat 2D image — make it a **full-screen, portrait, screen-indexed** 2.5D world. The garden is e.g. a **4-wide ×
6-tall** plot and *all the surrounding area is garden too*; as you develop it, the **surrounding dark trees turn
to grass one by one** and the garden area expands. **(2)** A bottom-left button to **see just the garden (hide
all HUD)**, like the bottom-right recenter symbol; next to it a **camera mode** where you frame any angle, take a
**screenshot**, and **set it as a background** — the background can be **active** (live, with critters wandering,
wallpaper-engine style) **or a static photo**. **(3)** The engine should be **suitable for a live wallpaper**.
Decisions taken up front (via AskUserQuestion): in-app live background + static export (no OS live-wallpaper
service — iOS has no API, Android would need native Kotlin that breaks the no-Mac CI); rectangular **cols×rows
starting 4×6**; the **forest is a receding border** of one unified world; camera framing keeps the **fixed tilt**
(yaw/zoom/pan only); the **static photo lives only in the garden section**, while the **home screen** gets a
**Settings `Clean | Garden`** toggle where Garden = the **live** garden behind the timer.

**Changes (all in `flutter/`):**
- **Rectangular garden model** — `Garden` is now **`cols × rows` (default 4×6)** instead of a square `size`;
  index = `r*cols+c`, `grow()` adds a centered ring (4×6 → 6×8), `Economy.upgradeCost(cols,rows)=2*(cols+rows)+1`,
  and `decode` migrates a legacy `size:` square. `Projector`/`GardenCamera`/`GardenPainter`/`GardenView`/`store`
  all generalized off the single dimension. TDD: rewritten `logic_test` + new rectangular `engine_test` group.
- **One screen-filling 2.5D world (#1)** — new `WorldGrid` (claimed plot centered inside a **margin-2 forest
  border**) + `forestMargin`. The painter now sizes the projector to the **whole world**, so the scene fills the
  portrait screen; unclaimed tiles draw a new **`tree.png`** billboard (depth-sorted with flowers/fences) over a
  dark forest floor, replacing the old flat screen-space `forest` blit. EXPAND converts the inner forest ring to
  grass. Taps map world-tile → claimed-tile (forest isn't plantable); pan-clamp uses world bounds.
- **Peek button (#2)** — bottom-left `peekButton` in `GardenView` (mirrors the recenter button) toggles a flag
  on the now-**stateful `GardenScreen`** that hides **all** HUD (title, EXPAND, help, CUSTOMIZE/CLOSE), leaving
  only the world. Tap again to restore.
- **Camera mode + screenshot + background (#2, #3)** — a `cameraButton` enters a clean framing mode
  (HUD hidden, yaw/zoom/pan). New `lib/camera.dart`: `captureBoundary` (screenshots a `RepaintBoundary` keyed
  `captureKey`), `saveBackdropPng` (persists via `path_provider`), `sharePng` (system share sheet via
  `share_plus`). CAPTURE → **Set as backdrop** (static photo shown in the garden section, with a CLEAR control) /
  **Save / Share** / Cancel. New deps: `share_plus`, `path_provider`.
- **Home-screen mode (#3)** — `AppStore.homeGardenBackdrop` + Settings **`CLEAN | GARDEN`** toggle; when GARDEN,
  `HomeScreen` renders a dimmed, **non-interactive** live `GardenView` behind the timer (the "engine as live
  wallpaper" deliverable). The static photo is deliberately **never** placed behind the running timer.
- **Tests:** `flutter analyze` clean, **31 tests** (24 logic + 7 engine + smoke). Smoke now exercises peek,
  camera mode, and the home-mode toggle, and uses `runAsync` to load the sprite PNGs in-test.
- **Docs:** `TESTING.md`, `README.md`, `flutter/README.md`, `prompt.md` updated; version → **0.11.0+12**.

## v10 — no-sun flat lighting, flowers back to single billboards, fences become real low-poly 3D
**Date:** 2026-06-18

**Prompt (Flutter, feedback photos in `feedback & guides/Feedback/Version 08-09v Feedback/`):** a step-back
architecture review before committing further. The garden "acts like a sun is looking from one way and other
angles have shadows" — it should look like **there is no sun, every angle has the same sunlight**; and the
**fences have bugs** (a thin metallic post that nearly vanishes at some angles). Goals restated: pixel-art look,
360° camera, pinch/pan/rotate, view from any angle, **no billboard fakeness**, *between* pixel-art and low-poly
3D (Apico/Littlewood feel; Kynseed roof-off house interiors **near-term**), not Stardew's fixed camera, not
realistic 3D. After a critical no-agreement-bias evaluation of 8 rendering approaches, **decisions taken:**
adopt a staged move to real low-poly 3D (not Unity/Godot — a dependency-free `Canvas`-based mesh pipeline), and
**don't 3D-model radially-symmetric flowers** (a billboard is indistinguishable and 8× cheaper). v10 is the
bounded, shippable first step.

**Changes (all in `flutter/`):**
- **No-sun lighting:** `tools/gen_objects.py` `spin_frame` dropped the view-dependent `front-bright/back-dark`
  shading **and** the leading-edge highlight — frames now only carry the `|cos|` horizontal squash. Rotating an
  object no longer sweeps a fake sun across it; light is flat sky-ambient, identical from every side. This was
  the literal cause of the "sun from one direction" complaint (`bright = 0.62 + 0.38*cos θ`).
- **Flowers → single billboards:** flowers were shipping as 8-frame directional atlases, but a flower is
  radially symmetric so all 8 facets looked the same — it read as a flat card *and* cost 8× the memory. The
  generator now emits one frame per flower (PNG `1280×160 → 160×160`); the engine draws the full image (no
  atlas slice). Same look, far cheaper, simpler code.
- **Fences → real low-poly 3D mesh (first piece of the reusable pipeline):** new tested geometry —
  `Projector.projectElevated(g, e)` (vertical maps straight up the screen by `e·t`, identical for every yaw)
  and top-level `boxCorners(p, c, half, height)` (the 8 screen corners of an upright box). A fence is now an
  upright **3D post** (4 flat side faces + a slightly-brighter sky-lit top, drawn last) with **raised 3D
  ribbon rails** between any adjacent posts (`_paintFenceRails`/`_paintFencePost`/`_fillQuad`). It keeps a solid
  footprint and consistent thickness from every angle — the "thin antenna" bug is gone. Fences are no longer
  loaded into `SpriteBank`; their PNG is now only a shop thumbnail (`objectThumb` simplified — no atlas slice).
- **Critters unchanged:** still 8-frame atlases (a bee should face its travel heading), now with the flat
  lighting too.

**Testing:** new `test/engine_test.dart` (TDD, 3 tests) covers `projectElevated` yaw-independence and `boxCorners`
(8 corners, top directly above base, centred footprint with real width from every angle). Full suite **26 tests**
green (20 logic + 3 engine + 3 placeable-overlay) plus the boot/overlay **smoke test**; `flutter analyze` clean;
debug APK builds locally. The garden render itself is verified **on-device** (headless `toImage` hangs here).

---

## v9 — 8-direction sprite atlases, standing connected fences, fences-on-roads, forest surround, plain 2D coin
**Date:** 2026-06-18

**Prompt (Flutter, feedback photos in `feedback & guides/Feedback/Version 07v Feedback/`):**
(1) different fences don't **connect** to each other — make them join; and fences sit on the
ground as **dots** (a bug), they should **stand like flowers**. (2) let fences be built **on top
of roads** too, but **not** flowers. (3) make everything **outside** the garden look like a
**dense forest / rocks** filling the whole area, as if the critters come from deep in the woods.
(4) build objects with an **8-direction sprite** system (`flower_n…flower_nw`) and pick the right
frame from the atlas by **camera angle**, for a multi-dimensional (3D) illusion. (5) the gold coin
should be **plain 2D** — no animation, no smiley inside, just gold. *(Decisions taken via a quick
ask: 8-dir applies to flowers + fences + critters; fences stand & connect across any material;
fence-on-road keeps both as an overlay.)*

**Changes (all in `flutter/`):**
- **8-direction atlases (#4):** `tools/gen_objects.py` now spins each base sprite about its
  vertical axis into an **8-frame horizontal atlas** (`spin_frame` + `make_atlas`): horizontal
  squash by `|cos|`, front-bright/back-dark shading, and a leading-edge highlight so left/right
  turns differ. Flowers, fences and critters all ship as atlases. The engine adds `frameForAngle`
  and slices the facet that matches the **camera yaw** (flowers/fences) or the **travel heading**
  (critters), so objects visibly turn in 3D instead of staying dead-on (and never flip to face you).
- **Standing, connected fences (#1):** reverted v8's flat ground-network. A fence is now a
  **standing post billboard** (directional atlas), and `_paintFenceRails` draws two raised
  screen-space rails between **any** adjacent fence posts — wood joins dark joins stone — so
  different materials connect, horizontally and vertically. No more ground "dots".
- **Fences on roads / overlay model (#2):** a tile can hold a flat **ground** (road) plus a
  standing **prop** (flower or fence). `Placeables.split/combine/groundOf/propOf` parse the new
  `"road+fence"` composite; `Garden.plant` layers a fence onto a road (keeps both), slides a road
  under a fence, and **refuses flowers on roads**. The place dialog hides flowers on road tiles.
- **Forest/rock surround (#3):** new `forest.png` tile; the painter fills the **whole screen**
  with it behind the soil slab, so the plot reads as a clearing and critters drift in from the trees.
- **Plain 2D coin (#5):** `coin.png` regenerated as a clean struck-gold disc — dark rim, gold face,
  one top-left shine, **no centre marks** (the old bevel that read as a smiley is gone). `GoldCoin`
  is now a **static** `StatelessWidget` (no spin/animation); the `animate` flag is kept as a no-op.
- **Version → 0.9.0+10**, publishes **`flutter-v9`** (v6/v7/v8 kept as history).

**Verified:** `flutter analyze` clean, **23/23 tests pass** (added 3 overlay tests: fence-on-road
layering + round-trip, road-under-fence vs clears-flower, flowers-refuse-roads). Debug APK builds
locally with the new atlas sprites; iOS `.ipa` builds on the macOS CI runner. *The 8-direction
turning, fence joins, forest backdrop and coin are visual — please eyeball them on the v9 build.*

---

## v8 — Garden-anchored critters, customize gridlines, ground-connected fences, plant/grass contrast, animated pixel coin
**Date:** 2026-06-17

**Prompt (Flutter, feedback photos in `feedback/Version 07v Feedback/`, incl. inspiration
images):** (1) versioning — keep incrementing, this build = **v8** (chosen via a quick ask).
(2) critters are pinned to the **screen**, not the garden — when I rotate, they don't move
with it. (3) on **CUSTOMIZE**, show **gridlines** on the tiles so I know where I can place.
(4) all objects face the **screen** not the garden — fences/flowers keep turning to follow me
when I rotate, and **fences don't connect** (should join horizontally *and* vertically like
roads). (5) the **cactus + plant stems blend** into the green grass — separate them (refs:
`1000_F*` grass + `seamless` cactus). (6) the coin isn't **pixel** — make it pixel-style
(ref: a pixel-coin spin animation), don't copy directly.

**Changes (all in `flutter/`):**
- **Garden-anchored critters (#2):** `CritterSystem` now lives in **garden coordinates**
  (tiles), not screen pixels — it spawns at plot edges, flies to flower tiles, hovers, leaves,
  and the painter **projects** each critter through the camera. So they rotate/zoom with the
  map instead of floating on the screen.
- **Customize gridlines (#3):** in CUSTOMIZE the painter draws the tile grid (projected, so it
  follows the rotation) so it's obvious which tile a tap will hit.
- **Ground-connected fences (#4):** fences are no longer upright billboards (which spun to
  face you). They're drawn as a **connected ground network** — a post per tile plus rails
  toward each same-fence neighbour, **joining horizontally and vertically** like roads — in
  garden space, so they rotate *with* the garden. Flowers stay standing (they read fine from
  any side). The fence sprites are now solid colours (`_fencePalette`), not PNGs.
- **Plant/grass contrast (#5):** grass redrawn brighter + textured (tufts, olive speckle, like
  the inspiration), and every garden flower/cactus PNG now gets a **dark 1px outline**
  (rendered on a 10×10 canvas) so green stems/cacti separate cleanly from the grass.
- **Animated pixel coin (#6):** replaced the smooth-circle coin with a **pixel-art `coin.png`**
  that **spins** in the wallet (horizontal squash, crisp `filterQuality.none`). A
  `GoldCoin.animate` flag lets tests disable the perpetual spin.
- **Version → 0.8.0+9**, publishes **`flutter-v8`** (kept v6/v7 as history per your choice).

**Verified:** `flutter analyze` clean, **20/20 tests pass** (smoke test taps the new coin
button by key and disables the spin so it settles), debug APK builds locally with 22 sprites.
iOS `.ipa` builds on the macOS CI runner. *Camera rotation, fence joins and critter motion are
visual/time-based — please eyeball them on the v8 build.*

---

## v7 — Centered garden growth, hand-rotate camera, concrete road, fence/road trims, bigger Korean font, $-free coin
**Date:** 2026-06-17

**Prompt (Flutter, with feedback photos in `feedback/Version 06v Feedback/`):** (1) keep
the critters — they're great. (2) EXPAND grows to one side; it should grow **centered**, a
square ring on all 4 sides. (3) Korean font is **too small to read**. (4) let me **change
the angle by hand** like Google Maps (look from E/W/N). (5) remove **brick road** and **white
fence**; keep wood + dark-brown + stone fences. (6) change the **asphalt road → concrete**.
(7) the coin shows a **dollar sign**; it should just be gold.

**Changes (all in `flutter/`):**
- **Centered growth (#2):** `Garden.grow()` now adds a **ring on every side** (size +2,
  existing tiles shifted +1/+1) so the plot expands from the middle instead of the
  bottom-right. The engine already centers the plot, so content now stays put as it grows.
- **Hand-rotate camera (#4):** brought back angle control, but as a **two-finger twist**
  (`GardenCamera.yaw`) — like Google Maps, look at the garden from any compass direction.
  The renderer now draws the ground (grass + flat roads) through a **yaw+squash affine** and
  sorts standing objects back-to-front by screen depth, so rotation is correct and taps still
  land right (`Projector` inverse un-rotates). Tilt stays fixed (no slider). Recenter resets
  zoom/pan/rotation.
- **Korean font (#3):** Galmuri11 sits small in its em box, so Korean text is now scaled
  **×1.5** in `pixelStyle` — readable while staying pixel-styled.
- **Road/fence trims (#5,#6):** roads are now **concrete / wood / dirt / stone** (asphalt
  reworked into a gray concrete-slab tile, **brick removed**); fences are **wood / dark /
  stone** (**white removed**). Sprites regenerated (21 PNGs); the dropped ones are deleted.
- **Gold coin (#7):** replaced Material's `monetization_on` (which draws a "$") with a
  custom **`GoldCoin`** disc — just gold, no symbol.
- 6-language strings updated (concrete name, dropped brick/white, "twist to rotate" help).
  **Version → 0.7.0+8** → publishes the **`flutter-v7`** release.

**Verified:** `flutter analyze` clean, **20/20 tests pass** (catalogue now 4 roads + 3 fences;
grow test asserts the centered ring; smoke test taps the new coin button by key), debug APK
builds locally with the 21 sprites. iOS `.ipa` builds on the macOS CI runner.

> Note on the home-screen icon in the feedback photos: App-info already shows the correct
> pixel-tomato, so the icon itself is fixed; the blue launcher tile looked like the older
> install. Flag it again if a fresh v7 install still shows the default.

---

## v6 — Fixed 2.5D garden (no tilt), 5 roads + 4 fences, flower-visiting critters, Korean pixel font
**Date:** 2026-06-17

**Prompt (Flutter, garden polish):** (1) the garden must stay **fixed on screen** — I
could drag it off, I don't want that. (2) **Remove** the bottom tilt/angle slider; just
give a fixed **2.5D depth** feel. (3) fences connected badly (lay flat / didn't read in
the vertical direction) and flowers **floated** when tilting — fix it (the angle feature
is gone anyway). (4) **5 roads** (asphalt, wood, dirt, brick, stone). (5) **3 more fences**
(dark brown, stone-gray, white/concrete) → 4 total. (6) **fewer, smarter critters**: tiny
bee/butterfly/ladybug that **visit flowers** (land as if sniffing) then leave — not a swarm
of random dots. (7) add a **Korean pixel font** (Press Start 2P has no Hangul).

**Changes (all in `flutter/`):**
- **Garden engine rewritten** (`lib/engine/`): removed the camera **pitch/tilt** entirely —
  depth is now a single fixed projection constant (`kVy`). Pan is **clamped** so the garden
  can never leave the viewport (it stays centered when not zoomed in). Pinch-zoom is bounded
  to 1×–4×. New shared `Projector` (fit + exact tile↔screen inverse). Removed the tilt slider
  from `garden_view.dart`.
- **Standing vs flat**, fixes #3: roads draw **flat** on the ground; **fences stand up** as
  billboards (a column of them reads as a fence going back, so vertical runs look right);
  **flowers are anchored** to the tile base (no more floating), with a contact shadow.
- **5 roads + 4 fences**: `Placeables` now holds `roadIds` (asphalt/wood/dirt/brick/stone)
  and `fenceIds` (wood/dark/stone/white) with `isRoad`/`isFence`; all 5 coins. Adjacent
  same-kind tiles abut, so paths/fences read as continuous — the old connector-bar
  auto-tiling (`connectionMask`) was **deleted** (it caused the bad flat fence joins).
  *(Your road list had "wood" twice; I made #4 **brick** so all five are distinct.)*
- **Critters reworked**: max **2** at a time, spawned every ~6–14s. Each flies in from an
  edge, heads to a **random planted flower**, hovers (sniffs) ~2–4s, then leaves the map and
  despawns. Three tiny sprites — **bee / butterfly / ladybug** (no oversized wings).
- **Sprites** regenerated by `tools/gen_objects.py` (now 23 PNGs in `assets/objects/`):
  5 roads, 4 fences, 3 critters; old `road/fence/bug.png` removed.
- **Korean pixel font (#7)**: bundled **Galmuri11** (OFL pixel font with full Hangul) at
  `assets/fonts/Galmuri11.ttf` (+ `Galmuri-OFL.txt`); `fontFor('ko')` now returns it instead
  of the system font, so Korean keeps the retro look.
- 6-language strings updated for the 9 new item names; dropped the stale "slider tilts the
  view" help text. **Version → 0.6.0+7.** CI now publishes a permanent **`flutter-v6`**
  release (and keeps the rolling `latest-flutter`).

**Verified:** `flutter analyze` clean, **20/20 tests pass** (Placeables catalogue/costOf/codec
rewritten for the new ids; connectionMask tests removed), debug APK builds locally with the
new font + 23 sprites. iOS `.ipa` builds on the macOS CI runner.

---

## Living 2.5D garden + a purpose-built engine, road/fence decor, logo fix (Flutter)
**Date:** 2026-06-16

**Prompt:** redo the garden as a live, gapless, green **2.5D** scene (no tile numbers,
no max size) with **pinch-zoom / pan / adjustable look-from-above angle** and
**random wandering pixel bugs**; add **road + fence** to the shop at **5 coins** that
**auto-connect** like a simulation game; keep every drawn object as a **PNG in an
objects directory**; use a **custom mini game engine** (no Unity); and **fix the
Flutter launcher icon** that reverted to the default logo on the phone.

**What landed (all in `flutter/`):**
- **Custom garden engine** — `lib/engine/garden_engine.dart` + `lib/engine/garden_view.dart`.
  A tiny purpose-built renderer (no Flame/Unity): an oblique **2.5D "look from above"
  projection** that **tilts** (slider), **pinch-zooms** and **pans** with fingers; a
  **contiguous green grass field with no gaps**; a raised soil slab for depth; flowers
  that **stand up and sway** as you tilt; and a flock of **randomly-wandering pixel bugs**
  (each with its own speed/heading/wobble/tint, count scales with plot size). The
  screen↔tile inverse is exact so taps still land right.
- **Garden screen rebuilt** (`main.dart`) — full-screen live scene, **no `8×8` tile
  numbers shown**, **no size cap** (EXPAND keeps costing `2n+1`). Tap a tile while
  customizing to place/clear anything you own (flowers **and** objects).
- **Road & fence decor** — new `Placeables` in `logic.dart`; both cost **5 coins**
  (`Economy.objectCost`), buyable in the SHOP under a **DECOR** section. They
  **auto-tile**: `Garden.connectionMask` bridges toward same-kind neighbours so paths
  and fences read as continuous (no edge wrap). `buyFlower` now routes through a generic
  `buyItem(id)`.
- **Art as data** — every object is a crisp **PNG in `assets/objects/`** (grass, bug,
  road, fence + all 10 flowers), generated by the dependency-free `tools/gen_objects.py`.
- **Launcher-icon fix (#9)** — added `flutter_launcher_icons` + `assets/icon/app_icon*.png`
  (the pixel tomato) and a CI step `dart run flutter_launcher_icons` **after** `flutter
  create`, so the real logo is baked back in every build instead of the Flutter default.
  Source icon generated by `tools/gen_icon.py`.
- 6-language strings updated (DECOR/ROAD/FENCE/RECENTER, new garden help, EXPAND).

**Verified:** `flutter analyze` clean, **20/20 tests pass** (was 16 — added no-cap
growth, `costOf`, codec round-trip for objects, and `connectionMask` edge cases incl.
no-wrap; the widget smoke test now drives the live garden ticker), and a **debug APK
builds locally** with the bundled assets + Android launcher icon. iOS icon + `.ipa`
build on the macOS CI runner.

---

## Flutter port verified green — smoke test + CI hardening
**Date:** 2026-06-16

**Prompt:** "check again where we left off and continue" (the Flutter iOS step was
left mid-validation when the connection dropped).

**Where we picked up:** the Flutter port code was already committed; what remained was
the final validation pass. Flutter is now installed locally (3.44.2 / Dart 3.12.2), so
this was validated on-machine, not just in CI.

**What landed:**
- `flutter/test/widget_smoke_test.dart` — boots the **real** app and opens every overlay
  (settings, garden, stats, shop, theme, labels), asserting no exceptions or layout
  overflow. This is the runtime check the pure-logic tests can't give. It's part of the
  CI gate (`flutter test`), so a broken screen now blocks the build.
- `flutter/README.md` — pinned the validated toolchain (Flutter 3.44.2 / Dart 3.12.2,
  Android SDK 36 + build-tools 36) and documented the Gradle `-Xmx8G` low-RAM crash
  workaround for local builds.
- **CI hardening:** bumped `actions/checkout` and `actions/upload-artifact` to **v5** in
  both pipelines (GitHub forced Node 20 actions onto Node 24 starting 2026-06-16).

**Verified:** locally `flutter analyze` clean + **16/16 tests pass** (15 logic + smoke).
In CI both pipelines are **green on v5** — Build Flutter (iOS+Android) 7.6 min, Build APK
88 s. The unsigned **`pixel_pomo_ios.ipa`** (~6.4 MB) + **`pixel_pomo_flutter.apk`**
(~46 MB) are published to the **`latest-flutter`** prerelease. **The iOS build is real and
working** — sideload the `.ipa` via SideStore/AltStore (on-device signing, no Mac).

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
