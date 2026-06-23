import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_pomo/pixel.dart';

/// Content-based font selection (#v22 round 3): Latin text stays Press Start 2P in
/// every language; only Hangul-bearing strings switch to Galmuri11 as the primary
/// face (its own metrics → aligned baseline, natural size). No per-language scale.
void main() {
  group('content-based font (#v22 Korean)', () {
    test('hasHangul flags Korean glyphs only', () {
      expect(hasHangul('설정'), isTrue); // syllables
      expect(hasHangul('집중 (분)'), isTrue); // mixed Hangul + Latin punctuation
      expect(hasHangul('한국어'), isTrue);
      expect(hasHangul('English'), isFalse);
      expect(hasHangul('25'), isFalse);
      expect(hasHangul('ON'), isFalse);
      expect(hasHangul('Türkçe'), isFalse); // accented Latin is NOT Hangul
    });

    test('Latin text → Press Start 2P primary (Galmuri fallback), even in ko', () {
      final s = pixelStyle('ko', 12, const Color(0xFFFFFFFF), text: 'English');
      expect(s.fontFamily, 'PressStart2P');
      expect(s.fontFamilyFallback, contains('Galmuri11'));
    });

    test('Hangul text → Galmuri11 primary (Press Start fallback)', () {
      final s = pixelStyle('ko', 12, const Color(0xFFFFFFFF), text: '설정');
      expect(s.fontFamily, 'Galmuri11');
      expect(s.fontFamilyFallback, contains('PressStart2P'));
    });

    test('no text given → Latin-primary default (safe for any locale)', () {
      final s = pixelStyle('ko', 12, const Color(0xFFFFFFFF));
      expect(s.fontFamily, 'PressStart2P');
    });

    test('no size bump — Korean matches the other languages\' size', () {
      final ko = pixelStyle('ko', 14, const Color(0xFF000000), text: '집중');
      final en = pixelStyle('en', 14, const Color(0xFF000000), text: 'FOCUS');
      expect(ko.fontSize, en.fontSize);
    });
  });
}
