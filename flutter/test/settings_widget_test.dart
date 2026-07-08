import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pixel_pomo/main.dart';
import 'package:pixel_pomo/store.dart';

/// #v31.15 — "at the top there should be two options stopwatch and pomodoro
/// (when we click pomodoro, the pomodoro settings pop up, when we click
/// stopwatch, the pomodoro settings should disappear)". POMODORO is the
/// default (matches AppStore.isPomodoroMode's default of true).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppStore> boot() async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore();
    await s.load();
    return s;
  }

  // matches openPanel's own wrapping — SettingsScreen only rebuilds on
  // AppStore.notifyListeners() (e.g. setPomodoroMode) via this AnimatedBuilder,
  // it doesn't listen for external changes on its own.
  Widget host(AppStore s) => MaterialApp(
      home: Scaffold(body: AnimatedBuilder(animation: s, builder: (_, __) => SettingsScreen(s))));

  testWidgets('POMODORO selected by default shows the work/break/session steppers', (tester) async {
    final s = await boot();
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();
    expect(find.text('POMODORO'), findsOneWidget);
    expect(find.text('STOPWATCH'), findsOneWidget);
    expect(find.text('STUDY (MIN)'), findsOneWidget);
    expect(find.text('BREAK (MIN)'), findsOneWidget);
    expect(find.text('SESSIONS'), findsOneWidget);
  });

  testWidgets('tapping STOPWATCH hides the steppers; tapping POMODORO brings them back', (tester) async {
    final s = await boot();
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();

    await tester.tap(find.text('STOPWATCH'));
    await tester.pumpAndSettle();
    expect(find.text('STUDY (MIN)'), findsNothing);
    expect(find.text('BREAK (MIN)'), findsNothing);
    expect(find.text('SESSIONS'), findsNothing);
    expect(s.isPomodoroMode, false);

    await tester.tap(find.text('POMODORO'));
    await tester.pumpAndSettle();
    expect(find.text('STUDY (MIN)'), findsOneWidget);
    expect(s.isPomodoroMode, true);
  });

  testWidgets('the choice persists across a reload', (tester) async {
    final s = await boot();
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();
    await tester.tap(find.text('STOPWATCH'));
    await tester.pumpAndSettle();

    final s2 = AppStore();
    await s2.load();
    expect(s2.isPomodoroMode, false);
  });
}
