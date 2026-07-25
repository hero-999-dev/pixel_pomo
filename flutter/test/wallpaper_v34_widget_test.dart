import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pixel_pomo/main.dart';
import 'package:pixel_pomo/store.dart';

/// #v34 wallpaper round: HOME SCREEN always offers WALLPAPER (tapping it with
/// no photo saved explains where to get one), and the crop screen can throw
/// the photo away.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppStore> boot([Map<String, Object> prefs = const {}]) async {
    SharedPreferences.setMockInitialValues({'flutter.tutorial_done': true, ...prefs});
    final s = AppStore();
    await s.load();
    return s;
  }

  Widget settingsHost(AppStore s) => MaterialApp(
      home: Scaffold(body: AnimatedBuilder(animation: s, builder: (_, __) => SettingsScreen(s))));

  testWidgets('WALLPAPER is on the row even with no photo saved', (tester) async {
    final s = await boot();
    await tester.pumpWidget(settingsHost(s));
    await tester.pumpAndSettle();

    expect(s.wallpaperPath, isNull);
    expect(find.byKey(const Key('homeMode_wallpaper')), findsOneWidget,
        reason: 'hiding it left no hint the mode existed');

    s.dispose();
  });

  testWidgets('tapping it with no photo opens the how-to instead of silently doing nothing',
      (tester) async {
    final s = await boot();
    await tester.pumpWidget(settingsHost(s));
    await tester.pumpAndSettle();

    final before = s.homeBackdrop;
    await tester.ensureVisible(find.byKey(const Key('homeMode_wallpaper')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('homeMode_wallpaper')));
    await tester.pumpAndSettle();

    expect(find.text('NO WALLPAPER YET'), findsOneWidget);
    expect(find.textContaining('DETAILED CUSTOMISATION'), findsOneWidget);
    expect(find.textContaining('THEME'), findsWidgets);
    expect(find.textContaining('CHOOSE WALLPAPER'), findsOneWidget);
    expect(s.homeBackdrop, before, reason: 'the mode must not change until there is a photo');

    s.dispose();
  });

  testWidgets('with a photo saved, the button switches the mode as usual', (tester) async {
    final s = await boot();
    s.setWallpaper('/tmp/photo.png'); // also flips the mode
    s.setHomeBackdrop('clean');
    await tester.pumpWidget(settingsHost(s));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('homeMode_wallpaper')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('homeMode_wallpaper')));
    await tester.pumpAndSettle();

    expect(find.text('NO WALLPAPER YET'), findsNothing);
    expect(s.homeBackdrop, 'wallpaper');

    s.dispose();
  });

  testWidgets('the crop screen can delete the wallpaper', (tester) async {
    // a real (tiny) file: the crop screen renders Image.file, and a missing
    // path would fail the test on the image load rather than on the button.
    final dir = Directory.systemTemp.createTempSync('pp_wall');
    final photo = File('${dir.path}/photo.png')
      ..writeAsBytesSync(base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='));

    final s = await boot();
    s.setWallpaper(photo.path);
    s.setWallpaperCrop(2.0, 0.5, 0.5);
    expect(s.homeBackdrop, 'wallpaper');

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () => openPanel(ctx, s, () => WallpaperCropScreen(s, photo.path)),
            child: const Text('GO'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('GO'));
    await tester.pumpAndSettle();

    final remove = find.byKey(const Key('wallpaperRemove'));
    expect(remove, findsOneWidget);
    await tester.ensureVisible(remove);
    await tester.pumpAndSettle();
    await tester.tap(remove);
    await tester.pumpAndSettle();

    expect(s.wallpaperPath, isNull);
    expect(s.homeBackdrop, 'clean', reason: 'nothing left to show');
    expect(s.wallZoom, 1.0, reason: 'the next photo starts uncropped');

    dir.deleteSync(recursive: true);
    s.dispose();
  });

  testWidgets('Settings can replay the tour', (tester) async {
    final s = await boot();
    expect(s.tutorialDone, true);
    await tester.pumpWidget(settingsHost(s));
    await tester.pumpAndSettle();

    final replay = find.byKey(const Key('replayTutorial'));
    await tester.ensureVisible(replay);
    await tester.pumpAndSettle();
    await tester.tap(replay);
    await tester.pumpAndSettle();

    expect(s.tutorialDone, false, reason: 'SKIP would otherwise be one-way');
    final reopened = AppStore();
    await reopened.load();
    expect(reopened.tutorialDone, false);

    s.dispose();
    reopened.dispose();
  });
}
