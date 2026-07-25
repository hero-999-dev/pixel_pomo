import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pixel_pomo/store.dart';

/// #v25 item2 — the focus label must survive a full app restart (it was
/// reportedly reverting to STUDY). Each fresh AppStore().load() simulates a
/// cold start reading back the persisted prefs.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a selected seed label survives an app restart', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore();
    await s.load();
    s.selectLabel('CODING');
    expect(s.currentLabel, 'CODING');

    final s2 = AppStore();
    await s2.load();
    expect(s2.currentLabel, 'CODING'); // must NOT fall back to STUDY
  });

  test('a custom added+selected label survives an app restart', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore();
    await s.load();
    s.addLabel('GYM');
    s.selectLabel('GYM');

    final s2 = AppStore();
    await s2.load();
    expect(s2.labels.contains('GYM'), true);
    expect(s2.currentLabel, 'GYM');
  });

  test('selecting then completing a session still restores the label', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore();
    await s.load();
    s.selectLabel('MATH');
    // a quick work session records under MATH (writes stats prefs)
    s.start();
    s.reset();

    final s2 = AppStore();
    await s2.load();
    expect(s2.currentLabel, 'MATH');
  });

  test('relabelRecord reassigns one session and persists (#v25 item3)', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore();
    await s.load();
    final n = s.records.length;
    expect(n, greaterThan(0)); // seeded fixture
    final orig = s.records[0].label;
    s.relabelRecord(0, 'READING');
    expect(s.records[0].label, 'READING');
    expect(s.records.length, n); // nothing added/removed
    expect(s.records[0].label == orig, isFalse);

    final s2 = AppStore();
    await s2.load();
    expect(s2.records[0].label, 'READING'); // survives a restart
  });


  // #v33.9 — the web launcher passes the picked language as ?lang=xx; the app
  // honours it only when we ship that language, else keeps the stored choice.
  test('web ?lang override takes a shipped language and refuses the rest', () {
    expect(AppStore.webLangOverride('en', 'tr'), 'tr'); // shipped -> wins
    expect(AppStore.webLangOverride('en', 'de'), 'de');
    expect(AppStore.webLangOverride('tr', null), 'tr'); // no query -> stored
    expect(AppStore.webLangOverride('tr', 'xx'), 'tr'); // unknown -> stored
    expect(AppStore.webLangOverride('tr', 'ko'), 'tr'); // dropped lang -> stored
    expect(AppStore.webLangOverride('en', ''), 'en'); // empty -> stored
  });
}
