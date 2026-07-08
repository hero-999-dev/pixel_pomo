import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pixel_pomo/logic.dart';
import 'package:pixel_pomo/store.dart';

/// #v31.16 — Log History soft-delete: a removed log moves to the Recycle
/// Bin rather than being destroyed outright, and stops counting toward
/// stats immediately (it's simply no longer in AppStore.records).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('removeRecord moves a log to deletedRecords and it stops counting toward stats', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore();
    await s.load();
    final before = s.records.length;
    // find a MATH record and note its total minutes before removal —
    // labelHabitCounts counts SESSIONS not minutes, so use
    // LabelHabits.minutesFromRecords directly for the actual time total.
    final mathIdx = s.records.indexWhere((r) => r.label == 'MATH' && r.minutes > 0);
    expect(mathIdx, greaterThanOrEqualTo(0)); // TestData seeds MATH
    final removedMinutes = s.records[mathIdx].minutes;
    final sessionsBefore = s.labelHabitCounts['MATH']!.values.fold(0, (a, b) => a + b);
    final mathMinutesBefore = LabelHabits.minutesFromRecords(s.records)['MATH']!.values.fold(0, (a, b) => a + b);

    s.removeRecord(mathIdx);

    expect(s.records.length, before - 1);
    expect(s.deletedRecords.length, 1);
    expect(s.deletedRecords.first.label, 'MATH');
    expect(s.deletedRecords.first.minutes, removedMinutes);
    // stats no longer see it — both aggregations are derived straight from
    // records, so this proves exclusion end to end, not just list length
    final sessionsAfter = (s.labelHabitCounts['MATH']?.values ?? const <int>[]).fold(0, (a, b) => a + b);
    expect(sessionsAfter, sessionsBefore - 1);
    final mathMinutesAfter =
        (LabelHabits.minutesFromRecords(s.records)['MATH']?.values ?? const <int>[]).fold(0, (a, b) => a + b);
    expect(mathMinutesAfter, mathMinutesBefore - removedMinutes);
  });

  test('purgeRecord permanently removes from the recycle bin, does not touch records', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore();
    await s.load();
    final recordsBefore = s.records.length;
    s.removeRecord(0);
    expect(s.deletedRecords.length, 1);

    s.purgeRecord(0);
    expect(s.deletedRecords, isEmpty);
    expect(s.records.length, recordsBefore - 1); // still removed from records, obviously
  });

  test('cleanRecycleBin empties deletedRecords entirely, leaves records untouched', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore();
    await s.load();
    final recordsBefore = s.records.length;
    s.removeRecord(0);
    s.removeRecord(0); // indices shift as records are removed — still index 0
    s.removeRecord(0);
    expect(s.deletedRecords.length, 3);

    s.cleanRecycleBin();
    expect(s.deletedRecords, isEmpty);
    expect(s.records.length, recordsBefore - 3);
  });

  test('both records and deletedRecords persist across a reload', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore();
    await s.load();
    final recordsBefore = s.records.length;
    s.removeRecord(0);
    final removed = s.deletedRecords.first;

    final s2 = AppStore();
    await s2.load();
    expect(s2.records.length, recordsBefore - 1);
    expect(s2.deletedRecords.length, 1);
    expect(s2.deletedRecords.first.label, removed.label);
    expect(s2.deletedRecords.first.epochDay, removed.epochDay);
    expect(s2.deletedRecords.first.minutes, removed.minutes);
  });

  test('out-of-range indices are safely ignored', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore();
    await s.load();
    final recordsBefore = s.records.length;
    s.removeRecord(-1);
    s.removeRecord(999999);
    s.purgeRecord(-1);
    s.purgeRecord(999999);
    s.restoreRecord(-1);
    s.restoreRecord(999999);
    expect(s.records.length, recordsBefore); // untouched
    expect(s.deletedRecords, isEmpty);
  });

  test('restoreRecord moves a log back out of the Recycle Bin and it counts toward stats again', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore();
    await s.load();
    final recordsBefore = s.records.length;
    final mathIdx = s.records.indexWhere((r) => r.label == 'MATH' && r.minutes > 0);
    final removedMinutes = s.records[mathIdx].minutes;
    final mathMinutesBefore = LabelHabits.minutesFromRecords(s.records)['MATH']!.values.fold(0, (a, b) => a + b);

    s.removeRecord(mathIdx);
    expect(s.records.length, recordsBefore - 1);
    expect(s.deletedRecords.length, 1);

    s.restoreRecord(0);
    expect(s.deletedRecords, isEmpty);
    expect(s.records.length, recordsBefore); // back to the original count
    expect(s.records.any((r) => r.label == 'MATH' && r.minutes == removedMinutes), true);
    final mathMinutesAfter = LabelHabits.minutesFromRecords(s.records)['MATH']!.values.fold(0, (a, b) => a + b);
    expect(mathMinutesAfter, mathMinutesBefore, reason: 'restored record must count toward stats again');
  });

  test('restored records persist across a reload', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore();
    await s.load();
    final recordsBefore = s.records.length;
    s.removeRecord(0);
    s.restoreRecord(0);

    final s2 = AppStore();
    await s2.load();
    expect(s2.records.length, recordsBefore);
    expect(s2.deletedRecords, isEmpty);
  });
}
