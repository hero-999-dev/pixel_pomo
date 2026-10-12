import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

// In-app updates for the sideloaded Android APKs (#v37).
//
// Neither app is on a store, so until now every build meant opening GitHub,
// downloading an APK and tapping through the installer by hand. Both builds are
// already published by CI to a GitHub release on every push; this asks that
// release whether it holds something newer than the build that is running, and
// if so downloads it and hands it to Android's own installer.
//
// "Newer" is decided by one number, the build's Unix time. The build stamps it
// into the app (`--dart-define=BUILD_TIME=…`) and the same workflow writes it
// into the release notes as `build:<n>`, so the two cannot disagree: the APK a
// run uploads carries exactly the number its notes announce. The pubspec
// version would not do — it is not bumped on every push — and the asset's own
// upload time would not either, since it always trails the build that made it.

/// When this APK was built, Unix seconds. 0 for anything not built to be
/// published (`flutter run`, a test), which therefore never looks for updates.
const kBuildTime = int.fromEnvironment('BUILD_TIME');

const _testBuild = bool.fromEnvironment('TEST_BUILD');
const _releasesUrl = 'https://api.github.com/repos/hero-999-dev/pixel_pomo/releases?per_page=30';
const _channel = MethodChannel('pixel_pomo/updater');

/// A published build newer than the one running.
class AppUpdate {
  final Uri apk;
  final int built;
  const AppUpdate(this.apk, this.built);
}

/// The update the home screen is offering, or null. Set by [refreshUpdate].
final ValueNotifier<AppUpdate?> pendingUpdate = ValueNotifier(null);

/// Android only, and only for a build that knows when it was made.
bool get updatesSupported =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android && kBuildTime > 0;

/// The newest build of this app in GitHub's release list, or null.
///
/// The real app and Test Pixel Pomo are different packages published side by
/// side in one repo, so each looks only at its own: the test build at the single
/// rolling `flutter-test` release, the real one at the `flutter-vNN` series
/// (one per minor version — hence "newest of", not "the latest"). A release
/// with no `build:` line predates this and is skipped. Pure, so it is tested
/// against a captured response rather than the network.
AppUpdate? newestBuild(Object? releases, {required bool test}) {
  if (releases is! List) return null;
  final asset = test ? 'pixel_pomo_test.apk' : 'pixel_pomo_flutter.apk';
  AppUpdate? best;
  for (final r in releases) {
    if (r is! Map) continue;
    final tag = '${r['tag_name']}';
    if (test ? tag != 'flutter-test' : !tag.startsWith('flutter-v')) continue;
    final stamp = RegExp(r'\bbuild:(\d+)').firstMatch('${r['body']}');
    if (stamp == null) continue;
    final built = int.parse(stamp.group(1)!);
    final assets = r['assets'];
    if (assets is! List) continue;
    for (final a in assets) {
      if (a is! Map || a['name'] != asset) continue;
      final url = Uri.tryParse('${a['browser_download_url']}');
      if (url != null && (best == null || built > best.built)) best = AppUpdate(url, built);
    }
  }
  return best;
}

/// [newestBuild], if it is newer than a build made at [runningBuild].
AppUpdate? updateFor(Object? releases, {required bool test, required int runningBuild}) {
  final newest = newestBuild(releases, test: test);
  return newest != null && newest.built > runningBuild ? newest : null;
}

DateTime? _lastCheck;

/// Ask GitHub, at most once every [every], and publish the answer on
/// [pendingUpdate]. Silent on any failure — offline is the normal case for a
/// timer app, and the next launch simply asks again.
Future<void> refreshUpdate({Duration every = const Duration(minutes: 15)}) async {
  if (!updatesSupported) return;
  final now = DateTime.now();
  if (_lastCheck != null && now.difference(_lastCheck!) < every) return;
  _lastCheck = now;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final req = await client.getUrl(Uri.parse(_releasesUrl)).timeout(const Duration(seconds: 8));
    req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    final resp = await req.close().timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) return;
    final body = await resp.transform(utf8.decoder).join().timeout(const Duration(seconds: 15));
    pendingUpdate.value =
        updateFor(jsonDecode(body), test: _testBuild, runningBuild: kBuildTime);
  } catch (_) {
    // keep whatever was already on offer
  } finally {
    client.close(force: true);
  }
}

/// Download [update] and open Android's installer on it. [onProgress] gets
/// 0..100. Completes once the installer has been handed the file — from there
/// the system asks the user to confirm and replaces the app, which ends this
/// process. [cancelled] is polled so a closed dialog stops the download.
Future<void> downloadAndInstall(AppUpdate update,
    {required void Function(int percent) onProgress, bool Function()? cancelled}) async {
  final dir = Directory('${(await getTemporaryDirectory()).path}/update');
  if (dir.existsSync()) dir.deleteSync(recursive: true); // never install a stale download
  dir.createSync(recursive: true);
  final file = File('${dir.path}/update.apk');
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final resp = await (await client.getUrl(update.apk)).close();
    if (resp.statusCode != 200) throw HttpException('HTTP ${resp.statusCode}', uri: update.apk);
    final total = resp.contentLength;
    final sink = file.openWrite();
    var got = 0;
    try {
      await for (final chunk in resp) {
        if (cancelled?.call() ?? false) throw const HttpException('cancelled');
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress((got * 100 ~/ total).clamp(0, 100));
      }
    } finally {
      await sink.close();
    }
  } finally {
    client.close(force: true);
  }
  await _channel.invokeMethod<void>('install', {'path': file.path});
}
