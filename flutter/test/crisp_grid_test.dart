import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pixel_pomo/logic.dart';
import 'package:pixel_pomo/main.dart';
import 'package:pixel_pomo/store.dart';

/// #v32.10 — "in weekly, the labels after the first three lose their
/// sharpness". Nothing was wrong with those labels: dividing a 3-up column by
/// 7 days gave a cell of 16.1905, which made each label block 78.19 tall, so
/// the SECOND row of blocks started at y = 284.19 — 852.57 physical pixels at
/// a 3x device pixel ratio. Every pixel-art box in that row was resampled
/// across a device-pixel boundary and went soft, while the first row (y = 192,
/// a clean 576) stayed sharp.
///
/// The fix is to floor every grid cell to a whole logical pixel. These tests
/// pin both halves: the cell size itself, and the row origin that follows from
/// it — the second one is what actually matters and would not have been caught
/// by checking cell sizes alone.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppStore> boot() async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore();
    await s.load();
    return s;
  }

  /// A real phone, at the 3x ratio where a .19 offset is visible.
  void phone(WidgetTester t) {
    t.view.physicalSize = const Size(390 * 3, 844 * 3);
    t.view.devicePixelRatio = 3.0;
    addTearDown(t.view.reset);
  }

  Widget host(AppStore s) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FocusSessionsSection(
                  th: Themes.dark, lang: 'en', s: s, today: epochDayOf(DateTime.now())),
            ),
          ),
        ),
      );

  /// Every rendered pixel-art day cell (they all carry the same 2px right margin).
  List<RenderBox> dayCells(WidgetTester t) => [
        for (final el in t.elementList(find.byType(Container)))
          if ((el.widget as Container).margin == const EdgeInsets.only(right: 2))
            el.renderObject as RenderBox
      ];

  testWidgets('every grid cell is a whole logical pixel, in all four period shapes', (tester) async {
    phone(tester);
    final s = await boot();
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();

    for (final period in ['WEEKLY', 'MONTHLY', '18 WEEKS', 'YEARLY']) {
      await tester.tap(find.text(period));
      await tester.pumpAndSettle();
      final cells = dayCells(tester);
      expect(cells, isNotEmpty, reason: '$period rendered no cells');
      for (final c in cells) {
        expect(c.size.width, c.size.width.floorToDouble(),
            reason: '$period cell width ${c.size.width} is fractional');
      }
    }
  });

  testWidgets('YEARLY vertical cells are whole pixels too', (tester) async {
    phone(tester);
    final s = await boot();
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();
    await tester.tap(find.text('YEARLY'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('yearStyleButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('VERTICAL'));
    await tester.pumpAndSettle();
    for (final c in dayCells(tester)) {
      expect(c.size.width, c.size.width.floorToDouble());
    }
  });

  testWidgets('WEEKLY: the second row of labels starts on a whole pixel, like the first', (tester) async {
    phone(tester);
    final s = await boot();
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();
    await tester.tap(find.text('WEEKLY'));
    await tester.pumpAndSettle();

    // group the label blocks by the row they landed in
    final tops = <double>{};
    for (final l in s.labelHabitCounts.keys) {
      final f = find.text(l);
      if (f.evaluate().isEmpty) continue;
      tops.add(tester.getRect(find.ancestor(of: f.first, matching: find.byType(Column)).first).top);
    }
    expect(tops.length, greaterThan(1), reason: 'need at least two rows to test the regression');
    for (final y in tops) {
      expect(y, y.floorToDouble(), reason: 'a label row starts at fractional y=$y and will render soft');
    }
  });

  testWidgets('SESSIONS IN PIXELS session boxes are whole pixels', (tester) async {
    phone(tester);
    final s = await boot();
    await tester.pumpWidget(MaterialApp(home: SessionsInPixelsScreen(s)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MONTHLY').first);
    await tester.pumpAndSettle();
    final boxes = [
      for (final el in tester.elementList(find.byType(Container)))
        if ((el.widget as Container).key is ValueKey<String> &&
            ((el.widget as Container).key as ValueKey<String>).value.startsWith('sessBox_'))
          el.renderObject as RenderBox
    ];
    expect(boxes, isNotEmpty);
    for (final b in boxes) {
      expect(b.size.width, b.size.width.floorToDouble());
    }
  });
}
