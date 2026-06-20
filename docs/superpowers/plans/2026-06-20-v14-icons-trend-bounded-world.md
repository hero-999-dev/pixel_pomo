# Pixel Pomo v14 — visible icons, stats TREND, bounded forest, polish — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the 7 v13-feedback items: visible generated menu icons, the LINE→TREND stats redesign (session timestamps + daily cumulative + CURRENT/AVG/BEST + in-bounds callout), a bounded forest world, garden HUD/session placement, a calmer grass tile, and a shop cleanup.

**Architecture:** Pure logic/aggregators in `logic.dart` (framework-free, unit-tested); custom `Canvas` engine in `lib/engine/`; Flutter screens in `main.dart`; charts in `lib/pixel.dart`; sprite/icon generation in `tools/gen_objects.py`. Visuals stay device-verified; the math/aggregators underneath are unit-pinned.

**Tech Stack:** Flutter 3.44.2 / Dart 3.12.2, `shared_preferences`, `share_plus`, `path_provider`, `wallpaper_manager_flutter` (Android). No new pub deps.

## Global Constraints

- Project root `C:\Users\claude\pixel_pomo`; Flutter paths under `flutter/`. Run Flutter as `& C:\src\flutter\bin\flutter.bat`; build/test from `flutter/` (`Set-Location C:\Users\claude\pixel_pomo\flutter` — PowerShell CWD can reset between calls).
- CI gate: `flutter analyze` clean + `flutter test` green before every commit. Current suite = **46 tests**.
- Pure logic stays in `logic.dart` with **no Flutter imports**. Headless `toImage` hangs here → generated icons, trend chart, bounded world, HUD, grass are device-verified; unit-test only pure logic + projection math + prefs.
- 6 languages stay in sync (en/tr/pl/de/ko/it) for any new string in `lib/strings.dart`.
- Final version: `pubspec.yaml` → `0.14.0+15`. Release title `Flutter build (iOS + Android, vX.Y.Z)` → `flutter-v14`. No `Co-Authored-By` trailer.
- Live animated wallpaper stays OUT (future). Keep the existing "SET AS LIVE WALLPAPER" button.

## File Structure

- `flutter/lib/logic.dart` — `SessionRecord.minuteOfDay`; `StatsCodec` 4-field+legacy; `StatsAggregator.dailyCumulative`/`periodStats`. Pure.
- `flutter/lib/store.dart` — stamp `minuteOfDay` in `_recordWork` + `reset`.
- `flutter/lib/pixel.dart` — `StatsChart`: drop daily multi-line; trend cumulative for daily; clamp `_callout` in-bounds; trend callout (FOCUS/AVG).
- `flutter/lib/main.dart` — `StatsScreen` (TREND label, CURRENT/AVG/BEST block in trend mode, build trend inputs); `HomeScreen` (`Image.asset` icons; SESSION into the garden-mode top bar); `GardenScreen` (solid HUD bands); `ShopScreen` (drop flowers help).
- `flutter/lib/engine/garden_engine.dart` — `kForestBorder`, `worldOf`, `isGardenTile`; bounded forest ring in the painter; `Projector` fit margin = `2·border`; world-bounded `GardenCamera.clamp`.
- `flutter/lib/icons.dart` — **deleted**.
- `flutter/lib/strings.dart` — `chartLine`→TREND; `statCurrent`/`statAverage`/`statBest`.
- `flutter/tools/gen_objects.py` — 5 menu icons; calmer `grass_grid`.
- `flutter/assets/icon/icon_*.png` (generated); remove `menu_sheet.png`/`store_sheet.png`.
- `flutter/test/{logic,engine,widget_smoke}_test.dart` — extend.
- Root docs: `log.md`, `prompt.md`, `README.md`, `flutter/README.md`, `TESTING.md`.

---

### Task 1: Session timestamps (#2 data model)

**Files:**
- Modify: `flutter/lib/logic.dart` (`SessionRecord`, `StatsCodec`)
- Modify: `flutter/lib/store.dart` (`_recordWork`, `reset`)
- Test: `flutter/test/logic_test.dart`

**Interfaces:**
- Produces: `SessionRecord(int epochDay, int minutes, String label, {int? minuteOfDay})`.
- `StatsCodec.encode` → `day,min,minOfDay,label` (empty `minOfDay` when null); `decode` reads 4-field and legacy 3-field.

- [ ] **Step 1: Write the failing test**

In `flutter/test/logic_test.dart` (add a group near the stats tests):

```dart
group('SessionRecord timestamp codec (v14)', () {
  test('4-field round-trip + legacy 3-field decode', () {
    final recs = [
      const SessionRecord(100, 60, 'MATH', minuteOfDay: 480),
      const SessionRecord(100, 30, 'CODING'), // no time
    ];
    final decoded = StatsCodec.decode(StatsCodec.encode(recs));
    expect(decoded[0].minuteOfDay, 480);
    expect(decoded[0].label, 'MATH');
    expect(decoded[1].minuteOfDay, isNull);
    // legacy rows (3 fields) still parse, minuteOfDay null
    final legacy = StatsCodec.decode('100,60,MATH\n100,30,CODING');
    expect(legacy.length, 2);
    expect(legacy[0].minuteOfDay, isNull);
    expect(legacy[0].label, 'MATH');
  });
});
```

- [ ] **Step 2: Run test, verify it fails**

Run: `& C:\src\flutter\bin\flutter.bat test test/logic_test.dart`
Expected: FAIL — `minuteOfDay` is not a named parameter.

- [ ] **Step 3: Add the field + codec**

Replace `class SessionRecord`:

