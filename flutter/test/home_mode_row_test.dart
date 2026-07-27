import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pixel_pomo/main.dart';
import 'package:pixel_pomo/pixel.dart';
import 'package:pixel_pomo/store.dart';

/// The HOME SCREEN mode buttons must all be the same size, in every language
/// (#v35.6).
///
/// `PixelButton` fits its label with `BoxFit.scaleDown` **per button**, so in a
/// row of four the longest label shrank its own text the most — and a shorter
/// text makes a shorter box. WALLPAPER ended up visibly smaller than CLEAN
/// beside it: "wallpaper diger karelerle ayni boyutta degil kücük duruyor".
/// Laid out 2x2 now, which gives every label room at the full font size.
///
/// Checked in all six languages because the label that overflows is a different
/// one in each — English "WALLPAPER" is short, German "HINTERGRUNDBILD" is not.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const modes = ['clean', 'garden', 'forest', 'wallpaper'];

  Future<AppStore> boot(String lang) async {
    SharedPreferences.setMockInitialValues(
        {'flutter.tutorial_done': true, 'flutter.language': lang});
    final s = AppStore();
    await s.load();
    return s;
  }

  Widget host(AppStore s) => MaterialApp(
      home: Scaffold(
          body: AnimatedBuilder(animation: s, builder: (_, __) => SettingsScreen(s))));

  for (final lang in ['en', 'tr', 'pl', 'de', 'fr', 'it']) {
    testWidgets('home mode buttons are all one size in $lang', (tester) async {
      PixelButton.animate = false;
      addTearDown(() => PixelButton.animate = true);
      final s = await boot(lang);
      await tester.pumpWidget(host(s));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
          find.byKey(const Key('homeMode_wallpaper')), 120,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();

      final sizes = [
        for (final m in modes) tester.getSize(find.byKey(Key('homeMode_$m')))
      ];
      for (var i = 1; i < sizes.length; i++) {
        expect(sizes[i].height, closeTo(sizes[0].height, 0.5),
            reason: '${modes[i]} is ${sizes[i].height} tall against '
                '${modes[0]} at ${sizes[0].height} — labels scaling differently');
        expect(sizes[i].width, closeTo(sizes[0].width, 0.5),
            reason: '${modes[i]} is ${sizes[i].width} wide against '
                '${modes[0]} at ${sizes[0].width}');
      }
      s.dispose();
    });
  }
}
