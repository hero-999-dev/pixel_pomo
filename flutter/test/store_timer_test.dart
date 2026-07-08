import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pixel_pomo/logic.dart';
import 'package:pixel_pomo/store.dart';

/// #v31.15 — "I changed some settings while a pomodoro was running and it
/// reset my current session, but the notification just kept counting like
/// nothing happened." saveSettings() used to unconditionally cancel the
/// timer and rebuild the engine from scratch, wiping live progress; the
/// native notification (an independent, deadline-based system chronometer)
/// was never touched, so the two visibly disagreed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('saveSettings mid-pomodoro leaves the active run untouched; new settings apply on the next one', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore();
    await s.load();

    s.start(); // begins the default 25-min work phase
    expect(s.engine.isRunning, true);
    s.engine.setTimeLeft(10 * 60 * 1000); // simulate ~15 minutes having ticked by

    s.saveSettings(50, 10, 6); // change work/break/session mid-run

    // the ACTIVE run is completely untouched: still running, same time left,
    // same (old) 25-minute duration for THIS phase — the actual bug
    expect(s.engine.isRunning, true, reason: 'a settings save must not stop the running timer');
    expect(s.engine.timeLeftMillis, 10 * 60 * 1000, reason: 'live progress must not be wiped');
    expect(s.engine.workMillis, 25 * 60 * 1000, reason: 'the CURRENT phase keeps its original duration');
    // but the settings themselves did update, ready for the next run
    expect(s.workMin, 50);
    expect(s.breakMin, 10);
    expect(s.sessions, 6);

    // an explicit cancel/reset is a fresh start — it must pick up the NEW
    // settings, not silently keep using the stale pre-change ones forever
    s.reset();
    expect(s.engine.workMillis, 50 * 60 * 1000);
    expect(s.engine.breakMillis, 10 * 60 * 1000);
    expect(s.engine.totalSessions, 6);

    s.dispose();
  });

  test('saveSettings applies immediately when no run is in progress', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore();
    await s.load();

    expect(s.engine.isRunning, false); // fresh, never started
    s.saveSettings(45, 15, 3);
    expect(s.engine.workMillis, 45 * 60 * 1000, reason: 'safe to rebuild immediately — nothing in progress to disrupt');
    expect(s.engine.breakMillis, 15 * 60 * 1000);
    expect(s.engine.totalSessions, 3);

    s.dispose();
  });

  test('finishing a run naturally (not via reset) also picks up settings changed mid-run', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore();
    await s.load();
    s.saveSettings(1, 1, 1); // 1-minute work/break, single session — fast to finish

    s.start();
    s.engine.setTimeLeft(0);
    final finished = s.engine.finishPhase(); // work -> break
    expect(finished, Mode.work);
    s.engine.setTimeLeft(0);
    s.engine.finishPhase(); // last break -> finished
    expect(s.engine.isFinished, true);

    s.saveSettings(20, 4, 2); // change settings once the run is fully done

    s.start(); // isFinished == true → must rebuild from the NEW settings
    expect(s.engine.workMillis, 20 * 60 * 1000);
    expect(s.engine.breakMillis, 4 * 60 * 1000);
    expect(s.engine.totalSessions, 2);

    s.dispose();
  });
}
