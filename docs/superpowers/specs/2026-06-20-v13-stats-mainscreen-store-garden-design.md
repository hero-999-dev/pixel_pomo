# Pixel Pomo v13 — stats polish, main-screen rework, store categories, bigger garden + forest

**Date:** 2026-06-20
**Version target:** Flutter `0.13.0+14` → release `flutter-v13` (Android APK + unsigned iOS IPA)
**Scope:** one release — all v12-feedback items **except** the animated live wallpaper (its own **v14**, native Android `WallpaperService`).

v13 is the feedback round on v12 (photos in `feedback & guides/Feedback/Version 12v Feedback/`). Items
1–7. The single largest ask, "finish the live wallpaper," is a native Android subsystem and is split off
to v14; everything else is pure-Flutter and ships here.

## Decisions locked with the user

1. **Scope:** v13 = all the Flutter polish/features below. The true **animated** live wallpaper
   (a `WallpaperService` rendering the garden) is **v14** (Android-only; iOS has no API). v13 keeps the
   existing "SET AS LIVE WALLPAPER" button (still sets the captured *still* on Android).
2. **Garden size (#7):** **ratio-aware, fills the portrait screen.** Because the garden is drawn in
   oblique 2.5D (vertical squashed ×`kVy`=0.6), the guide's wide 24×16 would read short-and-wide; instead
   start ~**10×16** (taller-than-wide in tiles → near-square, screen-filling projected), expand keeping
   that shape.
3. **Forest (#5):** a scattered variety pack — **~20 trees + ~10 bushes + ~5 rocks**, picked
   deterministically per tile (no shimmer) for a natural forest instead of one repeated tree.

## Background: current state (v12, shipped)

- `lib/pixel.dart` — `StatsChart` (StatefulWidget, tappable line + callout, pie, bar; `_ChartPainter`);
  `_short(s)` truncates labels to 6; bar tops show `_fmt(value)` ("5h 40m"); pie legend `"${_short} $pct%"`;
  line callout `"${tick} · ${total}"` then `"${_short} ${val}"`.
- `lib/main.dart` — `HomeScreen` (top bar: left palette+florist, right bar_chart+settings+coin; centered
  timer with **SWITCH MODE** text + SESSION; garden-mode backdrop wraps the timer in a **scrim Container**),
  `StatsScreen` (period selector 5 buttons; no history navigator), `ShopScreen` (flowers list + DECOR
  list, no tabs), `GardenScreen` (camera dialog: **SET AS LIVE WALLPAPER** / **SET AS BACKDROP** /
  SAVE-SHARE; `_staticBackdrop` shows `gardenBackdropPath`), `SettingsScreen` (timers + language +
  `CLEAN|GARDEN`). Top-bar uses Material `Icons.*`.
- `lib/logic.dart` — `Garden` (cols×rows, base 4×6), `Economy.upgradeCost(cols,rows)=2*(cols+rows)+1`,
  `StatsAggregator.byLabelInWindow/seriesFor/labelSeriesFor(records, now, period)`, `StatPeriod`.
- `lib/store.dart` — `AppStore`: `reset()` discards the running session; `_onTick` auto-starts the next
  phase after `finishPhase()`; `statPeriod`; `gardenBackdropPath`; `homeGardenBackdrop`.
- `lib/engine/garden_engine.dart` — painter draws `sprites.tree()` on **every** visible non-claimed
  tile (`visibleTileBounds`); `Projector.fit` frames a clearing via `kFitMargin`.
- `lib/strings.dart` — `work`='WORK'; 6 langs.

## Architecture by feature

### A. Stats formatting + history navigator (#1, #2)

**A1 — Bar tops in minutes (#1).** In `_ChartPainter._bars`, the value drawn above each bar becomes the
**total minutes integer** (e.g. `340`) instead of `_fmt` ("5h 40m"). `_fmt` stays for the by-label list /
totals.

**A2 — Pie legend: full labels, right-aligned % (#1).** Replace `_short` (6-char) with a 12-char cap
(`Labels.maxLen`). In `_pie`, lay the legend out as a **two-column list**: swatch + full label on the
left, **`%` right-aligned** to a common right edge (computed from the longest label so values line up).
Widen the legend column (and shrink the pie) so up-to-12-char labels fit on one line each. Format `20%`.

**A3 — Line callout reformat + axis tick (#2).** In `_line`'s selection callout:
- Top row is **`TOTAL`** + the bucket total, value **right-aligned** (e.g. `TOTAL    2h 20m`).
- Then one row per label, **full label** left + value right-aligned (`SCIENCE  1h 40m`, `ENGLISH  40m`),
  same alignment style as the pie.
- The **bucket's day/tick number moves out of the callout to the bottom axis**: when a point is selected,
  draw its `tickLabel` at the bottom at the point's x (highlighted in the line color), on the same line as
  the `1..30` axis labels. (Keeps the callout about the data, the axis about the date.)
- A shared helper `_alignedRows(canvas, rows: List<(String left, String right)>, ...)` draws the
  right-aligned two-column list, reused by the callout (and conceptually matching the pie legend).

**A4 — Daily multi-line legend (#2).** In DAILY line mode (multi-line per label), draw a compact
**legend** (colored dash + label) below/beside the chart so each subject's line is identifiable — like
the seizures example. Only in multi-line mode.

**A5 — History navigator (#1).** Add `int statOffset = 0` to `AppStore` (periods back from now;
`0`=current, clamped `≥0`) + `setStatOffset` / `shiftStatPeriod(±1)` (reset to 0 when the period type
changes). New pure `StatsAggregator.anchorFor(DateTime now, StatPeriod, int offset)` shifts the anchor:
daily → `now - offset days`; weekly → `- offset*7 days`; monthly → `- offset months`; yearly →
`- offset years`; all → `now` (no nav). `byLabelInWindow`/`seriesFor`/`labelSeriesFor` gain an `offset`
param (default 0) that anchors via `anchorFor`. `StatsScreen` shows a **◀ [period label] ▶** row under the
chart-type buttons (hidden for ALL): label = `periodLabel(now, period, offset)` (daily `MON 19` /
weekly `15–21 JUN` / monthly `JUNE 2026` / yearly `2026`), localized; **▶ disabled at offset 0** (no
future). The TODAY/WEEK/MONTH/YEAR/ALL totals block stays always-now (a fixed summary).

### B. Main screen rework (#4) + custom icons (#3)

**B1 — Icon layout + custom pixel icons.** Top bar becomes **left: theme, garden, stats** · **right:
settings, store, coin-count**. The Material `Icons.*` are replaced by the user's pixel art: bundle
`assets/icon/menu_sheet.png` (= the chosen *Main menu.png*: palette / potted-flower / framed-bar-chart /
gear / market-stall) and `assets/icon/store_sheet.png` (= *Only Get Store.png*, for the store icon). New
`IconBank` (decodes both sheets once, like `SpriteBank`) + a `MenuIcon` `CustomPaint` that slices one
icon (5 equal columns, label band cropped) via `drawImageRect`. The top bar renders `MenuIcon`s. (Runtime
slicing — works on-device; crop fractions tuned against the sheet dimensions, no `toImage`.) The **store**
icon opens `ShopScreen` (replacing the coin button as the shop entry; the coin stays as a count, also
tappable to shop).

**B2 — Remove SWITCH MODE + auto-break toggle.** Delete the "SWITCH MODE" text button. Add
`bool autoBreak = true` to `AppStore` (+ `setAutoBreak`, persisted) and a Settings toggle **"AUTO-START
BREAK"** (`CLEAN|GARDEN`-style on/off). In `_onTick`, when a **focus** phase finishes:
- `autoBreak` on → auto-start the break (current behavior);
- off → don't auto-start; set `bool awaitingBreakPrompt = true` (engine is now in break mode, paused at
  full break) + notify. `HomeScreen` shows an `AlertDialog` "**Start the break?** YES/NO": YES →
  `store.start()`; NO → leave it paused (user can press START). Break→focus stays auto.

**B3 — WORK → FOCUS.** Change the `work` mode label string to **FOCUS** in all 6 langs (en FOCUS, tr ODAK,
pl SKUPIENIE, de FOKUS, ko 집중, it FOCUS) and `workDone` → "FOCUS DONE!" equivalents.

### C. Garden-mode home layout (#5)

When `homeGardenBackdrop` is on: **remove the scrim Container** (the "different-color area" blocking the
garden). Re-layout: top bar (icons) → **SESSION `n/N`** in the empty space just under the bar → the live
garden fills the middle (full strength) → the **timer block** (FOCUS / label / clock / progress /
START-RESET) docks at the **bottom**, drawn directly over the garden with **text shadows** for legibility
(no scrim box). Clean mode keeps today's centered layout (SESSION stays at the bottom there).

### D. Store categories (#6)

`ShopScreen` becomes stateful with a **tab row**: **FLOWERS · OUTER DECOR · INNER DECOR · PETS**. FLOWERS =
the 10 flowers; OUTER DECOR = the 4 roads + 3 fences (today's DECOR); INNER DECOR and PETS show a
**"coming soon"** placeholder (empty for now). Selected tab filters the list. (No logic change to
`Placeables`; categorization is in the shop UI.)

### E. Coins on cancel (#6)

When a focus session is canceled mid-way, count the elapsed minutes and pay out. New pure
`Economy.elapsedFocusMinutes(workMin, timeLeftMillis)` = `workMin - (timeLeftMillis/60000).ceil()`
(25-min, 14 left → 11). In `AppStore.reset()`, **before** resetting: if `engine.mode == work` and the
session was started (`timeLeftMillis < workMillis`) and `elapsed > 0`, record a `SessionRecord(today,
elapsed, currentLabel)` and award `Economy.coinsFor(elapsed)` coins (persist stats + wallet), then reset.

### F. Bigger ratio-aware garden + migration (#7)

Change only the base dimensions: `Economy.baseGardenCols = 10`, `baseGardenRows = 16` (was 4×6). **`Garden.grow()`
stays +2/+2** (clean +1/+1 centered ring, unchanged from v12) — 10×16 stays portrait-ish for many expands
(10:16 → 12:18 → 14:20 …), so no asymmetric-ring complexity. `Economy.upgradeCost(cols,rows)=2*(cols+rows)+1`
unchanged (≈53 for the first 10×16 expand; the 1000 seed coins cover it; tunable). **Migration:** add
`Garden.atLeast(cols, rows)` (pure) that, if the plot is smaller than the target, grows it to the target
re-centering existing plantings; call it in `AppStore.load` with the new base so current testers get the
bigger plot without losing flowers. `Projector.fit`'s `kFitMargin` keeps a forest border around it.

### G. Forest variety (#5)

`tools/gen_objects.py` generates **~20 `tree_NN`, ~10 `bush_NN`, ~5 `rock_NN`** sprites (parameterized:
varied canopy shape/size/green, trunk, shrub blobs, gray rock shades — flat, no-sun, like the existing
tree). `SpriteBank` loads the pools. A pure `forestPropAt(int c, int r)` returns a stable choice — hash
`(c,r)` → one of `{tree pool, bush pool, rock pool, or none}` with weighting (mostly trees, some bushes,
few rocks, some empty grass gaps) — so the forest is varied **and deterministic** (no per-frame shimmer).
The painter's forest loop draws `forestPropAt(c,r)` instead of always `tree()`, still depth-sorted +
contact-shadowed. `forestPropAt` is unit-tested (stable, in-range, weighting sane).

### H. Remove the backdrop option (#4)

Remove the in-app **static garden backdrop**: drop the `SET AS BACKDROP` camera action, `_staticBackdrop`,
`CLEAR BACKDROP`, and `AppStore.gardenBackdropPath`/`setGardenBackdrop` + its pref. The garden section
always shows the live scene. Camera capture keeps **SET AS LIVE WALLPAPER** (Android) + **SAVE/SHARE**.

## New assets / deps

- `flutter/assets/icon/menu_sheet.png`, `store_sheet.png` (copied from the feedback PNGs).
- ~35 new forest sprites in `assets/objects/` from `gen_objects.py`.
- No new pub dependencies.

## Testing (per the standing edge-test practice)

TDD where pure; visuals stay device-verified (headless `toImage` gotcha).
- **logic_test:** `anchorFor`/offset windows (daily/weekly/monthly/yearly back-navigation; never future);
  `Economy.elapsedFocusMinutes`; `Garden` new base 10×16 + `grow()` still +2/+2 centered + `Garden.atLeast`
  migration grows a smaller saved plot to the base keeping plantings centered; `Economy.upgradeCost` at the base.
- **engine_test:** `forestPropAt` stable + in-range + weighting; `visibleTileBounds` still covers screen
  at the bigger plot.
- **widget_smoke_test:** boots; taps the **store** icon (opens shop) + a **shop tab**; opens stats, taps a
  period + **◀/▶** navigator; toggles **AUTO-START BREAK**; asserts **FOCUS** renders and **no SWITCH
  MODE**; opens garden; no exceptions/overflow. (Custom icons render via `MenuIcon`; sheets preloaded with
  `runAsync`.)
- Update `TESTING.md` with cases + known gaps (pie/line callout layout, custom icon slicing, forest
  variety, garden size, garden-mode layout are visual / device-verified).

## Deliverables (standing workflow)

`log.md`, `prompt.md`, `README.md`, `flutter/README.md`, `TESTING.md`, a v13 memory; bump
`pubspec.yaml` → `0.13.0+14`; commit & push `main` → CI builds APK + unsigned IPA → publishes
`flutter-v13` + `latest-flutter` (title `Flutter build (iOS + Android, vX.Y.Z)`). No `Co-Authored-By`.

## Out of scope (explicit — v14)

- **Animated live wallpaper** — a native Android `WallpaperService` rendering the live garden (+ the
  `ACTION_CHANGE_LIVE_WALLPAPER` intent from the app, an `android/` native overlay restored in CI).
  iOS can't (no API). This is v14.
- INNER DECOR / PETS shop contents (tabs exist, empty for now).
- Any change to the existing static-wallpaper button beyond keeping it.
