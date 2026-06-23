# v22 polish — Korean font, full-bleed camera, wallpaper zoom, rose remake

**Date:** 2026-06-22
**Version:** stays **0.22.0+23** — no bump (user: "yeni versiyona geçmeden işimizi halledelim"). Delivery = local release APK re-clobbering the `flutter-v22` release (CI minutes still out).
**Scope:** 4 device-feedback items. Flowers = **ROSE ONLY** — the other 9 flowers are untouched this round; the same method gets applied to them in a later round (user: "ilk olarak tek bir çiçeği mükemmelleştirmeye çalışıyorum").

---

## 1. Korean font — `flutter/lib/pixel.dart`

**Problem:** residual baseline "kayma" (shift) + Korean glyphs too small.
**Cause:** `pixelStyle` uses `PressStart2P` primary + `Galmuri11` fallback; the Hangul fallback glyphs sit off the PressStart2P line box (mixed metrics) and render smaller at the same `fontSize`.
**Change:** in `pixelStyle`, when `lang == 'ko'`, use `fontFamily: 'Galmuri11'` (its own metrics → no shift) with `PressStart2P` as fallback, and a modest size bump (`size * 1.15`). All other languages keep `PressStart2P` primary, unchanged. No global scale (avoids the v22 ×1.5 regression that bloated Latin).
**Done when:** Korean screens render a tick larger with aligned baselines; Latin languages render byte-identically to now.

## 2. Full-bleed camera mode — `flutter/lib/main.dart` (`_GardenScreenState`)

**Problem:** in camera mode a dark `th.bg` band sits below CAPTURE/CANCEL and a gray system-bar strip remains; the garden doesn't reach the bottom edge.
**Change:** in camera mode only, replace `Column[Expanded(GardenView), Padding(Row[CAPTURE,CANCEL])]` with a `Stack` filling the Scaffold body: `Positioned.fill(GardenView)` (edge-to-edge forest) + a bottom-anchored floating `Row[CAPTURE,CANCEL]` wrapped in `SafeArea` (buttons clear the nav bar; the garden still paints behind/below them). Non-camera customize/peek layout unchanged.
**Done when:** camera mode shows forest from top edge to bottom edge; no black band under the buttons, no gray strip; CAPTURE/CANCEL float over the scene.

## 3. Wallpaper zoom + critters — `flutter/android_overlay/.../GardenRenderer.kt`

**Problem:** bugs stay one size ("böcekler hep aynı boyutta"); scene feels far/small when zoomed.
**Changes:**
- (a) Critter size: replace `(t*0.42).coerceIn(12.0, 30.0)` with a `t`-proportional size (drop the 30px upper cap, keep a small lower floor) so critters grow with zoom.
- (b) Framing fidelity (free from item 2): the in-app capture boundary becomes full-screen, matching the wallpaper surface aspect → "what you frame = what you get" (no extra forest top/bottom). Zoom is already persisted (`wallpaper_cam`) and applied (`t = min(fitW,fitH) * cam.zoom`).
**Device-verify after:** if still too far, raise max zoom (4→6) in `garden_view.dart _onScaleUpdate` and/or add a small wallpaper zoom bias.
**Done when:** on device, zooming before set yields a correspondingly closer wallpaper, and bugs scale with the zoom.

## 4. Rose remake — 3 variants — `flutter/tools/gen_objects.py`, `flutter/lib/logic.dart`

**Problem:** the current 4 roses are blobby and read uniformly; remake to the ChatGPT 4-rose reference quality. **3 variants** (not 4 — user: "4 çeşit fazla geldi").
**Approach (hybrid modular):** shared `outline` + a tightened palette (**3 reds**: dark/mid/light, plus the dark outline; **2 greens**: stem, leaf) + shared `_ROSE_STEM`/leaf module; **3 distinct bloom silhouettes** authored to match the reference — side bud / front spiral / open bloom — with clean petal + spiral structure, strong silhouette, 16px, no anti-alias. Single decorative sprite (no growth stages).
**Plumbing:** `Flowers.variantCounts['gul'] = 3` (was 4); regenerate `flower_gul_0..2.png` + `flower_gul.png` (= variant 0 = shop thumbnail + fallback); delete the stale `flower_gul_3.png`. Dart `SpriteBank.flower` / Kotlin `flowerBitmap` already resolve `gul~N` with fallback (keep parity). The same pipeline must stay reusable for the other 9 flowers later.
**Verification:** render each generated PNG on-machine and view it, compare to the reference, iterate until the 3 read as one species in 3 clean distinct shapes; then plant-test in the garden.
**Done when:** 3 cohesive, clearly-distinct roses matching the reference cozy style; `variantCounts` = 3; tests updated and green.

---

## Out of scope (deferred)
- The other 9 flowers (same method, later round).
- App blocker (its own round, v23+).
- Optional: legacy plain-`gul` tiles rendering varied variants by tile hash — only if the user asks (default: no, keep focus on rose quality).

## Tests / verification
- `flutter analyze` clean.
- Dart tests: update the `gul` variant-count assertion (4→3); suite stays green (was 60).
- `flutter build apk --release` locally → upload to `flutter-v22` (no version bump).
- Visual items (Korean, camera, wallpaper) device-verified by the user; rose PNGs self-verified on-machine by rendering; rose-in-garden device-verified.
- Update `log.md` / `prompt.md` / `TESTING.md` per the project loop.
