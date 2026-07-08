import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pixel_pomo/main.dart';
import 'package:pixel_pomo/store.dart';

/// #v31.16 — "when stop watch chosen remove the session 1/4 from main
/// page". HomeScreen owns its own AnimatedBuilder(animation: s, ...)
/// internally, so directly mutating the store (e.g. setPomodoroMode)
/// outside the widget tree still triggers a rebuild — no extra wrapper
/// needed in the test host, unlike openPanel-opened overlay screens.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppStore> boot() async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore();
    await s.load();
    return s;
  }

  Widget host(AppStore s) => MaterialApp(home: HomeScreen(s));

  testWidgets('pomodoro mode (default): shows SESSION x/y and START', (tester) async {
    final s = await boot();
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();
    expect(find.textContaining('SESSION'), findsOneWidget);
    expect(find.text('START'), findsOneWidget);
    expect(find.text('STOPWATCH'), findsNothing);
  });

  testWidgets('stopwatch mode: SESSION x/y is gone, shows STOPWATCH label and 00:00', (tester) async {
    final s = await boot();
    s.setPomodoroMode(false);
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();
    expect(find.textContaining('SESSION'), findsNothing);
    expect(find.text('STOPWATCH'), findsOneWidget);
    expect(find.text('00:00'), findsOneWidget);
    expect(find.text('START'), findsOneWidget);

    s.dispose();
  });

  testWidgets('stopwatch mode: START/PAUSE reflects the stopwatch, not the pomodoro engine', (tester) async {
    final s = await boot();
    s.setPomodoroMode(false);
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();

    await tester.tap(find.text('START'));
    await tester.pumpAndSettle();
    expect(find.text('PAUSE'), findsOneWidget);
    expect(s.stopwatch.isRunning, true);
    expect(s.engine.isRunning, false);

    s.dispose();
  });

  testWidgets('switching modes while on the home screen updates the layout live', (tester) async {
    final s = await boot();
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();
    expect(find.textContaining('SESSION'), findsOneWidget);

    s.setPomodoroMode(false);
    await tester.pumpAndSettle();
    expect(find.textContaining('SESSION'), findsNothing);
    expect(find.text('STOPWATCH'), findsOneWidget);

    s.setPomodoroMode(true);
    await tester.pumpAndSettle();
    expect(find.textContaining('SESSION'), findsOneWidget);
    expect(find.text('STOPWATCH'), findsNothing);

    s.dispose();
  });
}
