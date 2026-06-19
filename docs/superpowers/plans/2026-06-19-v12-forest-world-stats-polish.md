# Pixel Pomo v12 — forest world, theming polish, stats rework — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the 12 v11-feedback fixes: a screen-filling forest world (garden = clearing), themed system bars + no white splash, a stuck-critter fix, themed garden HUD, a renamed "live wallpaper" action that sets the Android phone wallpaper, an un-dimmed home backdrop, label rename, and a stats rework (period selector, pie separators, tappable line chart, daily per-label multi-line).

**Architecture:** Pure logic/aggregators in `logic.dart` (framework-free, unit-tested); the custom `Canvas` garden engine in `lib/engine/`; Flutter screens in `main.dart`; charts in `pixel.dart`. Visual results (forest, charts, wallpaper, system bars) are user-verified on-device — the math underneath is unit-pinned.

**Tech Stack:** Flutter 3.44.2 / Dart 3.12.2, `shared_preferences`, `share_plus`, `path_provider`; new Android-only `wallpaper_manager_flutter`.

## Global Constraints

- Project root `C:\Users\claude\pixel_pomo`; Flutter paths under `flutter/`. Run Flutter as `& C:\src\flutter\bin\flutter.bat`; build/test from `flutter/` (use `Set-Location C:\Users\claude\pixel_pomo\flutter` — the PowerShell CWD can reset between calls).
- CI gate: `flutter analyze` clean + `flutter test` green before every commit. Current suite = **31 tests** (24 logic + 7 engine + smoke).
- Pure logic stays in `logic.dart` with **no Flutter imports**. Headless `toImage`/offscreen render hangs here, so forest/chart/wallpaper/system-bar visuals are device-verified; unit-test only pure logic + projection math + prefs.
- 6 languages stay in sync (en/tr/pl/de/ko/it) for any new string in `lib/strings.dart`.
- New deps must be iOS-build-safe under `flutter build ios --no-codesign` on the macOS CI. `wallpaper_manager_flutter` is **Android-only** and must be called **only behind `Platform.isAndroid`**; the wallpaper button is hidden on iOS.
- Final version: `pubspec.yaml` → `0.12.0+13`. Release title stays `Flutter build (iOS + Android, vX.Y.Z)`.
- No `Co-Authored-By: Claude` / AI-attribution trailer on commits.
- Live *animated* wallpaper (WallpaperService) is OUT — that's v13.

## File Structure

- `flutter/lib/logic.dart` — ADD `StatPeriod` enum, `Labels.rename`, `StatsAggregator.byLabelInWindow`/`seriesFor`/`labelSeriesFor` + result types `StatSeries`/`LabelSeries`. Pure.
- `flutter/lib/store.dart` — ADD `statPeriod` + `setStatPeriod`, `renameLabel` (migrates color/current/records); remove month-navigator state usage.
- `flutter/lib/pixel.dart` — ADD `systemOverlayFor`; rework `StatsChart` (stateful, period-aware, pie separators, tappable line, daily multi-line); `LabelLine` type.
- `flutter/lib/main.dart` — `PixelPomoApp` (ThemeData no-splash + `AnnotatedRegion` system bars); `StatsScreen` (period selector); `LabelScreen` (long-press rename); `GardenScreen` (themed HUD chips, peek full-bleed, wallpaper rename); `HomeScreen` (un-dim backdrop).
- `flutter/lib/engine/garden_engine.dart` — `Projector.gridAt`/`visibleTileBounds`; forest fills the visible range; `CritterSystem` max-lifetime; simplify `WorldGrid`; widen `GardenCamera.clamp`.
- `flutter/lib/engine/garden_view.dart` — themed HUD chips; peek full-bleed plumbing.
- `flutter/lib/camera.dart` — `setPhoneWallpaper`.
- `flutter/lib/strings.dart` — new keys ×6.
- `flutter/pubspec.yaml` — dep + version.
- `flutter/test/{logic,engine,widget_smoke}_test.dart` — extend.
- Root docs: `log.md`, `prompt.md`, `README.md`, `flutter/README.md`, `TESTING.md`.

---

### Task 1: Theme polish — system bars (#2) + kill white splash (#12)

**Files:**
- Modify: `flutter/lib/pixel.dart` (add `systemOverlayFor`)
- Modify: `flutter/lib/main.dart` (`PixelPomoApp`: `ThemeData` + `AnnotatedRegion`)
- Test: `flutter/test/logic_test.dart` (brightness decision is pure)

**Interfaces:**
- Produces: `SystemUiOverlayStyle systemOverlayFor(PixelTheme th)` (pixel.dart) — status+nav bar colored to `th.bg`, icon brightness from bg luminance.
- Produces: a helper `bool _isLightBg(int argb)` is internal; expose `bool isLightColor(int argb)` in pixel.dart for the test.

- [ ] **Step 1: Write the failing test**

In `flutter/test/logic_test.dart` add (needs `import 'package:pixel_pomo/pixel.dart';` and `import 'package:flutter/material.dart';` at top):

```dart
group('theme system-bar brightness', () {
  test('isLightColor splits light vs dark backgrounds', () {
    expect(isLightColor(0xFFF7EFDD), true);  // latte cream
    expect(isLightColor(0xFFF2F2F4), true);  // light
    expect(isLightColor(0xFF161616), false); // dark
    expect(isLightColor(0xFF1E1E2E), false); // mocha
  });

  test('systemOverlayFor colors bars to bg and picks icon brightness', () {
    final dark = systemOverlayFor(Themes.dark);
    expect(dark.systemNavigationBarColor, const Color(0xFF161616));
    expect(dark.statusBarIconBrightness, Brightness.light); // light icons on dark bg
    final light = systemOverlayFor(Themes.light);
    expect(light.statusBarIconBrightness, Brightness.dark);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `& C:\src\flutter\bin\flutter.bat test test/logic_test.dart`
Expected: FAIL — `isLightColor`/`systemOverlayFor` undefined.

- [ ] **Step 3: Implement in `pixel.dart`**

Add near the top of `pixel.dart` (after `col`), and add `import 'package:flutter/services.dart';`:

```dart
/// True if [argb] is a light color (luminance test) — used to choose contrasting
/// system-bar icon brightness and on-scene contrast.
bool isLightColor(int argb) {
  final r = (argb >> 16) & 0xFF, g = (argb >> 8) & 0xFF, b = argb & 0xFF;
  // perceived luminance 0..255
  return (0.299 * r + 0.587 * g + 0.114 * b) > 140;
}

