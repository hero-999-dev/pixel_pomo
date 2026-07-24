import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pixel_pomo/logic.dart';
import 'package:pixel_pomo/main.dart';
import 'package:pixel_pomo/pixel.dart';
import 'package:pixel_pomo/store.dart';
import 'package:pixel_pomo/strings.dart';

/// #v32.3 — the theme picker gains a user-built palette: every colour the user
/// can point at (background, the two text colours, the selected square, the
/// other squares, BREAK, income) is picked outright, no base theme. These drive
/// the whole flow through the real screens.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // the whole section lives behind Settings → DETAILED CUSTOMISATION (#v32.4),
  // so every editor test opts in first
  Future<AppStore> boot({bool detailed = true}) async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore();
    await s.load();
    if (detailed) s.setDetailedCustom(true);
    return s;
  }

  Widget host(AppStore s) =>
      MaterialApp(home: AnimatedBuilder(animation: s, builder: (_, __) => ThemeScreen(s)));

  // the editor is taller than the 800x600 test viewport — scroll before tapping
  Future<void> tapVisible(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  // #v33.2 — one shared palette: select the slot, then tap the colour. The
  // swatch key no longer carries the slot (there is one palette, not seven).
  Future<void> pick(WidgetTester tester, int slot, int color) async {
    await tapVisible(tester, find.byKey(ValueKey('slotBox_$slot')));
    await tapVisible(tester, find.byKey(ValueKey('swatch_$color')));
  }

  testWidgets('with nothing saved the picker offers one CUSTOM button that opens the editor',
      (tester) async {
    final s = await boot();
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();

    expect(find.text('CUSTOM'), findsOneWidget);
    expect(find.text('EDIT COLORS'), findsNothing);

    await tester.tap(find.text('CUSTOM'));
    await tester.pumpAndSettle();
    // labels name what each colour paints, not what the field is called (#v32.5).
    // BACKGROUND appears twice — the slot tile and the "EDITING …" heading for
    // the active slot (slot 0), which is fine (#v33.2).
    expect(find.textContaining('BACKGROUND'), findsWidgets);
    expect(find.textContaining('HIGHLIGHT'), findsOneWidget);
    expect(find.textContaining('INCOME'), findsOneWidget);
    // the base-theme starting point (#v33.1): the row and a button per preset
    expect(find.textContaining('BASE THEME'), findsOneWidget);
    for (final theme in Themes.all) {
      expect(find.text(theme.displayName), findsWidgets, reason: '${theme.displayName} base button');
    }
    // the slot labels must say where the colour shows up, not just name it
    for (final key in const ['cText1', 'cText2', 'cSelected', 'cSquares']) {
      expect(t('en', key), contains(' - '), reason: '$key should explain where it applies');
    }
  });

  testWidgets('a base theme loads its colours into every slot, then a swatch overrides one (#v33.1)',
      (tester) async {
    final s = await boot();
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CUSTOM'));
    await tester.pumpAndSettle();

    // start from MATCHA: its palette becomes the picks, so its background is
    // what the BACKGROUND slot's colour box shows and what saving keeps.
    await tapVisible(tester, find.text('MATCHA'));
    final box0 = tester.widget<Container>(find.byKey(const ValueKey('slotBox_0')));
    expect((box0.decoration as BoxDecoration).color, col(Themes.matcha.bg),
        reason: 'the BACKGROUND colour box did not follow the base theme');

    // now change ONE slot (the highlight) and save — every other slot must
    // still be matcha's, proving the base seeded them all.
    await pick(tester, 3, 0xFFE8C547);
    await tapVisible(tester, find.text('SAVE'));
    expect(s.theme.id, customThemeId);
    expect(s.theme.bg, Themes.matcha.bg, reason: 'background should be matcha, untouched');
    expect(s.theme.accent, 0xFFE8C547, reason: 'highlight is the one slot the user changed');
  });

  testWidgets('picking colours and saving switches the app to the custom theme', (tester) async {
    final s = await boot();
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CUSTOM'));
    await tester.pumpAndSettle();

    await pick(tester, 0, 0xFF1B3A63); // background
    await pick(tester, 3, 0xFFE8C547); // selected square
    await tapVisible(tester, find.text('SAVE'));

    expect(s.theme.id, customThemeId);
    expect(s.theme.bg, 0xFF1B3A63); // the background is the anchor, never corrected
    expect(s.theme.accent, 0xFFE8C547);
    expect(customThemePicks(s.customSpec)![0], 0xFF1B3A63);
    // back on the picker, the saved palette is selected and editable
    expect(find.text('> CUSTOM'), findsOneWidget);
    expect(find.text('EDIT COLORS'), findsOneWidget);
  });

  testWidgets('BREAK and income are picked here too, and the editor reopens on them',
      (tester) async {
    final s = await boot();
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CUSTOM'));
    await tester.pumpAndSettle();

    await pick(tester, 4, 0xFF422A63); // squares
    await pick(tester, 5, 0xFF9D7CD8); // BREAK
    await pick(tester, 6, 0xFFE8C547); // income
    await tapVisible(tester, find.text('SAVE'));

    expect(s.theme.breakColor, 0xFF9D7CD8);
    expect(s.theme.work, 0xFFE8C547);

    await tapVisible(tester, find.text('EDIT COLORS'));
    expect(customThemePicks(s.customSpec)![4], 0xFF422A63);
    expect(customThemePicks(s.customSpec)![6], 0xFFE8C547);
  });

  testWidgets('a hex code sets the active slot to any colour, off-palette (#v33.2)',
      (tester) async {
    final s = await boot();
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CUSTOM'));
    await tester.pumpAndSettle();

    // 0x123456 is not one of the 26 swatches — the whole point of the field
    await tapVisible(tester, find.byKey(const ValueKey('slotBox_0'))); // BACKGROUND active
    await tester.enterText(find.byKey(const Key('hexField')), '123456');
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('SAVE'));

    expect(s.theme.bg, 0xFF123456, reason: 'background is the anchor; the hex applies verbatim');
    expect(customThemePicks(s.customSpec)![0], 0xFF123456);
  });

  testWidgets('the palette edits whichever slot is active, not a fixed one (#v33.2)',
      (tester) async {
    final s = await boot();
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CUSTOM'));
    await tester.pumpAndSettle();

    // tap the SAME swatch after selecting two different slots: it must land on
    // whichever slot is active, proving the palette is shared, not per-slot.
    await pick(tester, 1, 0xFFE5484D); // MAIN TEXT
    await pick(tester, 5, 0xFFE5484D); // BREAK
    await tapVisible(tester, find.text('SAVE'));
    expect(customThemePicks(s.customSpec)![1], 0xFFE5484D);
    expect(customThemePicks(s.customSpec)![5], 0xFFE5484D);
  });

  testWidgets('an unreadable pick is corrected on save, and the app stays legible',
      (tester) async {
    final s = await boot();
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CUSTOM'));
    await tester.pumpAndSettle();

    // one mid-grey for every slot: text on top of its own colour
    for (var slot = 0; slot < kCustomSlots; slot++) {
      await pick(tester, slot, 0xFF565656);
    }
    await tapVisible(tester, find.text('SAVE'));

    final th = s.theme;
    expect(contrastRatio(th.onSurface, th.bg), greaterThanOrEqualTo(kMinTextContrast));
    expect(contrastRatio(th.panel, th.bg), greaterThanOrEqualTo(kMinFillContrast));
    expect(contrastRatio(th.accent, th.panel), greaterThanOrEqualTo(kMinFillContrast));
    expect(tester.takeException(), isNull);
  });

  // ---- DETAILED CUSTOMISATION gate (#v32.4) ----

  testWidgets('with the switch off the picker shows the presets and nothing else',
      (tester) async {
    final s = await boot(detailed: false);
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();

    expect(find.text('CUSTOM'), findsNothing);
    expect(find.text('EDIT COLORS'), findsNothing);
    expect(find.text('> DARK'), findsOneWidget); // the presets are still there
  });

  testWidgets('turning the switch off stops wearing the custom theme but keeps the picks',
      (tester) async {
    final s = await boot();
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CUSTOM'));
    await tester.pumpAndSettle();
    await pick(tester, 0, 0xFF1B3A63);
    await tapVisible(tester, find.text('SAVE'));
    expect(s.theme.id, customThemeId);

    s.setDetailedCustom(false);
    await tester.pumpAndSettle();

    expect(s.theme.id, isNot(customThemeId), reason: 'an unreachable theme must not stay worn');
    expect(customThemePicks(s.customSpec)![0], 0xFF1B3A63, reason: 'the picks survive');
    expect(find.text('EDIT COLORS'), findsNothing);

    // switching back on restores it exactly as it was
    s.setDetailedCustom(true);
    await tester.pumpAndSettle();
    expect(find.text('EDIT COLORS'), findsOneWidget);
    expect(s.customTheme!.bg, 0xFF1B3A63);
  });

  // ---- home wallpaper (#v32.4) ----

  group('home wallpaper', () {
    test('the crop is clamped, so a corrupt pref cannot render it off-screen', () async {
      SharedPreferences.setMockInitialValues({});
      final s = AppStore();
      await s.load();

      s.setWallpaperCrop(9.0, 5.0, -5.0);
      expect(s.wallZoom, 3.0);
      expect(s.wallDx, 1.0);
      expect(s.wallDy, -1.0);

      s.setWallpaperCrop(0.1, 0.25, -0.25);
      expect(s.wallZoom, 1.0, reason: 'zooming out past cover would show empty edges');
      expect(s.wallDx, 0.25);
      expect(s.wallDy, -0.25);
    });

    test('WALLPAPER mode is refused until one is saved, and released when removed', () async {
      SharedPreferences.setMockInitialValues({});
      final s = AppStore();
      await s.load();

      s.setHomeBackdrop('wallpaper');
      expect(s.homeBackdrop, 'clean', reason: 'nothing to show yet');

      s.setWallpaper('/tmp/photo.jpg');
      expect(s.homeBackdrop, 'wallpaper', reason: 'saving one switches to it');
      expect(s.homeOverImage, isTrue);
      expect(s.homeGardenBackdrop, isFalse, reason: 'the garden getter must not claim it');

      s.setWallpaperCrop(2.0, 0.5, 0.5);
      s.removeWallpaper();
      expect(s.wallpaperPath, isNull);
      expect(s.homeBackdrop, 'clean');
      expect(s.wallZoom, 1.0, reason: 'a fresh photo starts uncropped');
    });

    test('the legacy garden bool still loads, and a missing file falls back', () async {
      // saves made before #v32.4 only knew home_garden_backdrop
      SharedPreferences.setMockInitialValues({'flutter.home_garden_backdrop': true});
      var s = AppStore();
      await s.load();
      expect(s.homeBackdrop, 'garden');
      expect(s.homeGardenBackdrop, isTrue);

      SharedPreferences.setMockInitialValues({'flutter.home_garden_backdrop': false});
      s = AppStore();
      await s.load();
      expect(s.homeBackdrop, 'clean');

      // wallpaper mode saved, but the path is gone → a blank home screen would
      // be the alternative
      SharedPreferences.setMockInitialValues({'flutter.home_backdrop': 'wallpaper'});
      s = AppStore();
      await s.load();
      expect(s.homeBackdrop, 'clean');
    });
  });
}
