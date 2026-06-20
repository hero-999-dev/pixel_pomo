# Pixel Pomo v14 — visible menu icons, stats TREND redesign, bounded forest world, polish

**Date:** 2026-06-20
**Version target:** Flutter `0.14.0+15` → release `flutter-v14` (Android APK + unsigned iOS IPA)
**Scope:** one release — the 7 v13-feedback items.

v14 is the feedback round on v13 (photos in `feedback & guides/Feedback/Version 13v Feedback/`). The big
ones are the **menu icons** (invisible) and the **LINE → TREND** stats redesign; the rest are the bounded
forest world, the garden-screen HUD readability, a calmer grass tile, and a shop cleanup.

## Decisions locked with the user

1. **Icons (#1):** the v13 runtime-slicer cropped the sheet's **non-transparent navy background**, so icons
   rendered as dark boxes. Fix = **generate 5 clean transparent 32×32 pixel-art icons** in the sprite
   generator and draw them directly (no sheet slicing).
2. **Daily TREND (#2):** add a **per-session timestamp** (`minuteOfDay`) so DAILY trend is a true cumulative
   curve over 00→24h. Legacy/seeded records lack the time and simply don't appear on the hourly curve.
3. **Stats summary (#2):** **CURRENT / AVERAGE / BEST** (period-contextual) replaces the TODAY/WEEK/MONTH/
   YEAR/ALL-TIME block **only on the TREND page**; BAR/PIE keep the existing 5-row totals.
4. **Forest world (#4):** **bounded** — a fixed forest border around the garden, sized to fill the portrait
   screen; EXPAND grows the garden toward the border; the forest is no longer infinite/roamable.

## Background: current state (v13, shipped)

- `lib/icons.dart` — `IconBank` (loads `menu_sheet.png`/`store_sheet.png`) + `MenuIcon` (slices a column).
  `HomeScreen._topBar` renders `MenuIcon`s via a `FutureBuilder<IconBank>`. **This is the broken path.**
- `lib/logic.dart` — `SessionRecord(epochDay, minutes, label)`; `StatsCodec` CSV `day,min,label`;
  `StatsAggregator` (`windowDays`/`anchorFor`/`byLabelInWindow`/`seriesFor`/`labelSeriesFor`,
  `StatPeriod`, `StatSeries`, `LabelSeries`); `Economy`, `Garden` (base 10×16, `grow()` +2/+2).
- `lib/pixel.dart` — `StatsChart`/`_ChartPainter`: bar (minutes), pie (aligned legend), **line** (single or
  daily multi-line per label + legend), tap **`_callout`** (can overflow the chart top — the #2 bug).
- `lib/main.dart` — `StatsScreen` (period buttons + ◀▶ navigator + BAR/LINE/PIE + 5-row totals + by-label),
  `HomeScreen` (garden mode = full-screen `Positioned.fill` garden behind session/timer — text unreadable),
  `GardenScreen` (top title+EXPAND / bottom CUSTOMIZE-CLOSE on the Scaffold bg, scene in an `Expanded`),
  `ShopScreen` (flowers tab shows the `shopHelp` text).
- `lib/engine/garden_engine.dart` — painter draws forest on **every visible tile** via `visibleTileBounds`
  (#4 "infinite"); `forestPropAt(c,r)` picks tree/bush/rock; `Projector.fit` frames a clearing.
- `tools/gen_objects.py` — `grass_grid()` is heavily speckled (the #6 "quilt").

## Architecture by feature

### A. Visible menu icons (#1)

Generate **5 transparent 32×32 pixel-art icons** in `tools/gen_objects.py`
(`icon_theme` = artist palette + brush, `icon_garden` = wooden planter + flowers, `icon_stats` = clipboard +
bar chart, `icon_settings` = wrench + gear, `icon_store` = striped-canopy market stall) → emit
`assets/icon/icon_{theme,garden,stats,settings,store}.png` (sharp, 4–8 colors, dark 1px outline, transparent
bg, consistent weight). Replace the `IconBank`/`MenuIcon` slicing: `HomeScreen._topBar` draws each as a plain
`Image.asset('assets/icon/icon_<name>.png', filterQuality: FilterQuality.none, width/height: 30)` inside the
keyed `IconButton`s (keys unchanged: theme/garden/stats/settings/store). Delete `lib/icons.dart`,
`menuIcons()`/`_iconsFuture`, and the two `*_sheet.png` (the launcher `app_icon*.png` stay). `assets/icon/`
is already globbed in `pubspec.yaml`.

### B. Stats LINE → TREND (#2)

**B1 — Session timestamps.** `SessionRecord` gains `final int? minuteOfDay` (0..1439; `null` = legacy).
`StatsCodec` writes 4 fields `day,min,minOfDay,label` (empty `minOfDay` when null) and decodes both the new
4-field and legacy 3-field forms (labels are comma-free, so the field count is unambiguous). `AppStore`
stamps `minuteOfDay = now.hour*60 + now.minute` when recording a completed focus block (`_recordWork`) and a
cancelled one (`reset` payout).

**B2 — Rename + semantics.** The chart-type label `chartLine` → **"TREND"** (the `ChartMode.line` enum value
stays). In TREND mode the chart draws a **single progress line**:
- **DAILY** → a **cumulative** curve over the anchored day at hours **[0,4,8,12,16,20,24]** (7 points;
  `StatsAggregator.dailyCumulative(records, now, offset)` sums that day's `minuteOfDay`-stamped sessions up to
  each hour); ticks `00 04 08 12 16 20 24`.
- **WEEKLY/MONTHLY/YEARLY/ALL** → the existing `seriesFor(...).totals` per-bucket line (day/day/month/year).
- The v13 daily **per-label multi-line + legend is removed** (TREND is about progress, not labels);
  `labelLines`/`multiLine` drop out of `StatsChart`.

**B3 — CURRENT / AVERAGE / BEST (TREND only).** New pure `StatsAggregator.periodStats(records, now, period,
offset) → (int current, int average, int best)`: bucket all history by the period's unit (day/week/month/
year; ALL→year), `current` = the anchored period's total, `average` = mean of non-empty buckets, `best` = max
bucket. `StatsScreen` shows a **CURRENT / AVERAGE / BEST** three-row block (labels per period: e.g. Weekly →
`CURRENT WEEK` / `WEEK AVG` / `BEST WEEK`; ALL → `CURRENT YEAR` / `LIFETIME AVG` / `BEST YEAR`) **in place of**
the TODAY/WEEK/MONTH/YEAR/ALL block — only when `chartMode == line` (TREND). BAR/PIE keep the 5-row totals.

**B4 — Callout stays inside the chart (#2).** Rework `_callout` so the box is **clamped fully within the
chart rect** (both axes) and flips below the point when it would overflow the top. The TREND tap callout
shows the bucket tick + `FOCUS` total + `AVG` (the period's average bucket), right-aligned.

### C. Bounded forest world (#4)

Reintroduce a **fixed-border world** (revert the infinite `visibleTileBounds` forest):
- `worldOf(cols, rows)` → `(wCols, wRows) = (cols + 2*kForestBorder, rows + 2*kForestBorder)` with
  `kForestBorder` ≈ 4 (a fixed forest frame). The **projector fits the whole world** to the portrait screen,
  so the forest fills the screen with a **defined edge**; **pan is clamped to the world** (no infinite roam).
- The painter iterates the **world** tiles: garden region (centered `cols×rows`) → grass/roads/props as
  today; border tiles → `forestPropAt` (varied trees/bushes/rocks). The garden grows (EXPAND +2/+2 → world
  grows with it, border stays `kForestBorder` thick, projector refits) so it visibly fills more of the
  framed world over time. `Projector.fit` keeps the world framed; `visibleTileBounds`-based infinite drawing
  is removed. A pure `WorldGrid`-style helper (`worldOf` + `isGardenTile`) is unit-tested.

### D. Garden HUD readability (#5)

The forest must sit **under** the top and bottom HUD, not over the text:
- **Home garden-mode:** stop using a full-screen `Positioned.fill` garden. Lay it out as **top band (icons +
  SESSION) on solid `theme.bg`** → **`Expanded` garden scene (the only place the forest shows)** → **bottom
  band (timer block) on solid `theme.bg`**. The garden is a clean middle window; the text bands are solid.
- **Garden screen:** wrap the top (GARDEN title + EXPAND) and bottom (CUSTOMIZE/CLOSE) rows in a `Container`
  with `color: theme.bg` so the scene can't bleed under them.

### E. Calmer grass (#6)

Regenerate `grass_grid()` with **much less texture**: drop the bright olive speckle, reduce variant-pixel
frequency (≈1 in 30 instead of 1 in 14), keep only a subtle darker/lighter shade near the base green, and
drop the hard tufts (or make them rare). Goal: a clean field that doesn't read as a patchwork.

### F. Shop cleanup (#7)

Remove the `shopHelp` line (and its spacing) from the FLOWERS tab in `ShopScreen` — the flowers list starts
directly under the tabs.

## New assets

- `flutter/assets/icon/icon_{theme,garden,stats,settings,store}.png` (generated, 32×32 transparent).
- Regenerated `grass.png` (calmer).
- Removed: `menu_sheet.png`, `store_sheet.png` (no longer used).

## Testing (per the standing edge-test practice)

TDD where pure; visuals stay device-verified (headless `toImage` gotcha).
- **logic_test:** `SessionRecord`/`StatsCodec` 4-field round-trip **+ legacy 3-field decode** (minuteOfDay);
  `dailyCumulative` (monotonic, sums today's stamped sessions to each hour, ignores legacy); `periodStats`
  current/average/best for daily/weekly/monthly/yearly/all; `worldOf` dims + `isGardenTile` classification.
- **engine_test:** the bounded-world helper (garden centered in `cols+2B × rows+2B`, border = forest);
  `forestPropAt` unchanged.
- **widget_smoke_test:** boots; opens stats, taps **TREND** + period buttons + the ◀ navigator + a chart tap
  (no crash); the top-bar **icon keys** still resolve (now `Image.asset`); store/flowers tab still opens.
- Update `TESTING.md` with the new cases + known gaps (generated icons, trend chart layout, bounded world,
  HUD bands, grass, callout clamping are visual / device-verified).

## Deliverables (standing workflow)

`log.md`, `prompt.md`, `README.md` (the GitHub page readme), `flutter/README.md`, `TESTING.md`, a v14
memory; bump `pubspec.yaml` → `0.14.0+15`; commit & push `main` → CI builds APK + unsigned IPA → publishes
`flutter-v14` + `latest-flutter` (title `Flutter build (iOS + Android, vX.Y.Z)`). No `Co-Authored-By`.

## Out of scope (explicit)

- The true **animated live wallpaper** (native Android `WallpaperService`) — still a future version; v14
  keeps the existing static-set "SET AS LIVE WALLPAPER" button.
- The full weekly multi-average tooltip (Daily/Month/Year avg-day) — the TREND callout shows
  bucket + FOCUS + AVG; the richer breakdown is future polish.
- INNER DECOR / PETS shop contents (tabs stay, empty).