/// System status + navigation bars colored to the theme background, with icon
/// brightness that contrasts it (#2).
SystemUiOverlayStyle systemOverlayFor(PixelTheme th) {
  final light = isLightColor(th.bg);
  final iconBrightness = light ? Brightness.dark : Brightness.light;
  return SystemUiOverlayStyle(
    statusBarColor: col(th.bg),
    statusBarIconBrightness: iconBrightness,
    statusBarBrightness: light ? Brightness.light : Brightness.dark, // iOS
    systemNavigationBarColor: col(th.bg),
    systemNavigationBarIconBrightness: iconBrightness,
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `& C:\src\flutter\bin\flutter.bat test test/logic_test.dart`
Expected: PASS.

- [ ] **Step 5: Apply ThemeData (no splash) + AnnotatedRegion in `main.dart`**

In `PixelPomoApp.build`, add `import 'package:flutter/services.dart';` and replace the `return MaterialApp(...)` so it's wrapped to react to theme changes and carry a no-splash theme:

```dart
return AnimatedBuilder(
  animation: store,
  builder: (context, _) {
    final th = store.theme;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemOverlayFor(th),
      child: MaterialApp(
        title: 'Pixel Pomo',
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: messengerKey,
        theme: ThemeData(
          useMaterial3: false,
          scaffoldBackgroundColor: col(th.bg),
          splashFactory: NoSplash.splashFactory, // #12 no white ripple
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          dialogBackgroundColor: col(th.panel),
        ),
        home: HomeScreen(store),
      ),
    );
  },
);
```

- [ ] **Step 6: Run analyze + full tests, verify pass**

Run: `& C:\src\flutter\bin\flutter.bat analyze` then `& C:\src\flutter\bin\flutter.bat test`
Expected: analyze clean; all tests pass.

- [ ] **Step 7: Commit**

```bash
git add flutter/lib/pixel.dart flutter/lib/main.dart flutter/test/logic_test.dart
git commit -m "v12: theme system bars (#2) + remove white splash (#12)"
```

---

### Task 2: Stats period aggregators (pure) — data for #10 + #11

**Files:**
- Modify: `flutter/lib/logic.dart` (`StatPeriod`, `StatSeries`, `LabelSeries`, aggregators)
- Modify: `flutter/lib/store.dart` (`statPeriod` + `setStatPeriod`)
- Test: `flutter/test/logic_test.dart`

**Interfaces:**
- Produces (`logic.dart`):
  - `enum StatPeriod { daily, weekly, monthly, yearly, allTime }`
  - `class StatSeries { final List<int> totals; final List<String> tickLabels; final List<List<MapEntry<String,int>>> byLabel; const StatSeries(this.totals, this.tickLabels, this.byLabel); }`
  - `class LabelSeries { final String label; final List<int> values; const LabelSeries(this.label, this.values); }`
  - `StatsAggregator.byLabelInWindow(List<SessionRecord>, DateTime now, StatPeriod) → List<MapEntry<String,int>>` (desc)
  - `StatsAggregator.seriesFor(List<SessionRecord>, DateTime now, StatPeriod) → StatSeries`
  - `StatsAggregator.labelSeriesFor(List<SessionRecord>, DateTime now, StatPeriod) → List<LabelSeries>`
- Produces (`store.dart`): `StatPeriod statPeriod = StatPeriod.monthly;` + `void setStatPeriod(StatPeriod p)`.

- [ ] **Step 1: Write the failing tests**

In `flutter/test/logic_test.dart`, add. Use a fixed `now` and hand-built records (each `SessionRecord(epochDay, minutes, label)`; build days via `epochDayOf`).

```dart
group('StatsAggregator periods (v12)', () {
  // Wed 2026-06-17
  final now = DateTime(2026, 6, 17, 12);
  int day(int y, int m, int d) => epochDayOf(DateTime(y, m, d));
  final records = [
    SessionRecord(day(2026, 6, 17), 60, 'MATH'),   // today
    SessionRecord(day(2026, 6, 17), 30, 'CODING'), // today
    SessionRecord(day(2026, 6, 15), 40, 'MATH'),   // Mon this week
    SessionRecord(day(2026, 6, 10), 50, 'READING'),// earlier this month
    SessionRecord(day(2026, 3, 4), 90, 'MATH'),    // earlier this year
    SessionRecord(day(2025, 12, 1), 25, 'MATH'),   // last year
  ];

  test('byLabelInWindow daily = today only', () {
    final r = StatsAggregator.byLabelInWindow(records, now, StatPeriod.daily);
    expect(r.map((e) => e.key).toList(), ['MATH', 'CODING']); // 60 then 30
    expect(r.first.value, 60);
  });

  test('byLabelInWindow weekly = Mon..Sun of this week', () {
    final total = StatsAggregator.byLabelInWindow(records, now, StatPeriod.weekly)
        .fold<int>(0, (a, e) => a + e.value);
    expect(total, 60 + 30 + 40); // today + Mon
  });

  test('byLabelInWindow monthly / yearly / allTime sum correctly', () {
    int sum(StatPeriod p) => StatsAggregator.byLabelInWindow(records, now, p)
        .fold<int>(0, (a, e) => a + e.value);
    expect(sum(StatPeriod.monthly), 60 + 30 + 40 + 50);
    expect(sum(StatPeriod.yearly), 60 + 30 + 40 + 50 + 90);
    expect(sum(StatPeriod.allTime), 60 + 30 + 40 + 50 + 90 + 25);
  });

  test('seriesFor monthly has one bucket per day with today populated', () {
    final s = StatsAggregator.seriesFor(records, now, StatPeriod.monthly);
    expect(s.totals.length, 30);       // June has 30 days
    expect(s.totals[16], 90);          // day 17 → index 16 → 60+30
    expect(s.byLabel[16].length, 2);   // MATH + CODING that day
  });

  test('seriesFor daily has 7 buckets ending today', () {
    final s = StatsAggregator.seriesFor(records, now, StatPeriod.daily);
    expect(s.totals.length, 7);
    expect(s.totals.last, 90);         // today = 60+30
  });

  test('seriesFor yearly has 12 month buckets; allTime per year', () {
    final y = StatsAggregator.seriesFor(records, now, StatPeriod.yearly);
    expect(y.totals.length, 12);
    expect(y.totals[5], 90);           // June = 60+30+40+50 ... wait
    final a = StatsAggregator.seriesFor(records, now, StatPeriod.allTime);
    expect(a.totals.length, 2);        // 2025 + 2026
    expect(a.totals.last, 60 + 30 + 40 + 50 + 90); // 2026
    expect(a.totals.first, 25);        // 2025
  });

  test('labelSeriesFor daily gives one series per label over 7 days', () {
    final ls = StatsAggregator.labelSeriesFor(records, now, StatPeriod.daily);
    final math = ls.firstWhere((s) => s.label == 'MATH');
    expect(math.values.length, 7);
    expect(math.values.last, 60); // today's MATH
  });
});
```

Note: fix the yearly-June assertion — June index 5 total = 60+30+40+50 = 180. Replace the `y.totals[5]` line with `expect(y.totals[5], 180);` and delete the stray "wait" comment when writing.

- [ ] **Step 2: Run tests, verify they fail**

Run: `& C:\src\flutter\bin\flutter.bat test test/logic_test.dart`
Expected: FAIL — new symbols undefined.

- [ ] **Step 3: Implement the period helpers in `logic.dart`**

Add to `logic.dart` (after the existing `StatsAggregator` class members; reuse `epochDayOf`/`dateOfEpochDay`). Add the enum + result types above `StatsAggregator`:

```dart
enum StatPeriod { daily, weekly, monthly, yearly, allTime }

class StatSeries {
  final List<int> totals; // per x-bucket
  final List<String> tickLabels; // x labels
  final List<List<MapEntry<String, int>>> byLabel; // per bucket, desc
  const StatSeries(this.totals, this.tickLabels, this.byLabel);
}

class LabelSeries {
  final String label;
  final List<int> values; // per x-bucket
  const LabelSeries(this.label, this.values);
}
```

Add these static methods inside `StatsAggregator`:

```dart
/// Inclusive [startEpochDay, endEpochDay] window for a period relative to [now].
static (int, int) windowDays(DateTime now, StatPeriod p) {
  final todayE = epochDayOf(now);
  switch (p) {
    case StatPeriod.daily:
      return (todayE, todayE);
    case StatPeriod.weekly:
      final monday = todayE - (now.weekday - 1);
      return (monday, monday + 6);
    case StatPeriod.monthly:
      final first = epochDayOf(DateTime(now.year, now.month, 1));
      final lastDay = DateTime(now.year, now.month + 1, 0).day;
      return (first, first + lastDay - 1);
    case StatPeriod.yearly:
      return (epochDayOf(DateTime(now.year, 1, 1)), epochDayOf(DateTime(now.year, 12, 31)));
    case StatPeriod.allTime:
      return (-100000000, todayE);
  }
}

static List<MapEntry<String, int>> byLabelInWindow(
    List<SessionRecord> records, DateTime now, StatPeriod p) {
  final (lo, hi) = windowDays(now, p);
  final map = <String, int>{};
  for (final r in records) {
    if (r.epochDay < lo || r.epochDay > hi) continue;
    map[r.label] = (map[r.label] ?? 0) + (r.minutes < 0 ? 0 : r.minutes);
  }
  final list = map.entries.where((e) => e.value > 0).toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return list;
}

static StatSeries seriesFor(List<SessionRecord> records, DateTime now, StatPeriod p) {
  // bucketIndex(record) → 0..n-1 or -1; plus n + tick labels.
  late int n;
  late int Function(SessionRecord) idx;
  late List<String> ticks;
  switch (p) {
    case StatPeriod.daily:
      n = 7;
      final endE = epochDayOf(now);
      idx = (r) => r.epochDay - (endE - 6);
      ticks = [for (var i = 0; i < 7; i++) '${dateOfEpochDay(endE - 6 + i).day}'];
      break;
    case StatPeriod.weekly:
      n = 7;
      final mon = epochDayOf(now) - (now.weekday - 1);
      idx = (r) => r.epochDay - mon;
      ticks = [for (var i = 0; i < 7; i++) '${dateOfEpochDay(mon + i).day}'];
      break;
    case StatPeriod.monthly:
      n = DateTime(now.year, now.month + 1, 0).day;
      idx = (r) {
        final d = dateOfEpochDay(r.epochDay);
        return (d.year == now.year && d.month == now.month) ? d.day - 1 : -1;
      };
      ticks = [for (var i = 1; i <= n; i++) '$i'];
      break;
    case StatPeriod.yearly:
      n = 12;
      idx = (r) {
        final d = dateOfEpochDay(r.epochDay);
        return d.year == now.year ? d.month - 1 : -1;
      };
      ticks = [for (var i = 1; i <= 12; i++) '$i'];
      break;
    case StatPeriod.allTime:
      var minY = now.year;
      for (final r in records) {
        final y = dateOfEpochDay(r.epochDay).year;
        if (y < minY) minY = y;
      }
      n = now.year - minY + 1;
      idx = (r) => dateOfEpochDay(r.epochDay).year - minY;
      ticks = [for (var i = 0; i < n; i++) '${minY + i}'];
      break;
  }
  final totals = List<int>.filled(n, 0);
  final maps = List.generate(n, (_) => <String, int>{});
  for (final r in records) {
    final i = idx(r);
    if (i < 0 || i >= n) continue;
    final m = r.minutes < 0 ? 0 : r.minutes;
    totals[i] += m;
    maps[i][r.label] = (maps[i][r.label] ?? 0) + m;
  }
  final byLabel = [
    for (final m in maps)
      (m.entries.where((e) => e.value > 0).toList()
        ..sort((a, b) => b.value.compareTo(a.value)))
  ];
  return StatSeries(totals, ticks, byLabel);
}

static List<LabelSeries> labelSeriesFor(
    List<SessionRecord> records, DateTime now, StatPeriod p) {
  final s = seriesFor(records, now, p);
  final n = s.totals.length;
  // labels present in the window, ordered by total desc
  final totalByLabel = <String, int>{};
  for (final bucket in s.byLabel) {
    for (final e in bucket) {
      totalByLabel[e.key] = (totalByLabel[e.key] ?? 0) + e.value;
    }
  }
  final labels = totalByLabel.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return [
    for (final l in labels)
      LabelSeries(l.key, [
        for (var i = 0; i < n; i++)
          s.byLabel[i].firstWhere((e) => e.key == l.key, orElse: () => MapEntry(l.key, 0)).value
      ])
  ];
}
```

- [ ] **Step 4: Add `statPeriod` to `store.dart`**

After `ChartMode chartMode = ChartMode.bar;` add `StatPeriod statPeriod = StatPeriod.monthly;` and near `setChartMode`:

```dart
void setStatPeriod(StatPeriod p) {
  statPeriod = p;
  notifyListeners();
}
```

- [ ] **Step 5: Run tests, verify pass**

Run: `& C:\src\flutter\bin\flutter.bat analyze && & C:\src\flutter\bin\flutter.bat test test/logic_test.dart`
Expected: analyze clean; all new period tests pass.

- [ ] **Step 6: Commit**

```bash
git add flutter/lib/logic.dart flutter/lib/store.dart flutter/test/logic_test.dart
git commit -m "v12: stats period aggregators (window/series/per-label) (#11,#10 data)"
```

---

### Task 3: Stats screen rework — period selector (#11), pie separators (#9), tappable line + daily multi-line (#10)

**Files:**
- Modify: `flutter/lib/pixel.dart` (`LabelLine` type; `StatsChart` → stateful, period-aware, separators, tap callout, multi-line)
- Modify: `flutter/lib/main.dart` (`StatsScreen`: period row replaces month navigator; build chart inputs)
- Modify: `flutter/lib/strings.dart` (period keys ×6)
- Test: `flutter/test/widget_smoke_test.dart`

**Interfaces:**
- Consumes: `StatPeriod`, `StatSeries`, `LabelSeries`, `byLabelInWindow`, `seriesFor`, `labelSeriesFor` (Task 2); `setStatPeriod`/`statPeriod` (store).
- Produces (`pixel.dart`): `class LabelLine { final String label; final int color; final List<int> values; const LabelLine(this.label, this.color, this.values); }`; new `StatsChart` ctor:
  `StatsChart({entries: List<ChartEntry>, series: StatSeries, labelLines: List<LabelLine>?, multiLine: bool, mode: ChartMode, lang, axisColor, textColor, lineColor})`.

- [ ] **Step 1: Add period strings**

In `flutter/lib/strings.dart`, add to each language map: `pDaily`, `pWeekly`, `pMonthly`, `pYearly`, `pAll`. en: `'DAILY'/'WEEKLY'/'MONTHLY'/'YEARLY'/'ALL'`. tr: `'GÜNLÜK'/'HAFTALIK'/'AYLIK'/'YILLIK'/'TÜMÜ'`. pl: `'DZIENNE'/'TYGODNIE'/'MIESIĄC'/'ROCZNE'/'WSZYSTKO'`. de: `'TÄGLICH'/'WÖCHENTL'/'MONATL'/'JÄHRL'/'GESAMT'`. ko: `'일간'/'주간'/'월간'/'연간'/'전체'`. it: `'GIORNO'/'SETTIMANA'/'MESE'/'ANNO'/'TUTTO'`.

- [ ] **Step 2: Write the failing smoke assertion**

In `flutter/test/widget_smoke_test.dart`, the stats block opens via `openClose(Icons.bar_chart, 'STATS')`. Replace that single call with an explicit block that taps period + chart-type and a line point, before closing:

```dart
// stats: period selector + chart types + line tap (no crash)
await tester.tap(find.byIcon(Icons.bar_chart));
await tester.pumpAndSettle();
expect(find.text('STATS'), findsWidgets);
await tester.tap(find.text('DAILY'));
await tester.pumpAndSettle();
await tester.tap(find.text('LINE'));
await tester.pumpAndSettle();
await tester.tap(find.text('PIE'));
await tester.pumpAndSettle();
final statsClose = find.text('CLOSE');
await tester.ensureVisible(statsClose);
await tester.pumpAndSettle();
await tester.tap(statsClose);
await tester.pumpAndSettle();
```

- [ ] **Step 3: Run smoke, verify it fails**

Run: `& C:\src\flutter\bin\flutter.bat test test/widget_smoke_test.dart`
Expected: FAIL — `DAILY` not found (period selector not built yet).

- [ ] **Step 4: Rewrite `StatsChart` in `pixel.dart`**

Replace the entire `StatsChart` class and `_ChartPainter` class with a stateful, period-aware version. Full replacement:

```dart
/// One per-label datum for bar/pie.
class ChartEntry {
  final String label;
  final int value;
  final int color;
  const ChartEntry(this.label, this.value, this.color);
}

/// One per-label line (daily multi-line mode).
class LabelLine {
  final String label;
  final int color;
  final List<int> values;
  const LabelLine(this.label, this.color, this.values);
}

/// Bar / line / pie chart for the selected stats period. Line mode is tappable:
/// tapping a bucket shows its total + per-label breakdown (#10). DAILY draws one
/// line per label (#10 multi-line); other periods draw one total line.
class StatsChart extends StatefulWidget {
  final List<ChartEntry> entries; // by-label for bar/pie
  final StatSeries series; // totals + tick labels + per-bucket by-label
  final List<LabelLine>? labelLines; // non-null + multiLine → daily per-label
  final bool multiLine;
  final ChartMode mode;
  final String lang;
  final int axisColor, textColor, lineColor, panelColor, panelBorder;

  const StatsChart({
    super.key,
    required this.entries,
    required this.series,
    required this.labelLines,
    required this.multiLine,
    required this.mode,
    required this.lang,
    required this.axisColor,
    required this.textColor,
    required this.lineColor,
    required this.panelColor,
    required this.panelBorder,
  });

  @override
  State<StatsChart> createState() => _StatsChartState();
}

class _StatsChartState extends State<StatsChart> {
  int? _sel; // selected bucket index (line mode)

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.mode == ChartMode.line ? _onTap : null,
      child: CustomPaint(
        painter: _ChartPainter(widget, _sel),
        child: const SizedBox.expand(),
      ),
    );
  }

  void _onTap(TapDownDetails d) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final w = box.size.width;
    final n = widget.series.totals.length;
    if (n == 0) return;
    const padL = 10.0, padR = 10.0;
    final plotW = w - padL - padR;
    final rel = ((d.localPosition.dx - padL) / (plotW <= 0 ? 1 : plotW)).clamp(0.0, 1.0);
    setState(() => _sel = (rel * (n - 1)).round());
  }
}

class _ChartPainter extends CustomPainter {
  final StatsChart c;
  final int? sel;
  _ChartPainter(this.c, this.sel);

  void _text(Canvas canvas, String s, double x, double y, double size, int color,
      {TextAlign align = TextAlign.left}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: pixelStyle(c.lang, size, col(color))),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout();
    var dx = x;
    if (align == TextAlign.center) dx = x - tp.width / 2;
    if (align == TextAlign.right) dx = x - tp.width;
    tp.paint(canvas, Offset(dx, y - tp.height));
  }

  bool _hasData() => c.mode == ChartMode.line
      ? c.series.totals.any((v) => v > 0)
      : c.entries.any((e) => e.value > 0);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    if (!_hasData()) {
      _text(canvas, _noData(), w / 2, h / 2 + 6, 9, c.textColor, align: TextAlign.center);
      return;
    }
    switch (c.mode) {
      case ChartMode.bar:
        _bars(canvas, w, h);
        break;
      case ChartMode.line:
        _line(canvas, w, h);
        break;
      case ChartMode.pie:
        _pie(canvas, w, h);
        break;
    }
  }

  String _noData() {
    const m = {
      'en': 'No focus minutes here.',
      'tr': 'Burada odak dakikası yok.',
      'pl': 'Brak minut tutaj.',
      'de': 'Keine Minuten hier.',
      'ko': '기록이 없습니다.',
      'it': 'Nessun minuto qui.',
    };
    return m[c.lang] ?? m['en']!;
  }

  String _short(String s) => s.length <= 6 ? s : s.substring(0, 6);
  String _fmt(int min) => StatsAggregator.formatMinutes(min);

  void _bars(Canvas canvas, double w, double h) {
    const padL = 8.0, padR = 8.0, padTop = 10.0, padBottom = 26.0;
    final plotW = w - padL - padR, plotH = h - padTop - padBottom;
    final maxVal = math.max(1, c.entries.map((e) => e.value).reduce(math.max));
    final n = c.entries.length;
    final slot = plotW / n, barW = slot * 0.62;
    final axis = Paint()..color = col(c.axisColor)..strokeWidth = 2;
    canvas.drawLine(Offset(padL, padTop + plotH), Offset(padL + plotW, padTop + plotH), axis);
    final fill = Paint();
    for (var i = 0; i < n; i++) {
      final e = c.entries[i];
      final cx = padL + slot * i + slot / 2;
      final barH = plotH * (e.value / maxVal);
      fill.color = col(e.color);
      canvas.drawRect(Rect.fromLTWH(cx - barW / 2, padTop + plotH - barH, barW, barH), fill);
      _text(canvas, _short(e.label), cx, h - 14, 7, c.textColor, align: TextAlign.center);
      _text(canvas, _fmt(e.value), cx, padTop + plotH - barH - 3, 7, c.textColor, align: TextAlign.center);
    }
  }

  void _line(Canvas canvas, double w, double h) {
    const padL = 10.0, padR = 10.0, padTop = 12.0, padBottom = 18.0;
    final plotW = w - padL - padR, plotH = h - padTop - padBottom;
    final totals = c.series.totals;
    final n = totals.length;
    final lines = (c.multiLine && c.labelLines != null && c.labelLines!.isNotEmpty)
        ? c.labelLines! : null;
    final maxVal = math.max(
        1,
        lines == null
            ? totals.reduce(math.max)
            : lines.expand((l) => l.values).fold(1, math.max));
    final axis = Paint()..color = col(c.axisColor)..strokeWidth = 2;
    canvas.drawLine(Offset(padL, padTop + plotH), Offset(padL + plotW, padTop + plotH), axis);
    double x(int i) => padL + plotW * (n <= 1 ? 0 : i / (n - 1));
    double y(int v) => padTop + plotH * (1 - v / maxVal);

    void drawSeries(List<int> vals, int color) {
      final path = Path();
      for (var i = 0; i < vals.length; i++) {
        final px = x(i), py = y(vals[i]);
        i == 0 ? path.moveTo(px, py) : path.lineTo(px, py);
      }
      canvas.drawPath(path, Paint()..color = col(color)..style = PaintingStyle.stroke..strokeWidth = 2.5);
      final dot = Paint()..color = col(color);
      for (var i = 0; i < vals.length; i++) {
        canvas.drawCircle(Offset(x(i), y(vals[i])), 2, dot);
      }
    }

    if (lines == null) {
      drawSeries(totals, c.lineColor);
    } else {
      for (final l in lines) {
        drawSeries(l.values, l.color);
      }
    }

    // x ticks: first + last (avoid clutter)
    if (c.series.tickLabels.isNotEmpty) {
      _text(canvas, c.series.tickLabels.first, padL, h - 4, 7, c.textColor);
      _text(canvas, c.series.tickLabels.last, padL + plotW, h - 4, 7, c.textColor, align: TextAlign.right);
    }

    // selection callout (#10)
    final s = sel;
    if (s != null && s >= 0 && s < n) {
      final sx = x(s);
      canvas.drawLine(Offset(sx, padTop), Offset(sx, padTop + plotH),
          Paint()..color = col(c.axisColor)..strokeWidth = 1);
      final detail = c.series.byLabel[s];
      final lines2 = <String>[
        '${c.series.tickLabels[s]} · ${_fmt(totals[s])}',
        for (final e in detail) '${_short(e.key)} ${_fmt(e.value)}',
      ];
      _callout(canvas, w, sx, padTop + 4, lines2);
    }
  }

  void _callout(Canvas canvas, double w, double anchorX, double top, List<String> lines) {
    const fs = 7.0, pad = 4.0, lh = 11.0;
    var maxW = 0.0;
    for (final s in lines) {
      final tp = TextPainter(
        text: TextSpan(text: s, style: pixelStyle(c.lang, fs, col(c.textColor))),
        textDirection: TextDirection.ltr,
      )..layout();
      maxW = math.max(maxW, tp.width);
    }
    final boxW = maxW + pad * 2;
    final boxH = lines.length * lh + pad * 2;
    var left = anchorX + 6;
    if (left + boxW > w) left = anchorX - 6 - boxW;
    if (left < 0) left = 0;
    final rect = Rect.fromLTWH(left, top, boxW, boxH);
    canvas.drawRect(rect, Paint()..color = col(c.panelColor));
    canvas.drawRect(rect, Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = col(c.panelBorder));
    var ty = top + pad + lh;
    for (final s in lines) {
      _text(canvas, s, left + pad, ty, fs, c.textColor);
      ty += lh;
    }
  }

  void _pie(Canvas canvas, double w, double h) {
    final total = c.entries.fold<int>(0, (a, e) => a + e.value).toDouble();
    final legendW = w * 0.42;
    final dia = math.min(h - 16, (w - legendW) - 16);
    final cx = 8 + (w - legendW - 8) / 2, cy = h / 2;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: dia / 2);
    var start = -math.pi / 2;
    final fill = Paint();
    final sep = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = col(c.panelColor); // #9 separator in the panel/bg color
    for (final e in c.entries) {
      final sweep = 2 * math.pi * (e.value / total);
      fill.color = col(e.color);
      canvas.drawArc(rect, start, sweep, true, fill);
      canvas.drawArc(rect, start, sweep, true, sep); // stroke wedge outline (#9)
      start += sweep;
    }
    final lx = w - legendW + 6;
    var ly = cy - (c.entries.length * 13) / 2 + 8;
    for (final e in c.entries) {
      fill.color = col(e.color);
      canvas.drawRect(Rect.fromLTWH(lx, ly - 7, 8, 8), fill);
      final pct = (100 * e.value / total).round();
      _text(canvas, '${_short(e.label)} $pct%', lx + 12, ly + 1, 7, c.textColor);
      ly += 13;
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) => true;
}
```

- [ ] **Step 5: Rewrite `StatsScreen` in `main.dart`**

Replace the `StatsScreen.build` body. Key changes: drop the `◀ month ▶` row; add a period row (5 buttons) above BAR/LINE/PIE; build `series`/`labelLines`/`entries` from the aggregators for `s.statPeriod`. Full new build:

```dart
@override
Widget build(BuildContext context) {
  final th = s.theme;
  final lang = s.lang;
  final now = DateTime.now();
  final totals = StatsAggregator.aggregate(s.records, now);
  final byLabel = StatsAggregator.byLabelInWindow(s.records, now, s.statPeriod);
  final series = StatsAggregator.seriesFor(s.records, now, s.statPeriod);
  final multiLine = s.statPeriod == StatPeriod.daily;
  final labelLines = multiLine
      ? [for (final ls in StatsAggregator.labelSeriesFor(s.records, now, s.statPeriod))
          LabelLine(ls.label, s.labelColorOf(ls.label), ls.values)]
      : null;

  Widget periodBtn(String text, StatPeriod p) {
    final sel = s.statPeriod == p;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: sel
            ? primaryBtn(th, lang, text, () => s.setStatPeriod(p), fontSize: 8, padding: const EdgeInsets.all(8))
            : secondaryBtn(th, lang, text, () => s.setStatPeriod(p), fontSize: 8, padding: const EdgeInsets.all(8)),
      ),
    );
  }

  Widget chartBtn(String text, ChartMode m) {
    final sel = s.chartMode == m;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: sel
            ? primaryBtn(th, lang, text, () => s.setChartMode(m), fontSize: 9, padding: const EdgeInsets.all(12))
            : secondaryBtn(th, lang, text, () => s.setChartMode(m), fontSize: 9, padding: const EdgeInsets.all(12)),
      ),
    );
  }

  Widget statRow(String caption, int minutes) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Text(caption, style: pixelStyle(lang, 11, col(th.onSurfaceDim))),
          const Spacer(),
          Text(StatsAggregator.formatMinutes(minutes), style: pixelStyle(lang, 13, col(th.onSurface))),
        ]),
      );

  return overlayScaffold(context, s, t(lang, 'stats'), [
    Row(children: [
      periodBtn(t(lang, 'pDaily'), StatPeriod.daily),
      periodBtn(t(lang, 'pWeekly'), StatPeriod.weekly),
      periodBtn(t(lang, 'pMonthly'), StatPeriod.monthly),
      periodBtn(t(lang, 'pYearly'), StatPeriod.yearly),
      periodBtn(t(lang, 'pAll'), StatPeriod.allTime),
    ]),
    const SizedBox(height: 12),
    Row(children: [chartBtn(t(lang, 'chartBar'), ChartMode.bar), chartBtn(t(lang, 'chartLine'), ChartMode.line), chartBtn(t(lang, 'chartPie'), ChartMode.pie)]),
    const SizedBox(height: 16),
    SizedBox(
      height: 200,
      child: StatsChart(
        entries: [for (final e in byLabel) ChartEntry(e.key, e.value, s.labelColorOf(e.key))],
        series: series,
        labelLines: labelLines,
        multiLine: multiLine,
        mode: s.chartMode,
        lang: lang,
        axisColor: th.onSurfaceDim,
        textColor: th.onSurface,
        lineColor: th.accent,
        panelColor: th.panel,
        panelBorder: th.onSurfaceDim,
      ),
    ),
    const SizedBox(height: 16),
    statRow(t(lang, 'today'), totals.today),
    statRow(t(lang, 'week'), totals.week),
    statRow(t(lang, 'month'), totals.month),
    statRow(t(lang, 'year'), totals.year),
    statRow(t(lang, 'all'), totals.all),
    const SizedBox(height: 16),
    Text(t(lang, 'byLabel'), style: pixelStyle(lang, 11, col(th.onSurfaceDim))),
    const SizedBox(height: 12),
    if (byLabel.isEmpty)
      Text(t(lang, 'chartNoData'), style: pixelStyle(lang, 9, col(th.onSurfaceDim)))
    else
      for (final e in byLabel)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Swatch(color: s.labelColorOf(e.key), border: th.onSurfaceDim, size: 16),
            const SizedBox(width: 10),
            Text(e.key, style: pixelStyle(lang, 11, col(th.onSurface))),
            const Spacer(),
            Text(StatsAggregator.formatMinutes(e.value), style: pixelStyle(lang, 11, col(th.onSurfaceDim))),
          ]),
        ),
  ]);
}
```

Add a `byLabel` string key ×6 in `strings.dart`: en `'BY LABEL'`, tr `'ETİKETE GÖRE'`, pl `'WG ETYKIETY'`, de `'NACH LABEL'`, ko `'라벨별'`, it `'PER ETICHETTA'`. (Replaces the old `byLabelMonth` usage; leave `byLabelMonth` in place, unused.)

- [ ] **Step 6: Remove now-unused store month-navigator (optional cleanup)**

Leave `viewYear`/`viewMonth`/`shiftMonth`/`canGoNextMonth` in `store.dart` (harmless, still compiles). Do not delete to keep the diff focused.

- [ ] **Step 7: Run analyze + smoke + full tests, verify pass**

Run: `& C:\src\flutter\bin\flutter.bat analyze && & C:\src\flutter\bin\flutter.bat test`
Expected: analyze clean; smoke taps DAILY/LINE/PIE without error; all pass.

- [ ] **Step 8: Commit**

```bash
git add flutter/lib/pixel.dart flutter/lib/main.dart flutter/lib/strings.dart flutter/test/widget_smoke_test.dart
git commit -m "v12: stats period selector + pie separators + tappable line + daily multi-line (#9,#10,#11)"
```

---

### Task 4: Label rename (#8)

**Files:**
- Modify: `flutter/lib/logic.dart` (`Labels.rename`)
- Modify: `flutter/lib/store.dart` (`renameLabel` migrating color/current/records)
- Modify: `flutter/lib/main.dart` (`LabelScreen`: long-press → rename dialog)
- Modify: `flutter/lib/strings.dart` (`renameTitle` ×6)
- Test: `flutter/test/logic_test.dart`

**Interfaces:**
- Produces: `Labels.rename(List<String> list, String oldLabel, String raw) → List<String>` (normalizes raw; returns unchanged on empty/dupe/missing).
- Produces: `AppStore.renameLabel(String oldLabel, String raw)`.

- [ ] **Step 1: Write the failing test**

In `flutter/test/logic_test.dart` (Labels group):

```dart
test('rename replaces a label in place, rejects empty/dupe', () {
  final list = ['STUDY', 'MATH', 'CODING'];
  expect(Labels.rename(list, 'MATH', 'algebra'), ['STUDY', 'ALGEBRA', 'CODING']);
  expect(Labels.rename(list, 'MATH', '   '), list); // empty → unchanged
  expect(Labels.rename(list, 'MATH', 'coding'), list); // dupe → unchanged
  expect(Labels.rename(list, 'NOPE', 'X'), list); // missing → unchanged
});
```

- [ ] **Step 2: Run test, verify it fails**

Run: `& C:\src\flutter\bin\flutter.bat test test/logic_test.dart`
Expected: FAIL — `Labels.rename` undefined.

- [ ] **Step 3: Implement `Labels.rename`**

Add to `class Labels` in `logic.dart`:

```dart
static List<String> rename(List<String> list, String oldLabel, String raw) {
  final next = normalize(raw);
  if (next == null) return list;
  final oldU = oldLabel.toUpperCase();
  if (!list.any((l) => l.toUpperCase() == oldU)) return list;
  if (next.toUpperCase() != oldU && list.any((l) => l.toUpperCase() == next.toUpperCase())) {
    return list; // would collide with another label
  }
  return [for (final l in list) l.toUpperCase() == oldU ? next : l];
}
```

- [ ] **Step 4: Run test, verify pass**

Run: `& C:\src\flutter\bin\flutter.bat test test/logic_test.dart`
Expected: PASS.

- [ ] **Step 5: Add `renameLabel` to `store.dart`**

```dart
void renameLabel(String oldLabel, String raw) {
  final updated = Labels.rename(labels, oldLabel, raw);
  if (identical(updated, labels) || updated == labels) return;
  // find the new name (the entry that changed)
  final newName = updated.firstWhere(
      (l) => !labels.any((o) => o.toUpperCase() == l.toUpperCase()),
      orElse: () => oldLabel);
  labels = updated;
  final oldU = oldLabel.toUpperCase();
  // migrate color
  if (labelColors.containsKey(oldU)) {
    labelColors[newName.toUpperCase()] = labelColors.remove(oldU)!;
    _saveLabelColors();
  }
  // migrate current selection
  if (currentLabel.toUpperCase() == oldU) currentLabel = newName;
  // migrate past stats records
  records = [
    for (final r in records)
      r.label.toUpperCase() == oldU ? SessionRecord(r.epochDay, r.minutes, newName) : r
  ];
  _saveStats();
  _saveLabels();
  notifyListeners();
}
```

- [ ] **Step 6: Add rename dialog to `LabelScreen` (`main.dart`)**

Add a `renameTitle` string ×6: en `'RENAME LABEL'`, tr `'ETİKETİ DEĞİŞTİR'`, pl `'ZMIEŃ NAZWĘ'`, de `'LABEL UMBENENNEN'`, ko `'라벨 이름 변경'`, it `'RINOMINA ETICHETTA'`.

In `_labelRow`, wrap the name button in a `GestureDetector` for long-press (the inner button keeps tap=select):

```dart
Expanded(
  child: GestureDetector(
    onLongPress: () => _renameLabel(context, s, label),
    child: selected
        ? primaryBtn(th, lang, '> $label', () => s.selectLabel(label))
        : secondaryBtn(th, lang, label, () => s.selectLabel(label)),
  ),
),
```

Add the method to `_LabelScreenState`:

```dart
void _renameLabel(BuildContext context, AppStore s, String label) {
  final th = s.theme;
  final lang = s.lang;
  final ctrl = TextEditingController(text: label);
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: col(th.panel),
      title: Text(t(lang, 'renameTitle'), style: pixelStyle(lang, 12, col(th.onSurface))),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        maxLength: 12,
        style: pixelStyle(lang, 12, col(th.onSurface)),
        decoration: InputDecoration(counterText: '', filled: true, fillColor: col(th.bg)),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t(lang, 'no'), style: pixelStyle(lang, 11, col(th.onSurfaceDim)))),
        TextButton(
            onPressed: () {
              s.renameLabel(label, ctrl.text);
              Navigator.pop(ctx);
            },
            child: Text(t(lang, 'save'), style: pixelStyle(lang, 11, col(th.accent)))),
      ],
    ),
  );
}
```

Add a hint under the LABEL list: in `build`, after the `for (final label ...)` rows, the existing add-row stays; insert before it `Text(t(lang,'renameHint'), ...)` with `renameHint` ×6 (en `'Long-press a label to rename it.'`, tr `'Yeniden adlandırmak için etikete basılı tut.'`, pl `'Przytrzymaj etykietę, aby zmienić nazwę.'`, de `'Zum Umbenennen lange drücken.'`, ko `'이름을 바꾸려면 길게 누르세요.'`, it `'Tieni premuto per rinominare.'`), styled `pixelStyle(lang, 8, col(th.onSurfaceDim))`.

- [ ] **Step 7: Extend smoke test**

In `widget_smoke_test.dart`, the label overlay is opened at the end (`find.text(store.currentLabel)`). After `expect(find.text('ADD'), findsOneWidget);` add a long-press rename:

```dart
await tester.longPress(find.text('> ${store.currentLabel}').first);
await tester.pumpAndSettle();
expect(find.text('RENAME LABEL'), findsOneWidget);
await tester.enterText(find.byType(TextField).last, 'RENAMED');
await tester.tap(find.text('SAVE'));
await tester.pumpAndSettle();
expect(find.text('RENAMED'), findsWidgets);
```

(If the current label isn't shown with the `> ` prefix in the list, long-press `find.text(store.currentLabel).last` instead.)

- [ ] **Step 8: Run analyze + tests, verify pass**

Run: `& C:\src\flutter\bin\flutter.bat analyze && & C:\src\flutter\bin\flutter.bat test`
Expected: clean + green.

- [ ] **Step 9: Commit**

```bash
git add flutter/lib/logic.dart flutter/lib/store.dart flutter/lib/main.dart flutter/lib/strings.dart flutter/test/logic_test.dart flutter/test/widget_smoke_test.dart
git commit -m "v12: rename labels via long-press, migrate color/current/stats (#8)"
```

---

### Task 5: Forest fills the whole screen (#1)

**Files:**
- Modify: `flutter/lib/engine/garden_engine.dart` (`Projector.gridAt`/`visibleTileBounds`; forest over visible range; widen `clamp`; simplify `WorldGrid`)
- Modify: `flutter/lib/engine/garden_view.dart` (clamp call uses new roam bound)
- Test: `flutter/test/engine_test.dart`

**Interfaces:**
- Produces (`Projector`): `Offset gridAt(Offset screen)` → continuous (col,row) in claimed-index space (inverse of `ground`); `({int minC, int maxC, int minR, int maxR}) visibleTileBounds(Size size)` → integer tile range (with 1-tile bleed) covering the screen.
- Changes: `GardenCamera.clamp(int cols, int rows, Size size)` now bounds pan to a roam radius (keeps the garden reachable but lets you pan into the forest).

- [ ] **Step 1: Write the failing tests**

In `flutter/test/engine_test.dart` add:

```dart
group('Projector forest fill (v12)', () {
  test('gridAt inverts ground for fractional coords at several yaws', () {
    const cols = 4, rows = 6, t = 40.0;
    const center = Offset(200, 400);
    for (final yaw in [0.0, 0.7, -1.3]) {
      final p = Projector(cols, rows, t, center, yaw);
      for (final g in [const Offset(0, 0), const Offset(2.5, 3.5), const Offset(-3, 8)]) {
        final screen = p.projectGrid(p.gridOfD(g.dx, g.dy));
        final back = p.gridAt(screen);
        expect(back.dx, closeTo(g.dx + (cols - 1) / 2.0, 1e-6));
        expect(back.dy, closeTo(g.dy + (rows - 1) / 2.0, 1e-6));
      }
    }
  });

  test('visibleTileBounds spans beyond the claimed plot to fill the screen', () {
    final cam = GardenCamera();
    const size = Size(360, 720);
    final p = Projector.fit(4, 6, cam, size);
    final b = p.visibleTileBounds(size);
    // covers the whole claimed plot...
    expect(b.minC <= 0 && b.maxC >= 3, true);
    expect(b.minR <= 0 && b.maxR >= 5, true);
    // ...and bleeds beyond it (forest fills the rest)
    expect(b.minC < 0 || b.maxC > 3, true);
    expect(b.minR < 0 || b.maxR > 5, true);
  });
});
```

(Note: `gridOfD` is a small double-coord helper added below.)

- [ ] **Step 2: Run tests, verify they fail**

Run: `& C:\src\flutter\bin\flutter.bat test test/engine_test.dart`
Expected: FAIL — `gridAt`/`gridOfD`/`visibleTileBounds` undefined.

- [ ] **Step 3: Add the projection helpers to `garden_engine.dart`**

In `class Projector`, add (next to `gridOf`):

```dart
/// Continuous garden coord for fractional (col,row).
Offset gridOfD(double c, double r) => Offset(c - (cols - 1) / 2.0, r - (rows - 1) / 2.0);

/// Inverse of [ground]: continuous (col,row) in claimed-index space for a
/// screen point. Used to find which tiles are visible so the forest can fill
/// the whole screen.
Offset gridAt(Offset p) {
  final dx = (p.dx - center.dx) / t;
  final dy = (p.dy - center.dy) / (t * kVy);
  final gx = dx * _cos + dy * _sin;
  final gy = -dx * _sin + dy * _cos;
  return Offset(gx + (cols - 1) / 2.0, gy + (rows - 1) / 2.0);
}

/// Integer tile range (1-tile bleed) covering the screen, so every visible tile
/// outside the claimed plot can be painted as forest (no void).
({int minC, int maxC, int minR, int maxR}) visibleTileBounds(Size size) {
  final corners = [
    gridAt(const Offset(0, 0)),
    gridAt(Offset(size.width, 0)),
    gridAt(Offset(size.width, size.height)),
    gridAt(Offset(0, size.height)),
  ];
  var minC = double.infinity, maxC = -double.infinity, minR = double.infinity, maxR = -double.infinity;
  for (final c in corners) {
    minC = math.min(minC, c.dx); maxC = math.max(maxC, c.dx);
    minR = math.min(minR, c.dy); maxR = math.max(maxR, c.dy);
  }
  return (minC: minC.floor() - 1, maxC: maxC.ceil() + 1, minR: minR.floor() - 1, maxR: maxR.ceil() + 1);
}
```

- [ ] **Step 4: Run tests, verify pass**

Run: `& C:\src\flutter\bin\flutter.bat test test/engine_test.dart`
Expected: PASS.

- [ ] **Step 5: Draw the forest over the visible range in `GardenPainter.paint`**

Replace the v11 standing-props build (the block that iterates `world.worldRows`/`worldCols` and adds trees for unclaimed tiles) with a visible-range version. The claimed-tile prop loop stays. Specifically:

- Remove the `final margin = forestMargin(...)` / `WorldGrid world = ...` / `Projector.fit(world.worldCols, world.worldRows, ...)` lines; build the projector from the claimed plot: `final p = Projector.fit(_cols, _rows, cam, size);`
- The forest floor full-screen dark fill stays (`canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF12301A));`).
- Claimed corners `cs` use `p.projectGrid(Offset(±_cols/2, ±_rows/2))` (unchanged).
- Build the combined standing list from the **visible tile range** for trees + claimed tiles for props:

```dart
final b = p.visibleTileBounds(size);
const treeTag = '__tree__';
final standing = <(double, int, int, String)>[]; // (depthY, col, row, id)
for (var r = b.minR; r <= b.maxR; r++) {
  for (var c = b.minC; c <= b.maxC; c++) {
    final claimed = c >= 0 && c < _cols && r >= 0 && r < _rows;
    if (claimed) {
      final prop = garden.propAt(r * _cols + c);
      if (prop != null) standing.add((p.ground(c, r).dy, c, r, prop));
    } else {
      standing.add((p.ground(c, r).dy, c, r, treeTag));
    }
  }
}
standing.sort((a, b2) => a.$1.compareTo(b2.$1));
for (final (_, c, r, id) in standing) {
  final anchor = p.ground(c, r);
  if (id == treeTag) {
    _paintBillboard(canvas, sprites.tree(), anchor, p.t, height: 1.25, width: 1.1);
  } else if (Placeables.isFence(id)) {
    _paintFencePost(canvas, p, c, r, id);
  } else {
    final sway = math.sin(time * 1.6 + c * 7 + r) * 1.4;
    _paintBillboard(canvas, sprites.flower(id), anchor, p.t, sway: sway);
  }
}
```

- `_paintFenceRails(canvas, p, margin)` no longer takes a margin — change its call to `_paintFenceRails(canvas, p)` and update the method signature + its `gridOf(c, r)` (drop the `+ margin`), since claimed tiles now use claimed coords directly with the claimed-sized projector.
- `_paintRoads` and `_paintGrid` already use claimed coords — unchanged.
- Delete the now-unused `WorldGrid` class and `forestMargin` (and their `engine_test` references for `WorldGrid` claimed/forest — remove that v11 test group; the new `visibleTileBounds` test replaces its intent). Keep `tree()` in `SpriteBank`.

Tree grounding (#1 "floating"): `_paintBillboard` already draws a contact-shadow ellipse and anchors the sprite bottom to `anchor.dy + t*kVy*0.30`. Lower the tree slightly so the trunk sits on the tile: when drawing the tree, pass the same anchor — the shadow + bottom anchor handle grounding. No extra change needed beyond using `p.ground(c,r)`.

- [ ] **Step 6: Widen the pan clamp for roaming**

In `garden_engine.dart` `GardenCamera.clamp`, replace the body so pan is bounded to a roam radius around the plot (lets you pan into the forest, keeps the garden reachable):

```dart
void clamp(int cols, int rows, Size size) {
  final p = Projector.fit(cols, rows, this, size);
  // allow roaming up to `roam` tiles of forest beyond the plot in each axis
  final roam = math.max(cols, rows).toDouble();
  final maxX = (cols / 2 + roam) * p.t;
  final maxY = (rows / 2 + roam) * p.t * kVy;
  panX = panX.clamp(-maxX, maxX);
  panY = panY.clamp(-maxY, maxY);
}
```

In `garden_view.dart`, the `_clampWorld()` helper currently computes world dims with `forestMargin`; replace it to clamp on the claimed dims:

```dart
void _clampWorld() {
  _cam.clamp(widget.garden.cols, widget.garden.rows, _lastSize);
}
```

And in `_onTapUp`, drop the margin/WorldGrid mapping — the projector is claimed-sized again, so `tileAt` returns the claimed index directly:

```dart
void _onTapUp(TapUpDetails d) {
  if (!widget.customizing || _lastSize == Size.zero) return;
  final p = Projector.fit(widget.garden.cols, widget.garden.rows, _cam, _lastSize);
  final index = p.tileAt(d.localPosition);
  if (index >= 0) widget.onTapTile(index);
}
```

(Remove the now-unused `forestMargin`/`WorldGrid` import usages in `garden_view.dart`.)

- [ ] **Step 7: Run analyze + full tests, verify pass**

Run: `& C:\src\flutter\bin\flutter.bat analyze && & C:\src\flutter\bin\flutter.bat test`
Expected: analyze clean (no references to removed `WorldGrid`/`forestMargin`); all tests pass. If analyze flags leftover `WorldGrid` usage, remove it.

- [ ] **Step 8: Commit**

```bash
git add flutter/lib/engine/garden_engine.dart flutter/lib/engine/garden_view.dart flutter/test/engine_test.dart
git commit -m "v12: forest fills the whole screen; garden is a clearing you roam (#1)"
```

---

### Task 6: Stuck-critter fix (#3)

**Files:**
- Modify: `flutter/lib/engine/garden_engine.dart` (`Critter` lifetime; `CritterSystem.step` despawn)
- Test: `flutter/test/engine_test.dart`

**Interfaces:**
- Changes: `Critter` gains `double life = 0;`; `CritterSystem.step` despawns any critter older than `Critter.maxLife` (≈18s) regardless of state, and `leave` heads to a guaranteed off-plot point.

- [ ] **Step 1: Write the failing test**

In `flutter/test/engine_test.dart`:

```dart
group('CritterSystem no stuck critters (v12)', () {
  test('a critter always despawns within its max lifetime', () {
    final sys = CritterSystem(7);
    final flowers = [const Offset(0, 0)];
    // force a spawn and then run well past max life
    for (var i = 0; i < 4000; i++) {
      sys.step(0.05, 6, flowers); // 0.05s steps → 200s total
    }
    expect(sys.critters.length, lessThanOrEqualTo(CritterSystem.maxActive));
    // none should be older than the cap
    for (final c in sys.critters) {
      expect(c.life, lessThanOrEqualTo(Critter.maxLife + 0.2));
    }
  });
});
```

- [ ] **Step 2: Run test, verify it fails**

Run: `& C:\src\flutter\bin\flutter.bat test test/engine_test.dart`
Expected: FAIL — `Critter.maxLife`/`c.life` undefined.

- [ ] **Step 3: Add lifetime to `Critter`/`CritterSystem`**

In `garden_engine.dart`, add to `class Critter`: `static const double maxLife = 18.0;` and a field `double life = 0;`.

In `CritterSystem.step`, at the start of the per-critter loop, age + despawn:

```dart
for (final c in critters) {
  c.life += d;
  _stepOne(c, d, half);
}
critters.removeWhere((c) =>
    c.life > Critter.maxLife ||
    (c.state == _CState.leave &&
        (c.pos.dx.abs() > half + 0.5 || c.pos.dy.abs() > half + 0.5)));
```

And in `_stepOne`, make `leave` always progress even if `dist` is ~0 by snapping a nonzero heading:

```dart
case _CState.leave:
  final dir = dist > 1e-3 ? to / dist : const Offset(1, 0);
  c.pos += dir * c.speed * 1.4 * dt;
  break;
```

- [ ] **Step 4: Run test, verify pass**

Run: `& C:\src\flutter\bin\flutter.bat test test/engine_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add flutter/lib/engine/garden_engine.dart flutter/test/engine_test.dart
git commit -m "v12: critters can't get stuck — max-lifetime despawn + nonzero exit heading (#3)"
```

---

### Task 7: Garden HUD theming chips (#4) + peek full-bleed (#5)

**Files:**
- Modify: `flutter/lib/engine/garden_view.dart` (wrap the peek/camera/recenter icons in themed chips)
- Modify: `flutter/lib/main.dart` (`GardenScreen`: full-bleed scene + matching system bars while peeking)
- Test: `flutter/test/widget_smoke_test.dart` (peek already covered; assert chips render)

**Interfaces:**
- Consumes: `systemOverlayFor` (Task 1); `isLightColor`.
- Changes: `GardenView` icon buttons sit on a `theme.panel` chip with `theme.onSurfaceDim` border; `GardenScreen` wraps its body in `AnnotatedRegion` that, while peeking, sets transparent/forest-colored system bars and drops the scene's `SafeArea` padding.

- [ ] **Step 1: Theme the in-scene icons in `garden_view.dart`**

Replace each of the three corner `IconButton`s with a chip wrapper. Add a small helper inside `_GardenViewState`:

```dart
Widget _chip(Color ui, Color panel, Color borderC, IconData icon, String tip, VoidCallback? onTap, Key? key) {
  return Container(
    decoration: BoxDecoration(
      color: panel.withValues(alpha: 0.85),
      border: Border.all(color: borderC, width: 2),
    ),
    child: IconButton(
      key: key,
      icon: Icon(icon, size: 20, color: ui),
      tooltip: tip,
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
    ),
  );
}
```

Then in `build`, where `ui = Color(widget.uiColor)`, also derive `final panel = Color(widget.panelColor); final borderC = Color(widget.uiColor).withValues(alpha: 0.5);` and use `_chip(...)` for recenter (`Icons.center_focus_strong`), peek (`Icons.visibility`, key `peekButton`), camera (`Icons.photo_camera`, key `cameraButton`). Add a `final int panelColor;` field to `GardenView` (passed from `GardenScreen` as `th.panel`).

- [ ] **Step 2: Pass `panelColor` from `GardenScreen`**

In `main.dart` `GardenScreen`, add `panelColor: th.panel,` to both `GardenView(...)` constructions (the live garden view; the home-backdrop view in `HomeScreen` also constructs `GardenView` — add `panelColor: th.panel` there too, though its controls are hidden).

- [ ] **Step 3: Peek full-bleed + matching bars in `GardenScreen`**

Wrap the `GardenScreen` `Scaffold` in an `AnnotatedRegion<SystemUiOverlayStyle>`: when `_peek`, use an overlay style with transparent status/nav bars (so the forest shows behind them); otherwise the themed `systemOverlayFor(th)`. While peeking, the scene already fills via `Expanded`; set the `Scaffold`'s `body` SafeArea to not pad top/bottom when `_peek` (use `SafeArea(top: !_peek, bottom: !_peek, child: ...)`). Concretely, change the `SafeArea(child: Column(...))` to `SafeArea(top: !_peek, bottom: !_peek, child: Column(...))` and wrap the returned `Scaffold` with:

```dart
return AnnotatedRegion<SystemUiOverlayStyle>(
  value: _peek
      ? const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent)
      : systemOverlayFor(th),
  child: Scaffold( ... ),
);
```

(Imports: `package:flutter/services.dart` in main.dart — already added in Task 1.)

- [ ] **Step 4: Run analyze + smoke, verify pass**

Run: `& C:\src\flutter\bin\flutter.bat analyze && & C:\src\flutter\bin\flutter.bat test test/widget_smoke_test.dart`
Expected: clean; the existing peek/camera smoke taps still pass (keys unchanged).

- [ ] **Step 5: Commit**

```bash
git add flutter/lib/engine/garden_view.dart flutter/lib/main.dart
git commit -m "v12: themed garden HUD chips (#4) + full-bleed peek with matching bars (#5)"
```

---

### Task 8: Un-dim the home garden backdrop (#7)

**Files:**
- Modify: `flutter/lib/main.dart` (`HomeScreen._liveBackdrop` + timer scrim)

**Interfaces:**
- Changes: remove `Opacity(0.45)`; add a localized scrim behind the timer column only.

- [ ] **Step 1: Remove the opacity wrapper**

In `HomeScreen._liveBackdrop`, drop the `Opacity(opacity: 0.45, child: ...)` and return the `GardenView(... interactive: false ...)` directly (full strength). Keep the `FutureBuilder`.

- [ ] **Step 2: Add a scrim behind the timer block**

In `HomeScreen.build`, the foreground `SafeArea > Column` has `_topBar` + an `Expanded` with the timer column. Wrap the **timer column's** centered content in a translucent panel so text stays legible over the live garden without washing it out. Specifically, wrap the inner `Column(mainAxisAlignment: center, children: [...])` in:

```dart
Container(
  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
  decoration: s.homeGardenBackdrop
      ? BoxDecoration(color: col(th.bg).withValues(alpha: 0.55))
      : null,
  child: Column( ... existing timer children ... ),
)
```

(Only applies the scrim when the backdrop is on.)

- [ ] **Step 3: Run analyze + tests, verify pass**

Run: `& C:\src\flutter\bin\flutter.bat analyze && & C:\src\flutter\bin\flutter.bat test`
Expected: clean + green.

- [ ] **Step 4: Commit**

```bash
git add flutter/lib/main.dart
git commit -m "v12: home garden backdrop shown full-strength; scrim only behind timer (#7)"
```

---

### Task 9: "Set as live wallpaper" rename + Android phone wallpaper (#6)

**Files:**
- Modify: `flutter/pubspec.yaml` (Android-only `wallpaper_manager_flutter`)
- Modify: `flutter/lib/camera.dart` (`setPhoneWallpaper`)
- Modify: `flutter/lib/main.dart` (`GardenScreen._capture` dialog: rename + Android-guarded action)
- Modify: `flutter/lib/strings.dart` (`setLiveWallpaper`, `wallpaperSet`, `wallpaperAsk` ×6)
- Test: smoke (button guarded; not invoked)

**Interfaces:**
- Produces (`camera.dart`): `Future<bool> setPhoneWallpaper(Uint8List bytes)` — Android only (returns false on other platforms); writes a temp PNG and sets the home-screen wallpaper.

- [ ] **Step 1: Add the dependency**

In `flutter/pubspec.yaml` dependencies, add `wallpaper_manager_flutter: ^1.0.1` (Android-only; iOS build skips it). Run:

Run: `& C:\src\flutter\bin\flutter.bat pub get`
Expected: resolves. (If this exact version fails to resolve, pick the latest `wallpaper_manager_flutter` on pub and pin it.)

- [ ] **Step 2: Add `setPhoneWallpaper` to `camera.dart`**

Add (with `import 'dart:io' show Platform, File;` already partly present — ensure `Platform` is imported, and `import 'package:wallpaper_manager_flutter/wallpaper_manager_flutter.dart';`):

```dart
/// Set the captured PNG as the phone's HOME-screen wallpaper (Android only).
/// Returns false on non-Android (the caller hides the button there).
Future<bool> setPhoneWallpaper(Uint8List bytes) async {
  if (!Platform.isAndroid) return false;
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/pixel_pomo_wallpaper.png');
  await file.writeAsBytes(bytes, flush: true);
  await WallpaperManagerFlutter().setwallpaperfromFile(file, WallpaperManagerFlutter.homeScreen);
  return true;
}
```

(If the plugin API differs at the pinned version, adapt the call — the method that sets a home-screen wallpaper from a `File`.)

- [ ] **Step 3: Rename the action + add the Android-guarded option in `GardenScreen._capture`**

Add strings ×6: `setLiveWallpaper` (en `'SET AS LIVE WALLPAPER'`, tr `'CANLI DUVAR KAĞIDI YAP'`, pl `'USTAW TAPETĘ'`, de `'ALS LIVE-HINTERGRUND'`, ko `'라이브 배경화면으로'`, it `'IMPOSTA SFONDO LIVE'`), `wallpaperSet` (en `'WALLPAPER SET'`, tr `'DUVAR KAĞIDI AYARLANDI'`, pl `'USTAWIONO TAPETĘ'`, de `'HINTERGRUND GESETZT'`, ko `'배경화면 설정됨'`, it `'SFONDO IMPOSTATO'`).

In `_capture`'s `SimpleDialog` children, **rename** the existing "set as backdrop" option text to keep the in-app backdrop action (label it with the existing `setBackdrop` key — unchanged), and **add** a new Android-only option above Save/Share:

```dart
if (Platform.isAndroid)
  SimpleDialogOption(
    onPressed: () async {
      final ok = await setPhoneWallpaper(bytes);
      if (ctx.mounted) Navigator.pop(ctx);
      if (ok) s.messenger?.call('wallpaperSet');
      _exitCamera();
    },
    child: Text(t(lang, 'setLiveWallpaper'), style: pixelStyle(lang, 11, col(th.onSurface))),
  ),
```

Add `import 'dart:io' show Platform;` to `main.dart` (it already imports `dart:io` for `File` — extend the show or use the bare import).

- [ ] **Step 4: Run analyze + tests, verify pass; build APK to validate the dep**

Run: `& C:\src\flutter\bin\flutter.bat analyze && & C:\src\flutter\bin\flutter.bat test`
Expected: clean + green (the wallpaper call isn't invoked in tests).
Run: `& C:\src\flutter\bin\flutter.bat build apk --debug`
Expected: APK builds with the new plugin. If the plugin breaks the build, swap to the latest compatible `wallpaper_manager_flutter` version or fall back to keeping only Save/Share + the rename.

- [ ] **Step 5: Commit**

```bash
git add flutter/pubspec.yaml flutter/lib/camera.dart flutter/lib/main.dart flutter/lib/strings.dart
git commit -m "v12: rename to SET AS LIVE WALLPAPER + set Android phone wallpaper (#6)"
```

---

### Task 10: Docs, version bump, edge tests, release

**Files:**
- Modify: `flutter/pubspec.yaml` (version); `log.md`, `prompt.md`, `README.md`, `flutter/README.md`, `TESTING.md`

- [ ] **Step 1: Bump version**

`flutter/pubspec.yaml`: `version: 0.12.0+13`.

- [ ] **Step 2: Full edge-test sweep**

Run: `& C:\src\flutter\bin\flutter.bat analyze && & C:\src\flutter\bin\flutter.bat test`
Confirm analyze clean + all tests pass; record the count.

- [ ] **Step 3: Build debug APK**

Run: `& C:\src\flutter\bin\flutter.bat build apk --debug`
Expected: builds with new deps/assets.

- [ ] **Step 4: Update `TESTING.md`**

Add a v12 section: new pure tests (period aggregators window/series/per-label; `Labels.rename` + migration; `isLightColor`/`systemOverlayFor`; `Projector.gridAt`/`visibleTileBounds`; critter max-life), updated counts, and known gaps (forest fill, pie separators, line callout, system bars, wallpaper set are visual / device-verified; wallpaper is Android-only).

- [ ] **Step 5: Update `log.md`**

Add a v12 entry (newest on top): the prompt (12 items + the 4 decisions) and the per-task changes.

- [ ] **Step 6: Update `prompt.md`, `README.md`, `flutter/README.md`**

Reflect: forest fills the screen / garden is a roamable clearing; themed system bars + no splash; stuck-critter fix; themed garden HUD chips + full-bleed peek; SET AS LIVE WALLPAPER (Android static now, live later); un-dimmed home backdrop; label rename; stats period selector + pie separators + tappable line + daily multi-line; new dep `wallpaper_manager_flutter` (Android-only).

- [ ] **Step 7: Commit + push (on a branch, then merge)**

```bash
git add flutter/pubspec.yaml log.md prompt.md README.md flutter/README.md TESTING.md
git commit -m "v12: docs, testing, version bump 0.12.0+13"
git push -u origin <feature-branch>
```

Then merge to `main` (which triggers CI) per finishing-a-development-branch.

- [ ] **Step 8: Verify CI**

Watch `build-flutter.yml` go green; confirm `flutter-v12` + `latest-flutter` publish the APK + unsigned IPA with title `Flutter build (iOS + Android, 0.12.0)`. Report the release URL.

- [ ] **Step 9: Write the v12 memory**

Add a v12 entry to the Pixel Pomo memory (forest-fill, theming/system-bars/splash, stuck-critter, HUD chips, live-wallpaper rename + Android static set, un-dim backdrop, label rename, stats period/pie/line rework, new dep) + update `MEMORY.md` if needed.

---

## Self-Review

**Spec coverage:**
- #1 forest fills screen → Task 5. ✓
- #2 system bars → Task 1. ✓  #12 no splash → Task 1. ✓
- #3 stuck critter → Task 6. ✓
- #4 garden HUD theme → Task 7. ✓  #5 peek bars → Task 7. ✓
- #6 live-wallpaper rename + Android set → Task 9. ✓
- #7 un-dim backdrop → Task 8. ✓
- #8 label rename → Task 4. ✓
- #9 pie separators → Task 3. ✓  #10 line tap + daily multi-line → Tasks 2+3. ✓  #11 period selector → Tasks 2+3. ✓
- Standing deliverables (docs/tests/memory/APK+IPA/version/push) → Task 10. ✓

**Placeholder scan:** No TBD/TODO. The wallpaper plugin version + API call note a concrete fallback (swap version / keep Save+Share), not a vague placeholder. The yearly-June test line has an explicit correction note in Task 2 Step 1.

**Type consistency:** `StatPeriod`, `StatSeries`, `LabelSeries` defined in Task 2 and consumed in Task 3 with matching names; `StatsChart` new ctor params (`series`, `labelLines`, `multiLine`, `panelColor`, `panelBorder`) defined in Task 3 and supplied by `StatsScreen` in the same task; `LabelLine` defined+used in Task 3; `systemOverlayFor`/`isLightColor` defined Task 1, reused Task 7; `Projector.gridAt`/`gridOfD`/`visibleTileBounds` defined Task 5 and used by the painter in the same task; `setPhoneWallpaper` defined+used Task 9; `renameLabel`/`Labels.rename` defined Task 4. `GardenView.panelColor` added Task 7 and supplied at all `GardenView` call sites in the same task.
