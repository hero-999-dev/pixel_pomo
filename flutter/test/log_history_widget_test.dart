import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pixel_pomo/main.dart';
import 'package:pixel_pomo/store.dart';

/// #v31.16 — "when we click to log there should be remove this log option
/// appear ... are you sure about removing this log? ... there should be
/// [a] recycle bin and that log should move there". Tap a row -> the
/// existing CHANGE LABEL dialog now also offers REMOVE THIS LOG -> confirm
/// -> soft-deleted into the Recycle Bin, reachable from a button on Log
/// History, with per-item permanent delete and a bulk CLEAN RECYCLE BIN.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppStore> boot() async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore();
    await s.load();
    return s;
  }

  // matches openPanel's own wrapping (see #v31.15's gotcha) — these screens
  // only rebuild on AppStore.notifyListeners() via this AnimatedBuilder.
  Widget host(AppStore s, Widget Function() build) =>
      MaterialApp(home: Scaffold(body: AnimatedBuilder(animation: s, builder: (_, __) => build())));

  testWidgets('tapping a log row offers REMOVE THIS LOG alongside the label list', (tester) async {
    final s = await boot();
    await tester.pumpWidget(host(s, () => LogHistoryScreen(s)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MATH').first);
    await tester.pumpAndSettle();
    expect(find.text('REMOVE THIS LOG'), findsOneWidget);
  });

  testWidgets('remove -> confirm -> the log leaves Log History and lands in the Recycle Bin', (tester) async {
    final s = await boot();
    final recordsBefore = s.records.length;
    await tester.pumpWidget(host(s, () => LogHistoryScreen(s)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('MATH').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('REMOVE THIS LOG'));
    await tester.pumpAndSettle();
    expect(find.text('Remove this log?'), findsOneWidget); // the confirm prompt
    await tester.tap(find.text('YES'));
    await tester.pumpAndSettle();

    expect(s.records.length, recordsBefore - 1);
    expect(s.deletedRecords.length, 1);
    expect(s.deletedRecords.first.label, 'MATH');
  });

  testWidgets('tapping NO on the confirm leaves the log untouched', (tester) async {
    final s = await boot();
    final recordsBefore = s.records.length;
    await tester.pumpWidget(host(s, () => LogHistoryScreen(s)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('MATH').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('REMOVE THIS LOG'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('NO'));
    await tester.pumpAndSettle();

    expect(s.records.length, recordsBefore);
    expect(s.deletedRecords, isEmpty);
  });

  testWidgets('Recycle Bin: empty by default, reachable from Log History', (tester) async {
    final s = await boot();
    await tester.pumpWidget(host(s, () => LogHistoryScreen(s)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recycleBinButton')), findsOneWidget);

    await tester.pumpWidget(host(s, () => RecycleBinScreen(s)));
    await tester.pumpAndSettle();
    expect(find.text('Recycle Bin is empty'), findsOneWidget);
    expect(find.byKey(const Key('cleanRecycleBinButton')), findsNothing); // nothing to clean
  });

  testWidgets('Recycle Bin: a soft-deleted log can be permanently purged', (tester) async {
    final s = await boot();
    s.removeRecord(s.records.indexWhere((r) => r.label == 'MATH'));
    expect(s.deletedRecords.length, 1);

    await tester.pumpWidget(host(s, () => RecycleBinScreen(s)));
    await tester.pumpAndSettle();
    expect(find.text('MATH'), findsOneWidget);

    await tester.tap(find.text('MATH'));
    await tester.pumpAndSettle();
    expect(find.text('Delete forever?'), findsOneWidget);
    await tester.tap(find.text('YES'));
    await tester.pumpAndSettle();

    expect(s.deletedRecords, isEmpty);
    expect(find.text('Recycle Bin is empty'), findsOneWidget);
  });

  testWidgets('CLEAN RECYCLE BIN empties everything at once, after confirming', (tester) async {
    final s = await boot();
    s.removeRecord(0);
    s.removeRecord(0);
    s.removeRecord(0);
    expect(s.deletedRecords.length, 3);

    await tester.pumpWidget(host(s, () => RecycleBinScreen(s)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cleanRecycleBinButton')), findsOneWidget);
    await tester.tap(find.byKey(const Key('cleanRecycleBinButton')));
    await tester.pumpAndSettle();
    expect(find.text('Empty the Recycle Bin?'), findsOneWidget);
    await tester.tap(find.text('YES'));
    await tester.pumpAndSettle();

    expect(s.deletedRecords, isEmpty);
    expect(find.text('Recycle Bin is empty'), findsOneWidget);
  });
}
