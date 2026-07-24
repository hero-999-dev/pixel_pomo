import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_pomo/logic.dart';
import 'package:pixel_pomo/main.dart' show kAllSwatches, kSwatches;

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

// ---- colour probes, for the "is this still the colour I picked?" tests ----

double _hue(int argb) {
  final r = ((argb >> 16) & 0xFF) / 255, g = ((argb >> 8) & 0xFF) / 255, b = (argb & 0xFF) / 255;
  final mx = [r, g, b].reduce((a, c) => a > c ? a : c);
  final mn = [r, g, b].reduce((a, c) => a < c ? a : c);
  final d = mx - mn;
  if (d == 0) return -1; // achromatic: no hue to preserve
  final h = mx == r ? (g - b) / d % 6 : (mx == g ? (b - r) / d + 2 : (r - g) / d + 4);
  return (h * 60 + 360) % 360;
}

/// How far apart two hues are on the colour wheel, in degrees.
double _hueGap(double a, double b) {
  final d = (a - b).abs() % 360;
  return d > 180 ? 360 - d : d;
}

/// RGB chroma, 0..1 — how much colour is left after a correction.
double _chroma(int argb) {
  final r = ((argb >> 16) & 0xFF) / 255, g = ((argb >> 8) & 0xFF) / 255, b = (argb & 0xFF) / 255;
  return [r, g, b].reduce((a, c) => a > c ? a : c) - [r, g, b].reduce((a, c) => a < c ? a : c);
}

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

    test('a preset with one pick changed is corrected like any other custom theme', () {
      // The editor seeds from whatever theme is on screen, so most custom
      // themes start life as a preset with a colour or two swapped. An
      // UNTOUCHED preset is passed through as itself (#v33.4, its own group
      // below) — DARK ships squares at 1.20 against its background, under the
      // 1.25 bar, and correcting the shipped themes was never the intent.
      for (final preset in Themes.all) {
        final th = PixelTheme.fromPicks(List.of(preset.picks)..[5] = 0xFF9D7CD8);
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

  // #v32.5 — "the colours don't feel like they landed; in places the picked
  // colour isn't the theme's". Two measured causes, one group each.
  group('a corrected pick is still the colour that was picked', () {
    test('correction moves lightness, never hue', () {
      // Blending toward black/white in RGB washes the colour out: a light
      // lavender used to come back grey. Whatever the correction does, the
      // result has to still read as the hue the user tapped.
      for (final bg in kSwatches) {
        for (final pick in kSwatches) {
          final hue = _hue(pick);
          if (hue < 0) continue; // greys have no hue to keep
          final got = nudgeContrast(pick, bg, kMinDimTextContrast);
          if (_chroma(got) < 0.02) {
            fail('pick ${pick.toRadixString(16)} on bg ${bg.toRadixString(16)} '
                'came back grey (${got.toRadixString(16)})');
          }
          expect(_hueGap(_hue(got), hue), lessThan(6.0),
              reason: 'pick ${pick.toRadixString(16)} on bg ${bg.toRadixString(16)} '
                  'shifted hue: ${got.toRadixString(16)}');
        }
      }
    });

    test('a colour that already clears the bar is returned untouched', () {
      expect(nudgeContrast(0xFFF7F7F7, 0xFF0B0B0B, kMinTextContrast), 0xFFF7F7F7);
    });

    test('the guarantee survives: every corrected pick still clears its bar', () {
      for (final bg in kSwatches) {
        for (final pick in kSwatches) {
          expect(contrastRatio(nudgeContrast(pick, bg, kMinDimTextContrast), bg),
              greaterThanOrEqualTo(kMinDimTextContrast));
        }
      }
    });
  });

  group('the text colours read on the squares, not just the background', () {
    // Every button draws onSurface as its label and onSurfaceDim as its border,
    // both on a `panel` fill — but the theme corrects them against `bg`, so a
    // pick could pass on the background and vanish on a button. Demanding one
    // colour clear both surfaces is often unsatisfiable (a mid-tone background
    // beside a dark panel admits no such colour at 4.5), so PixelButton
    // corrects against its own fill instead. These lock that this always works.
    test('a heading still reads on the background', () {
      for (final bg in kSwatches) {
        for (final text in kSwatches) {
          final th = PixelTheme.fromPicks(
              [bg, text, text, 0xFFE5484D, 0xFF2B2B2B, 0xFF58A6FF, 0xFF46A03C]);
          expect(contrastRatio(th.onSurface, th.bg), greaterThanOrEqualTo(kMinTextContrast));
          expect(contrastRatio(th.onSurfaceDim, th.bg), greaterThanOrEqualTo(kMinDimTextContrast));
        }
      }
    });

    // KNOWN GAP, deliberately not asserted: picking the same colour for FAINT
    // TEXT and PANELS leaves a button's 3px border invisible against its own
    // fill. Correcting the dim colour against `panel` as well as `bg` is what
    // that would take, and those two bars are frequently unsatisfiable together
    // — a mid-tone background beside a dark panel admits no colour clearing 3.0
    // on both. Left alone until someone actually picks that pair and minds.
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

  group('a preset loaded in the editor stays that preset (#v33.4)', () {
    /// Every colour a screen can actually paint with, so nothing hides behind
    /// a field the comparison forgot.
    List<int> colours(PixelTheme t) => [
          t.bg, t.panel, t.accent, t.work, t.breakColor,
          t.onSurface, t.onSurfaceDim, t.onAccent, t.shadow, t.focusTint,
        ];

    test('every preset survives the round trip through the picks', () {
      for (final preset in Themes.all) {
        final built = PixelTheme.fromPicks(preset.picks);
        expect(built.id, customThemeId, reason: 'it is still the user theme slot');
        expect(colours(built), colours(preset),
            reason: '${preset.id} came back a different theme — the whole '
                '"pressing LATTE in custom is not LATTE" report');
      }
    });

    test('changing one pick goes back to the derivation, and still reads', () {
      final picks = List.of(Themes.latte.picks)..[5] = 0xFF9D7CD8; // BREAK → purple
      final th = PixelTheme.fromPicks(picks);
      expect(th.breakColor, isNot(Themes.latte.breakColor));
      expect(th.bg, Themes.latte.bg, reason: 'the untouched picks are still latte');
      expectReadable(th);
    });

    test("a light theme's shadow stays a tint of its own background", () {
      // latte with one pick changed, so it takes the derived path on purpose
      final light = PixelTheme.fromPicks(List.of(Themes.latte.picks)..[6] = 0xFF46A03C);
      expect(contrastRatio(light.shadow, light.bg), lessThan(1.6),
          reason: 'a cream theme got hard black bars under its buttons');
      // a dark theme still wants its near-black edge
      final dark = PixelTheme.fromPicks(List.of(Themes.dark.picks)..[6] = 0xFF46A03C);
      expect(contrastRatio(dark.shadow, dark.bg), lessThan(2.0));
      expect(dark.shadow, lessThan(0xFF202020), reason: 'dark themes keep a near-black shadow');
    });
  });

  group('colour wheel maths (#v33.5)', () {
    test('the rim is the hue, the centre has no colour left', () {
      expect(wheelHueSat(50, 0, 50)[0], closeTo(0, 0.001), reason: 'right of centre is hue 0');
      // screen y grows downward, so the wheel reads clockwise from there
      expect(wheelHueSat(0, 50, 50)[0], closeTo(90, 0.001));
      expect(wheelHueSat(-50, 0, 50)[0], closeTo(180, 0.001));
      expect(wheelHueSat(0, -50, 50)[0], closeTo(270, 0.001));
      expect(wheelHueSat(50, 0, 50)[1], closeTo(1, 0.001), reason: 'the rim is full saturation');
      expect(wheelHueSat(0, 0, 50)[1], 0, reason: 'the centre is grey');
      expect(wheelHueSat(25, 0, 50)[1], closeTo(0.5, 0.001));
    });

    test('a drag off the edge keeps picking instead of sticking', () {
      expect(wheelHueSat(500, 0, 50)[1], 1);
      expect(wheelHueSat(0, 0, 0)[1], 0, reason: 'a zero-radius wheel must not divide by zero');
    });

    test('HSL round trips, so opening the picker lands on the colour it was given', () {
      for (final c in kAllSwatches) {
        final hsl = hslOf(c);
        final back = colorFromHsl(hsl[0], hsl[1], hsl[2]);
        expect(back, c, reason: '#${c.toRadixString(16)} did not survive the round trip');
      }
    });

    test('the bar ends are black and white for every hue', () {
      for (var h = 0.0; h < 360; h += 45) {
        expect(colorFromHsl(h, 1, 0), 0xFF000000);
        expect(colorFromHsl(h, 1, 1), 0xFFFFFFFF);
      }
    });
  });

  group('palette order (#v33.4)', () {
    test('the teal is a full trio now — 28 base swatches', () {
      expect(kSwatches.length, 28);
      for (final teal in [0xFF14504B, 0xFF1E9E92, 0xFF9BE0D8]) {
        expect(kSwatches, contains(teal));
      }
    });

    test('the whole palette is one sorted run, every colour once', () {
      final keys = [for (final c in kAllSwatches) swatchOrder(c)];
      expect(keys, orderedEquals(List.of(keys)..sort()),
          reason: 'the preset colours were appended in theme order, not colour order');
      expect(kAllSwatches.toSet().length, kAllSwatches.length, reason: 'a duplicate cell is wasted');
      for (final c in kSwatches) {
        expect(kAllSwatches, contains(c));
      }
    });

    test('greys come first, darkest to lightest, and no hue lands among them', () {
      const greys = [0xFF0B0B0B, 0xFF2B2B2B, 0xFF565656, 0xFF8E8E8E, 0xFFCFCFCF, 0xFFF7F7F7];
      for (var i = 1; i < greys.length; i++) {
        expect(swatchOrder(greys[i]), greaterThan(swatchOrder(greys[i - 1])));
      }
      for (final c in kAllSwatches.where((c) => !greys.contains(c))) {
        // every hue sorts after every grey; other near-greys may join the ramp
        if (swatchOrder(c) < swatchOrder(greys.last)) {
          expect(swatchOrder(c), lessThan(1.0), reason: 'a hue sorted into the grey ramp');
        }
      }
    });

    test('a dark/mid/light family shares one place in the order', () {
      const families = [
        [0xFF7A1F2B, 0xFFE5484D, 0xFFF7A8AC], // red
        [0xFF7A4212, 0xFFE8801E, 0xFFF5C48A], // orange
        [0xFF6E5A10, 0xFFE8C547, 0xFFF6E9A8], // yellow
        [0xFF14504B, 0xFF1E9E92, 0xFF9BE0D8], // teal
        [0xFF1B3A63, 0xFF58A6FF, 0xFFBBD9FF], // blue
        [0xFF422A63, 0xFF9D7CD8, 0xFFD9C7F5], // purple
      ];
      for (final family in families) {
        final bins = {for (final c in family) swatchOrder(c).floor()};
        expect(bins.length, 1, reason: 'family $family split across the palette');
        // and inside the family, dark sorts before light
        expect(swatchOrder(family[0]), lessThan(swatchOrder(family[1])));
        expect(swatchOrder(family[1]), lessThan(swatchOrder(family[2])));
      }
    });

    test('the wheel runs red → orange → yellow → green → teal → blue → purple', () {
      const wheel = [0xFFE5484D, 0xFFE8801E, 0xFFE8C547, 0xFF46A03C, 0xFF1E9E92, 0xFF58A6FF, 0xFF9D7CD8];
      for (var i = 1; i < wheel.length; i++) {
        expect(swatchOrder(wheel[i]), greaterThan(swatchOrder(wheel[i - 1])),
            reason: 'the palette is not in colour-wheel order at index $i');
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
