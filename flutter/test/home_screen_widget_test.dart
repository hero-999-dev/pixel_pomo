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
    // tutorial_done: the #v34 first-run tour covers the home screen with a
    // tap-blocking scrim, and none of these tests are about the tour.
    SharedPreferences.setMockInitialValues({'flutter.tutorial_done': true});
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

  testWidgets('the top bar fits a narrow phone with every icon showing (#v34.9)', (tester) async {
    // Both trackers ship ON now, which puts 7 icons plus the coin in the bar.
    // At the old fixed 30px glyph that overflowed a 360px phone by ~44px — a
    // yellow overflow stripe on a brand-new install. The glyph scales and the
    // coin block yields, so the row has to fit at any width.
    for (final width in [320.0, 360.0, 412.0]) {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = Size(width, 640);
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues({
        'flutter.tutorial_done': true,
        'flutter.home_backdrop': 'clean',
        'flutter.coins': 999999, // a wide count, the worst case for the bar
      });
      final s = AppStore();
      await s.load();
      await tester.pumpWidget(MaterialApp(home: HomeScreen(s)));
      await tester.pumpAndSettle();

      expect(s.showMoneyTracker, isTrue, reason: 'sanity: both trackers should be on');
      expect(s.showHabitTracker, isTrue);
      expect(tester.takeException(), isNull, reason: 'the top bar overflows at ${width}px');
      s.dispose();
    }
  });
}
