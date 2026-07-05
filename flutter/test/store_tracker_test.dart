import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pixel_pomo/logic.dart';
import 'package:pixel_pomo/store.dart';

/// #v30.9 tracker mutators — editable past moods + removable custom money
/// categories, both must survive a cold restart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('setMoodOn edits a PAST day and persists across restart', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore();
    await s.load();
    final today = epochDayOf(DateTime.now());
    s.setMoodOn(today - 3, 2);
    s.setMoodOn(today - 3, 5); // overwrite sticks
    s.setMoodOn(today - 3, 9); // out of range → ignored
    expect(s.moods[today - 3], 5);
    expect(s.todayMood, null); // today untouched

    final s2 = AppStore();
    await s2.load();
    expect(s2.moods[today - 3], 5);
  });

  test('removeCustomCategory removes + persists; built-ins unaffected', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore();
    await s.load();
    s.addCustomCategory('kebab');
    s.addCustomCategory('RENT');
    expect(s.customCategories, ['KEBAB', 'RENT']);
    s.removeCustomCategory('KEBAB');
    s.removeCustomCategory('catFood'); // not a custom category → no-op
    expect(s.customCategories, ['RENT']);

    final s2 = AppStore();
    await s2.load();
    expect(s2.customCategories, ['RENT']);
  });
}
