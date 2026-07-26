import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pixel_pomo/logic.dart';
import 'package:pixel_pomo/main.dart';
import 'package:pixel_pomo/store.dart';

/// #v31.5 — "session heatmap is not working well": originally fixed a
/// scroll-direction bug in a one-row horizontal-scrolling strip. #v31.7
/// wrapped that strip into a grid of buckets. #v31.8 grouped sessions by day
/// (bordered per-day rectangles, like Session Timeline in a Week). #v31.9 —
/// "tek sırada soldan sağa gitsin, Monday Tuesday diye kapatılmasın, sadece
/// kutular olsun" — dropped the day framing entirely: ONE flat, chronological
/// sequence of session boxes, wrapping left-to-right, box count exactly
/// matching session count, no padding and no per-day borders/labels.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppStore> boot() async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore();
    await s.load(); // seeds TestData: ~all of 2025 + scattered 2026 sessions
    return s;
  }

  // The session heatmap is ONE painted grid since #v34.7 (it used to be a
  // Container per session, ~900 of them, which is what stopped the page
  // scrolling). Its cell count is the number of session boxes drawn.
  int sessionBoxCount(WidgetTester tester) {
    final g = find.byKey(const Key('sessionHeatmap'));
    if (g.evaluate().isEmpty) return 0;
    return tester.widget<CellGrid>(g).count;
  }

  testWidgets('no bordered day-group wrappers remain (#v31.9)', (tester) async {
    final s = await boot();
    await tester.pumpWidget(MaterialApp(home: SessionsInPixelsScreen(s)));
    await tester.pumpAndSettle();
    final dayGroupWrapper = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) =>
            c.decoration is BoxDecoration &&
            (c.decoration as BoxDecoration).border != null &&
            (c.decoration as BoxDecoration).color == null);
    expect(dayGroupWrapper, isEmpty);
  });

  testWidgets('DAILY box count matches exactly how many sessions happened today', (tester) async {
    final s = await boot();
    await tester.pumpWidget(MaterialApp(home: SessionsInPixelsScreen(s)));
    await tester.pumpAndSettle();
    final today = epochDayOf(DateTime.now());
    final expected = s.records.where((r) => r.epochDay == today).length;
    expect(expected, greaterThan(0)); // seeded MATH session today
    expect(sessionBoxCount(tester), expected);
  });

  testWidgets('WEEKLY box count matches exactly how many sessions happened this calendar week', (tester) async {
    final s = await boot();
    await tester.pumpWidget(MaterialApp(home: SessionsInPixelsScreen(s)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('WEEKLY').first);
    await tester.pumpAndSettle();
    final today = epochDayOf(DateTime.now());
    final monday = today - (dateOfEpochDay(today).weekday - 1);
    final expected = s.records.where((r) => r.epochDay >= monday && r.epochDay <= monday + 6).length;
    expect(sessionBoxCount(tester), expected);
  });

  testWidgets('YEARLY box count matches the full year and is far more than DAILY', (tester) async {
    final s = await boot();
    await tester.pumpWidget(MaterialApp(home: SessionsInPixelsScreen(s)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('YEARLY').first);
    await tester.pumpAndSettle();
    final now = DateTime.now();
    final lo = epochDayOf(DateTime.utc(now.year, 1, 1));
    final hi = epochDayOf(DateTime.utc(now.year, 12, 31));
    final expected = s.records.where((r) => r.epochDay >= lo && r.epochDay <= hi).length;
    expect(expected, greaterThan(1)); // TestData scatters many sessions across the year
    expect(sessionBoxCount(tester), expected);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a session box shows its date, label, and duration', (tester) async {
    final s = await boot();
    await tester.pumpWidget(MaterialApp(home: SessionsInPixelsScreen(s)));
    await tester.pumpAndSettle();
    // MATH is seeded with a session today, so DAILY has a box for it. The grid
    // is painted since #v34.7, so tap its cell by coordinate — which also
    // exercises the hit-test arithmetic that replaced the per-cell detectors.
    final gridFinder = find.byKey(const Key('sessionHeatmap'));
    final grid = tester.widget<CellGrid>(gridFinder);
    final mathFill = s.labelColorOf('MATH');
    final i = [for (var i = 0; i < grid.count; i++) i].firstWhere((i) => grid.fillOf(i) == mathFill,
        orElse: () => -1);
    expect(i, isNonNegative, reason: 'no MATH session box on screen');

    await tester.tapAt(tester.getTopLeft(gridFinder) + grid.rectOfIndex(i).center);
    await tester.pumpAndSettle();
    expect(find.text('MATH'), findsWidgets); // the callout now shows the label
  });

  testWidgets('no horizontal scroll strip', (tester) async {
    final s = await boot();
    await tester.pumpWidget(MaterialApp(home: SessionsInPixelsScreen(s)));
    await tester.pumpAndSettle();
    final horizontalScroll = find.byWidgetPredicate(
        (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal);
    expect(horizontalScroll, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching units re-renders without exceptions', (tester) async {
    final s = await boot();
    await tester.pumpWidget(MaterialApp(home: SessionsInPixelsScreen(s)));
    await tester.pumpAndSettle();
    // .first: WEEKLY/MONTHLY/YEARLY also appear in Focus Sessions' own period
    // row on this merged screen — .first hits Session Heatmap's unit row.
    for (final period in ['WEEKLY', 'MONTHLY', 'YEARLY', 'DAILY']) {
      await tester.tap(find.text(period).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$period threw');
    }
  });

  testWidgets('contains both the heatmap and Focus Sessions, titled Sessions in Pixels', (tester) async {
    final s = await boot();
    await tester.pumpWidget(MaterialApp(home: SessionsInPixelsScreen(s)));
    await tester.pumpAndSettle();
    expect(find.text('SESSIONS IN PIXELS'), findsOneWidget);
    expect(find.text('SESSION HEATMAP'), findsOneWidget);
    expect(find.text('FOCUS SESSIONS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('WEEKLY prev button browses to last week — box count matches last week exactly (#v31.10)', (tester) async {
    final s = await boot();
    await tester.pumpWidget(MaterialApp(home: SessionsInPixelsScreen(s)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('WEEKLY').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('heatmapPrev')));
    await tester.pumpAndSettle();

    final now = DateTime.now();
    final anchor = StatsAggregator.anchorFor(now, StatPeriod.weekly, 1);
    final (lo, hi) = StatsAggregator.windowDays(anchor, StatPeriod.weekly);
    final expected = s.records.where((r) => r.epochDay >= lo && r.epochDay <= hi).length;
    expect(sessionBoxCount(tester), expected);
  });

  testWidgets('next button is a no-op at the current period (cannot browse into the future)', (tester) async {
    final s = await boot();
    await tester.pumpWidget(MaterialApp(home: SessionsInPixelsScreen(s)));
    await tester.pumpAndSettle();
    final beforeCount = sessionBoxCount(tester);
    await tester.tap(find.byKey(const Key('heatmapNext')));
    await tester.pumpAndSettle();
    expect(sessionBoxCount(tester), beforeCount);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching units resets the navigator back to the current period', (tester) async {
    final s = await boot();
    await tester.pumpWidget(MaterialApp(home: SessionsInPixelsScreen(s)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('WEEKLY').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('heatmapPrev')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MONTHLY').first);
    await tester.pumpAndSettle();

    final now = DateTime.now();
    final (lo, hi) = StatsAggregator.windowDays(now, StatPeriod.monthly);
    final expected = s.records.where((r) => r.epochDay >= lo && r.epochDay <= hi).length;
    expect(sessionBoxCount(tester), expected);
  });

  testWidgets('heatmap boxes are coloured by label, not one flat colour', (tester) async {
    final s = await boot();
    await tester.pumpWidget(MaterialApp(home: SessionsInPixelsScreen(s)));
    await tester.pumpAndSettle();

    // seeded TestData spreads MATH/HISTORY/READING/SCIENCE/CODING/TURKISH
    // across many different days, so a truly single-coloured strip is
    // impossible unless every active box was forced to one flat colour.
    final activeColors = <Color>{};
    for (final el in tester.elementList(find.byType(Container))) {
      final c = el.widget as Container;
      final deco = c.decoration;
      if (deco is BoxDecoration && deco.color != null && deco.color!.a == 1.0) {
        activeColors.add(deco.color!);
      }
    }
    expect(activeColors.length, greaterThan(1),
        reason: 'every active box rendered the same colour — the flat-accent bug is back');
  });

  // #v32.6 — "session in pixels'de average olsun". Session count, total, and
  // the mean over the days that actually had focus, above the strip.
  String summary(WidgetTester t) =>
      t.widget<Text>(find.byKey(const Key('sessionsWindowSummary'))).data!;

  testWidgets('the window summary states sessions, total and the per-active-day average', (tester) async {
    final s = await boot();
    await tester.pumpWidget(MaterialApp(home: SessionsInPixelsScreen(s)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MONTHLY').first);
    await tester.pumpAndSettle();

    final (lo, hi) = StatsAggregator.windowDays(DateTime.now(), StatPeriod.monthly);
    final inWindow = s.records.where((r) => r.epochDay >= lo && r.epochDay <= hi).toList();
    final (total, days, avg) = StatsAggregator.windowAverage(inWindow, lo, hi);
    expect(days, greaterThan(1)); // sanity: the seeded month spans several days

    final line = summary(tester);
    expect(line, contains('${inWindow.length} SESSIONS'));
    expect(line, contains(StatsAggregator.formatMinutes(total)));
    expect(line, contains('AVG ${StatsAggregator.formatMinutes(avg)}/DAY'));
    // the mean must be a per-DAY figure, not the whole window restated
    expect(avg, lessThan(total));
  });

  testWidgets('DAILY averages over the single day, so the average equals the total', (tester) async {
    final s = await boot();
    await tester.pumpWidget(MaterialApp(home: SessionsInPixelsScreen(s)));
    await tester.pumpAndSettle(); // DAILY is the default unit

    final today = epochDayOf(DateTime.now());
    final todayMinutes =
        s.records.where((r) => r.epochDay == today).fold(0, (a, r) => a + r.minutes);
    final line = summary(tester);
    expect(line, contains(StatsAggregator.formatMinutes(todayMinutes)));
    expect(line, contains('AVG ${StatsAggregator.formatMinutes(todayMinutes)}/DAY'));
  });

  testWidgets('an empty window shows no summary at all, just the empty notice', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore();
    await s.load();
    // browse far enough back that the seeded history cannot reach: TestData
    // starts at 1 Jan 2024, so ~30 years of DAILY steps lands well before it
    await tester.pumpWidget(MaterialApp(home: SessionsInPixelsScreen(s)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('YEARLY').first);
    await tester.pumpAndSettle();
    for (var i = 0; i < 30; i++) {
      await tester.tap(find.byKey(const Key('heatmapPrev')));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sessionsWindowSummary')), findsNothing);
    expect(sessionBoxCount(tester), 0);
    expect(tester.takeException(), isNull);
  });
}
