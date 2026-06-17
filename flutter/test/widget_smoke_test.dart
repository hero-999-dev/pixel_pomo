import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pixel_pomo/main.dart';
import 'package:pixel_pomo/store.dart';

/// Boots the real app and opens every overlay, asserting no exceptions or layout overflow.
/// This is the runtime check the pure-logic tests can't give us.
void main() {
  testWidgets('app boots and every overlay opens cleanly', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load();

    await tester.pumpWidget(PixelPomoApp(store));
    await tester.pumpAndSettle();
    expect(find.text('START'), findsOneWidget);

    Future<void> openClose(IconData icon, String title) async {
      await tester.tap(find.byIcon(icon));
      await tester.pumpAndSettle();
      expect(find.text(title), findsWidgets);
      final close = find.text('CLOSE');
      await tester.ensureVisible(close); // CLOSE sits below the fold in the test viewport
      await tester.pumpAndSettle();
      await tester.tap(close);
      await tester.pumpAndSettle();
    }

    await openClose(Icons.settings, 'SAVE');

    // The garden runs a live animation ticker (the bugs), so pumpAndSettle would
    // never settle — drive it with fixed pumps long enough to finish the push/pop
    // route transitions (~300ms), then settle the home (ticker is disposed by then).
    await tester.tap(find.byIcon(Icons.local_florist));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450)); // finish push + load sprites
    expect(find.text('GARDEN'), findsWidgets);
    await tester.tap(find.text('CLOSE').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450)); // finish pop + dispose ticker
    await tester.pumpAndSettle();

    await openClose(Icons.bar_chart, 'STATS');
    await openClose(Icons.palette, 'THEME');

    // Shop opens from the gold-coin wallet button (no longer a Material icon).
    await tester.tap(find.byKey(const Key('shopButton')));
    await tester.pumpAndSettle();
    expect(find.text('SHOP'), findsWidgets);
    final shopClose = find.text('CLOSE');
    await tester.ensureVisible(shopClose);
    await tester.pumpAndSettle();
    await tester.tap(shopClose);
    await tester.pumpAndSettle();

    // Label overlay opens from the focus-label chip on the home screen.
    await tester.tap(find.text(store.currentLabel));
    await tester.pumpAndSettle();
    expect(find.text('ADD'), findsOneWidget);
  });
}
