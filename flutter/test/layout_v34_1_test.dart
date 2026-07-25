import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pixel_pomo/main.dart';
import 'package:pixel_pomo/pixel.dart';
import 'package:pixel_pomo/store.dart';

/// #v34.1 — two alignment reports: the shop's BUY/SELL pair stopped wherever
/// its own price text ended instead of lining up with the screen's right edge,
/// and the CHANGE LABEL dialog's swatch was still rounded while the Log
/// History rows it opens from went square back in #v31.16.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppStore> boot() async {
    SharedPreferences.setMockInitialValues({'flutter.tutorial_done': true});
    final s = AppStore();
    await s.load();
    return s;
  }

  Widget host(AppStore s, Widget Function() build) =>
      MaterialApp(home: Scaffold(body: AnimatedBuilder(animation: s, builder: (_, __) => build())));

  testWidgets('every shop row ends its BUY/SELL pair on the same right edge', (tester) async {
    final s = await boot();
    await tester.pumpWidget(host(s, () => ShopScreen(s)));
    await tester.pumpAndSettle();

    // SELL is the right-hand button of each pair; the prices differ per item
    // (flowers sell for 5, decor for 2), which is exactly what used to make
    // the rows stop at different places.
    final sells = find.byWidgetPredicate(
        (w) => w is PixelButton && w.text.startsWith('SELL'));
    expect(sells.evaluate().length, greaterThan(2), reason: 'need several rows to compare');

    final rights = sells.evaluate().map((e) => tester.getRect(find.byWidget(e.widget as PixelButton)).right).toList();
    for (final r in rights) {
      expect((r - rights.first).abs(), lessThan(1.0),
          reason: 'BUY/SELL pairs do not share a right edge: $rights');
    }

    // ...and that shared edge really is the screen's, not somewhere mid-row.
    final screenWidth = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(rights.first, greaterThan(screenWidth - 40),
        reason: 'the pair is not anchored to the right of the screen');

    s.dispose();
  });

  testWidgets('the CHANGE LABEL dialog swatch is square, like the rows it opens from', (tester) async {
    final s = await boot();
    await tester.pumpWidget(host(s, () => LogHistoryScreen(s)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('MATH').first);
    await tester.pumpAndSettle();
    expect(find.text('CHANGE LABEL'), findsOneWidget);

    final swatches = tester.widgetList<Swatch>(find.byType(Swatch));
    expect(swatches, isNotEmpty, reason: 'the dialog lists one swatch per label');
    for (final sw in swatches) {
      expect(sw.plain, isTrue, reason: 'a rounded swatch is left in the dialog');
    }

    s.dispose();
  });
}
