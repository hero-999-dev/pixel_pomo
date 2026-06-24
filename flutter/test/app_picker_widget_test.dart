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
}
