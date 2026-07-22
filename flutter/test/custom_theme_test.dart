import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_pomo/logic.dart';
import 'package:pixel_pomo/main.dart' show kSwatches;

/// The promise the custom theme makes: whatever colours the user taps, the
/// result is still readable and its squares are still tellable apart. Every
/// assertion below is on the BUILT theme, not on the raw picks.
void expectReadable(PixelTheme th) {
  expect(contrastRatio(th.onSurface, th.bg), greaterThanOrEqualTo(kMinTextContrast),
      reason: 'body text on background');
  expect(contrastRatio(th.onSurfaceDim, th.bg), greaterThanOrEqualTo(kMinDimTextContrast),
      reason: 'dim text on background');
  expect(contrastRatio(th.panel, th.bg), greaterThanOrEqualTo(kMinFillContrast),
      reason: 'squares on background');
  expect(contrastRatio(th.accent, th.panel), greaterThanOrEqualTo(kMinFillContrast),
      reason: 'selected square on the other squares');
  expect(contrastRatio(th.onAccent, th.accent), greaterThanOrEqualTo(kMinTextContrast),
      reason: 'label inside the selected square');
  expect(contrastRatio(th.breakColor, th.bg), greaterThanOrEqualTo(kMinDimTextContrast),
      reason: 'BREAK countdown on background');
  expect(contrastRatio(th.work, th.bg), greaterThanOrEqualTo(kMinDimTextContrast),
      reason: 'income amount on background');
}

List<int> allSlots(int c) => List.filled(kCustomSlots, c);

void main() {
  group('custom theme contrast', () {
    test('the worst pick — one colour for every slot — still reads', () {
      for (final c in kSwatches) {
        expectReadable(PixelTheme.fromPicks(allSlots(c)));
      }
    });

    test('every swatch as background against every swatch as everything else', () {
      for (final bg in kSwatches) {
        for (final other in kSwatches) {
          expectReadable(PixelTheme.fromPicks([bg, ...List.filled(kCustomSlots - 1, other)]));
        }
      }
    });

    test('every preset theme survives a round trip through the picker', () {
      // the editor seeds from whatever theme is on screen, so a preset's own
      // colours have to come back out as a usable custom theme
      for (final preset in Themes.all) {
        final th = PixelTheme.fromPicks(preset.picks);
        expectReadable(th);
        expect(th.bg, preset.bg, reason: 'the background is never corrected');
      }
    });

    test('a pick that already passes is left untouched', () {
      final th = PixelTheme.fromPicks([
        0xFF161616, // background
        0xFFF7F7F7, // text 1
        0xFF8E8E8E, // text 2
        0xFFE5484D, // selected square
        0xFF2B2B2B, // squares
        0xFF58A6FF, // BREAK
        0xFF46A03C, // income
      ]);
      expect(th.bg, 0xFF161616);
      expect(th.onSurface, 0xFFF7F7F7);
      expect(th.onSurfaceDim, 0xFF8E8E8E);
      expect(th.accent, 0xFFE5484D);
      expect(th.panel, 0xFF2B2B2B);
      expect(th.breakColor, 0xFF58A6FF);
      expect(th.work, 0xFF46A03C);
    });

    test('BREAK and income are the user\'s, not inherited from any preset', () {
      final th = PixelTheme.fromPicks(
          [0xFF0B0B0B, 0xFFF7F7F7, 0xFF8E8E8E, 0xFFE5484D, 0xFF2B2B2B, 0xFF9D7CD8, 0xFFE8C547]);
      expect(th.breakColor, 0xFF9D7CD8);
      expect(th.work, 0xFFE8C547);
      expect(Themes.all.any((p) => p.breakColor == th.breakColor), isFalse);
    });

    test('the shadow tracks the background instead of being picked', () {
      expect(PixelTheme.fromPicks(allSlots(0xFFF7F7F7)).shadow,
          isNot(PixelTheme.fromPicks(allSlots(0xFF0B0B0B)).shadow));
    });
  });

  // #v32.4 — the reported bug: picking SELECTED SQUARE also recoloured the home
  // screen countdown, and a dark pick sank it into the background.
  group('the countdown does not follow the selected square', () {
    test('a custom theme clocks in TEXT 1, whatever the selected square is', () {
      final th = PixelTheme.fromPicks(
          [0xFF161616, 0xFFF7F7F7, 0xFF8E8E8E, 0xFF0B0B0B, 0xFF2B2B2B, 0xFF58A6FF, 0xFF46A03C]);
      expect(th.focusTint, th.onSurface);
      expect(th.phaseColor(Mode.work), th.onSurface);
      expect(th.focusTint, isNot(th.accent));
    });

    test('the focus colour reads on the background for every swatch pair', () {
      // the whole point of the fix: no pick can sink the clock into the bg
      for (final bg in kSwatches) {
        for (final square in kSwatches) {
          final th = PixelTheme.fromPicks(
              [bg, 0xFF8E8E8E, 0xFF8E8E8E, square, 0xFF8E8E8E, 0xFF8E8E8E, 0xFF8E8E8E]);
          expect(contrastRatio(th.focusTint, th.bg), greaterThanOrEqualTo(kMinTextContrast));
        }
      }
    });

    test('BREAK still overrides it — only the focus phase changed', () {
      final th = PixelTheme.fromPicks(
          [0xFF161616, 0xFFF7F7F7, 0xFF8E8E8E, 0xFFE5484D, 0xFF2B2B2B, 0xFF9D7CD8, 0xFF46A03C]);
      expect(th.phaseColor(Mode.breakMode), th.breakColor);
    });

    test('the six presets are untouched — they still carry their accent (#v32.1)', () {
      for (final preset in Themes.all) {
        expect(preset.focusColor, isNull, reason: '${preset.id} must not set an override');
        expect(preset.focusTint, preset.accent);
        expect(preset.phaseColor(Mode.work), preset.accent);
      }
    });
  });

  group('custom theme persistence', () {
    final picks = [
      0xFF161616,
      0xFFF7F7F7,
      0xFF8E8E8E,
      0xFFE5484D,
      0xFF2B2B2B,
      0xFF58A6FF,
      0xFF46A03C,
    ];

    test('encode → decode keeps every raw pick', () {
      final spec = encodeCustomTheme(picks);
      expect(customThemePicks(spec), picks);
      expect(decodeCustomTheme(spec)!.id, customThemeId);
      expect(decodeCustomTheme(spec)!.breakColor, 0xFF58A6FF);
    });

    test('the editor reopens on the raw picks, not the corrected ones', () {
      // grey on grey: bg survives as picked, the text gets pushed off it
      final spec = encodeCustomTheme(allSlots(0xFF565656));
      expect(customThemePicks(spec), allSlots(0xFF565656));
      expect(decodeCustomTheme(spec)!.onSurface, isNot(0xFF565656));
    });

    test('a missing or corrupt spec falls back instead of crashing boot', () {
      expect(decodeCustomTheme(null), isNull);
      expect(decodeCustomTheme(''), isNull);
      expect(decodeCustomTheme(encodeCustomTheme(picks.take(5).toList())), isNull); // too few
      expect(decodeCustomTheme('${encodeCustomTheme(picks)},ff000000'), isNull); // too many
      expect(decodeCustomTheme('zz,zz,zz,zz,zz,zz,zz'), isNull); // not hex
      expect(decodeCustomTheme(encodeCustomTheme(picks)), isNotNull); // control
    });
  });
}
