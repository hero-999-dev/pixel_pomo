import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pixel_pomo/logic.dart';
import 'package:pixel_pomo/main.dart';
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
    // yearly shows ONE label (#v31.3): the picker button carries its name,
    // so the first label appears twice (button + block title)
    await tester.tap(find.text('YEARLY'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'YEARLY threw');
    expect(find.text('MATH'), findsWidgets);
    // switch the chosen label via the popup (rows carry the blocker toggle)
    await tester.tap(find.byKey(const Key('labelFilterButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('HISTORY').last);
    await tester.pumpAndSettle();
    expect(find.text('HISTORY'), findsWidgets); // button + block title
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
    // days/times is far bigger than any single window, so this string can
    // only appear if a caption wrongly falls back to whole-history totals.
    final allTime = s.labelHabitCounts['MATH']!;
    final allTimeCaption =
        tf('en', 'daysTimes', [HabitLog.daysDone(allTime), HabitLog.totalTimes(allTime)]);
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();
    // default period = 18 WEEKS (a ~126-day trailing window)
    expect(find.text(allTimeCaption), findsNothing);

    await tester.tap(find.text('YEARLY'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('labelFilterButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MATH').last);
    await tester.pumpAndSettle();
    expect(find.text(allTimeCaption), findsNothing); // yearly must be scoped too

    await tester.tap(find.text('WEEKLY'));
    await tester.pumpAndSettle();
    expect(find.text(allTimeCaption), findsNothing);
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
}
