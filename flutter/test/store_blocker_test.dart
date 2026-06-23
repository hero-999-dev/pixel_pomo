import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pixel_pomo/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('app blocker state persists and blockerActive tracks the session (#v23)', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore();
    await s.load();

    expect(s.appBlockerEnabled, false);
    expect(s.blockerActive, false);

    s.setAppBlocker(true);
    s.setBlocked('com.insta', true);
    s.setBlocked('com.tiktok', true);
    s.setBlocked('com.tiktok', false); // toggling off removes it
    expect(s.appBlockerEnabled, true);
    expect(s.blockedApps, {'com.insta'});

    // inactive until a WORK session is actually running
    expect(s.blockerActive, false);
    s.start();
    expect(s.blockerActive, true); // enabled + running + WORK + not finished
    s.pause(); // also cancels the timer so the test leaves none pending
    expect(s.blockerActive, false);

    // a fresh store reads the persisted settings back
    final s2 = AppStore();
    await s2.load();
    expect(s2.appBlockerEnabled, true);
    expect(s2.blockedApps, {'com.insta'});
  });
}