```dart
class SessionRecord {
  final int epochDay;
  final int minutes;
  final String label;
  final int? minuteOfDay; // 0..1439 start-of-session; null = legacy (#2)
  const SessionRecord(this.epochDay, this.minutes, this.label, {this.minuteOfDay});
}
```

Replace `class StatsCodec`:

```dart
class StatsCodec {
  static String encode(List<SessionRecord> records) => records
      .map((r) => '${r.epochDay},${r.minutes},${r.minuteOfDay ?? ''},${r.label}')
      .join('\n');

  static List<SessionRecord> decode(String? text) {
    final out = <SessionRecord>[];
    if (text == null || text.trim().isEmpty) return out;
    for (final line in text.split('\n')) {
      if (line.trim().isEmpty) continue;
      final parts = line.split(',');
      if (parts.length < 3) continue;
      final day = int.tryParse(parts[0].trim());
      final min = int.tryParse(parts[1].trim());
      if (day == null || min == null) continue;
      int? minute;
      String label;
      if (parts.length >= 4) {
        // new format: day,min,minOfDay,label (labels are comma-free)
        minute = int.tryParse(parts[2].trim());
        label = parts.sublist(3).join(',').trim();
      } else {
        label = parts.sublist(2).join(',').trim(); // legacy day,min,label
      }
      if (label.isEmpty) continue;
      out.add(SessionRecord(day, min, label, minuteOfDay: minute));
    }
    return out;
  }
}
```

- [ ] **Step 4: Stamp the time in `store.dart`**

In `_recordWork`:

```dart
void _recordWork() {
  final now = DateTime.now();
  records.add(SessionRecord(epochDayOf(now), workMin, currentLabel,
      minuteOfDay: now.hour * 60 + now.minute));
  _saveStats();
  coins += Economy.coinsFor(workMin);
  _saveWallet();
}
```

In `reset()`, the cancel-payout `records.add(...)` line becomes:

```dart
final now = DateTime.now();
records.add(SessionRecord(epochDayOf(now), spent, currentLabel,
    minuteOfDay: now.hour * 60 + now.minute));
```

- [ ] **Step 5: Run analyze + tests**

Run: `& C:\src\flutter\bin\flutter.bat analyze && & C:\src\flutter\bin\flutter.bat test test/logic_test.dart`
Expected: analyze clean; tests pass.

- [ ] **Step 6: Commit**

```bash
git add flutter/lib/logic.dart flutter/lib/store.dart flutter/test/logic_test.dart
git commit -m "v14: per-session timestamp (minuteOfDay) + codec (legacy-compatible) (#2)"
```

---

### Task 2: Trend aggregators — daily cumulative + current/avg/best (#2)

**Files:**
- Modify: `flutter/lib/logic.dart` (`StatsAggregator.dailyCumulative`, `periodStats`)
- Test: `flutter/test/logic_test.dart`

**Interfaces:**
- Produces: `StatsAggregator.dailyCumulative(List<SessionRecord>, DateTime now, [int offset=0]) → StatSeries` (7 points at hours [0,4,8,12,16,20,24], cumulative; tick labels `00..24`).
- Produces: `StatsAggregator.periodStats(List<SessionRecord>, DateTime now, StatPeriod, [int offset=0]) → (int current, int average, int best)`.

- [ ] **Step 1: Write the failing test**

```dart
group('StatsAggregator trend (v14)', () {
  final now = DateTime(2026, 6, 17, 23); // late today so all of today's hours are past
  int day(int y, int m, int d) => epochDayOf(DateTime(y, m, d));
  final recs = [
    SessionRecord(day(2026, 6, 17), 25, 'MATH', minuteOfDay: 8 * 60),   // 08:00
    SessionRecord(day(2026, 6, 17), 75, 'CODING', minuteOfDay: 12 * 60), // 12:00
    SessionRecord(day(2026, 6, 17), 40, 'MATH'),                         // legacy (ignored on curve)
    SessionRecord(day(2026, 6, 10), 60, 'MATH'),                         // earlier this month
    SessionRecord(day(2026, 6, 9), 120, 'MATH'),                         // prev week
  ];

  test('dailyCumulative is monotonic, hours bucketed, legacy ignored', () {
    final s = StatsAggregator.dailyCumulative(recs, now);
    expect(s.totals.length, 7);             // [0,4,8,12,16,20,24]
    expect(s.totals[0], 0);                 // before 08:00
    expect(s.totals[2], 25);                // by 08:00 → 25 (the 12:00 not yet)
    expect(s.totals[3], 100);               // by 12:00 → 25+75
    expect(s.totals.last, 100);             // legacy 40 not on the hourly curve
    for (var i = 1; i < s.totals.length; i++) {
      expect(s.totals[i] >= s.totals[i - 1], true); // monotonic
    }
  });

  test('periodStats current/average/best per period', () {
    // weekly: this week = 25+75+40 (today) = 140 (legacy counts toward day totals);
    //         prev week = 120 → avg over 2 weeks = (140+120)/2 = 130, best = 140
    final (cur, avg, best) = StatsAggregator.periodStats(recs, now, StatPeriod.weekly);
    expect(cur, 140);
    expect(best, 140);
    expect(avg, 130);
    // daily: best day = today's 140, current = 140
    final (dCur, _, dBest) = StatsAggregator.periodStats(recs, now, StatPeriod.daily);
    expect(dCur, 140);
    expect(dBest, 140);
  });
});
```

- [ ] **Step 2: Run test, verify it fails**

Run: `& C:\src\flutter\bin\flutter.bat test test/logic_test.dart`
Expected: FAIL — `dailyCumulative`/`periodStats` undefined.

- [ ] **Step 3: Implement in `StatsAggregator`**

