import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pixel_pomo/store.dart';

/// #v34 — the fresh-install defaults the user asked for, in one place:
/// auto-start OFF, home GARDEN, app blocker OFF, stats SIMPLE, detailed
/// customisation OFF, habits OFF, money tracker OFF.
///
/// The other half of the contract matters just as much: a value someone
/// already saved must survive, so nobody's existing setup flips underneath
/// them when they update.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fresh install starts on the #v34 defaults', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore();
    await s.load();

    expect(s.autoBreak, false);
    expect(s.homeBackdrop, 'garden');
    expect(s.appBlockerEnabled, false);
    expect(s.statsDetailed, false); // SIMPLE
    expect(s.detailedCustom, false);
    expect(s.showHabitTracker, false);
    expect(s.showMoneyTracker, false);
    expect(s.tutorialDone, false); // the tour runs itself once
  });

  test('a saved value always beats the default', () async {
    // every flag set to the OPPOSITE of its #v34 default
    SharedPreferences.setMockInitialValues({
      'flutter.auto_break': true,
      'flutter.home_backdrop': 'clean',
      'flutter.app_blocker': true,
      'flutter.stats_detailed': true,
      'flutter.detailed_custom': true,
      'flutter.show_habit_tracker': true,
      'flutter.show_money_tracker': true,
      'flutter.tutorial_done': true,
    });
    final s = AppStore();
    await s.load();

    expect(s.autoBreak, true);
    expect(s.homeBackdrop, 'clean');
    expect(s.appBlockerEnabled, true);
    expect(s.statsDetailed, true);
    expect(s.detailedCustom, true);
    expect(s.showHabitTracker, true);
    expect(s.showMoneyTracker, true);
    expect(s.tutorialDone, true);
  });

  test('an install that pre-dates home_backdrop keeps the mode it chose', () async {
    // #v32.4 and earlier stored the home mode as a bool. The new GARDEN
    // default must not overwrite an explicit legacy CLEAN.
    SharedPreferences.setMockInitialValues({'flutter.home_garden_backdrop': false});
    final legacyClean = AppStore();
    await legacyClean.load();
    expect(legacyClean.homeBackdrop, 'clean');

    SharedPreferences.setMockInitialValues({'flutter.home_garden_backdrop': true});
    final legacyGarden = AppStore();
    await legacyGarden.load();
    expect(legacyGarden.homeBackdrop, 'garden');
  });

  test('the tutorial flag persists both ways (SKIP, then replay from Settings)', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore();
    await s.load();
    expect(s.tutorialDone, false);

    s.setTutorialDone(true); // SKIP or DONE — same thing
    final reopened = AppStore();
    await reopened.load();
    expect(reopened.tutorialDone, true, reason: 'the tour must not come back on every launch');

    reopened.setTutorialDone(false); // Settings > SHOW TUTORIAL
    final replayed = AppStore();
    await replayed.load();
    expect(replayed.tutorialDone, false);
  });

  test('asking for WALLPAPER with no photo saved still falls back to CLEAN', () async {
    // the Settings row intercepts this tap and shows the how-to instead, but
    // the store keeps its own guard — a hand-edited pref can't strand the home
    // screen on a wallpaper that isn't there.
    SharedPreferences.setMockInitialValues({});
    final s = AppStore();
    await s.load();
    s.setHomeBackdrop('wallpaper');
    expect(s.homeBackdrop, 'clean');
  });
}
