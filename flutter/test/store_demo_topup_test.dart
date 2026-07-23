import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pixel_pomo/logic.dart';
import 'package:pixel_pomo/store.dart';

/// #v32.6 — the demo history must reach yesterday on EVERY update, not only on
/// a fresh install. `_seedOnce` is latched by a prefs flag and installing an
/// APK over the old one keeps the prefs, so the top-up in `load()` is the only
/// thing that keeps an upgraded install current — in BOTH directions: forward
/// to yesterday, and backward when a release moves the history's start date
/// (v32.6 moved it from 2025-01-01 to 2024-01-01, and an already-seeded phone
/// would otherwise never see 2024 at all).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Prefs as they look on a phone that already ran a pre-v32.6 build: seeded
  /// flag set, history starting 2025-01-01 and stopping 20 days short of today.
  Map<String, Object> oldInstall(DateTime today) => {
        'flutter.stats': StatsCodec.encode(TestData.fill(
            epochDayOf(DateTime(2025, 1, 1)),
            epochDayOf(today.subtract(const Duration(days: 20))))),
        'flutter.test_seeded_v5': true,
        'flutter.coins': 1000,
      };

  Set<int> yearsIn(List<SessionRecord> rs) =>
      {for (final r in rs) dateOfEpochDay(r.epochDay).year};

  test('an upgrade fills BOTH ends: back to 2024 and forward to yesterday', () async {
    final today = DateTime.now();
    SharedPreferences.setMockInitialValues(oldInstall(today));
    final s = AppStore();
    await s.load();

    final days = s.records.map((r) => r.epochDay).toList()..sort();
    expect(yearsIn(s.records), contains(2024),
        reason: 'the moved start date never reached an already-seeded install');
    expect(days.first, TestData.firstFillDay);
    expect(days.last, epochDayOf(today) - 1, reason: 'history must run up to yesterday');
  });

  test('loading again changes nothing — no duplicated days', () async {
    final today = DateTime.now();
    SharedPreferences.setMockInitialValues(oldInstall(today));
    final first = AppStore();
    await first.load();
    final countAfterOne = first.records.length;

    // same prefs store, loaded a second time (i.e. the next app launch)
    final second = AppStore();
    await second.load();
    expect(second.records.length, countAfterOne);
  });

  test('a fresh install already spans 2024 through yesterday', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore();
    await s.load();
    final days = s.records.map((r) => r.epochDay).toList()..sort();
    expect(yearsIn(s.records).containsAll({2024, 2025}), true);
    expect(days.first, TestData.firstFillDay);
    expect(days.last, epochDayOf(DateTime.now())); // hand-written sessions are today
  });
}