Add (uses existing `anchorFor`, `windowDays`, `epochDayOf`, `dateOfEpochDay`):

```dart
/// Cumulative focus minutes through the anchored day at hours [0,4,8,12,16,20,24]
/// (legacy records without a [SessionRecord.minuteOfDay] are not placed on the curve).
static StatSeries dailyCumulative(List<SessionRecord> records, DateTime now, [int offset = 0]) {
  final a = anchorFor(now, StatPeriod.daily, offset);
  final dayE = epochDayOf(a);
  const hours = [0, 4, 8, 12, 16, 20, 24];
  final totals = List<int>.filled(hours.length, 0);
  for (final r in records) {
    if (r.epochDay != dayE || r.minuteOfDay == null) continue;
    final m = r.minutes < 0 ? 0 : r.minutes;
    for (var i = 0; i < hours.length; i++) {
      if (r.minuteOfDay! < hours[i] * 60) totals[i] += m; // counted once the hour passes its start
    }
  }
  final ticks = [for (final h in hours) h.toString().padLeft(2, '0')];
  return StatSeries(totals, ticks, [for (var _ in hours) const <MapEntry<String, int>>[]]);
}

/// (current, average, best) period totals across all history for the trend
/// comparison block. Buckets by the period's unit; average is over non-empty buckets.
static (int, int, int) periodStats(
    List<SessionRecord> records, DateTime now, StatPeriod p, [int offset = 0]) {
  int keyOf(int epochDay) {
    final d = dateOfEpochDay(epochDay);
    switch (p) {
      case StatPeriod.daily:
        return epochDay;
      case StatPeriod.weekly:
        return epochDay - (d.weekday - 1); // Monday epoch-day
      case StatPeriod.monthly:
        return d.year * 12 + d.month;
      case StatPeriod.yearly:
      case StatPeriod.allTime:
        return d.year;
    }
  }
  final buckets = <int, int>{};
  for (final r in records) {
    buckets[keyOf(r.epochDay)] = (buckets[keyOf(r.epochDay)] ?? 0) + (r.minutes < 0 ? 0 : r.minutes);
  }
  // current = the anchored window's total
  final a = anchorFor(now, p, offset);
  final (lo, hi) = windowDays(a, p);
  var current = 0;
  for (final r in records) {
    if (r.epochDay >= lo && r.epochDay <= hi) current += r.minutes < 0 ? 0 : r.minutes;
  }
  if (buckets.isEmpty) return (current, 0, 0);
  final best = buckets.values.reduce(math.max);
  final average = buckets.values.reduce((x, y) => x + y) ~/ buckets.length;
  return (current, average, best);
}
```

Add `import 'dart:math' as math;` at the top of `logic.dart` **only if not already present** (it is not — confirm and add if missing).

- [ ] **Step 4: Run analyze + tests**

Run: `& C:\src\flutter\bin\flutter.bat analyze && & C:\src\flutter\bin\flutter.bat test test/logic_test.dart`
Expected: clean + pass.

- [ ] **Step 5: Commit**

```bash
git add flutter/lib/logic.dart flutter/test/logic_test.dart
git commit -m "v14: trend aggregators — dailyCumulative + periodStats current/avg/best (#2)"
```

---

### Task 3: Stats UI — TREND chart + CURRENT/AVG/BEST + in-bounds callout (#2)

**Files:**
- Modify: `flutter/lib/pixel.dart` (`StatsChart`/`_ChartPainter`: drop multi-line; daily cumulative; clamp callout)
- Modify: `flutter/lib/main.dart` (`StatsScreen`)
- Modify: `flutter/lib/strings.dart` (`chartLine`→TREND; `statCurrent`/`statAverage`/`statBest`)
- Test: `flutter/test/widget_smoke_test.dart`

**Interfaces:**
- Consumes: `dailyCumulative`/`periodStats` (Task 2), `seriesFor`/`anchorFor` (existing).
- Changes: `StatsChart` drops `labelLines`/`multiLine`; gains nothing else (series carries the line).

- [ ] **Step 1: Strings**

In `strings.dart`, change each `chartLine` value to **TREND** (en `'TREND'`, tr `'TREND'`, pl `'TREND'`, de `'TREND'`, ko `'추세'`, it `'TREND'`), and add per language `statCurrent`/`statAverage`/`statBest`:
- en `CURRENT`/`AVERAGE`/`BEST` · tr `MEVCUT`/`ORTALAMA`/`EN İYİ` · pl `OBECNY`/`ŚREDNIA`/`NAJLEPSZY` · de `AKTUELL`/`DURCHSCHN`/`BESTE` · ko `현재`/`평균`/`최고` · it `ATTUALE`/`MEDIA`/`MIGLIORE`.

- [ ] **Step 2: Failing smoke assertion**

In `widget_smoke_test.dart`, the stats block taps `LINE`. Replace that tap with `TREND` and assert the comparison label shows:

```dart
await tester.tap(find.text('TREND'));
await tester.pumpAndSettle();
expect(find.text('CURRENT MONTH'), findsWidgets); // trend block, MONTHLY is the default period
```

(Leave the later `find.text('PIE')` tap as is.)

- [ ] **Step 3: Run smoke, verify it fails**

Run: `& C:\src\flutter\bin\flutter.bat test test/widget_smoke_test.dart`
Expected: FAIL — `TREND` not found (button still says LINE).

- [ ] **Step 4: Drop multi-line + clamp the callout in `pixel.dart`**

Remove the daily multi-line: delete the `labelLines` and `multiLine` fields from `StatsChart` (constructor + usages), and in `_line` delete the `lines`/`drawSeries`-per-label branch + the daily legend block — `_line` now always draws the single `c.series.totals` line. Concretely, `_line`'s series setup becomes:

