import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pixel_pomo/main.dart';
import 'package:pixel_pomo/store.dart';

/// #v31.5 — "session heatmap is not working well": originally fixed a
/// scroll-direction bug in a one-row horizontal-scrolling strip. #v31.7
/// replaced that strip entirely with a wrapping grid (like Focus Sessions'
/// monthly view) showing the FULL history at once via the screen's normal
/// vertical scroll — so the horizontal-scroll tests below were replaced with
/// grid-shape ones.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppStore> boot() async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore();
    await s.load(); // seeds TestData: ~all of 2025 + scattered 2026 sessions
    return s;
  }

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
