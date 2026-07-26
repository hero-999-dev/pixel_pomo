import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pixel_pomo/main.dart';
import 'package:pixel_pomo/store.dart';

/// Regression for the app-locker lag (#v23 fb): openPanel rebuilds the picker on
/// every store change (each block toggle), and the old `future: installedApps()`
/// in build() re-queried the native side — enumerating apps + PNG-encoding every
/// icon — on each rebuild. The cached future must make that happen exactly ONCE.
void main() {
  testWidgets('app picker queries installedApps once, not per rebuild', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load();

    var queries = 0;
    const ch = MethodChannel('pixel_pomo/blocker');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(ch, (c) async {
      if (c.method == 'installedApps') {
        queries++;
        return [
          {'package': 'com.alpha', 'label': 'Alpha'},
          {'package': 'com.beta', 'label': 'Beta'},
        ];
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(ch, null));

    // Wrap exactly like openPanel does, so a notifyListeners() rebuilds the screen.
    await tester.pumpWidget(MaterialApp(
      home: AnimatedBuilder(animation: store, builder: (_, __) => AppPickerScreen(store)),
    ));
    await tester.pumpAndSettle();
    expect(queries, 1);
    expect(find.text('Alpha'), findsOneWidget);

    // A block toggle rebuilds the picker; the cached future must NOT re-query.
    store.setBlocked('com.alpha', true);
    await tester.pumpAndSettle();
    expect(store.blockedApps.contains('com.alpha'), true);
    expect(queries, 1, reason: 'cached future — rebuild must not re-query installedApps');
  });

  testWidgets('blocked apps float to the top (#v23 fb)', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load();

    const ch = MethodChannel('pixel_pomo/blocker');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(ch, (c) async {
      if (c.method == 'installedApps') {
        return [
          {'package': 'com.alpha', 'label': 'Alpha'},
          {'package': 'com.zeta', 'label': 'Zeta'},
        ];
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(ch, null));

    await tester.pumpWidget(MaterialApp(
      home: AnimatedBuilder(animation: store, builder: (_, __) => AppPickerScreen(store)),
    ));
    await tester.pumpAndSettle();
    // alpha-sorted, none picked → Alpha above Zeta
    expect(tester.getTopLeft(find.text('Alpha')).dy, lessThan(tester.getTopLeft(find.text('Zeta')).dy));

    // block Zeta → it jumps above Alpha
    store.setBlocked('com.zeta', true);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Zeta')).dy, lessThan(tester.getTopLeft(find.text('Alpha')).dy));
  });

  testWidgets('only the visible rows are built — a few hundred apps stay scrollable (#v34.6)',
      (tester) async {
    // The whole list used to be one Column inside a SingleChildScrollView, so
    // all ~300 rows (each with a decoded icon) were built and laid out at
    // once. RepaintBoundary fixed the painting half only; this is the build
    // and layout half, and it is what made the page feel stuck rather than
    // scrolled.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(360, 640);
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.load();

    const ch = MethodChannel('pixel_pomo/blocker');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(ch, (c) async {
      if (c.method == 'installedApps') {
        return [
          for (var i = 0; i < 300; i++)
            {'package': 'com.app$i', 'label': 'App ${i.toString().padLeft(3, '0')}'},
        ];
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(ch, null));

    await tester.pumpWidget(MaterialApp(
        home: AnimatedBuilder(animation: store, builder: (_, __) => AppPickerScreen(store))));
    await tester.pumpAndSettle();

    // rows are identified by their label text; the private toggle widget
    // cannot be named from a test
    final built = tester
        .widgetList<Text>(find.byType(Text))
        .where((w) => (w.data ?? '').startsWith('App '))
        .length;
    expect(built, greaterThan(0), reason: 'sanity: some rows should render');
    expect(built, lessThan(60),
        reason: 'all 300 rows were built at once ($built) - the list is not lazy');

    // and it still scrolls to reach the far end of the list
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -4000));
    await tester.pumpAndSettle();
    expect(find.text('App 000'), findsNothing, reason: 'the list did not move');

    store.dispose();
  });
}
