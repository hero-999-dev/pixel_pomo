# Pixel Pomo v13 — stats polish, main-screen rework, store categories, bigger garden + forest — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the v12-feedback items (all but the animated live wallpaper, which is v14): stats formatting + history navigator, main-screen rework (custom pixel icons, FOCUS, auto-break, no switch-mode), garden-mode layout fix, store category tabs, coins-on-cancel, a bigger ratio-aware garden, a varied forest, and removal of the static backdrop option.

**Architecture:** Pure logic/aggregators in `logic.dart` (framework-free, unit-tested); custom `Canvas` engine in `lib/engine/`; Flutter screens in `main.dart`; charts + icons in `lib/pixel.dart`/`lib/icons.dart`. Visual results stay device-verified; the math/aggregators underneath are unit-pinned.

**Tech Stack:** Flutter 3.44.2 / Dart 3.12.2, `shared_preferences`, `share_plus`, `path_provider`, `wallpaper_manager_flutter` (Android). No new pub deps.

## Global Constraints

- Project root `C:\Users\claude\pixel_pomo`; Flutter paths under `flutter/`. Run Flutter as `& C:\src\flutter\bin\flutter.bat`; build/test from `flutter/` (use `Set-Location C:\Users\claude\pixel_pomo\flutter` — PowerShell CWD can reset between calls).
- CI gate: `flutter analyze` clean + `flutter test` green before every commit. Current suite = **42 tests**.
- Pure logic stays in `logic.dart` with **no Flutter imports**. Headless `toImage` hangs here, so charts/icons/forest/garden visuals are device-verified; unit-test only pure logic + projection math + prefs.
- 6 languages stay in sync (en/tr/pl/de/ko/it) for any new string in `lib/strings.dart`.
- Final version: `pubspec.yaml` → `0.13.0+14`. Release title `Flutter build (iOS + Android, vX.Y.Z)`. No `Co-Authored-By` trailer.
- The animated live wallpaper is OUT (v14). Keep the existing "SET AS LIVE WALLPAPER" button (sets the still).
- Garden base becomes **10×16**; `grow()` stays +2/+2. Forest = scattered ~20 trees + ~10 bushes + ~5 rocks.

## File Structure

- `flutter/lib/logic.dart` — ADD `StatsAggregator.anchorFor` + `offset` params on `byLabelInWindow`/`seriesFor`/`labelSeriesFor`; `Economy.elapsedFocusMinutes`; `Economy.baseGardenCols/Rows`=10/16; `Garden.atLeast`. Pure.
- `flutter/lib/store.dart` — ADD `statOffset`, `autoBreak`, `awaitingBreakPrompt`; coins-on-cancel in `reset()`; auto-break gate in `_onTick()`; garden migration in `load()`; REMOVE `gardenBackdropPath`.
- `flutter/lib/pixel.dart` — chart: bar minutes, pie aligned legend, line callout reformat + axis tick, daily legend (shared `_alignedRows`).
- `flutter/lib/icons.dart` — NEW: `IconBank` (loads the two sheets) + `MenuIcon` (slices one icon).
- `flutter/lib/main.dart` — `HomeScreen` (top-bar rearrange + custom icons + FOCUS + no switch-mode + garden-mode layout + break prompt), `StatsScreen` (navigator), `ShopScreen` (tabs), `SettingsScreen` (auto-break toggle), `GardenScreen` (remove backdrop).
- `flutter/lib/engine/garden_engine.dart` — `SpriteBank` loads forest pools + `forestProp(id)`; `forestPropAt(c,r)`; painter draws varied forest.
- `flutter/lib/strings.dart` — `work`→FOCUS (+`workDone`), `autoBreak`, `startBreakTitle`, `comingSoon`, shop tab names, store-icon label.
- `flutter/tools/gen_objects.py` — emit `tree_NN`/`bush_NN`/`rock_NN`.
- `flutter/assets/icon/menu_sheet.png`, `store_sheet.png` — copied from feedback PNGs.
- `flutter/pubspec.yaml` — version (+ assets already glob `assets/icon/` and `assets/objects/`).
- `flutter/test/{logic,engine,widget_smoke}_test.dart` — extend.
- Root docs: `log.md`, `prompt.md`, `README.md`, `flutter/README.md`, `TESTING.md`.

---

### Task 1: Stats history navigator — aggregator offset (pure) + store state (#1)

**Files:**
- Modify: `flutter/lib/logic.dart` (`anchorFor` + `offset` on the three window funcs)
- Modify: `flutter/lib/store.dart` (`statOffset` + setters)
- Test: `flutter/test/logic_test.dart`

**Interfaces:**
- Produces: `StatsAggregator.anchorFor(DateTime now, StatPeriod p, int offset) → DateTime`.
- Changes: `byLabelInWindow(records, now, p, [int offset = 0])`, `seriesFor(records, now, p, [int offset = 0])`, `labelSeriesFor(records, now, p, [int offset = 0])` — each anchors `now` via `anchorFor` before computing.
- Produces (`store.dart`): `int statOffset = 0`; `void setStatPeriod(StatPeriod)` resets `statOffset=0`; `void shiftStatOffset(int d)` (clamps `≥0`, notifies).

- [ ] **Step 1: Write the failing test**

In `flutter/test/logic_test.dart`, add inside the existing `StatsAggregator periods (v12)` group (it already defines `now`, `day`, `records`):

