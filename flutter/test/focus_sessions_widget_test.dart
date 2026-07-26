import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pixel_pomo/logic.dart';
import 'package:pixel_pomo/main.dart';
import 'package:pixel_pomo/pixel.dart';
import 'package:pixel_pomo/store.dart';
import 'package:pixel_pomo/strings.dart';

/// #v31 — the Focus Sessions section across its four period shapes. The user
/// reported "monthly shows no boxes"; this pins the layout down: every period
/// must render its used labels' grids without exceptions, labels UNUSED in
/// the window must be hidden, and tapping a day cell must show the callout.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppStore> boot() async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore();
    await s.load(); // seeds TestData: sessions today + scattered weeks back
    return s;
  }

  Widget host(AppStore s) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FocusSessionsSection(
                th: Themes.dark, lang: 'en', s: s, today: epochDayOf(DateTime.now())),
          ),
        ),
      );

  testWidgets('all four periods render used labels without exceptions', (tester) async {
    final s = await boot();
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();
    // seeded MATH has a session TODAY → visible in every window
    for (final period in ['WEEKLY', 'MONTHLY', '18 WEEKS']) {
      await tester.tap(find.text(period));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$period threw');
      expect(find.text('MATH'), findsOneWidget, reason: '$period lost MATH');
    }
    // yearly is now multi-select like 18 WEEKS (#v31.13, was single-select):
    // every in-window label shows by default.
    await tester.tap(find.text('YEARLY'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'YEARLY threw');
    expect(find.text('MATH'), findsOneWidget);
    // toggle MATH off via the popup (rows carry the blocker toggle) — the
    // same narrowing behaviour 18 WEEKS already has
    await tester.tap(find.byKey(const Key('labelFilterButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MATH').last); // the dialog row (block title is .first)
    await tester.pumpAndSettle();
    await tester.tap(find.text('CLOSE'));
    await tester.pumpAndSettle();
    expect(find.text('MATH'), findsNothing);
  });

  testWidgets('label filter narrows 18 WEEKS to the chosen labels (#v31.2)', (tester) async {
    final s = await boot();
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();
    // default period = 18 WEEKS → the filter button is present, all labels shown
    expect(find.byKey(const Key('labelFilterButton')), findsOneWidget);
    expect(find.text('MATH'), findsOneWidget);
    expect(find.text('HISTORY'), findsOneWidget);
    // open the picker and toggle MATH off
    await tester.tap(find.byKey(const Key('labelFilterButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MATH').last); // the dialog row (block title is .first)
    await tester.pumpAndSettle();
    await tester.tap(find.text('CLOSE'));
    await tester.pumpAndSettle();
    expect(find.text('MATH'), findsNothing);
    expect(find.text('HISTORY'), findsOneWidget);
  });

  testWidgets('labels unused in the window are hidden; unused-today label still in 18 WEEKS', (tester) async {
    final s = await boot();
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();
    // READING's seeded sessions are all >20 days back → outside WEEKLY, inside 18 WEEKS
    expect(find.text('READING'), findsOneWidget); // default = 18 WEEKS
    await tester.tap(find.text('WEEKLY'));
    await tester.pumpAndSettle();
    expect(find.text('READING'), findsNothing);
    expect(find.text('MATH'), findsOneWidget);
  });

  testWidgets('days/times caption is scoped to the shown window, not all-time (#v31.4 bug)', (tester) async {
    final s = await boot();
    // MATH's seeded history spans all of 2025 plus 2026 — its ALL-TIME
    // days/times/duration is far bigger than any single window, so this
    // string can only appear if a caption wrongly falls back to whole-history
    // totals. Uses the same template actually rendered on screen (#v31.13's
    // daysTimesTotal, with duration) so a scoping regression can't hide
    // behind a format mismatch instead of a real "not this string" check.
    final allTimeDays = s.labelHabitCounts['MATH']!;
    final allTimeMinutes = LabelHabits.minutesFromRecords(s.records)['MATH']!;
    final allTimeCaption = tf('en', 'daysTimesTotal', [
      HabitLog.daysDone(allTimeDays),
      HabitLog.totalTimes(allTimeDays),
      StatsAggregator.formatMinutes(allTimeMinutes.values.fold(0, (a, b) => a + b)),
    ]);
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();
    // default period = 18 WEEKS (a ~126-day trailing window)
    expect(find.text(allTimeCaption), findsNothing);

    await tester.tap(find.text('YEARLY'));
    await tester.pumpAndSettle();
    // MATH is visible by default (yearly is multi-select like 18 WEEKS,
    // #v31.13 — no need to open the picker to see it)
    expect(find.text('MATH'), findsOneWidget);
    expect(find.text(allTimeCaption), findsNothing); // yearly must be scoped too

    await tester.tap(find.text('WEEKLY'));
    await tester.pumpAndSettle();
    expect(find.text(allTimeCaption), findsNothing);
  });

  testWidgets('days/times/duration caption now shows on WEEKLY and MONTHLY too (#v31.13)', (tester) async {
    final s = await boot();
    final today = epochDayOf(DateTime.now());
    final monday = today - (dateOfEpochDay(today).weekday - 1);
    final now = DateTime.now();
    final monthLo = epochDayOf(DateTime.utc(now.year, now.month, 1));
    final monthHi = epochDayOf(DateTime.utc(now.year, now.month + 1, 0));
    final mathDays = s.labelHabitCounts['MATH']!;
    final mathMinutes = LabelHabits.minutesFromRecords(s.records)['MATH']!;

    // #v32.12 — four fixed lines split by field (DAYS and TIMES each own a
    // line), not one wrapping string, so a value can never be broken in half
    // by the column width.
    List<String> captionFor(int lo, int hi) {
      final winDays = {for (final kv in mathDays.entries) if (kv.key >= lo && kv.key <= hi) kv.key: kv.value};
      final (winMinutes, _, winAvg) = StatsAggregator.dayMapAverage(mathMinutes, lo, hi);
      // #v34.3 — two lines: days+times, then total+average.
      return [
        tf('en', 'capDaysTimes', [HabitLog.daysDone(winDays), HabitLog.totalTimes(winDays)]),
        '${StatsAggregator.formatMinutes(winMinutes)} · '
            '${tf('en', 'capAvg', [StatsAggregator.formatMinutes(winAvg)])}',
      ];
    }

    // A column wide enough for the whole caption puts it back on one joined
    // line (#v32.11) — which 2-up columns now are (#v34.1). Either shape is
    // correct; what must never happen is the caption going missing.
    void expectCaption(List<String> lines, String period) {
      if (find.text(lines.join(' · ')).evaluate().isNotEmpty) return;
      for (final line in lines) {
        expect(find.text(line), findsWidgets, reason: '$period lost "$line"');
      }
    }

    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();
    await tester.tap(find.text('WEEKLY'));
    await tester.pumpAndSettle();
    expectCaption(captionFor(monday, monday + 6), 'WEEKLY');

    await tester.tap(find.text('MONTHLY'));
    await tester.pumpAndSettle();
    expectCaption(captionFor(monthLo, monthHi), 'MONTHLY');
  });

  testWidgets('the full-width periods put the caption back on ONE line (#v32.11)', (tester) async {
    // 18 WEEKS and YEARLY HORIZONTAL give a label block ~358px against a
    // ~320px caption, so the three per-field lines were spending height for
    // nothing there. The narrow columns must still keep them.
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final s = await boot();
    final mathDays = s.labelHabitCounts['MATH']!;
    final mathMinutes = LabelHabits.minutesFromRecords(s.records)['MATH']!;
    final today = epochDayOf(DateTime.now());
    final now = DateTime.now();

    List<String> lines(int lo, int hi) {
      final winDays = {for (final kv in mathDays.entries) if (kv.key >= lo && kv.key <= hi) kv.key: kv.value};
      final (total, _, avg) = StatsAggregator.dayMapAverage(mathMinutes, lo, hi);
      // #v34.3 — two lines: days+times, then total+average.
      return [
        tf('en', 'capDaysTimes', [HabitLog.daysDone(winDays), HabitLog.totalTimes(winDays)]),
        '${StatsAggregator.formatMinutes(total)} · '
            '${tf('en', 'capAvg', [StatsAggregator.formatMinutes(avg)])}',
      ];
    }

    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();

    // 18 WEEKS — one joined line, and the separate pieces must NOT be there
    await tester.tap(find.text('18 WEEKS'));
    await tester.pumpAndSettle();
    final monday = today - (dateOfEpochDay(today).weekday - 1);
    final l18 = lines(monday - 17 * 7, monday + 6);
    expect(find.text(l18.join(' · ')), findsOneWidget);
    expect(find.text(l18[0]), findsNothing, reason: 'still split into per-field lines');

    // YEARLY horizontal — same
    await tester.tap(find.text('YEARLY'));
    await tester.pumpAndSettle();
    final ly = lines(epochDayOf(DateTime.utc(now.year, 1, 1)), epochDayOf(DateTime.utc(now.year, 12, 31)));
    expect(find.text(ly.join(' · ')), findsOneWidget);

    // MONTHLY is 3-up again (#v34.3) and must still be split, or values get cut in half
    await tester.tap(find.text('MONTHLY'));
    await tester.pumpAndSettle();
    final lm = lines(epochDayOf(DateTime.utc(now.year, now.month, 1)),
        epochDayOf(DateTime.utc(now.year, now.month + 1, 0)));
    expect(find.text(lm.join(' · ')), findsNothing, reason: 'joined caption cannot fit a 3-up column');
    for (final line in lm) {
      expect(find.text(line), findsWidgets);
    }
  });

  testWidgets('no caption line is ever wide enough to split a value in a narrow column', (tester) async {
    // The real failure this replaced: one 312px-wide caption string in a
    // 113px column broke wherever it ran out of room, putting "92h" on one
    // line and "45m" on the next. Each line is now its own Text, and every
    // line must fit its column outright — a value must never need to wrap
    // at all. Since #v32.12 that includes DAYS and TIMES, which are their own
    // lines now, so no line has a ` · ` left to break on.
    // The narrowest column the app produces is 2-up (#v34.1) on a 360px phone:
    // (360 - 28*2 page padding - 6 gap) / 2.
    const columnAt2Up = 149.0;
    final s = await boot();
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MONTHLY'));
    await tester.pumpAndSettle();

    final mathMinutes = LabelHabits.minutesFromRecords(s.records)['MATH']!;
    final now = DateTime.now();
    final (total, _, avg) = StatsAggregator.dayMapAverage(mathMinutes,
        epochDayOf(DateTime.utc(now.year, now.month, 1)),
        epochDayOf(DateTime.utc(now.year, now.month + 1, 0)));

    for (final line in [
      StatsAggregator.formatMinutes(total),
      tf('en', 'capAvg', [StatsAggregator.formatMinutes(avg)]),
      // a deliberately long value, to prove the rule holds beyond the fixture
      tf('en', 'capAvg', ['999h 59m']),
      // the #v32.12 lines, at counts a year of daily focus could reach
      ...tf('en', 'capDaysTimes', [365, 9999]).split(' · '),
    ]) {
      final tp = TextPainter(
        text: TextSpan(text: line, style: pixelStyle('en', 8, const Color(0xFF000000), text: line)),
        textDirection: TextDirection.ltr,
      )..layout();
      expect(tp.width, lessThan(columnAt2Up), reason: '"$line" would wrap mid-value at 2-up');
    }
  });

  testWidgets('has its own independent prev/next navigator (#v31.13)', (tester) async {
    final s = await boot();
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('focusSessionsPrev')), findsOneWidget);
    expect(find.byKey(const Key('focusSessionsNext')), findsOneWidget);
  });

  String navLabel(WidgetTester t) => t.widget<Text>(find.byKey(const Key('focusSessionsNavLabel'))).data!;

  testWidgets('prev/next actually moves the window, and next is a no-op at the current period', (tester) async {
    final s = await boot();
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();
    await tester.tap(find.text('WEEKLY'));
    await tester.pumpAndSettle();
    final thisWeek = navLabel(tester);

    await tester.tap(find.byKey(const Key('focusSessionsPrev')));
    await tester.pumpAndSettle();
    expect(navLabel(tester), isNot(thisWeek)); // genuinely a different week
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('focusSessionsNext')));
    await tester.pumpAndSettle();
    expect(navLabel(tester), thisWeek); // back to where it started

    // a genuine no-op once back at offset 0 (can't browse into the future)
    await tester.tap(find.byKey(const Key('focusSessionsNext')));
    await tester.pumpAndSettle();
    expect(navLabel(tester), thisWeek);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching periods resets the navigator back to the current one', (tester) async {
    final s = await boot();
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();
    await tester.tap(find.text('WEEKLY'));
    await tester.pumpAndSettle();
    final thisWeek = navLabel(tester);
    await tester.tap(find.byKey(const Key('focusSessionsPrev')));
    await tester.pumpAndSettle();
    expect(navLabel(tester), isNot(thisWeek)); // navigated away

    await tester.tap(find.text('MONTHLY'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('WEEKLY'));
    await tester.pumpAndSettle();
    // back on WEEKLY after a detour through MONTHLY, offset must be reset —
    // not stuck on the previously-navigated-to week
    expect(navLabel(tester), thisWeek);
  });

  testWidgets('monthly calendar cells lay out with a real size', (tester) async {
    final s = await boot();
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MONTHLY'));
    await tester.pumpAndSettle();
    // the MATH calendar exists and occupies real space (not zero-sized)
    final mathText = find.text('MATH');
    expect(mathText, findsOneWidget);
    final size = tester.getSize(find.ancestor(
        of: mathText, matching: find.byType(Column)).first);
    expect(size.height, greaterThan(30)); // label + calendar rows laid out
    expect(tester.takeException(), isNull);
  });

  // #v31.13 — YEARLY's grid-shape picker. Day cells (both styles use the
  // shared _dayCell helper) have this exact signature: right-only margin,
  // rounded corners — distinct from bordered month/frame containers. Blank
  // FILLER cells (short months' tails, #v32) share the widget shape but
  // render at a deliberately fainter alpha (0.07) than any real day cell
  // (0.18 faint / 1.0 active) — exclude them so the count stays "one cell
  // per REAL day of the year".
  int dayCellCount(WidgetTester t) => t
      .widgetList<Container>(find.byType(Container))
      .where((c) =>
          c.margin == const EdgeInsets.only(right: 2) &&
          c.decoration is BoxDecoration &&
          (c.decoration as BoxDecoration).borderRadius != null &&
          ((c.decoration as BoxDecoration).color?.a ?? 0) > 0.1)
      .length;

  testWidgets('STYLE button only appears for YEARLY', (tester) async {
    final s = await boot();
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();
    for (final period in ['WEEKLY', 'MONTHLY', '18 WEEKS']) {
      await tester.tap(find.text(period));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('yearStyleButton')), findsNothing, reason: '$period showed STYLE');
    }
    await tester.tap(find.text('YEARLY'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('yearStyleButton')), findsOneWidget);
  });

  testWidgets('HORIZONTAL (default) renders exactly one cell per day of the year, no bleed from neighbouring months', (tester) async {
    final s = await boot();
    final now = DateTime.now();
    final yearLo = epochDayOf(DateTime.utc(now.year, 1, 1));
    final yearHi = epochDayOf(DateTime.utc(now.year, 12, 31));
    final daysInYear = yearHi - yearLo + 1; // 365 or 366, leap-year aware
    final labelsThisYear =
        s.labelHabitCounts.values.where((byDay) => byDay.keys.any((d) => d >= yearLo && d <= yearHi)).length;
    expect(labelsThisYear, greaterThan(0)); // sanity: TestData seeds this year

    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();
    await tester.tap(find.text('YEARLY'));
    await tester.pumpAndSettle();
    // exactly daysInYear cells per visible label — a week-aligned grid with
    // bleed (the old _YearBand) would NOT land on this exact total.
    expect(dayCellCount(tester), daysInYear * labelsThisYear);
    expect(tester.takeException(), isNull);
  });

  testWidgets('VERTICAL (Daylio-style) switches without exceptions and shows month initials', (tester) async {
    final s = await boot();
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();
    await tester.tap(find.text('YEARLY'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('yearStyleButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('VERTICAL'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // January's initial heads its column, same as Daylio's own reference shape
    expect(find.text('J'), findsWidgets);
    // day-of-month row numbers are present (up to 31) — findsWidgets, not
    // findsOneWidget: every currently-visible label gets its own grid
    expect(find.text('31'), findsWidgets);
  });

  // #v32.6 — "labelları seçtiğimizde o zaman aralığının averajını söylesin":
  // one combined figure for whatever labels are on screen, plus the per-label
  // average already pinned by the caption test above.
  String sectionSummary(WidgetTester t) =>
      t.widget<Text>(find.byKey(const Key('focusSessionsSummary'))).data!;

  testWidgets('the combined summary merges the visible labels PER DAY before averaging', (tester) async {
    final s = await boot();
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MONTHLY'));
    await tester.pumpAndSettle();

    final now = DateTime.now();
    final lo = epochDayOf(DateTime.utc(now.year, now.month, 1));
    final hi = epochDayOf(DateTime.utc(now.year, now.month + 1, 0));
    final byLabel = LabelHabits.minutesFromRecords(s.records);
    final merged = <int, int>{};
    for (final byDay in byLabel.values) {
      for (final kv in byDay.entries) {
        if (kv.key < lo || kv.key > hi) continue;
        merged[kv.key] = (merged[kv.key] ?? 0) + kv.value;
      }
    }
    final (total, days, avg) = StatsAggregator.dayMapAverage(merged, lo, hi);
    expect(days, greaterThan(1));

    final line = sectionSummary(tester);
    expect(line, contains(StatsAggregator.formatMinutes(total)));
    expect(line, contains('AVG ${StatsAggregator.formatMinutes(avg)}/DAY'));

    // a day used by two labels must count ONCE — summing the per-label
    // averages would come out higher than the merged one
    final perLabelAvgSum = byLabel.values
        .map((byDay) => StatsAggregator.dayMapAverage(byDay, lo, hi).$3)
        .fold(0, (a, b) => a + b);
    expect(avg, lessThanOrEqualTo(perLabelAvgSum));
  });

  testWidgets('all selected says so; narrowing names the picks; the total tracks both', (tester) async {
    final s = await boot();
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();
    await tester.tap(find.text('18 WEEKS'));
    await tester.pumpAndSettle();
    // #v32.8 — with everything on, say so in a word or two rather than
    // listing every label back (which was just the picker's own contents)
    final all = tester.widget<Text>(find.byKey(const Key('focusSessionsSelected'))).data!;
    expect(all, contains('LABELS'));
    expect(all, isNot(contains('MATH')));
    final everything = sectionSummary(tester);

    // switch one label off in the picker
    await tester.tap(find.byKey(const Key('labelFilterButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MATH').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('CLOSE'));
    await tester.pumpAndSettle();

    final narrowedNames = tester.widget<Text>(find.byKey(const Key('focusSessionsSelected'))).data!;
    expect(narrowedNames, isNot(all));
    expect(narrowedNames, isNot(contains('MATH')));
    expect(sectionSummary(tester), isNot(everything), reason: 'the average ignored the filter');
    expect(tester.takeException(), isNull);
  });

  testWidgets('one label left → the whole top block goes away, it only repeated the caption', (tester) async {
    final s = await boot();
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();
    await tester.tap(find.text('18 WEEKS'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('focusSessionsSummary')), findsOneWidget);

    // turn every label off except MATH
    await tester.tap(find.byKey(const Key('labelFilterButton')));
    await tester.pumpAndSettle();
    for (final l in TestData.labels.where((l) => l != 'MATH')) {
      final row = find.text(l);
      if (row.evaluate().isEmpty) continue; // label not used in this window
      await tester.tap(row.last);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('CLOSE'));
    await tester.pumpAndSettle();

    expect(find.text('MATH'), findsOneWidget, reason: 'only MATH should be left on screen');
    expect(find.byKey(const Key('focusSessionsSummary')), findsNothing);
    expect(find.byKey(const Key('focusSessionsSelected')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // #v32.8 grid widths. The test surface is 800 wide, so a full-width block is
  // far wider than any 2-up or 3-up column — measuring the block a label's
  // heatmap sits in separates the three layouts unambiguously.
  double blockWidth(WidgetTester t, String label) =>
      t.getSize(find.ancestor(of: find.text(label), matching: find.byType(Column)).first).width;

  testWidgets('WEEKLY packs 2 per row and MONTHLY 3, at any screen width', (tester) async {
    // #v34.3 — weekly 2, monthly 3. #v34.1 briefly put monthly on 2 as well,
    // which was not asked for. Both counts are FIXED, so the same assertion
    // runs at a narrow phone and a wide tablet.
    for (final width in [360.0, 1024.0]) {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = Size(width, 900);
      addTearDown(tester.view.reset);
      final s = await boot();
      await tester.pumpWidget(host(s));
      await tester.pumpAndSettle();
      for (final (period, perRow) in [('WEEKLY', 2), ('MONTHLY', 3)]) {
        await tester.tap(find.text(period));
        await tester.pumpAndSettle();
        final w = blockWidth(tester, 'MATH');
        expect(w, lessThan(width / perRow + 20),
            reason: '$period is not $perRow-up at ${width}px');
        expect(w, greaterThan(width / (perRow + 1)),
            reason: '$period packed more than $perRow at ${width}px');
      }
      s.dispose();
    }
  });

  testWidgets('the caption is TWO lines in the narrow columns, not four (#v34.3)', (tester) async {
    // 360px so the columns are genuinely narrow and the caption cannot join
    // onto one line - which is the case that used to spend four lines of
    // height above every grid.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(360, 900);
    addTearDown(tester.view.reset);

    final s = await boot();
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();

    for (final period in ['WEEKLY', 'MONTHLY']) {
      await tester.tap(find.text(period));
      await tester.pumpAndSettle();

      // The old shape put each field on its own line, so a bare "N DAYS" was
      // its own Text. Paired up, that string only ever appears joined to TIMES.
      final bareDays = find.byWidgetPredicate((w) =>
          w is Text && w.data != null && RegExp(r'^\d+ DAYS$').hasMatch(w.data!));
      expect(bareDays, findsNothing, reason: '$period still splits DAYS onto its own line');

      // ...and every caption line must be unwrappable, or a value gets cut in
      // half at 3-up, which is what the four-line version was protecting.
      final caps = tester.widgetList<Text>(find.descendant(
          of: find.byType(FittedBox), matching: find.byType(Text)));
      expect(caps, isNotEmpty, reason: '$period caption is not scale-to-fit');
      for (final c in caps) {
        expect(c.maxLines, 1, reason: 'a caption line can wrap');
        expect(c.softWrap, isFalse);
      }
    }

    s.dispose();
  });

  testWidgets('YEARLY VERTICAL stays 2 per row', (tester) async {
    final s = await boot();
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();
    await tester.tap(find.text('YEARLY'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('yearStyleButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('VERTICAL'));
    await tester.pumpAndSettle();
    final w = blockWidth(tester, 'MATH');
    expect(w, lessThan(800 / 2 + 20));
    expect(w, greaterThan(800 / 3));
  });
}
