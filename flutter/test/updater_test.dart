import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_pomo/logic.dart';
import 'package:pixel_pomo/main.dart';
import 'package:pixel_pomo/strings.dart';
import 'package:pixel_pomo/updater.dart';

// In-app updates (#v37). Neither APK is on a store, so the app asks the GitHub
// release its build was published to whether something newer is there. What can
// be pinned without a phone is the decision — WHICH release, and whether it is
// newer — and the dialog's states. The download and the installer hand-off are
// Android's and are checked on a device.
void main() {
  Map<String, dynamic> release(String tag, String body, List<String> assets) => {
        'tag_name': tag,
        'body': body,
        'assets': [
          for (final a in assets)
            {'name': a, 'browser_download_url': 'https://example.test/$tag/$a'},
        ],
      };

  // The shape of GET /repos/hero-999-dev/pixel_pomo/releases, cut down to the
  // fields that are read. Deliberately out of order, the way GitHub may send it.
  final releases = [
    release('flutter-v36', 'Pixel Pomo v36 from abc1234.', ['pixel_pomo_flutter.apk']),
    release('flutter-test', 'Test build. build:1700000300', ['pixel_pomo_test.apk']),
    release('flutter-v37', 'Pixel Pomo v37. build:1700000100', ['pixel_pomo_flutter.apk', 'pixel_pomo_ios.ipa']),
    release('flutter-v38', 'Pixel Pomo v38. build:1700000200', ['pixel_pomo_flutter.apk']),
  ];

  group('newestBuild — which published APK is this app\'s', () {
    test('the real app takes the newest of the flutter-vNN series', () {
      final u = newestBuild(releases, test: false)!;
      expect(u.built, 1700000200);
      expect(u.apk.toString(), 'https://example.test/flutter-v38/pixel_pomo_flutter.apk');
    });

    test('the test app takes flutter-test and never the real app\'s APK', () {
      // Different packages: installing the other one's APK would not update
      // this app, it would install a second one beside it.
      final u = newestBuild(releases, test: true)!;
      expect(u.built, 1700000300);
      expect(u.apk.toString(), 'https://example.test/flutter-test/pixel_pomo_test.apk');
    });

    test('a release with no build stamp predates the updater and is skipped', () {
      expect(newestBuild([releases[0]], test: false), isNull);
    });

    test('a stamped release whose APK is missing offers nothing', () {
      // A manual iOS-only upload, or a run that failed before the upload step.
      final r = [release('flutter-v39', 'build:1700000900', ['pixel_pomo_ios.ipa'])];
      expect(newestBuild(r, test: false), isNull);
    });

    test('anything that is not a release list is nothing, not a crash', () {
      // A rate-limited request answers with an error OBJECT.
      expect(newestBuild({'message': 'API rate limit exceeded'}, test: false), isNull);
      expect(newestBuild(null, test: true), isNull);
      expect(newestBuild(['nonsense', 3], test: false), isNull);
    });
  });

  group('updateFor — is it newer than what is running', () {
    test('an older running build is offered the update', () {
      expect(updateFor(releases, test: false, runningBuild: 1700000100)?.built, 1700000200);
    });

    test('the build that IS the release is not offered itself', () {
      // The same CI run stamps one number into the APK and into the notes, so
      // equality means "you have it" — a looser test would nag forever.
      expect(updateFor(releases, test: false, runningBuild: 1700000200), isNull);
    });

    test('a build newer than the release is left alone', () {
      // The locally built test APK with the voxel models is this case.
      expect(updateFor(releases, test: true, runningBuild: 1700009999), isNull);
    });
  });

  group('a build that was not made to be published', () {
    test('has no build time, so it never looks', () {
      // `flutter test` and `flutter run` pass no BUILD_TIME.
      expect(kBuildTime, 0);
      expect(updatesSupported, isFalse);
    });
  });

  group('UpdateDialog', () {
    final update = AppUpdate(Uri.parse('https://example.test/a.apk'), 1700000200);
    const th = Themes.fallback;

    Future<void> open(WidgetTester tester, Future<void> Function(AppUpdate,
            {required void Function(int) onProgress, bool Function()? cancelled}) install) =>
        tester.pumpWidget(MaterialApp(home: UpdateDialog(update, th, 'en', install: install)));

    testWidgets('starts downloading at once and reports progress', (tester) async {
      final done = Completer<void>();
      late void Function(int) progress;
      await open(tester, (u, {required onProgress, cancelled}) {
        progress = onProgress;
        return done.future;
      });
      expect(find.text('DOWNLOADING 0%'), findsOneWidget);
      progress(42);
      await tester.pump();
      expect(find.text('DOWNLOADING 42%'), findsOneWidget);
      expect(find.text('CANCEL'), findsOneWidget);
      done.complete();
      await tester.pump(); // the download's future lands...
      await tester.pump(); // ...and the dialog redraws
      expect(find.text('INSTALLING...'), findsOneWidget);
    });

    testWidgets('says so when the download fails', (tester) async {
      await open(tester, (u, {required onProgress, cancelled}) async => throw Exception('offline'));
      await tester.pump();
      expect(find.text('UPDATE FAILED'), findsOneWidget);
      expect(find.text('CLOSE'), findsOneWidget);
    });

    testWidgets('closing it tells the download to stop', (tester) async {
      bool Function()? stop;
      await open(tester, (u, {required onProgress, cancelled}) {
        stop = cancelled;
        return Completer<void>().future;
      });
      expect(stop!(), isFalse);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(stop!(), isTrue);
    });
  });

  group('the words', () {
    test('are translated in every language the app ships', () {
      // t() falls back to English, which is exactly what would hide a
      // language someone forgot.
      for (final key in ['updateAvailable', 'updateInstalling', 'updateFailed', 'updateDownloading']) {
        final seen = <String>{};
        for (final lang in languageOptions.map((l) => l.first)) {
          expect(t(lang, key), isNot(key), reason: '$lang/$key');
          seen.add(t(lang, key));
        }
        expect(seen.length, greaterThan(languageOptions.length ~/ 2), reason: '$key is mostly untranslated');
      }
    });
  });
}
