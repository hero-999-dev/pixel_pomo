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
    await openClose(Icons.local_florist, 'GARDEN');
    await openClose(Icons.bar_chart, 'STATS');
    await openClose(Icons.monetization_on, 'SHOP');
    await openClose(Icons.palette, 'THEME');

    // Label overlay opens from the focus-label chip on the home screen.
    await tester.tap(find.text(store.currentLabel));
    await tester.pumpAndSettle();
    expect(find.text('ADD'), findsOneWidget);
  });
}
