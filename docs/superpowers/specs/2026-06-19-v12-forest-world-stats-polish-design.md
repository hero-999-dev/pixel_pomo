# Pixel Pomo v12 — screen-filling forest world, theming polish, stats rework

**Date:** 2026-06-19
**Version target:** Flutter `0.12.0+13` → release `flutter-v12` (Android APK + unsigned iOS IPA)
**Scope:** one release, all 12 feedback items (live *animated* wallpaper deferred to v13)

v12 is the feedback round on v11 (photos in `feedback & guides/Feedback/Version 10-11v Feedback/`).
12 items: a screen-filling forest world, system-bar + splash theming, a stuck-critter bug,
garden HUD theming, a live-wallpaper rename + static phone-wallpaper set, an un-dimmed home
backdrop, label rename, and three stats upgrades (pie separators, line-chart tap details, a
period selector).

## Decisions locked with the user

1. **Forest world (#1):** the forest covers the **entire screen** edge-to-edge at any pan/zoom
   (no dark void, trees grounded). The grass garden is a **clearing** in the middle that EXPAND
   grows outward into the woods. Drop the fixed margin-2 border.
2. **Live wallpaper (#6):** rename "SET AS BACKDROP" → **"SET AS LIVE WALLPAPER"**, and on
   **Android** set the captured frame as the phone's wallpaper (static image) after a confirm
   prompt. Use an **Android-only pub plugin guarded by `Platform.isAndroid`** so the iOS build is
   unaffected (button hidden on iOS; iOS keeps Save/Share). True *animated* live wallpaper =
   future v13.
3. **Stats period (#11):** a period selector (DAILY/WEEKLY/MONTHLY/YEARLY/ALL-TIME) **above** the
   BAR/LINE/PIE row sets a **time window**; all three charts redraw for it. **Replaces** the
   `◀ month ▶` navigator.
4. **Scope:** all 12 in v12. Both APK + IPA still publish.

## Background: current code

- `flutter/lib/engine/garden_engine.dart` — `Projector` (rectangular cols×rows), `WorldGrid`
  (claimed plot + `forestMargin`=2), `GardenPainter` (forest floor fill + tree billboards on
  unclaimed world tiles), `CritterSystem` (garden-coord critters), `GardenCamera.clamp`.
- `flutter/lib/engine/garden_view.dart` — gestures, ticker, peek/camera buttons, `interactive`.
- `flutter/lib/main.dart` — `PixelPomoApp` (`MaterialApp`, **no `ThemeData`**, **no `SystemChrome`**),
  `HomeScreen` (live backdrop wrapped in `Opacity(0.45)`), `GardenScreen` (peek/camera/static
  backdrop), `LabelScreen` (select+color+delete, **no rename**), `StatsScreen` (`◀ month ▶` +
  BAR/LINE/PIE + totals + by-label-month).
- `flutter/lib/pixel.dart` — `StatsChart`/`_ChartPainter` (bar/line/pie, **no pie separators, no
  line tap**), `PixelButton` (GestureDetector, no splash).
- `flutter/lib/logic.dart` — `Labels` (normalize/add/remove, **no rename**), `StatsAggregator`
  (aggregate/byLabelInMonth/dailySeries/monthTotal/byLabelAll), `LabelColors`.
- `flutter/lib/store.dart` — `AppStore`; stats view state (`chartMode`, `viewYear/Month`).

## Architecture by item

### #1 — Screen-filling forest world (engine)
Replace the finite `WorldGrid` margin with a forest that always fills the viewport.
- `GardenPainter.paint`: compute the **visible tile range** by inverse-projecting the four screen
  corners (`Projector.tileAtContinuous`), then draw a tree billboard on **every visible tile that
  is not in the claimed clearing** (plus a 1-tile bleed), over the existing full-screen dark forest
  floor. This guarantees no void at any pan/zoom.
- **Grounding (#1 "floating"):** each tree keeps a contact-shadow ellipse and anchors its base to
  the tile center; verified the sprite's trunk sits on the ground line.
- The **claimed clearing** stays a rectangular `cols×rows` plot (grass + soil slab + roads/fences/
  flowers), centered; EXPAND grows it (unchanged mechanic) so it eats into the surrounding forest.
- **Pan clamp (#1 "roam"):** widen `GardenCamera.clamp` to a roam bound (a few tiles of forest
  beyond the clearing in every direction, scaled with zoom) so you can pan around the woods but
  can't lose the garden entirely. `WorldGrid` simplifies to "is this tile claimed?"; `forestMargin`
  is removed (the forest is view-driven, not a fixed ring).
- New pure-ish helpers on `Projector` for the visible-range math get engine_test coverage
  (`tileAtContinuous` inverse + a `visibleTileBounds(size)` returning min/max col,row).

### #2 — System bars match the theme (cross-cutting)
Add `SystemChrome.setSystemUIOverlayStyle` driven by the active theme:
- status bar + system navigation bar colored to `theme.bg`; icon brightness chosen from `bg`
  luminance (light bg → dark icons, dark bg → light icons).
- Applied in `PixelPomoApp.build` (already rebuilds on theme change via the messenger/AnimatedBuilder
  path) using `AnnotatedRegion<SystemUiOverlayStyle>` around `home`, so it re-applies on every theme
  switch. A small pure helper `systemOverlayFor(PixelTheme)` (in `pixel.dart`) is unit-tested for the
  brightness decision.

### #3 — Stuck critter bug (systematic-debugging)
Investigated cause: a critter in `leave` whose exit target nearly equals its position barely moves
(`dist→0`) and is only removed once `|pos| > half+0.5`, so it can pin in place (worsened now that the
forest fills the screen). Fix: add a **hard max-lifetime** to every critter (despawn after ~N s
regardless of state) plus make `leave` always head to the nearest off-clearing edge with a guaranteed
nonzero heading. Covered by an engine/logic test that steps a critter past its lifetime and asserts it
despawns.

### #4 — Garden HUD follows the theme
The in-scene control icons (peek/camera/recenter) are tinted `theme.onSurface` but vanish on the
dark forest scene in light themes. Fix: wrap each in a small rounded **chip** filled with a
semi-opaque `theme.panel` + border `theme.onSurfaceDim`, icon `theme.onSurface` — so they both stay
visible on the scene **and** visibly recolor with the theme. Garden top bar / EXPAND / CUSTOMIZE /
CLOSE already use theme colors (unchanged).

### #5 — Peek mode: bars match the scene
When peeking (HUD hidden), make the garden **full-bleed** (extend behind the status/nav bar areas)
and set the system bars transparent so the forest shows edge-to-edge with no mismatched strips. On
peek exit, restore the themed system bars (#2). Implemented by toggling an `AnnotatedRegion` overlay
style + dropping the top/bottom `SafeArea` padding for the scene while peeking.

### #6 — Rename "Set as live wallpaper" + set Android phone wallpaper
- Rename the dialog action to **`setLiveWallpaper`** ("SET AS LIVE WALLPAPER" + 6-lang strings).
- New `camera.dart` `setPhoneWallpaper(Uint8List bytes)`: on `Platform.isAndroid`, write the PNG to a
  temp file and call an **Android-only wallpaper plugin** (e.g. `wallpaper_manager_flutter`, pinned)
  to set the home-screen wallpaper; show a confirm dialog first ("Set as phone wallpaper?"). The
  plugin is android-only, so the iOS build skips it; the button is hidden when `!Platform.isAndroid`.
- The plugin's manifest contributes `SET_WALLPAPER`; **no android/ native overlay** needed (keeps the
  no-Mac CI lazy). If the plugin fails to build on the CI, fall back to the existing Save/Share.
- (The captured shot can also still be set as the in-app static garden backdrop — that option stays.)

### #7 — Home garden backdrop not dimmed
Remove the `Opacity(0.45)` wrapper so the live garden shows at full strength behind the timer (#7:
no theme color wash). Keep text legible with a **localized scrim only behind the timer block** (a
subtle `theme.bg` vertical gradient / rounded panel behind the WORK/label/clock/controls column),
not over the whole garden. Garden stays fully visible.

### #8 — Rename labels
- `logic.dart` `Labels.rename(list, old, newRaw)` (pure: normalize new, reject empty/dupe, replace in
  place) — unit-tested.
- `store.dart` `renameLabel(old, newRaw)`: updates the labels list, **migrates** `labelColors` key,
  `currentLabel`, and existing `SessionRecord`s with that label to the new name (so stats stay
  consistent); persists. A pure `StatsCodec`-level remap helper is unit-tested.
- `LabelScreen`: **long-press** a label row opens a rename dialog (TextField prefilled, char cap 12);
  tap still selects, swatch still picks color, trash still deletes. A short hint is added to the
  screen.

### #9 — Pie chart slice separators
In `_ChartPainter._pie`, after filling each wedge, **stroke its boundary** (radial edges + arc) with
`theme.bg`, width ~2, so same-colored adjacent slices are visually separated. Plus an outer circle
stroke. Visual; no unit test (eyeballed + smoke).

### #10 — Line chart tap → day details
Make the chart interactive:
- `StatsChart` becomes stateful (or wrapped in a `GestureDetector`) tracking a **selected x-index**.
- On tap, find the nearest point; paint a callout near it showing the **bucket label** (e.g. day/
  month), **total minutes**, and the **per-label breakdown** for that bucket; highlight the x-axis
  tick.
- The screen passes a `List<List<ChartEntry>>` (per-x-bucket by-label) alongside the series, computed
  by a new aggregator. The per-bucket breakdown computation is pure and unit-tested.

### #11 — Stats period selector (replaces month navigator)
- `store.dart`: add `StatPeriod { daily, weekly, monthly, yearly, allTime }` + `statPeriod` state +
  `setStatPeriod`; remove the `viewYear/Month` navigator usage from `StatsScreen` (keep the fields or
  drop — decided: drop the `◀▶` UI, keep `shiftMonth` unused-removed).
- `StatsScreen`: a period row (5 buttons) **above** the BAR/LINE/PIE row. Selected = accent.
- `StatsAggregator` new functions, all pure + unit-tested, defined for "now":
  - **window by-label** `byLabelInWindow(records, now, period)` (today / this week Mon–Sun / this
    month / this year / all-time).
  - **series + bucket breakdown** `seriesFor(records, now, period)` →
    - daily → last 7 days, one point/day;
    - weekly → this week, 7 days;
    - monthly → this month, per-day;
    - yearly → this year, per-month (12);
    - allTime → per-year (min year..this year).
    returns the `List<int>` series, the x tick labels, and the per-bucket by-label list (for #10).
- BAR & PIE use `byLabelInWindow`; LINE uses the series. The 5-row totals block (today/week/month/
  year/all) stays as a quick summary; the by-label list reflects the selected period.

### #12 — Kill the white tap animation
Give `MaterialApp` a `ThemeData` with `splashFactory: NoSplash.splashFactory`,
`splashColor: Colors.transparent`, `highlightColor: Colors.transparent`, and a `canvasColor`/
`dialogBackgroundColor` from the theme, so `IconButton`/`TextButton`/dialog ripples no longer flash
white. Pixel buttons (GestureDetector) are already splash-free.

## New dependencies
- One **Android-only wallpaper plugin** (e.g. `wallpaper_manager_flutter`, pinned) — used only behind
  `Platform.isAndroid`; iOS build skips it. No other deps.

## Testing (per the standing edge-test practice)
TDD where pure; visuals stay user-verified on-device (headless `toImage`/render gotcha).
- **logic_test:** `Labels.rename` (normalize, dupe/empty reject, replace); label-rename record/color
  migration; `StatsAggregator.byLabelInWindow` + `seriesFor` for all 5 periods (bucketing edges);
  per-bucket by-label breakdown for #10.
- **engine_test:** `Projector.tileAtContinuous` inverse + `visibleTileBounds` cover the screen;
  critter max-lifetime despawn; `systemOverlayFor` brightness decision.
- **widget_smoke_test:** boots app; exercises label **rename** (long-press), stats **period** buttons
  + chart types, the garden (peek/camera) — asserting no exceptions/overflow; wallpaper call is
  guarded/mocked (not invoked in tests).
- Update `TESTING.md` with cases + the known gaps (forest fill / pie separators / line callout /
  wallpaper set / system bars are visual / device-only).

## Deliverables (standing workflow)
`log.md` (v12 entry), `prompt.md` (recreation prompt refresh), `README.md` + `flutter/README.md`
(structure), `TESTING.md` (results), a v12 memory; bump `pubspec.yaml` → `0.12.0+13`; commit & push
`main` → CI builds APK + unsigned IPA → publishes `flutter-v12` + `latest-flutter` with title
`Flutter build (iOS + Android, vX.Y.Z)`. No `Co-Authored-By` trailer.

## Out of scope (explicit YAGNI)
- True **animated** live-wallpaper service (Android `WallpaperService`) — that's v13.
- Any iOS wallpaper-setting (no API).
- Sub-day (hourly) stats (records store epoch-day granularity only).
- Native android/ overlay (the wallpaper set uses a pub plugin, not committed native code).
