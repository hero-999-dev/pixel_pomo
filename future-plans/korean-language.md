# Future plan: Korean (한국어) language

**Status:** removed from the app in v22 (2026-06-23). Parked here to revisit later.

## Why it was removed

Korean was one of the UI languages, but the **font never read right** next to the
Latin pixel font (Press Start 2P), and three rounds of tuning didn't satisfy:

1. **v22 first:** Press Start 2P primary + Galmuri11 *fallback*, no scale → Hangul
   inherited Press Start's metrics, so it sat off the baseline ("kayma") and looked
   too small.
2. **v22 polish:** Galmuri11 *primary* for the whole `ko` locale at ×1.15 → fixed the
   shift, but now **all** Korean-screen text (incl. English/numbers) was Galmuri and
   15% bigger → "uyumsuz" (didn't match the other languages).
3. **v22 "22v":** font chosen **per-string by content** (Hangul → Galmuri, Latin →
   Press Start) → cleaner, but the user decided Korean isn't worth more iteration
   right now and asked to drop it in favour of French.

## What still remains in the code (so re-adding is easy)

The per-string font machinery is **kept** — it's also what renders Latin-Extended
accents (Turkish ğ/ş/İ, Polish ł/ś, French é/ç…) via the Galmuri fallback:

- `flutter/lib/pixel.dart` — `hasHangul(s)` + `pixelStyle(..., text:)` still route
  Hangul strings to **Galmuri11** as primary.
- `flutter/assets/fonts/Galmuri11.ttf` (+ `Galmuri-OFL.txt`) still bundled (pubspec).
- `flutter/test/pixel_font_test.dart` still tests the Hangul→Galmuri routing.

## To restore Korean later

1. Add the `'ko'` block back to `_s` and `_months` in `flutter/lib/strings.dart`
   (the previous translations are in git history before the v22 "22v" commit).
2. Add `['ko', '한국어']` back to `languageOptions`.
3. Add `'ko'` entries to the three chart-label maps in `pixel.dart`
   (`_noData` / `_focus` / `_avg`).
4. Decide the Hangul **size** — the open question. Galmuri-as-primary at ×1.0 is the
   natural size; the user found ×1.15 (everywhere) too big, but per-string ×1.0–1.1
   for Hangul-only was never device-confirmed. Tune `pixelStyle`'s Hangul branch and
   verify on-device.

(Native Kotlin app still has its `values-ko/` — untouched; this note is about the
Flutter port, which is the one shipped.)