```dart
final totals = c.series.totals;
final n = totals.length;
final maxVal = math.max(1, totals.isEmpty ? 1 : totals.reduce(math.max));
```

and the draw is just `drawSeries(totals, c.lineColor);` (keep the local `drawSeries` for the single line; remove the `lines == null ? ... : for(...)` and the `if (lines != null) { legend }` block).

Clamp `_callout` fully inside the chart — replace its positioning:

```dart
void _callout(Canvas canvas, double w, double h, double anchorX, List<(String, String)> rows) {
  const fs = 7.0, pad = 4.0, lh = 11.0, gap = 8.0;
  double colW(String s) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: pixelStyle(c.lang, fs, col(c.textColor))),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.width;
  }
  var lW = 0.0, rW = 0.0;
  for (final (l, r) in rows) { lW = math.max(lW, colW(l)); rW = math.max(rW, colW(r)); }
  final boxW = lW + gap + rW + pad * 2;
  final boxH = rows.length * lh + pad * 2;
  var left = (anchorX + 6).clamp(0.0, math.max(0.0, w - boxW));
  var top = (12.0).clamp(0.0, math.max(0.0, h - boxH)); // stay inside the chart
  final rect = Rect.fromLTWH(left, top, boxW, boxH);
  canvas.drawRect(rect, Paint()..color = col(c.panelColor));
  canvas.drawRect(rect, Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = col(c.panelBorder));
  _alignedRows(canvas, rows, left + pad, top + pad - lh, left + boxW - pad, fs: fs, lh: lh);
}
```

Update the `_callout(...)` call site in `_line` to pass `h`: `_callout(canvas, w, h, sx, rows);`.

- [ ] **Step 5: Daily cumulative + trend callout in `StatsScreen`/chart**

The chart already draws `c.series`. In `StatsScreen`, build the series for TREND-daily from `dailyCumulative`; for other trend periods and bar/pie keep `seriesFor`. The chart entries (bar/pie) stay. Specifically, in `StatsScreen.build` replace the `series`/`multiLine`/`labelLines` lines:

```dart
final series = (s.chartMode == ChartMode.line && s.statPeriod == StatPeriod.daily)
    ? StatsAggregator.dailyCumulative(s.records, now, s.statOffset)
    : StatsAggregator.seriesFor(s.records, now, s.statPeriod, s.statOffset);
```

and remove `multiLine`/`labelLines` and their `StatsChart(...)` args (delete `labelLines:` and `multiLine:`).

The trend tap callout shows FOCUS + AVG: in `_line`, where the selected callout `rows` are built, use:

```dart
final detail = c.series.byLabel[s]; // empty for daily-cumulative
final rows = <(String, String)>[
  (c.series.tickLabels[s], ''),
  (_focus(), _fmt(totals[s])),
  for (final e in detail) (_cap(e.key), _fmt(e.value)),
];
```

Add a localized `_focus()` to `_ChartPainter` (inline map like `_total`): en `FOCUS`, tr `ODAK`, pl `SKUPIENIE`, de `FOKUS`, ko `집중`, it `FOCUS`. (`_total` may now be unused — remove it if so.)

- [ ] **Step 6: CURRENT/AVG/BEST block (trend mode) in `StatsScreen`**

Replace the 5-row `statRow(...)` block with a conditional: trend mode → CURRENT/AVG/BEST; else the existing today/week/month/year/all. Compute and render:

```dart
if (s.chartMode == ChartMode.line) ...[
  () {
    final (cur, avg, best) = StatsAggregator.periodStats(s.records, now, s.statPeriod, s.statOffset);
    final unit = switch (s.statPeriod) {
      StatPeriod.daily => 'pDaily', StatPeriod.weekly => 'pWeekly',
      StatPeriod.monthly => 'pMonthly', StatPeriod.yearly => 'pYearly', StatPeriod.allTime => 'pAll',
    };
    final u = t(lang, unit);
    return Column(children: [
      statRow('${t(lang, 'statCurrent')} $u', cur),
      statRow('${t(lang, 'statAverage')} $u', avg),
      statRow('${t(lang, 'statBest')} $u', best),
    ]);
  }(),
] else ...[
  statRow(t(lang, 'today'), totals.today),
  statRow(t(lang, 'week'), totals.week),
  statRow(t(lang, 'month'), totals.month),
  statRow(t(lang, 'year'), totals.year),
  statRow(t(lang, 'all'), totals.all),
],
```

(`statRow` builds a caption+value row; reuse the existing closure. `totals` from `aggregate` stays for bar/pie.)

- [ ] **Step 7: Run analyze + tests**

Run: `& C:\src\flutter\bin\flutter.bat analyze && & C:\src\flutter\bin\flutter.bat test`
Expected: clean + green (smoke taps TREND, sees CURRENT MONTH). Chart visuals are device-verified.

- [ ] **Step 8: Commit**

```bash
git add flutter/lib/pixel.dart flutter/lib/main.dart flutter/lib/strings.dart flutter/test/widget_smoke_test.dart
git commit -m "v14: stats LINE→TREND — daily cumulative, current/avg/best, in-bounds callout (#2)"
```

---

### Task 4: Generated transparent menu icons (#1)

**Files:**
- Modify: `flutter/tools/gen_objects.py` (5 icon generators + emit)
- Create (generated): `flutter/assets/icon/icon_{theme,garden,stats,settings,store}.png`
- Modify: `flutter/lib/main.dart` (`_topBar` → `Image.asset`)
- Delete: `flutter/lib/icons.dart`; remove `menuIcons()`/`_iconsFuture`/`import 'icons.dart'`; delete `assets/icon/menu_sheet.png`, `store_sheet.png`
- Test: `flutter/test/widget_smoke_test.dart` (icon keys unchanged)

