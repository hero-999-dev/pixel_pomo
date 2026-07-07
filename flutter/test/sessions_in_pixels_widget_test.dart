import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pixel_pomo/main.dart';
import 'package:pixel_pomo/pixel.dart';
import 'package:pixel_pomo/store.dart';

/// #v31.5 — "session heatmap is not working well": originally fixed a
/// scroll-direction bug in a one-row horizontal-scrolling strip. #v31.7
/// wrapped that strip into a grid. #v31.8 — "I want it like Session Timeline
/// in a Week" — rebuilt around individual SESSIONS (not aggregated buckets):
/// DAILY = today only, WEEKLY = this calendar week (all 7 days, even empty,
/// matching Session Timeline in a Week exactly), MONTHLY/YEARLY = every
/// session done that month/year, grouped per day.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppStore> boot() async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore();
    await s.load(); // seeds TestData: ~all of 2025 + scattered 2026 sessions
    return s;
  }

  // day-group wrappers have this exact signature (border, no fill colour, no
  // radius) — distinct from both the coloured session boxes inside them and
  // Focus Sessions' cells below, so this counts "how many days are shown".
  int dayGroupCount(WidgetTester tester) => tester
      .widgetList<Container>(find.byType(Container))
      .where((c) =>
          c.decoration is BoxDecoration &&
          (c.decoration as BoxDecoration).border != null &&
          (c.decoration as BoxDecoration).color == null &&
          (c.decoration as BoxDecoration).borderRadius == null)
      .length;

  testWidgets('DAILY shows exactly one day group (today only)', (tester) async {
    final s = await boot();
    await tester.pumpWidget(MaterialApp(home: SessionsInPixelsScreen(s)));
    await tester.pumpAndSettle();
    expect(dayGroupCount(tester), 1);
  });

  testWidgets('WEEKLY shows all 7 days of the calendar week, even empty ones', (tester) async {
    final s = await boot();
    await tester.pumpWidget(MaterialApp(home: SessionsInPixelsScreen(s)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('WEEKLY').first);
    await tester.pumpAndSettle();
    expect(dayGroupCount(tester), 7);
  });

  testWidgets('YEARLY shows more distinct days than DAILY — real per-session history, not one bucket', (tester) async {
    final s = await boot();
    await tester.pumpWidget(MaterialApp(home: SessionsInPixelsScreen(s)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('YEARLY').first);
    await tester.pumpAndSettle();
    // TestData scatters sessions across many months — yearly must show far
    // more than the single "today" group DAILY shows.
    expect(dayGroupCount(tester), greaterThan(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a session box shows its label and duration', (tester) async {
    final s = await boot();
    await tester.pumpWidget(MaterialApp(home: SessionsInPixelsScreen(s)));
    await tester.pumpAndSettle();
    // MATH is seeded with a session today, so DAILY's single day group has a
    // tappable coloured box.
    final mathBox = find.byWidgetPredicate((w) =>
        w is Container &&
        w.decoration is BoxDecoration &&
        (w.decoration as BoxDecoration).color == col(s.labelColorOf('MATH')));
    expect(mathBox, findsWidgets);
    await tester.tap(mathBox.first);
    await tester.pumpAndSettle();
    expect(find.text('MATH'), findsWidgets); // the callout now shows the label
  });

  testWidgets('DAILY view wraps into a grid — no horizontal scroll strip anymore', (tester) async {
    final s = await boot();
    await tester.pumpWidget(MaterialApp(home: SessionsInPixelsScreen(s)));
    await tester.pumpAndSettle();

    // the old one-row horizontal-scrolling strip is gone (#v31.7)
    final horizontalScroll = find.byWidgetPredicate(
        (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal);
    expect(horizontalScroll, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching units re-renders the grid without exceptions', (tester) async {
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

  testWidgets('contains both the heatmap strip and Focus Sessions, titled Sessions in Pixels', (tester) async {
    final s = await boot();
    await tester.pumpWidget(MaterialApp(home: SessionsInPixelsScreen(s)));
    await tester.pumpAndSettle();
    expect(find.text('SESSIONS IN PIXELS'), findsOneWidget);
    expect(find.text('SESSION HEATMAP'), findsOneWidget);
    expect(find.text('FOCUS SESSIONS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('heatmap boxes are coloured by label, not one flat colour (#v31.6)', (tester) async {
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
}
