import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_pomo/logic.dart';

void main() {
  group('AppBlocker (#v23)', () {
    test('active only during a running, unfinished WORK session when enabled', () {
      bool a({bool en = true, bool run = true, bool work = true, bool fin = false}) =>
          AppBlocker.active(enabled: en, isRunning: run, isWork: work, isFinished: fin);
      expect(a(), true);
      expect(a(en: false), false); // disabled
      expect(a(run: false), false); // paused/stopped
      expect(a(work: false), false); // break
      expect(a(fin: true), false); // finished
    });

    test('blocked-apps csv codec round-trips, dedupes, drops blanks', () {
      final s = {'com.a', 'com.b'};
      expect(AppBlocker.decode(AppBlocker.encode(s)), s);
      expect(AppBlocker.decode('com.a,com.a, ,com.b'), {'com.a', 'com.b'});
      expect(AppBlocker.decode(null), <String>{});
      expect(AppBlocker.encode(<String>{}), '');
    });

    test('shouldBlock: only blocked pkgs, never our app or the launcher', () {
      final b = {'com.insta', 'com.tiktok'};
      expect(AppBlocker.shouldBlock('com.insta', b, ownPkg: 'com.pixelpomo.pixel_pomo'), true);
      expect(AppBlocker.shouldBlock('com.other', b, ownPkg: 'com.pixelpomo.pixel_pomo'), false);
      expect(AppBlocker.shouldBlock('com.pixelpomo.pixel_pomo', b, ownPkg: 'com.pixelpomo.pixel_pomo'), false);
      expect(AppBlocker.shouldBlock('com.launcher', b, ownPkg: 'x', launcherPkg: 'com.launcher'), false);
    });
  });
}