```dart
test('anchorFor shifts the window back by period units, never future', () {
  // monthly offset 1 → previous month window
  final prevMonth = StatsAggregator.byLabelInWindow(records, now, StatPeriod.monthly, 1);
  expect(prevMonth, isEmpty); // no records in May 2026
  // daily offset 2 → 2026-06-15 (Mon), which has the 40-min MATH record
  final twoDaysAgo = StatsAggregator.byLabelInWindow(records, now, StatPeriod.daily, 2);
  expect(twoDaysAgo.fold<int>(0, (a, e) => a + e.value), 40);
  // yearly offset 1 → 2025, which has the 25-min record
  final lastYear = StatsAggregator.byLabelInWindow(records, now, StatPeriod.yearly, 1);
  expect(lastYear.fold<int>(0, (a, e) => a + e.value), 25);
  // seriesFor honours offset too (prev month series is all-zero)
  final s = StatsAggregator.seriesFor(records, now, StatPeriod.monthly, 1);
  expect(s.totals.every((v) => v == 0), true);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `& C:\src\flutter\bin\flutter.bat test test/logic_test.dart`
Expected: FAIL — `byLabelInWindow`/`seriesFor` don't accept a 4th arg.

- [ ] **Step 3: Add `anchorFor` and thread `offset`**

In `logic.dart`, add to `class StatsAggregator` (near `windowDays`):

```dart
/// Anchor date for browsing earlier periods: [offset] periods before [now].
static DateTime anchorFor(DateTime now, StatPeriod p, int offset) {
  if (offset <= 0) return now;
  switch (p) {
    case StatPeriod.daily:
      return now.subtract(Duration(days: offset));
    case StatPeriod.weekly:
      return now.subtract(Duration(days: offset * 7));
    case StatPeriod.monthly:
      return DateTime(now.year, now.month - offset, 1);
    case StatPeriod.yearly:
      return DateTime(now.year - offset, 1, 1);
    case StatPeriod.allTime:
      return now;
  }
}
```

Change the three function signatures + first lines to anchor:

```dart
static List<MapEntry<String, int>> byLabelInWindow(
    List<SessionRecord> records, DateTime now, StatPeriod p, [int offset = 0]) {
  final a = anchorFor(now, p, offset);
  final (lo, hi) = windowDays(a, p);
  // ...unchanged body, using a/lo/hi...
```

```dart
static StatSeries seriesFor(List<SessionRecord> records, DateTime now, StatPeriod p,
    [int offset = 0]) {
  final now0 = anchorFor(now, p, offset);
  // ...unchanged body, but replace every `now` BELOW this line with `now0`...
```

```dart
static List<LabelSeries> labelSeriesFor(
    List<SessionRecord> records, DateTime now, StatPeriod p, [int offset = 0]) {
  final s = seriesFor(records, now, p, offset);
  // ...unchanged...
```

(In `seriesFor`, the body references `now` in the daily/weekly/monthly/yearly/allTime branches — rename the local to `now0` and update those references. `windowDays` already takes its own arg.)

- [ ] **Step 4: Add store state**

In `store.dart`, after `StatPeriod statPeriod = StatPeriod.monthly;` add `int statOffset = 0;`. Update `setStatPeriod` and add `shiftStatOffset`:

```dart
void setStatPeriod(StatPeriod p) {
  statPeriod = p;
  statOffset = 0; // a fresh period starts at "now"
  notifyListeners();
}

void shiftStatOffset(int d) {
  final next = statOffset + d;
  if (next < 0) return; // can't browse the future
  statOffset = next;
  notifyListeners();
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `& C:\src\flutter\bin\flutter.bat analyze && & C:\src\flutter\bin\flutter.bat test test/logic_test.dart`
Expected: analyze clean; new test passes.

- [ ] **Step 6: Commit**

```bash
git add flutter/lib/logic.dart flutter/lib/store.dart flutter/test/logic_test.dart
git commit -m "v13: stats history navigator — anchorFor + offset aggregators (#1)"
```

---

### Task 2: Stats UI — bar minutes, pie aligned legend, line callout, daily legend, navigator (#1, #2)

**Files:**
- Modify: `flutter/lib/pixel.dart` (`_ChartPainter`: bars, pie, line callout, daily legend, `_alignedRows`)
- Modify: `flutter/lib/main.dart` (`StatsScreen`: navigator row + pass `statOffset`)
- Modify: `flutter/lib/strings.dart` (`total`, `navAll`)
- Test: `flutter/test/widget_smoke_test.dart`

**Interfaces:**
- Consumes: `statOffset`/`shiftStatOffset` (Task 1); `StatsAggregator.anchorFor`/`windowDays`.
- Produces (`pixel.dart`): a `_ChartPainter` that draws right-aligned two-column rows for the pie legend and the line callout, bar tops as minutes, and a daily multi-line legend.

- [ ] **Step 1: Add strings**

In `flutter/lib/strings.dart`, add to each language map: `total` and a generic period-less ALL label is already `pAll`. Values: en `'total': 'TOTAL'`; tr `'TOPLAM'`; pl `'RAZEM'`; de `'GESAMT'`; ko `'합계'`; it `'TOTALE'`.

- [ ] **Step 2: Write the failing smoke assertion**

In `flutter/test/widget_smoke_test.dart`, the stats block already taps DAILY/LINE/PIE. After tapping `DAILY`, add a navigator tap (the ◀ button uses key `Key('statPrev')`):

```dart
expect(find.byKey(const Key('statPrev')), findsOneWidget);
await tester.tap(find.byKey(const Key('statPrev'))); // browse one day back
await tester.pumpAndSettle();
```

- [ ] **Step 3: Run smoke to verify it fails**

Run: `& C:\src\flutter\bin\flutter.bat test test/widget_smoke_test.dart`
Expected: FAIL — `statPrev` not found.

- [ ] **Step 4: Bar tops → minutes; add `_alignedRows`; rework pie legend + line callout in `pixel.dart`**

In `_ChartPainter`:

(a) Bars — change the value label to plain minutes. In `_bars`, replace
`_text(canvas, _fmt(e.value), cx, padTop + plotH - barH - 3, 7, c.textColor, align: TextAlign.center);`
with
`_text(canvas, '${e.value}', cx, padTop + plotH - barH - 3, 7, c.textColor, align: TextAlign.center);`

(b) Add a shared aligned-rows drawer + a 12-cap label helper (replace `_short`'s callers in pie/line):

```dart
String _cap(String s) => s.length <= 12 ? s : s.substring(0, 12);

/// Draw rows as two columns: left label, right value right-aligned to [right].
/// Returns the height used.
double _alignedRows(Canvas canvas, List<(String, String)> rows, double left,
    double top, double right, {double fs = 7, double lh = 11}) {
  var ty = top + lh;
  for (final (l, r) in rows) {
    _text(canvas, l, left, ty, fs, c.textColor);
    _text(canvas, r, right, ty, fs, c.textColor, align: TextAlign.right);
    ty += lh;
  }
  return rows.length * lh;
}
```

(c) Pie legend — full labels + right-aligned %. Replace the legend loop at the end of `_pie` (the `final lx = ...` block) with:

```dart
final lx = w - legendW + 4;
final rightEdge = w - 4;
var ly = cy - (c.entries.length * 13) / 2;
for (final e in c.entries) {
  fill.color = col(e.color);
  canvas.drawRect(Rect.fromLTWH(lx, ly + 2, 8, 8), fill);
  final pct = (100 * e.value / total).round();
  _text(canvas, _cap(e.label), lx + 12, ly + 11, 7, c.textColor);
  _text(canvas, '$pct%', rightEdge, ly + 11, 7, c.textColor, align: TextAlign.right);
  ly += 13;
}
```

Also widen the legend so 12-char labels fit: change `final legendW = w * 0.42;` → `final legendW = w * 0.5;` at the top of `_pie`.

(d) Line callout — TOTAL on top, full labels, right-aligned values; move the day number to the bottom axis. Replace the selection block in `_line` (the `final s = sel; if (...) { ... _callout(...) }`):

```dart
final s = sel;
if (s != null && s >= 0 && s < n) {
  final sx = x(s);
  canvas.drawLine(Offset(sx, padTop), Offset(sx, padTop + plotH),
      Paint()..color = col(c.axisColor)..strokeWidth = 1);
  // selected bucket's tick at the bottom axis, highlighted (#2)
  _text(canvas, c.series.tickLabels[s], sx, h - 4, 7, c.lineColor, align: TextAlign.center);
  final detail = c.series.byLabel[s];
  final rows = <(String, String)>[
    (_total(), _fmt(totals[s])),
    for (final e in detail) (_cap(e.key), _fmt(e.value)),
  ];
  _callout(canvas, w, sx, padTop + 4, rows);
}
```

Add a tiny localized TOTAL helper to `_ChartPainter`:

```dart
String _total() {
  const m = {'en': 'TOTAL', 'tr': 'TOPLAM', 'pl': 'RAZEM', 'de': 'GESAMT', 'ko': '합계', 'it': 'TOTALE'};
  return m[c.lang] ?? m['en']!;
}
```

Rewrite `_callout` to take aligned rows and right-align values:

```dart
void _callout(Canvas canvas, double w, double anchorX, double top, List<(String, String)> rows) {
  const fs = 7.0, pad = 4.0, lh = 11.0, gap = 8.0;
  double colW(String s) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: pixelStyle(c.lang, fs, col(c.textColor))),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.width;
  }
  var lW = 0.0, rW = 0.0;
  for (final (l, r) in rows) {
    lW = math.max(lW, colW(l));
    rW = math.max(rW, colW(r));
  }
  final boxW = lW + gap + rW + pad * 2;
  final boxH = rows.length * lh + pad * 2;
  var left = anchorX + 6;
  if (left + boxW > w) left = anchorX - 6 - boxW;
  if (left < 0) left = 0;
  final rect = Rect.fromLTWH(left, top, boxW, boxH);
  canvas.drawRect(rect, Paint()..color = col(c.panelColor));
  canvas.drawRect(rect, Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = col(c.panelBorder));
  _alignedRows(canvas, rows, left + pad, top + pad - lh, left + boxW - pad, fs: fs, lh: lh);
}
```

(e) Daily multi-line legend (#2). At the end of `_line`, when `lines != null`, draw a compact legend along the top-left:

```dart
if (lines != null) {
  var lyy = padTop;
  for (final l in lines) {
    canvas.drawRect(Rect.fromLTWH(padL, lyy + 2, 10, 3), Paint()..color = col(l.color));
    _text(canvas, _cap(l.label), padL + 14, lyy + 9, 6, c.textColor);
    lyy += 9;
  }
}
```

- [ ] **Step 5: Add the navigator to `StatsScreen` (`main.dart`)**

In `StatsScreen.build`, pass the offset to the aggregators (add `, s.statOffset` as the 4th arg to `byLabelInWindow`, `seriesFor`, `labelSeriesFor`). After the chart-type `Row(children: [chartBtn(...)])` and before the chart `SizedBox`, insert a navigator row (hidden for ALL):

```dart
if (s.statPeriod != StatPeriod.allTime) ...[
  const SizedBox(height: 10),
  Row(children: [
    SizedBox(
      width: 52,
      child: secondaryBtn(th, lang, '<', () => s.shiftStatOffset(1),
          key: const Key('statPrev'), fontSize: 13, padding: const EdgeInsets.all(10)),
    ),
    Expanded(child: Center(child: Text(_periodLabel(s, lang),
        style: pixelStyle(lang, 11, col(th.onSurface))))),
    SizedBox(
      width: 52,
      child: PixelButton(
          text: '>', fill: th.panel, border: th.onSurfaceDim, textColor: th.onSurface, shadow: th.shadow,
          lang: lang, fontSize: 13, padding: const EdgeInsets.all(10),
          opacity: s.statOffset > 0 ? 1 : 0.35,
          onTap: () => s.shiftStatOffset(-1)),
    ),
  ]),
],
```

`secondaryBtn` does not currently accept a `key`; add an optional `Key? key` param to `secondaryBtn` (and pass it to the `PixelButton`). `PixelButton` already accepts `super.key`.

Add the period-label helper to `StatsScreen`:

```dart
String _periodLabel(AppStore s, String lang) {
  final now = DateTime.now();
  final a = StatsAggregator.anchorFor(now, s.statPeriod, s.statOffset);
  switch (s.statPeriod) {
    case StatPeriod.daily:
      return '${monthName(lang, a.month)} ${a.day}';
    case StatPeriod.weekly:
      final (lo, hi) = StatsAggregator.windowDays(a, StatPeriod.weekly);
      final loD = dateOfEpochDay(lo), hiD = dateOfEpochDay(hi);
      return '${loD.day}–${hiD.day} ${monthName(lang, hiD.month)}';
    case StatPeriod.monthly:
      return '${monthName(lang, a.month)} ${a.year}';
    case StatPeriod.yearly:
      return '${a.year}';
    case StatPeriod.allTime:
      return t(lang, 'pAll');
  }
}
```

(`monthName`, `dateOfEpochDay`, `t` are already imported via `strings.dart`/`logic.dart`.)

- [ ] **Step 6: Run analyze + tests**

Run: `& C:\src\flutter\bin\flutter.bat analyze && & C:\src\flutter\bin\flutter.bat test`
Expected: clean + green (smoke taps the navigator). The pie/line/bar layout is visual — verify on-device.

- [ ] **Step 7: Commit**

```bash
git add flutter/lib/pixel.dart flutter/lib/main.dart flutter/lib/strings.dart flutter/test/widget_smoke_test.dart
git commit -m "v13: stats — bar minutes, pie/line aligned labels, daily legend, history navigator (#1,#2)"
```

---

### Task 3: Coins on cancel (#6)

**Files:**
- Modify: `flutter/lib/logic.dart` (`Economy.elapsedFocusMinutes`)
- Modify: `flutter/lib/store.dart` (`reset()`)
- Test: `flutter/test/logic_test.dart`

**Interfaces:**
- Produces: `Economy.elapsedFocusMinutes(int workMin, int timeLeftMillis) → int`.

- [ ] **Step 1: Write the failing test**

In `logic_test.dart` (Economy + Garden group):

```dart
test('elapsedFocusMinutes counts spent time on cancel', () {
  expect(Economy.elapsedFocusMinutes(25, 14 * 60 * 1000), 11); // 25-min, 14 left → 11
  expect(Economy.elapsedFocusMinutes(25, 25 * 60 * 1000), 0);  // untouched → 0
  expect(Economy.elapsedFocusMinutes(25, 0), 25);              // finished → 25
});
```

- [ ] **Step 2: Run test, verify fail**

Run: `& C:\src\flutter\bin\flutter.bat test test/logic_test.dart`
Expected: FAIL — undefined.

- [ ] **Step 3: Implement `elapsedFocusMinutes`**

In `class Economy`:

```dart
/// Whole focus minutes spent so far in a [workMin] session with [timeLeftMillis]
/// remaining (uses the displayed ceil-minutes so 14 left in a 25 reads as 11).
static int elapsedFocusMinutes(int workMin, int timeLeftMillis) {
  final leftMin = (timeLeftMillis + 59999) ~/ 60000; // ceil
  final spent = workMin - leftMin;
  return spent < 0 ? 0 : spent;
}
```

- [ ] **Step 4: Award coins on cancel in `store.dart`**

Replace `reset()`:

```dart
void reset() {
  _timer?.cancel();
  // cancelling a started focus session still pays out the time spent (#6)
  if (engine.mode == Mode.work && engine.timeLeftMillis < engine.workMillis) {
    final spent = Economy.elapsedFocusMinutes(workMin, engine.timeLeftMillis);
    if (spent > 0) {
      records.add(SessionRecord(epochDayOf(DateTime.now()), spent, currentLabel));
      _saveStats();
      coins += Economy.coinsFor(spent);
      _saveWallet();
    }
  }
  engine.reset();
  notifyListeners();
}
```

- [ ] **Step 5: Run analyze + tests**

Run: `& C:\src\flutter\bin\flutter.bat analyze && & C:\src\flutter\bin\flutter.bat test test/logic_test.dart`
Expected: clean + pass.

- [ ] **Step 6: Commit**

```bash
git add flutter/lib/logic.dart flutter/lib/store.dart flutter/test/logic_test.dart
git commit -m "v13: pay out spent focus minutes when a session is cancelled (#6)"
```

---

### Task 4: Auto-break toggle, remove SWITCH MODE, WORK→FOCUS (#4)

**Files:**
- Modify: `flutter/lib/store.dart` (`autoBreak`, `awaitingBreakPrompt`, `_onTick`, persistence)
- Modify: `flutter/lib/strings.dart` (`work`→FOCUS, `workDone`, `autoBreak`, `startBreakTitle`)
- Modify: `flutter/lib/main.dart` (`SettingsScreen` toggle; `HomeScreen` remove SWITCH MODE + show break prompt)
- Test: `flutter/test/widget_smoke_test.dart`

**Interfaces:**
- Produces (`store.dart`): `bool autoBreak = true`, `bool awaitingBreakPrompt = false`, `void setAutoBreak(bool)`, `void confirmBreak(bool start)`.

- [ ] **Step 1: Strings**

In `strings.dart`: change the `work` value to FOCUS and `workDone` to the "focus done" form, and add `autoBreak` + `startBreakTitle`, per language:
- en: `work`→`'FOCUS'`, `workDone`→`'FOCUS DONE!'`, `autoBreak`:`'AUTO-START BREAK'`, `startBreakTitle`:`'Start the break?'`
- tr: `'ODAK'`, `'ODAK BİTTİ!'`, `'MOLAYI OTOMATİK BAŞLAT'`, `'Molayı başlat?'`
- pl: `'SKUPIENIE'`, `'KONIEC SKUPIENIA!'`, `'AUTO-START PRZERWY'`, `'Zacząć przerwę?'`
- de: `'FOKUS'`, `'FOKUS FERTIG!'`, `'PAUSE AUTOMATISCH'`, `'Pause starten?'`
- ko: `'집중'`, `'집중 완료!'`, `'휴식 자동 시작'`, `'휴식을 시작할까요?'`
- it: `'FOCUS'`, `'FOCUS FINITO!'`, `'AVVIO AUTO PAUSA'`, `'Iniziare la pausa?'`

- [ ] **Step 2: Failing smoke assertion**

In `widget_smoke_test.dart`, the home screen should show `FOCUS` (not `WORK`) and the settings should have an auto-break toggle. Near the top after boot, change/confirm:

```dart
expect(find.text('FOCUS'), findsWidgets); // was WORK
```

And in the settings block, after opening settings, add:

```dart
expect(find.text('AUTO-START BREAK'), findsWidgets);
```

(Place the settings assertion inside the existing settings open/close flow.)

- [ ] **Step 3: Run smoke, verify fail**

Run: `& C:\src\flutter\bin\flutter.bat test test/widget_smoke_test.dart`
Expected: FAIL — `FOCUS` not found.

- [ ] **Step 4: Store auto-break state**

In `store.dart`: add `static const _kAutoBreak = 'auto_break';`. Add fields `bool autoBreak = true;` and `bool awaitingBreakPrompt = false;`. In `load()` add `autoBreak = _prefs.getBool(_kAutoBreak) ?? true;`. Add:

```dart
void setAutoBreak(bool v) {
  autoBreak = v;
  _prefs.setBool(_kAutoBreak, v);
  notifyListeners();
}

/// Resolve the "start the break?" prompt (auto-break off path).
void confirmBreak(bool startNow) {
  awaitingBreakPrompt = false;
  if (startNow) {
    start();
  } else {
    notifyListeners();
  }
}
```

In `_onTick`, gate the auto-continue when a focus phase ends and `autoBreak` is off:

```dart
void _onTick() {
  final remaining = _deadline!.difference(DateTime.now()).inMilliseconds;
  if (remaining > 0) {
    engine.setTimeLeft(remaining);
    notifyListeners();
    return;
  }
  _timer?.cancel();
  engine.setTimeLeft(0);
  final finished = engine.finishPhase();
  if (finished == Mode.work) _recordWork();
  messenger?.call(finished == Mode.work ? 'workDone' : 'breakDone');
  if (engine.isFinished) {
    notifyListeners();
  } else if (finished == Mode.work && !autoBreak) {
    // pause before the break and ask (#4)
    awaitingBreakPrompt = true;
    notifyListeners();
  } else {
    start();
  }
}
```

- [ ] **Step 5: Settings toggle**

In `SettingsScreen.build`, after the `HOME SCREEN` `CLEAN|GARDEN` row, add an AUTO-START BREAK on/off row in the same two-button style:

```dart
const SizedBox(height: 24),
Text(t(lang, 'autoBreak'), style: pixelStyle(lang, 12, col(th.onSurfaceDim))),
const SizedBox(height: 12),
Row(children: [
  for (final on in const [true, false]) ...[
    if (!on) const SizedBox(width: 12),
    Expanded(child: PixelButton(
      text: t(lang, on ? 'pAll' : 'clean').isEmpty ? '' : (on ? 'ON' : 'OFF'),
      fill: s.autoBreak == on ? th.accent : th.panel,
      border: s.autoBreak == on ? th.onSurface : th.onSurfaceDim,
      textColor: s.autoBreak == on ? th.onAccent : th.onSurface,
      shadow: th.shadow, lang: lang, fontSize: 11,
      onTap: () => s.setAutoBreak(on),
    )),
  ],
]),
```

(Use literal `'ON'`/`'OFF'` — universally understood; no new strings needed beyond `autoBreak`.)

- [ ] **Step 6: HomeScreen — remove SWITCH MODE, show the break prompt**

In `HomeScreen.build`, delete the `GestureDetector(onTap: s.switchMode, child: Text(... 'switchMode' ...))` widget and the `SizedBox(height: 24)` immediately before it. After the `Scaffold` is built (or via a post-frame callback in the `AnimatedBuilder` builder), show the break dialog when `s.awaitingBreakPrompt`:

At the top of the `AnimatedBuilder` builder body (before `return Scaffold`):

```dart
if (s.awaitingBreakPrompt) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!s.awaitingBreakPrompt) return;
    s.awaitingBreakPrompt = false; // guard against re-entry
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: col(th.panel),
        title: Text(t(lang, 'startBreakTitle'), style: pixelStyle(lang, 12, col(th.onSurface))),
        actions: [
          TextButton(onPressed: () { Navigator.pop(ctx); s.confirmBreak(false); },
              child: Text(t(lang, 'no'), style: pixelStyle(lang, 11, col(th.onSurfaceDim)))),
          TextButton(onPressed: () { Navigator.pop(ctx); s.confirmBreak(true); },
              child: Text(t(lang, 'yes'), style: pixelStyle(lang, 11, col(th.accent)))),
        ],
      ),
    );
  });
}
```

(The `work` string is already used for `modeText`; changing its value to FOCUS in Step 1 is the WORK→FOCUS change — no widget change needed. `engine.switchMode`/`store.switchMode` stay defined but unused; leave them.)

- [ ] **Step 7: Run analyze + tests**

Run: `& C:\src\flutter\bin\flutter.bat analyze && & C:\src\flutter\bin\flutter.bat test`
Expected: clean + green (`FOCUS` shows; AUTO-START BREAK in settings; no SWITCH MODE).

- [ ] **Step 8: Commit**

```bash
git add flutter/lib/store.dart flutter/lib/strings.dart flutter/lib/main.dart flutter/test/widget_smoke_test.dart
git commit -m "v13: auto-break toggle + remove switch-mode + WORK→FOCUS (#4)"
```

---

### Task 5: Bigger ratio-aware garden + migration (#7)

**Files:**
- Modify: `flutter/lib/logic.dart` (`Economy.baseGardenCols/Rows`, `Garden.atLeast`)
- Modify: `flutter/lib/store.dart` (`load()` migration)
- Test: `flutter/test/logic_test.dart`

**Interfaces:**
- Produces: `Economy.baseGardenCols = 10`, `Economy.baseGardenRows = 16`; `Garden.atLeast(int cols, int rows) → Garden`.

- [ ] **Step 1: Write the failing test**

```dart
test('garden base is 10x16; atLeast grows a smaller plot keeping plantings centred', () {
  expect(Economy.baseGardenCols, 10);
  expect(Economy.baseGardenRows, 16);
  // a saved 4x6 with a flower at (1,1)=idx5 migrates into a 10x16, centred
  final small = const Garden(cols: 4, rows: 6).plant(5, 'gul');
  final big = small.atLeast(10, 16);
  expect(big.cols, 10);
  expect(big.rows, 16);
  expect(big.countPlanted('gul'), 1); // nothing lost
  // already-big plots are unchanged
  final already = const Garden(cols: 12, rows: 18);
  expect(identical(already.atLeast(10, 16), already) || already.atLeast(10, 16).cols == 12, true);
});
```

- [ ] **Step 2: Run test, verify fail**

Run: `& C:\src\flutter\bin\flutter.bat test test/logic_test.dart`
Expected: FAIL — base is 4/6; `atLeast` undefined.

- [ ] **Step 3: Implement**

In `class Economy`: change `static const baseGardenCols = 4;` → `10`, `static const baseGardenRows = 6;` → `16`.

In `class Garden`, add (reuses the existing `grow()` centred-ring logic):

```dart
/// Grow the plot (centred) until it is at least [cols]×[rows]. Existing
/// plantings stay centred. Used to migrate older, smaller saved gardens (#7).
Garden atLeast(int cols, int rows) {
  var g = this;
  while (g.cols < cols || g.rows < rows) {
    g = g.grow();
  }
  return g;
}
```

(`grow()` adds +2/+2 each step, so from 4×6 it reaches 10×16 in 5 steps; `atLeast` may overshoot one axis by 1 ring — acceptable, stays centred.)

- [ ] **Step 4: Migrate on load**

In `store.dart` `load()`, after `garden = Garden.decode(_prefs.getString(_kGarden));` add:

```dart
garden = garden.atLeast(Economy.baseGardenCols, Economy.baseGardenRows);
```

- [ ] **Step 5: Run analyze + tests**

Run: `& C:\src\flutter\bin\flutter.bat analyze && & C:\src\flutter\bin\flutter.bat test`
Expected: clean + green. (Existing garden tests that asserted 4×6 base were rewritten in v11/v12 to construct explicit sizes; if any assume the base default, update them to the new base.)

- [ ] **Step 6: Commit**

```bash
git add flutter/lib/logic.dart flutter/lib/store.dart flutter/test/logic_test.dart
git commit -m "v13: garden base 10x16 (ratio-aware) + atLeast migration (#7)"
```

---

### Task 6: Forest variety — trees/bushes/rocks (#5)

**Files:**
- Modify: `flutter/tools/gen_objects.py` (emit `tree_NN`/`bush_NN`/`rock_NN`)
- Create (generated): `flutter/assets/objects/tree_00..19.png`, `bush_00..09.png`, `rock_00..04.png`
- Modify: `flutter/lib/engine/garden_engine.dart` (`SpriteBank` pools + `forestProp`; `forestPropAt`; painter)
- Test: `flutter/test/engine_test.dart`

**Interfaces:**
- Produces: top-level `String? forestPropAt(int c, int r)` → a forest sprite id (`tree_NN`/`bush_NN`/`rock_NN`) or `null` (grass gap), deterministic per tile.
- Produces: `SpriteBank.forestProp(String id)`; constants `kForestTrees=20`, `kForestBushes=10`, `kForestRocks=5`.

- [ ] **Step 1: Write the failing test**

In `engine_test.dart`:

```dart
group('forest variety (v13)', () {
  test('forestPropAt is deterministic, in-range, with gaps', () {
    var trees = 0, bushes = 0, rocks = 0, gaps = 0;
    for (var c = -20; c < 20; c++) {
      for (var r = -20; r < 20; r++) {
        final id = forestPropAt(c, r);
        expect(forestPropAt(c, r), id); // stable
        if (id == null) { gaps++; continue; }
        if (id.startsWith('tree_')) { trees++; expect(int.parse(id.substring(5)) < kForestTrees, true); }
        else if (id.startsWith('bush_')) { bushes++; expect(int.parse(id.substring(5)) < kForestBushes, true); }
        else if (id.startsWith('rock_')) { rocks++; expect(int.parse(id.substring(5)) < kForestRocks, true); }
        else { fail('unexpected $id'); }
      }
    }
    expect(trees > bushes && bushes > rocks && gaps > 0, true); // trees dominate, some gaps
  });
});
```

- [ ] **Step 2: Run test, verify fail**

Run: `& C:\src\flutter\bin\flutter.bat test test/engine_test.dart`
Expected: FAIL — `forestPropAt`/`kForestTrees` undefined.

- [ ] **Step 3: Add the picker + constants to `garden_engine.dart`**

Near the top (after `kDirFrames`):

```dart
const int kForestTrees = 20, kForestBushes = 10, kForestRocks = 5;

int _hash2(int c, int r) {
  var h = (c * 73856093) ^ (r * 19349663);
  h ^= h >> 13;
  return h & 0x7fffffff;
}

/// Deterministic, varied forest prop for an unclaimed tile (or null = grass gap).
/// Weighting: mostly trees, some bushes, few rocks, occasional gap — stable so
/// the forest never shimmers between frames.
String? forestPropAt(int c, int r) {
  final h = _hash2(c, r);
  final bucket = h % 100;
  final pick = h ~/ 100;
  String id(String kind, int n) => '${kind}_${(pick % n).toString().padLeft(2, '0')}';
  if (bucket < 18) return null; // grass gap
  if (bucket < 80) return id('tree', kForestTrees);
  if (bucket < 95) return id('bush', kForestBushes);
  return id('rock', kForestRocks);
}
```

- [ ] **Step 4: Run test, verify pass**

Run: `& C:\src\flutter\bin\flutter.bat test test/engine_test.dart`
Expected: PASS.

- [ ] **Step 5: Generate the sprites in `gen_objects.py`**

In `tools/gen_objects.py`, add parameterized variant generators near `tree_grid()`:

```python
import math as _math

def _tree_variant(seed):
    rnd = (seed * 1103515245 + 12345) & 0x7fffffff
    def rb(n):
        nonlocal rnd
        rnd = (rnd * 1103515245 + 12345) & 0x7fffffff
        return rnd % n
    g = blank(16, 16)
    greens = ["1E4D27","2A6B33","246B2E","17401F","327A3B","1B5526"]
    canopy = hexrgb(greens[rb(len(greens))]) + (255,)
    canopy2 = hexrgb(greens[rb(len(greens))]) + (255,)
    trunk = hexrgb("3A2A18") + (255,)
    rad = 4.0 + rb(3)            # 4..6
    cx, cy = 7.5, 5.0 + rb(2)
    squash = 1.05 + rb(3) * 0.12
    for r in range(16):
        for c in range(16):
            if (c - cx) ** 2 + ((r - cy) * squash) ** 2 <= rad * rad:
                g[r][c] = canopy2 if (r + c + rb(2)) % 2 else canopy
    for r in range(int(cy + rad - 1), 16):
        if 0 <= r < 16:
            g[r][7] = trunk; g[r][8] = trunk
    return g

def _bush_variant(seed):
    rnd = (seed * 2654435761 + 40503) & 0x7fffffff
    def rb(n):
        nonlocal rnd
        rnd = (rnd * 1103515245 + 12345) & 0x7fffffff
        return rnd % n
    g = blank(16, 16)
    greens = ["2A6B33","327A3B","246B2E","3C8A45"]
    a = hexrgb(greens[rb(len(greens))]) + (255,)
    b = hexrgb(greens[rb(len(greens))]) + (255,)
    rad = 3.0 + rb(2)
    cx, cy = 7.5, 10.0
    for r in range(16):
        for c in range(16):
            if (c - cx) ** 2 + ((r - cy) * 1.3) ** 2 <= rad * rad:
                g[r][c] = b if (r + c) % 2 else a
    return g

def _rock_variant(seed):
    rnd = (seed * 40503 + 12345) & 0x7fffffff
    def rb(n):
        nonlocal rnd
        rnd = (rnd * 1103515245 + 12345) & 0x7fffffff
        return rnd % n
    g = blank(16, 16)
    grays = ["6E6E6E","7C7C7C","5E5E5E","888888"]
    a = hexrgb(grays[rb(len(grays))]) + (255,)
    b = hexrgb("4A4A4A") + (255,)
    rad = 2.5 + rb(2)
    cx, cy = 7.5, 11.0
    for r in range(16):
        for c in range(16):
            if (c - cx) ** 2 + ((r - cy) * 1.4) ** 2 <= rad * rad:
                g[r][c] = b if r > cy else a   # darker bottom
    return g
```

In `main()`, after the existing `tree.png` write, add:

```python
for i in range(20):
    write_png(os.path.join(OUT, f"tree_{i:02d}.png"), upscale(_tree_variant(i + 1), SCALE))
for i in range(10):
    write_png(os.path.join(OUT, f"bush_{i:02d}.png"), upscale(_bush_variant(i + 1), SCALE))
for i in range(5):
    write_png(os.path.join(OUT, f"rock_{i:02d}.png"), upscale(_rock_variant(i + 1), SCALE))
```

Run: `python flutter/tools/gen_objects.py` and confirm `flutter/assets/objects/tree_00.png` … `rock_04.png` exist (35 files).

- [ ] **Step 6: Load the pools + draw them**

In `SpriteBank.load`, add to the `Future.wait([...])`:

```dart
for (var i = 0; i < kForestTrees; i++) grab('tree_${i.toString().padLeft(2, '0')}', 'tree_${i.toString().padLeft(2, '0')}.png'),
for (var i = 0; i < kForestBushes; i++) grab('bush_${i.toString().padLeft(2, '0')}', 'bush_${i.toString().padLeft(2, '0')}.png'),
for (var i = 0; i < kForestRocks; i++) grab('rock_${i.toString().padLeft(2, '0')}', 'rock_${i.toString().padLeft(2, '0')}.png'),
```

Add `ui.Image? forestProp(String id) => images[id];`.

In `GardenPainter.paint`, the forest loop currently adds `treeTag` for every unclaimed tile and draws `sprites.tree()`. Change it:
- In the build loop, for an unclaimed tile compute `final fp = forestPropAt(c, r); if (fp != null) standing.add((p.ground(c, r).dy, c, r, fp));` (skip nulls).
- In the draw loop, branch on claimed vs forest by recomputing `claimed`:

```dart
for (final (_, c, r, id) in standing) {
  final anchor = p.ground(c, r);
  final claimed = c >= 0 && c < _cols && r >= 0 && r < _rows;
  if (!claimed) {
    final isRock = id.startsWith('rock_');
    _paintBillboard(canvas, sprites.forestProp(id), anchor, p.t,
        height: isRock ? 0.6 : 1.2, width: isRock ? 0.8 : 1.05);
  } else if (Placeables.isFence(id)) {
    _paintFencePost(canvas, p, c, r, id);
  } else {
    final sway = math.sin(time * 1.6 + c * 7 + r) * 1.4;
    _paintBillboard(canvas, sprites.flower(id), anchor, p.t, sway: sway);
  }
}
```

Remove the now-unused `const treeTag = '__tree__';` and its use. Keep `sprites.tree()` defined (harmless) or remove the load of `tree.png` (optional; leave it).

- [ ] **Step 7: Run analyze + tests; regenerate sprites already done**

Run: `& C:\src\flutter\bin\flutter.bat analyze && & C:\src\flutter\bin\flutter.bat test`
Expected: clean + green. The forest look is visual — verify on-device.

- [ ] **Step 8: Commit**

```bash
git add flutter/tools/gen_objects.py flutter/assets/objects/ flutter/lib/engine/garden_engine.dart flutter/test/engine_test.dart
git commit -m "v13: varied forest — 20 trees + 10 bushes + 5 rocks, scattered (#5)"
```

---

### Task 7: Custom pixel menu icons + top-bar rearrange (#3, #4)

**Files:**
- Create: `flutter/lib/icons.dart` (`IconBank`, `MenuIcon`)
- Create: `flutter/assets/icon/menu_sheet.png`, `flutter/assets/icon/store_sheet.png` (copied)
- Modify: `flutter/lib/main.dart` (`HomeScreen._topBar` + preload bank)
- Test: `flutter/test/widget_smoke_test.dart`

**Interfaces:**
- Produces: `IconBank` (`menu`/`store` `ui.Image`s, `load()`); `MenuIcon(bank, slot, size, color?)` — slices one icon by column.
- Slots: `MenuSlot { theme=0, garden=1, stats=2, settings=3, market=4 }` from the menu sheet; the store icon = column 4 of the store sheet.

- [ ] **Step 1: Copy the sheets into assets**

```bash
cp "feedback & guides/Feedback/Version 12v Feedback/Main menu.png" flutter/assets/icon/menu_sheet.png
cp "feedback & guides/Feedback/Version 12v Feedback/Only Get Store.png" flutter/assets/icon/store_sheet.png
```

(`pubspec.yaml` already includes `assets/icon/`.)

- [ ] **Step 2: Create `lib/icons.dart`**

```dart
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Decoded menu icon sheets (5 icons per row, label band below each). Sliced at
/// runtime by [MenuIcon] — the user's pixel art used verbatim.
class IconBank {
  final ui.Image menu; // Main menu.png: palette/flower/bar-chart/gear/market
  final ui.Image store; // Only Get Store.png: …/veggie stall
  const IconBank(this.menu, this.store);

  static Future<IconBank> load() async {
    Future<ui.Image> grab(String a) async {
      final d = await rootBundle.load(a);
      final c = await ui.instantiateImageCodec(d.buffer.asUint8List());
      return (await c.getNextFrame()).image;
    }
    return IconBank(await grab('assets/icon/menu_sheet.png'),
        await grab('assets/icon/store_sheet.png'));
  }
}

/// One icon sliced from a 5-column sheet. [column] selects the icon; the top
/// square of the cell is taken (the label band below is cropped out).
class MenuIcon extends StatelessWidget {
  final ui.Image sheet;
  final int column;
  final double size;
  const MenuIcon(this.sheet, this.column, {super.key, this.size = 30});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(size, size), painter: _IconPainter(sheet, column));
}

class _IconPainter extends CustomPainter {
  final ui.Image sheet;
  final int column;
  _IconPainter(this.sheet, this.column);

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = sheet.width / 5.0;
    const topPad = 24.0; // skip cell top padding
    final side = cellW; // square crop from the top of the cell holds the icon
    final src = Rect.fromLTWH(column * cellW, topPad, side, side);
    final dst = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawImageRect(sheet, src, dst, Paint()..filterQuality = FilterQuality.none);
  }

  @override
  bool shouldRepaint(covariant _IconPainter old) => old.column != column || old.sheet != sheet;
}
```

(The `topPad`/`side` crop is tuned for the 1717×916 / 1672×941 sheets — verify on-device and nudge if a label peeks in.)

- [ ] **Step 3: Preload the bank + rearrange the top bar**

In `main.dart`, add a cached future like `gardenSprites`:

```dart
Future<IconBank>? _iconsFuture;
Future<IconBank> menuIcons() => _iconsFuture ??= IconBank.load();
```

Add `import 'icons.dart';`. Rewrite `HomeScreen._topBar` to use `FutureBuilder<IconBank>` and the new arrangement (left: theme, garden, stats; right: settings, store, coin):

```dart
Widget _topBar(BuildContext context, PixelTheme th, String lang) {
  Widget iconBtn(IconBank? bank, int sheetCol, bool fromStore, VoidCallback onTap, Key? key) {
    final child = bank == null
        ? const SizedBox(width: 30, height: 30)
        : MenuIcon(fromStore ? bank.store : bank.menu, sheetCol, size: 30);
    return IconButton(key: key, icon: child, onPressed: onTap);
  }
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    child: FutureBuilder<IconBank>(
      future: menuIcons(),
      builder: (context, snap) {
        final bank = snap.data;
        return Row(children: [
          iconBtn(bank, 0, false, () => openPanel(context, s, () => ThemeScreen(s)), null),
          iconBtn(bank, 1, false, () => openPanel(context, s, () => GardenScreen(s)), null),
          iconBtn(bank, 2, false, () => openPanel(context, s, () => StatsScreen(s)), const Key('statsButton')),
          const Spacer(),
          iconBtn(bank, 3, false, () => openPanel(context, s, () => SettingsScreen(s)), null),
          iconBtn(bank, 4, true, () => openPanel(context, s, () => ShopScreen(s)), const Key('storeButton')),
          GestureDetector(
            key: const Key('shopButton'),
            onTap: () => openPanel(context, s, () => ShopScreen(s)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(children: [
                const GoldCoin(size: 28),
                const SizedBox(width: 6),
                Text('${s.coins}', style: pixelStyle(lang, 14, col(th.onSurface))),
              ]),
            ),
          ),
        ]);
      },
    ),
  );
}
```

(The store icon = column 4 of the store sheet. Coin keeps `shopButton` so the existing smoke test still finds it.)

- [ ] **Step 4: Smoke — preload icons + tap store**

In `widget_smoke_test.dart`, before tapping any home icon, preload the bank in a real zone (decode is real async):

```dart
await tester.runAsync(() => menuIcons());
await tester.pump();
```

Replace the stats-open tap `find.byIcon(Icons.bar_chart)` with `find.byKey(const Key('statsButton'))`, and the settings-open tap `find.byIcon(Icons.settings)`/`palette`/`local_florist` with the corresponding flow. Simplest: add a store-icon assertion:

```dart
expect(find.byKey(const Key('storeButton')), findsOneWidget);
```

And update any `find.byIcon(Icons.bar_chart|settings|palette|local_florist)` taps in the smoke test to the new keys: stats=`statsButton`; for theme/garden/settings, add keys `themeButton`/`gardenButton`/`settingsButton` to those `iconBtn` calls and use them in the test. (Add the three keys in Step 3's `iconBtn` calls.)

- [ ] **Step 5: Run analyze + tests**

Run: `& C:\src\flutter\bin\flutter.bat analyze && & C:\src\flutter\bin\flutter.bat test`
Expected: clean + green. Icon rendering is visual — verify on-device (and tune the crop if needed).

- [ ] **Step 6: Commit**

```bash
git add flutter/lib/icons.dart flutter/assets/icon/ flutter/lib/main.dart flutter/test/widget_smoke_test.dart
git commit -m "v13: custom pixel menu icons + top-bar rearrange (theme/garden/stats · settings/store/coin) (#3,#4)"
```

---

### Task 8: Garden-mode home layout — no scrim, session top, timer bottom (#5)

**Files:**
- Modify: `flutter/lib/main.dart` (`HomeScreen.build` garden-mode branch)
- Test: `flutter/test/widget_smoke_test.dart` (covered by existing garden-mode toggle)

**Interfaces:** none new — a layout branch on `s.homeGardenBackdrop`.

- [ ] **Step 1: Branch the layout**

In `HomeScreen.build`, extract the timer block into a local `Widget timerBlock` (FOCUS text / label button / clock / progress / start-reset Row — **without** the scrim Container and **without** SWITCH MODE, removed in Task 4). Then:

- **Clean mode** (`!s.homeGardenBackdrop`): the current centered column — `Expanded(child: Center(child: timerBlock))` with SESSION below it (as today).
- **Garden mode** (`s.homeGardenBackdrop`): build

```dart
SafeArea(
  child: Column(children: [
    _topBar(context, th, lang),
    Text(tf(lang, 'session', [e.session, e.totalSessions]),
        style: pixelStyle(lang, 12, col(th.onSurface))),
    const Spacer(), // garden shows through here
    Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: timerBlock, // docked at the bottom, drawn over the garden
    ),
  ]),
),
```

In garden mode, give `timerBlock`'s texts shadows for legibility: wrap the FOCUS/clock `Text`s' style with a shadow via a helper `pixelStyle(...).copyWith(shadows: const [Shadow(blurRadius: 0, offset: Offset(2,2), color: Color(0xCC000000))])` (a hard pixel drop-shadow, only when `homeGardenBackdrop`). The label/buttons already have solid fills so they stay legible. Remove the scrim `Container` (`decoration: s.homeGardenBackdrop ? BoxDecoration(...) : null`) entirely.

- [ ] **Step 2: Run analyze + tests**

Run: `& C:\src\flutter\bin\flutter.bat analyze && & C:\src\flutter\bin\flutter.bat test`
Expected: clean + green (the existing smoke toggles HOME=GARDEN→CLEAN). Layout is visual — verify on-device.

- [ ] **Step 3: Commit**

```bash
git add flutter/lib/main.dart
git commit -m "v13: garden home-mode layout — remove scrim, session on top, timer docked bottom (#5)"
```

---

### Task 9: Store category tabs (#6)

**Files:**
- Modify: `flutter/lib/main.dart` (`ShopScreen` → stateful with tabs)
- Modify: `flutter/lib/strings.dart` (`catFlowers`, `catOuter`, `catInner`, `catPets`, `comingSoon`)
- Test: `flutter/test/widget_smoke_test.dart`

**Interfaces:** none new — local tab state.

- [ ] **Step 1: Strings**

Add ×6: `catFlowers` (en `'FLOWERS'`), `catOuter` (`'OUTER DECOR'`), `catInner` (`'INNER DECOR'`), `catPets` (`'PETS'`), `comingSoon` (`'COMING SOON'`). tr: ÇİÇEKLER/DIŞ SÜS/İÇ SÜS/EVCİLLER/YAKINDA · pl: KWIATY/DEKOR ZEWN./DEKOR WEWN./ZWIERZAKI/WKRÓTCE · de: BLUMEN/AUSSEN-DEKO/INNEN-DEKO/TIERE/BALD · ko: 꽃/외부 장식/내부 장식/펫/곧 출시 · it: FIORI/DECORO EST./DECORO INT./ANIMALI/IN ARRIVO.

- [ ] **Step 2: Failing smoke assertion**

In `widget_smoke_test.dart`, the shop opens via `shopButton`. After `expect(find.text('SHOP'), findsWidgets);`, add a tab tap:

```dart
expect(find.text('OUTER DECOR'), findsWidgets);
await tester.tap(find.text('OUTER DECOR'));
await tester.pumpAndSettle();
```

- [ ] **Step 3: Run smoke, verify fail**

Run: `& C:\src\flutter\bin\flutter.bat test test/widget_smoke_test.dart`
Expected: FAIL — `OUTER DECOR` not found.

- [ ] **Step 4: Make `ShopScreen` stateful with tabs**

Convert `ShopScreen` to `StatefulWidget`; `_ShopScreenState` holds `int _tab = 0` (0 flowers, 1 outer, 2 inner, 3 pets). `build` returns `overlayScaffold` with a tab `Row` (4 buttons, selected = accent) then the tab body:

```dart
@override
Widget build(BuildContext context) {
  final s = widget.s; final th = s.theme; final lang = s.lang;
  Widget tabBtn(String text, int i) => Expanded(
    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 2),
      child: _tab == i
          ? primaryBtn(th, lang, text, () => setState(() => _tab = i), fontSize: 8, padding: const EdgeInsets.all(8))
          : secondaryBtn(th, lang, text, () => setState(() => _tab = i), fontSize: 8, padding: const EdgeInsets.all(8))));
  return overlayScaffold(context, s, t(lang, 'shop'), [
    Row(children: [
      tabBtn(t(lang, 'catFlowers'), 0), tabBtn(t(lang, 'catOuter'), 1),
      tabBtn(t(lang, 'catInner'), 2), tabBtn(t(lang, 'catPets'), 3),
    ]),
    const SizedBox(height: 16),
    if (_tab == 0) ...[
      Text(t(lang, 'shopHelp'), style: pixelStyle(lang, 9, col(th.onSurfaceDim))),
      const SizedBox(height: 12),
      for (final f in Flowers.all) _flowerRow(s, th, lang, f),
    ] else if (_tab == 1) ...[
      for (final id in Placeables.objectIds) _objectRow(s, th, lang, id),
    ] else
      Padding(padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(child: Text(t(lang, 'comingSoon'), style: pixelStyle(lang, 12, col(th.onSurfaceDim))))),
  ]);
}
```

Move the existing flower `Row` into a `_flowerRow(s, th, lang, f)` helper (same content). Keep `_objectRow` as-is.

- [ ] **Step 5: Run analyze + tests**

Run: `& C:\src\flutter\bin\flutter.bat analyze && & C:\src\flutter\bin\flutter.bat test`
Expected: clean + green.

- [ ] **Step 6: Commit**

```bash
git add flutter/lib/main.dart flutter/lib/strings.dart flutter/test/widget_smoke_test.dart
git commit -m "v13: store category tabs — flowers/outer/inner/pets (#6)"
```

---

### Task 10: Remove the static backdrop option (#4)

**Files:**
- Modify: `flutter/lib/main.dart` (`GardenScreen._capture` dialog, `_staticBackdrop`, `showStatic`)
- Modify: `flutter/lib/store.dart` (drop `gardenBackdropPath`/`setGardenBackdrop`/`_kBackdrop`)
- Test: `flutter/test/widget_smoke_test.dart` (camera flow still cancels cleanly)

**Interfaces:** removes `AppStore.gardenBackdropPath`/`setGardenBackdrop`.

- [ ] **Step 1: Remove from the camera dialog**

In `GardenScreen._capture`, delete the `SimpleDialogOption` whose child is `t(lang, 'setBackdrop')` (the saveBackdropPng + setGardenBackdrop option). Keep SET AS LIVE WALLPAPER (Android) + SAVE/SHARE + CANCEL.

- [ ] **Step 2: Remove the static-backdrop display**

In `GardenScreen.build`, delete the `showStatic` computation and its branch — the `Expanded`'s child is always the live `FutureBuilder<SpriteBank>` → `GardenView`. Delete the `_staticBackdrop(...)` method.

- [ ] **Step 3: Remove store state**

In `store.dart`, delete `_kBackdrop`, `gardenBackdropPath`, `setGardenBackdrop`, the `load()` line `gardenBackdropPath = _prefs.getString(_kBackdrop);`, and remove the now-unused `import 'dart:io'`/`File`/`Image.file` references in `main.dart` if they're no longer used (the `dart:io` import may still be needed for `Platform`; keep `Platform`, drop `File` use if `_staticBackdrop` was the only user — verify analyze).

- [ ] **Step 4: Run analyze + tests**

Run: `& C:\src\flutter\bin\flutter.bat analyze && & C:\src\flutter\bin\flutter.bat test`
Expected: clean (no unused imports/symbols) + green.

- [ ] **Step 5: Commit**

```bash
git add flutter/lib/main.dart flutter/lib/store.dart
git commit -m "v13: remove the static garden backdrop option (#4)"
```

---

### Task 11: Docs, version bump, edge tests, release

**Files:**
- Modify: `flutter/pubspec.yaml` (version); `log.md`, `prompt.md`, `README.md`, `flutter/README.md`, `TESTING.md`

- [ ] **Step 1: Bump version**

`flutter/pubspec.yaml`: `version: 0.13.0+14`.

- [ ] **Step 2: Full edge-test sweep**

Run: `& C:\src\flutter\bin\flutter.bat analyze && & C:\src\flutter\bin\flutter.bat test`
Confirm analyze clean + all tests pass; record the count.

- [ ] **Step 3: Build debug APK**

Run: `& C:\src\flutter\bin\flutter.bat build apk --debug`
Expected: builds with the new assets (icon sheets + 35 forest sprites).

- [ ] **Step 4: Update `TESTING.md`**

Add a v13 section: new pure tests (`anchorFor`/offset windows; `elapsedFocusMinutes`; garden base 10×16 + `atLeast` migration; `forestPropAt` determinism/weighting); updated counts; known gaps (chart label layout, custom icon slicing, forest variety, garden size, garden-mode layout, auto-break dialog are visual/device-verified).

- [ ] **Step 5: Update `log.md`**

Add a v13 entry (newest on top): the prompt (7 items + the 3 decisions, live wallpaper → v14) and the per-task changes.

- [ ] **Step 6: Update `prompt.md`, `README.md`, `flutter/README.md`**

Reflect: stats formatting + history navigator; custom icons + top-bar layout; FOCUS + auto-break (no switch-mode); garden-mode layout; store tabs; coins-on-cancel; garden base 10×16 + varied forest; backdrop removed; **v14 = live wallpaper**.

- [ ] **Step 7: Commit + push (branch → merge)**

```bash
git add flutter/pubspec.yaml log.md prompt.md README.md flutter/README.md TESTING.md
git commit -m "v13: docs, testing, version bump 0.13.0+14"
git push -u origin <feature-branch>
```

Then merge to `main` (triggers CI) per finishing-a-development-branch.

- [ ] **Step 8: Verify CI**

Watch `build-flutter.yml` go green; confirm `flutter-v13` + `latest-flutter` publish the APK + unsigned IPA with title `Flutter build (iOS + Android, 0.13.0)`. Report the release URL.

- [ ] **Step 9: Write the v13 memory**

Add a v13 entry to the Pixel Pomo memory (stats nav/format, custom icons + layout, FOCUS/auto-break, garden-mode layout, store tabs, coins-on-cancel, garden 10×16 + varied forest, backdrop removed; **NEXT v14 = native live wallpaper**) + `MEMORY.md` if needed.

---

## Self-Review

**Spec coverage:**
- #1 bar minutes / pie labels / line callout / history navigator → Tasks 1, 2. ✓
- #2 line callout style + daily multi-line compare/legend → Task 2. ✓
- #3 custom logos (Main menu + store) → Task 7. ✓
- #4 remove backdrop (Task 10), live wallpaper deferred (v14), stats icon left + 3/3 layout (Task 7), remove switch-mode + auto-break + WORK→FOCUS (Task 4). ✓
- #5 garden-mode scrim removed + session top + timer bottom (Task 8); 20 trees/10 bushes/5 rocks (Task 6). ✓
- #6 coins-on-cancel (Task 3); store categories (Task 9). ✓
- #7 bigger ratio-aware garden 10×16 + migration (Task 5). ✓
- Standing deliverables → Task 11. ✓

**Placeholder scan:** No TBD/TODO. The icon crop constants (`topPad`/`side`) and garden cost note are flagged "tunable/verify on-device" with concrete starting values — not placeholders.

**Type consistency:** `anchorFor`/offset params (Task 1) consumed in Tasks 2 & 5; `Economy.elapsedFocusMinutes` (Task 3) used in `reset` same task; `baseGardenCols/Rows`+`atLeast` (Task 5) used in store; `forestPropAt`/`kForestTrees/Bushes/Rocks`/`forestProp` (Task 6) defined+used same task; `IconBank`/`MenuIcon`/`menuIcons()` (Task 7) defined+used same task; `autoBreak`/`awaitingBreakPrompt`/`confirmBreak`/`setAutoBreak` (Task 4) defined+used same task; `secondaryBtn` gains an optional `Key? key` (Task 2) used in Task 2. `setStatPeriod` reset-offset (Task 1) consistent with `shiftStatOffset`.
