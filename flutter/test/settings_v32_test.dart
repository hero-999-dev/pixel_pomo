import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pixel_pomo/logic.dart';
import 'package:pixel_pomo/store.dart';

/// #v32 settings: hideable Money/Habit trackers + SIMPLE|DETAILED stats mode,
/// all persisted; and every theme carries its own distinct accent hue.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('tracker visibility + stats mode default OFF/SIMPLE (#v34) and persist across restart', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore();
    await s.load();
    expect(s.showMoneyTracker, false);
    expect(s.showHabitTracker, false);
    expect(s.statsDetailed, false);

    s.setShowMoneyTracker(true);
    s.setShowHabitTracker(true);
    s.setStatsDetailed(true);

    final s2 = AppStore();
    await s2.load();
    expect(s2.showMoneyTracker, true);
    expect(s2.showHabitTracker, true);
    expect(s2.statsDetailed, true);
  });

  test('MATCHA is the default theme and heads the list (#v34.4)', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore();
    await s.load();
    expect(s.theme.id, 'matcha', reason: 'a fresh install should open on MATCHA');
    expect(Themes.fallback.id, 'matcha');
    // the Theme screen lists them in this order, so first here IS first on screen
    expect(Themes.all.first.id, 'matcha');
    expect(Themes.all.length, 6, reason: 'reordering must not drop or add a theme');
    expect(Themes.all.map((t) => t.id).toSet().length, 6);
  });

  test('every theme has its own accent — no two share a colour (#v32)', () {
    // four of six accents used to sit in the same red family; the user read
    // light/latte/frappe as re-tinted copies of dark. Exact-duplicate check
    // is the regression net for reintroducing a shared accent.
    final accents = Themes.all.map((t) => t.accent).toList();
    expect(accents.toSet().length, Themes.all.length,
        reason: 'duplicate accent colours between themes');
  });
}
