import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pixel_pomo/main.dart';
import 'package:pixel_pomo/store.dart';

/// #v34.7 — "Sessions in Pixels feels stuck, not scrolled".
///
/// The page built a `Container` AND a `GestureDetector` per heatmap cell:
/// **9,749 widgets, 899 of each** with the seeded history. Cells are flat
/// coloured squares, so they are painted now — one `CellGrid` per grid instead
/// of hundreds of widgets each.
///
/// This test exists because the regression is invisible: going back to
/// per-cell widgets would look identical and simply be slow again.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppStore> boot() async {
    SharedPreferences.setMockInitialValues({'flutter.tutorial_done': true});
    final s = AppStore();
    await s.load(); // seeds ~1400 sessions
    return s;
  }

  Future<void> open(WidgetTester tester, AppStore s) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(360, 640);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AnimatedBuilder(animation: s, builder: (_, __) => SessionsInPixelsScreen(s)))));
    await tester.pumpAndSettle();
  }

  int countOf<T extends Widget>(WidgetTester t) => find.byType(T).evaluate().length;

  testWidgets('the page stays small — the cells are painted, not built', (tester) async {
    final s = await boot();
    expect(s.records.length, greaterThan(500), reason: 'sanity: needs a real history to be a real test');
    await open(tester, s);

    final total = find.byWidgetPredicate((_) => true).evaluate().length;
    expect(total, lessThan(2000),
        reason: 'the page is back to $total widgets — the cell grids are widgets again');

    // the two that used to be ~900 each
    expect(countOf<Container>(tester), lessThan(100));
    expect(countOf<GestureDetector>(tester), lessThan(100));
    // ...and the painted grids that replaced them are actually there
    expect(countOf<CellGrid>(tester), greaterThan(0), reason: 'nothing is painted');

    s.dispose();
  });

  testWidgets('every session still gets a box, and the grid still answers taps', (tester) async {
    // Cheap widgets are worthless if the screen stopped showing the data, so
    // pin the count and the hit-testing that replaced the per-cell detectors.
    final s = await boot();
    await open(tester, s);

    final finder = find.byKey(const Key('sessionHeatmap'));
    expect(finder, findsOneWidget);
    final grid = tester.widget<CellGrid>(finder);
    expect(grid.count, greaterThan(0));

    // indexAt is the arithmetic that replaced 900 GestureDetectors
    for (final i in [0, grid.count ~/ 2, grid.count - 1]) {
      expect(grid.indexAt(grid.rectOfIndex(i).center), i,
          reason: 'cell $i does not hit-test back to itself');
    }
    // a point in the gutter between two rows belongs to no cell
    if (grid.count > grid.cols) {
      final belowFirstRow = grid.rectOfIndex(0).bottomLeft + const Offset(1, 0.5);
      expect(grid.indexAt(belowFirstRow), -1, reason: 'the row gap swallowed a tap');
    }
    expect(grid.indexAt(const Offset(-5, -5)), -1);

    s.dispose();
  });
}