**Interfaces:** none new — top bar renders `Image.asset('assets/icon/icon_<name>.png')`.

- [ ] **Step 1: Add icon generators to `gen_objects.py`**

After `tree_grid()` (or near the other sprite builders), add a helper + 5 generators. (`blank`, `hexrgb`, `upscale`, `write_png`, `OUT` already exist; add `_outline` if `outline` isn't present — check first and reuse `outline` if it exists.)

```python
def _px(g, x, y, hexcol):
    if 0 <= y < len(g) and 0 <= x < len(g[0]):
        g[y][x] = hexrgb(hexcol) + (255,)

def _rect(g, x0, y0, x1, y1, hexcol):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            _px(g, x, y, hexcol)

def _disc(g, cx, cy, rad, hexcol):
    for y in range(32):
        for x in range(32):
            if (x - cx) ** 2 + (y - cy) ** 2 <= rad * rad:
                _px(g, x, y, hexcol)

def _outline32(g, hexcol):
    o = hexrgb(hexcol) + (255,)
    src = [row[:] for row in g]
    for y in range(32):
        for x in range(32):
            if src[y][x][3] != 0:
                continue
            near = False
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    yy, xx = y + dy, x + dx
                    if 0 <= yy < 32 and 0 <= xx < 32 and src[yy][xx][3] != 0:
                        near = True
            if near:
                g[y][x] = o

def icon_stats_grid():
    g = blank(32, 32)
    _rect(g, 7, 4, 25, 28, "E8E0CC")            # clipboard board
    _rect(g, 12, 2, 19, 5, "8A8A8A")            # clip
    _rect(g, 10, 16, 13, 24, "2BB39A")          # bars
    _rect(g, 15, 11, 18, 24, "7A4FE0")
    _rect(g, 20, 18, 23, 24, "F2C94C")
    _outline32(g, "23202B")
    return g

def icon_settings_grid():
    g = blank(32, 32)
    _disc(g, 12, 12, 8, "9AA0A6")               # gear body
    for (x, y) in ((12, 2), (12, 22), (2, 12), (22, 12)):
        _rect(g, x - 2, y - 2, x + 2, y + 2, "9AA0A6")  # teeth
    _disc(g, 12, 12, 3, "00000000" if False else "2E3138")  # hub
    for i in range(11):                          # wrench shaft
        _px(g, 17 + i, 17 + i, "B7BCC2")
        _px(g, 18 + i, 17 + i, "B7BCC2")
    _disc(g, 27, 27, 3, "B7BCC2")               # wrench head
    _disc(g, 28, 28, 1, "2E3138")
    _outline32(g, "23202B")
    return g

def icon_garden_grid():
    g = blank(32, 32)
    _rect(g, 7, 21, 25, 28, "7A4A24")           # planter
    _rect(g, 7, 19, 25, 21, "5E3A1C")           # rim
    for (x, col) in ((11, "E5484D"), (16, "F2C94C"), (21, "C24FE0")):
        _rect(g, x, 12, x, 21, "46A03C")        # stem
        _disc(g, x, 10, 3, col)                 # bloom
    _outline32(g, "23202B")
    return g

def icon_theme_grid():
    g = blank(32, 32)
    _disc(g, 13, 17, 9, "E8D9B0")               # palette
    _disc(g, 17, 21, 2, "00000000")             # thumb hole (clear)
    for y in range(32):                          # re-clear hole (disc can't write alpha 0)
        for x in range(32):
            if (x - 17) ** 2 + (y - 21) ** 2 <= 4:
                g[y][x] = (0, 0, 0, 0)
    for (x, y, c) in ((9, 14, "E5484D"), (13, 11, "F2C94C"), (17, 13, "2A7DE1"), (10, 20, "46A03C")):
        _disc(g, x, y, 1, c)                     # paint blobs
    for i in range(8):                           # brush handle
        _px(g, 20 + i, 8 + i, "7A4A24")
    _rect(g, 26, 14, 28, 16, "C9CDD2")          # ferrule
    _outline32(g, "23202B")
    return g

def icon_store_grid():
    g = blank(32, 32)
    _rect(g, 6, 7, 25, 12, "FBEFD8")            # canopy base (cream)
    for x in range(6, 26, 4):                    # red stripes
        _rect(g, x, 7, x + 1, 12, "D23A3A")
    _rect(g, 6, 20, 25, 26, "8A5A2C")           # counter
    _rect(g, 7, 12, 8, 20, "6E4520")            # posts
    _rect(g, 23, 12, 24, 20, "6E4520")
    _disc(g, 15, 23, 2, "F2C94C")               # coin on the counter
    _outline32(g, "23202B")
    return g
```

In `main()`, after the other writes, add:

```python
for name, fn in (("theme", icon_theme_grid), ("garden", icon_garden_grid),
                 ("stats", icon_stats_grid), ("settings", icon_settings_grid),
                 ("store", icon_store_grid)):
    write_png(os.path.join(OUT_ICON if 'OUT_ICON' in dir() else os.path.join(os.path.dirname(OUT), 'icon'),
              f"icon_{name}.png"), upscale(fn(), 8))
```

Simplify: the icon output dir is `assets/icon/`. Use a literal:

```python
ICON_OUT = os.path.join(os.path.dirname(OUT), "icon")
os.makedirs(ICON_OUT, exist_ok=True)
for name, fn in (("theme", icon_theme_grid), ("garden", icon_garden_grid),
                 ("stats", icon_stats_grid), ("settings", icon_settings_grid),
                 ("store", icon_store_grid)):
    write_png(os.path.join(ICON_OUT, f"icon_{name}.png"), upscale(fn(), 8))
```

Run: `python flutter/tools/gen_objects.py` and confirm `flutter/assets/icon/icon_theme.png` … `icon_store.png` exist (256×256 each).

- [ ] **Step 2: Top bar uses `Image.asset`; delete `icons.dart`**

In `main.dart`: remove `import 'icons.dart';`, the `Future<IconBank>? _iconsFuture;` + `menuIcons()` lines. Rewrite `_topBar`:

```dart
Widget _topBar(BuildContext context, PixelTheme th, String lang) {
  Widget icon(String name, VoidCallback onTap, Key key) => IconButton(
        key: key,
        icon: Image.asset('assets/icon/icon_$name.png', width: 30, height: 30, filterQuality: FilterQuality.none),
        onPressed: onTap,
      );
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    child: Row(children: [
      icon('theme', () => openPanel(context, s, () => ThemeScreen(s)), const Key('themeButton')),
      icon('garden', () => openPanel(context, s, () => GardenScreen(s)), const Key('gardenButton')),
      icon('stats', () => openPanel(context, s, () => StatsScreen(s)), const Key('statsButton')),
      const Spacer(),
      icon('settings', () => openPanel(context, s, () => SettingsScreen(s)), const Key('settingsButton')),
      icon('store', () => openPanel(context, s, () => ShopScreen(s)), const Key('storeButton')),
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
    ]),
  );
}
```

Delete `flutter/lib/icons.dart`. Remove the sheets:

```bash
git rm flutter/lib/icons.dart flutter/assets/icon/menu_sheet.png flutter/assets/icon/store_sheet.png
```

- [ ] **Step 3: Update smoke (drop the icon preload)**

In `widget_smoke_test.dart` remove the `await tester.runAsync(() => menuIcons());` line if present. The icon-key taps (`themeButton`/`statsButton`/etc.) and `storeButton` assertion stay (the keyed `IconButton`s still exist).

- [ ] **Step 4: Run analyze + tests**

Run: `& C:\src\flutter\bin\flutter.bat analyze && & C:\src\flutter\bin\flutter.bat test`
Expected: clean (no `icons.dart` refs) + green. Icon art is visual — verify on-device.

- [ ] **Step 5: Commit**

```bash
git add flutter/tools/gen_objects.py flutter/assets/icon/ flutter/lib/main.dart flutter/test/widget_smoke_test.dart
git commit -m "v14: generate transparent pixel menu icons; drop the broken sheet slicer (#1)"
```

---

### Task 5: Bounded forest world (#4)

**Files:**
- Modify: `flutter/lib/engine/garden_engine.dart` (`kForestBorder`, `worldOf`, `isGardenTile`; `Projector.fit` margin; painter forest ring; `clamp`)
- Test: `flutter/test/engine_test.dart`

**Interfaces:**
- Produces: `const int kForestBorder`; `(int,int) worldOf(int cols,int rows)`; `bool isGardenTile(int c,int r,int cols,int rows)`.

- [ ] **Step 1: Write the failing test**

```dart
group('bounded forest world (v14)', () {
  test('worldOf adds a fixed border; isGardenTile classifies', () {
    final (wc, wr) = worldOf(10, 16);
    expect(wc, 10 + 2 * kForestBorder);
    expect(wr, 16 + 2 * kForestBorder);
    expect(isGardenTile(0, 0, 10, 16), true);    // garden centred at 0..cols-1
    expect(isGardenTile(9, 15, 10, 16), true);
    expect(isGardenTile(-1, 0, 10, 16), false);  // forest border
    expect(isGardenTile(10, 0, 10, 16), false);
    expect(isGardenTile(-kForestBorder - 1, 0, 10, 16), false); // beyond the border (still false)
  });
});
```

- [ ] **Step 2: Run test, verify it fails**

Run: `& C:\src\flutter\bin\flutter.bat test test/engine_test.dart`
Expected: FAIL — `worldOf`/`kForestBorder`/`isGardenTile` undefined.

- [ ] **Step 3: Add the helpers**

Near `kForestTrees` in `garden_engine.dart`:

```dart
/// A fixed forest border (in tiles) framing the garden on every side. The world
/// is the garden + this border; the projector fits the whole world to the screen
/// so the forest fills it with a defined edge (#4).
const int kForestBorder = 4;

(int, int) worldOf(int cols, int rows) => (cols + 2 * kForestBorder, rows + 2 * kForestBorder);

/// Is garden tile (c,r) inside the plantable plot (true) or the forest border (false)?
bool isGardenTile(int c, int r, int cols, int rows) => c >= 0 && c < cols && r >= 0 && r < rows;
```

- [ ] **Step 4: Fit the world (widen the fit margin)**

In `Projector.fit`, change the fit margin from the v13 clearing value to `2*kForestBorder` so the world (garden + border) fills the screen. Find:

```dart
static const double kFitMargin = 3.0;
...
final fitW = size.width / (cols + kFitMargin);
final fitH = size.height / ((rows + kFitMargin) * kVy);
```

Replace the two divisors to use the forest border:

```dart
final fitW = size.width / (cols + 2 * kForestBorder + 0.5);
final fitH = size.height / ((rows + 2 * kForestBorder + 0.5) * kVy);
```

(Delete the now-unused `kFitMargin` const if nothing else references it; `analyze` will flag it.)

- [ ] **Step 5: Bounded forest ring in the painter**

In `GardenPainter.paint`, replace the v13 infinite forest loop (the `final b = p.visibleTileBounds(size); for (var r = b.minR ...)` block) with a fixed border-ring loop:

```dart
const int border = kForestBorder;
final standing = <(double, int, int, String)>[]; // (depthY, col, row, id)
for (var r = -border; r < _rows + border; r++) {
  for (var c = -border; c < _cols + border; c++) {
    if (isGardenTile(c, r, _cols, _rows)) {
      final prop = garden.propAt(r * _cols + c);
      if (prop != null) standing.add((p.ground(c, r).dy, c, r, prop));
    } else {
      final fp = forestPropAt(c, r);
      if (fp != null) standing.add((p.ground(c, r).dy, c, r, fp));
    }
  }
}
```

(The draw loop below is unchanged — it already recomputes `claimed`/`isGardenTile` via `c>=0 && c<_cols && r>=0 && r<_rows`. Keep it. The `visibleTileBounds` method may now be unused — leave it or remove; `analyze` won't flag an unused public method.)

- [ ] **Step 6: World-bounded pan clamp**

Replace `GardenCamera.clamp` so pan can't go past the forest edge:

```dart
void clamp(int cols, int rows, Size size) {
  final p = Projector.fit(cols, rows, this, size);
  final b = kForestBorder.toDouble();
  final halfWx = (cols / 2 + b) * p.t;            // world half-width in px
  final halfWy = (rows / 2 + b) * p.t * kVy;      // world half-height in px
  final maxX = math.max(0.0, halfWx - size.width / 2);
  final maxY = math.max(0.0, halfWy - size.height / 2);
  panX = panX.clamp(-maxX, maxX);
  panY = panY.clamp(-maxY, maxY);
}
```

(Taps already map correctly: `garden_view._onTapUp` uses `Projector.fit(cols,rows)` + `tileAt`, which returns the garden index or -1 for forest — no change.)

- [ ] **Step 7: Run analyze + tests**

Run: `& C:\src\flutter\bin\flutter.bat analyze && & C:\src\flutter\bin\flutter.bat test`
Expected: clean + green. The framed world is visual — verify on-device (forest fills the screen with an edge; garden centred; EXPAND grows it toward the border).

- [ ] **Step 8: Commit**

```bash
git add flutter/lib/engine/garden_engine.dart flutter/test/engine_test.dart
git commit -m "v14: bounded forest world — fixed border frames the garden, no infinite roam (#4)"
```

---

### Task 6: Garden HUD bands + SESSION in the garden-mode top bar (#5)

**Files:**
- Modify: `flutter/lib/main.dart` (`HomeScreen` garden-mode top bar + SESSION; `GardenScreen` solid HUD bands)
- Test: `flutter/test/widget_smoke_test.dart` (covered by existing garden-mode toggle)

**Interfaces:** none new.

- [ ] **Step 1: SESSION into the garden-mode top bar**

`HomeScreen._topBar` gains an optional centered child. Change its signature to
`Widget _topBar(BuildContext context, PixelTheme th, String lang, {Widget? center})` and put `center` in the
`Spacer` gap: replace `const Spacer(),` with `Expanded(child: Center(child: center ?? const SizedBox()))`.

In `HomeScreen.build`, the garden branch passes the SESSION as the top-bar center and drops the separate
`sessionText` line above the Spacer:

```dart
? Column(children: [
    _topBar(context, th, lang, center: Text(
      tf(lang, 'session', [e.session, e.totalSessions]),
      style: pixelStyle(lang, 11, col(th.onSurface)).copyWith(shadows: shadows))),
    const Spacer(),
    Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: timerBlock,
    ),
  ])
```

(The clean branch keeps `_topBar(context, th, lang)` with no center and `sessionText` under the timer.)

- [ ] **Step 2: Solid HUD bands on the garden screen**

In `GardenScreen.build`, wrap the top row (GARDEN title + EXPAND `Padding`) and the bottom controls
(`Padding` with CUSTOMIZE/CLOSE or CAPTURE/CANCEL) each in a `Container(color: col(th.bg), child: ...)` so the
forest can't bleed under them. (Only when not `_hudHidden` — the peek/camera full-bleed modes are unchanged.)
Concretely, change the top `if (!_hudHidden) Padding(...)` to `if (!_hudHidden) Container(color: col(th.bg), child: Padding(...))`, and likewise the bottom `if (_camera) ... else if (!_peek) ...` rows: wrap each `Padding(...)` in `Container(color: col(th.bg), child: ...)`.

- [ ] **Step 3: Run analyze + tests**

Run: `& C:\src\flutter\bin\flutter.bat analyze && & C:\src\flutter\bin\flutter.bat test`
Expected: clean + green (the smoke garden-mode toggle still works). Layout is visual — verify on-device.

- [ ] **Step 4: Commit**

```bash
git add flutter/lib/main.dart
git commit -m "v14: SESSION into garden-mode top bar; solid HUD bands on the garden screen (#5)"
```

---

### Task 7: Calmer grass (#6)

**Files:**
- Modify: `flutter/tools/gen_objects.py` (`grass_grid`)
- Create (regenerated): `flutter/assets/objects/grass.png`

- [ ] **Step 1: Simplify `grass_grid`**

Replace `grass_grid()` with a far less busy field (no bright olive, sparse subtle speckle, no hard tufts):

```python
def grass_grid():
    # A calm field: a base green with only sparse, low-contrast speckle so it
    # doesn't read as a patchwork (#6). Plants keep their dark outline to separate.
    base = hexrgb("57A636")
    d1 = hexrgb("4F9A30")   # subtle darker
    l1 = hexrgb("63B23E")   # subtle lighter
    g = [[base + (255,) for _ in range(16)] for _ in range(16)]
    seed = 1234567
    for r in range(16):
        for c in range(16):
            seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
            v = seed % 30
            if v == 0:
                g[r][c] = d1 + (255,)
            elif v == 1:
                g[r][c] = l1 + (255,)
    return g
```

Run: `python flutter/tools/gen_objects.py` and confirm `flutter/assets/objects/grass.png` updated.

- [ ] **Step 2: Run analyze + tests**

Run: `& C:\src\flutter\bin\flutter.bat analyze && & C:\src\flutter\bin\flutter.bat test`
Expected: clean + green (no code logic changed). Grass look is visual — verify on-device.

- [ ] **Step 3: Commit**

```bash
git add flutter/tools/gen_objects.py flutter/assets/objects/grass.png
git commit -m "v14: calmer grass tile — less speckle, no patchwork (#6)"
```

---

### Task 8: Remove the shop flowers help text (#7)

**Files:**
- Modify: `flutter/lib/main.dart` (`_ShopScreenState.build`)

- [ ] **Step 1: Drop the help row**

In `ShopScreen`'s flowers tab (`if (_tab == 0) ...[`), delete the
`Text(t(lang, 'shopHelp'), ...)` line and the following `const SizedBox(height: 12),` so the flower list
starts directly under the tabs. (Leave the `shopHelp` string key defined; harmless.)

- [ ] **Step 2: Run analyze + tests**

Run: `& C:\src\flutter\bin\flutter.bat analyze && & C:\src\flutter\bin\flutter.bat test`
Expected: clean + green.

- [ ] **Step 3: Commit**

```bash
git add flutter/lib/main.dart
git commit -m "v14: remove the unnecessary shop flowers help text (#7)"
```

---

### Task 9: Docs, version bump, edge tests, release

**Files:**
- Modify: `flutter/pubspec.yaml` (version); `log.md`, `prompt.md`, `README.md`, `flutter/README.md`, `TESTING.md`

- [ ] **Step 1: Bump version**

`flutter/pubspec.yaml`: `version: 0.14.0+15`.

- [ ] **Step 2: Full edge-test sweep**

Run: `& C:\src\flutter\bin\flutter.bat analyze && & C:\src\flutter\bin\flutter.bat test`
Confirm analyze clean + all tests pass; record the count.

- [ ] **Step 3: Build debug APK**

Run: `& C:\src\flutter\bin\flutter.bat build apk --debug`
Expected: builds with the new icon + grass assets.

- [ ] **Step 4: Update `TESTING.md`**

Add a v14 section: new pure tests (`SessionRecord`/`StatsCodec` 4-field+legacy; `dailyCumulative`;
`periodStats`; `worldOf`/`isGardenTile`); updated counts; known gaps (generated icons, trend chart, bounded
world, HUD bands, calmer grass, callout clamp are visual/device-verified).

- [ ] **Step 5: Update `log.md`**

Add a v14 entry (newest on top): the prompt (7 items + the 4 decisions) and the per-task changes.

- [ ] **Step 6: Update `prompt.md`, `README.md` (GitHub page), `flutter/README.md`**

Reflect: generated transparent icons; stats TREND (timestamps + daily cumulative + current/avg/best);
bounded forest world; garden HUD/session; calmer grass; shop cleanup.

- [ ] **Step 7: Commit + push (branch → merge)**

```bash
git add flutter/pubspec.yaml log.md prompt.md README.md flutter/README.md TESTING.md
git commit -m "v14: docs, testing, version bump 0.14.0+15"
git push -u origin <feature-branch>
```

Then merge to `main` (triggers CI) per finishing-a-development-branch.

- [ ] **Step 8: Verify CI**

Watch `build-flutter.yml` go green; confirm `flutter-v14` + `latest-flutter` publish the APK + unsigned IPA
with title `Flutter build (iOS + Android, 0.14.0)`. Report the release URL.

- [ ] **Step 9: Write the v14 memory**

Add a v14 entry to the Pixel Pomo memory (generated icons, stats TREND + timestamps + current/avg/best,
bounded world, HUD/session, calmer grass, shop cleanup) + `MEMORY.md` if needed.

---

## Self-Review

**Spec coverage:**
- #1 visible icons → Task 4. ✓
- #2 LINE→TREND (timestamps Task 1; daily cumulative + periodStats Task 2; UI + callout clamp Task 3). ✓
- #4 bounded forest world → Task 5. ✓
- #5 forest under HUD + SESSION in top bar → Task 6. ✓
- #6 calmer grass → Task 7. ✓
- #7 shop flowers help removed → Task 8. ✓
- Standing deliverables → Task 9. ✓

**Placeholder scan:** No TBD/TODO. The icon pixel grids and grass values are concrete; "verify on-device" notes flag genuine visual checks, not placeholders. The Task 4 `ICON_OUT` snippet supersedes the earlier `OUT_ICON` sketch — use the `ICON_OUT` block.

**Type consistency:** `SessionRecord.minuteOfDay` (Task 1) consumed by `dailyCumulative` (Task 2) + store (Task 1). `dailyCumulative`/`periodStats` (Task 2) consumed by `StatsScreen` (Task 3). `chartLine`→TREND string (Task 3) matches the smoke `find.text('TREND')`. `worldOf`/`isGardenTile`/`kForestBorder` (Task 5) defined+used same task; `Projector.fit` margin change (Task 5) consistent with `clamp` (Task 5). `_topBar` `center:` param (Task 6) used by HomeScreen garden branch same task. Icon assets `icon_<name>.png` (Task 4) match `Image.asset` paths.
