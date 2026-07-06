import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pixel_pomo/main.dart';
import 'package:pixel_pomo/store.dart';

/// #v31.5 — "session heatmap is not working well": pins down the actual
/// defect (the strip opened scrolled to the OLDEST end, not the most recent
/// one `reverse: true` alone was meant to give it), and the merge of Focus
/// Sessions into the renamed "Sessions in Pixels" screen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppStore> boot() async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore();
    await s.load(); // seeds TestData: ~all of 2025 + scattered 2026 sessions
    return s;
  }

  testWidgets('DAILY strip opens scrolled to the recent end, not the oldest', (tester) async {
    final s = await boot();
    await tester.pumpWidget(MaterialApp(home: SessionsInPixelsScreen(s)));
    await tester.pumpAndSettle();

    final horizontalScroll = find.byWidgetPredicate(
        (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal);
    expect(horizontalScroll, findsOneWidget);
    final scrollable = tester.state<ScrollableState>(
        find.descendant(of: horizontalScroll, matching: find.byType(Scrollable)));
    final pos = scrollable.position;
    // ~550 days of seeded history at ~16px/cell overflows the test viewport
    expect(pos.maxScrollExtent, greaterThan(0));
    // must rest at the RECENT end (maxScrollExtent), not offset 0 (oldest)
    expect(pos.pixels, closeTo(pos.maxScrollExtent, 0.5));
  });

  testWidgets('re-jumps to the recent end after switching unit', (tester) async {
    final s = await boot();
    await tester.pumpWidget(MaterialApp(home: SessionsInPixelsScreen(s)));
    await tester.pumpAndSettle();
    // .first: the merged screen now has TWO "YEARLY" buttons (Session
    // Heatmap's unit row and Focus Sessions' period row) — .first hits the
    // Session Heatmap one, which is what this test means to exercise.
    await tester.tap(find.text('YEARLY').first);
    await tester.pumpAndSettle();

    final horizontalScroll = find.byWidgetPredicate(
        (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal);
    final scrollable = tester.state<ScrollableState>(
        find.descendant(of: horizontalScroll, matching: find.byType(Scrollable)));
    final pos = scrollable.position;
    expect(pos.pixels, closeTo(pos.maxScrollExtent, 0.5));
    expect(tester.takeException(), isNull);
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
}
