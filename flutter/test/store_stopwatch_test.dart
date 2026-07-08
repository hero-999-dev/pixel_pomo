import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pixel_pomo/logic.dart';
import 'package:pixel_pomo/store.dart';

/// #v31.16 — "create that stopwatch (also user should not earn money from
/// stopwatch), ... stop watch should be counted in stats". A count-up timer
/// mode, selected via Settings' STOPWATCH/POMODORO toggle: logs to stats
/// like a pomodoro session but never pays coins, and pomodoro mode itself
/// must stay completely unaffected when the two coexist.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('stopwatch: start/pause/reset drive AppStore.stopwatch, not the pomodoro engine', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore();
    await s.load();
    s.setPomodoroMode(false);

    s.start();
    expect(s.stopwatch.isRunning, true);
    expect(s.engine.isRunning, false, reason: 'stopwatch mode must not touch the pomodoro engine');

    s.pause();
    expect(s.stopwatch.isRunning, false);

    s.dispose();
  });

  test('resetting a stopwatch run logs a session but awards ZERO coins', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore();
    await s.load();
    s.setPomodoroMode(false);
    final recordsBefore = s.records.length;
    final coinsBefore = s.coins;

    s.start();
    s.stopwatch.setElapsed(17 * 60 * 1000); // simulate 17 minutes elapsed
    s.reset();

    expect(s.records.length, recordsBefore + 1, reason: 'stopwatch time must still count toward stats');
    expect(s.records.last.minutes, 17);
    expect(s.records.last.label, s.currentLabel);
    expect(s.coins, coinsBefore, reason: 'stopwatch sessions must never earn coins');
    expect(s.stopwatch.elapsedMillis, 0); // reset back to 00:00

    s.dispose();
  });

  test('resetting a stopwatch with zero elapsed time does not log an empty session', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore();
    await s.load();
    s.setPomodoroMode(false);
    final recordsBefore = s.records.length;

    s.start();
    s.reset(); // never actually ran any time
    expect(s.records.length, recordsBefore);

    s.dispose();
  });

  test('a stopwatch session counts toward stats aggregation like any other', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore();
    await s.load();
    s.setPomodoroMode(false);
    final before = LabelHabits.minutesFromRecords(s.records)[s.currentLabel]
            ?.values
            .fold(0, (a, b) => a + b) ??
        0;

    s.start();
    s.stopwatch.setElapsed(9 * 60 * 1000);
    s.reset();

    final after = LabelHabits.minutesFromRecords(s.records)[s.currentLabel]!.values.fold(0, (a, b) => a + b);
    expect(after, before + 9);

    s.dispose();
  });

  test('pomodoro mode is unaffected: still uses the engine, and cancelling mid-run still pays partial coins', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore();
    await s.load();
    expect(s.isPomodoroMode, true); // default
    final recordsBefore = s.records.length;
    final coinsBefore = s.coins;

    s.start();
    expect(s.engine.isRunning, true);
    expect(s.stopwatch.isRunning, false, reason: 'pomodoro mode must not touch the stopwatch');
    s.engine.setTimeLeft(s.engine.workMillis - 10 * 60 * 1000); // 10 min elapsed
    s.reset(); // cancel mid-run — partial credit, unlike stopwatch's own reset

    expect(s.records.length, recordsBefore + 1);
    expect(s.records.last.minutes, 10);
    expect(s.coins, coinsBefore + Economy.coinsFor(10), reason: 'pomodoro cancel-mid-run must still pay coins');

    s.dispose();
  });

  test('blockerActive reflects stopwatch.isRunning in stopwatch mode', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore();
    await s.load();
    s.setAppBlocker(true);
    s.setPomodoroMode(false);
    expect(s.blockerActive, false); // not running yet

    s.start();
    expect(s.blockerActive, true);

    s.pause();
    expect(s.blockerActive, false);

    s.dispose();
  });
}
