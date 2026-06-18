# Pixel Pomo v11 — Full-screen living garden + camera / background mode

**Date:** 2026-06-18
**Version target:** Flutter `0.11.0+12` → release `flutter-v11`
**Scope:** one release, all pieces together (they interlock)

This is the Flutter port's v11. It implements the three v10-feedback requirements
the user gave: (1) make the garden a full-screen, portrait, screen-indexed world
instead of a small rectangle on a flat 2D image; (2) a peek button + a camera
mode that frames/screenshots the garden and sets a background; (3) the engine
must double as a live, wallpaper-style animated backdrop.

## Background: where v10 stands

- `flutter/lib/engine/garden_engine.dart` — `Projector` (assumes a single square
  size `n`), `GardenCamera` (zoom/pan/yaw, fixed tilt `kVy=0.60`), `SpriteBank`,
  `CritterSystem`, `GardenPainter`. The `forest` surround is painted **flat in
  screen space** (`paintImage(... repeat)`), NOT part of the 2.5D world.
- `flutter/lib/engine/garden_view.dart` — `GardenView` (Ticker + gestures +
  bottom-right `center_focus_strong` recenter button).
- `flutter/lib/main.dart` — `GardenScreen` (title + EXPAND + help + GardenView +
  CUSTOMIZE/CLOSE), `HomeScreen` (the pomodoro timer), `SettingsScreen`.
- `flutter/lib/logic.dart` — `Garden` (square `size`, `grow()` adds a centered
  ring), `Economy.upgradeCost`, `Placeables`, `Flowers`.

## Decisions locked with the user

1. **Wallpaper scope:** in-app live background + static export. No OS live
   wallpaper service (iOS has no API; Android would need native Kotlin that
   breaks the no-Mac CI). Export is via the system share sheet.
2. **Plot shape:** true rectangular `cols × rows`, starting **4×6** (portrait).
   EXPAND grows a centered ring (4×6 → 6×8 → 8×10 …).
3. **Full-screen model:** the plot fills the portrait viewport; the dark forest
   is the *unclaimed* border of the **same** 2.5D world and recedes as the
   garden expands.
4. **Camera tilt:** stays fixed (`kVy`). Framing uses existing yaw + zoom + pan
   only. No tilt/pitch axis (don't reintroduce the v6-removed tilt slider).
5. **Background placement:**
   - **Settings → Home-screen mode: `Clean` | `Garden`.** `Clean` = today's
     look. `Garden` = the **live animated** garden renders behind the pomodoro
     timer (critters wandering, wallpaper-engine feel).
   - The **static captured photo** is used **only inside the garden section**
     (as the garden screen's chosen backdrop) and/or exported. A frozen photo is
     never placed behind the running timer.

## Architecture

### A. One screen-filling 2.5D world (req #1) — the core change

Unify the floating plot and the flat forest into a single projected grid.

- **World grid:** the claimed `cols × rows` garden sits **centered** inside a
  larger world grid. Surrounding tiles are **forest** (dark ground + low-poly
  trees), drawn in the *same projection* so they tilt/yaw with everything.
- The world grid is sized so grass + a forest margin always fill the portrait
  viewport at fit-zoom; a visible forest ring remains around the claimed plot so
  expansion is seen converting trees → grass.
- **EXPAND** claims a centered ring: `cols+=2, rows+=2`, the claimed window
  shifts to stay centered, and a ring of forest tiles becomes grass. The camera
  re-fits.

**`Projector` generalization (square `n` → `cols, rows`):**
- `factory Projector.fit(cols, rows, cam, size)` — fits/fills the portrait
  viewport for a rectangular plot (replaces `min(w,h)/(n+1)`).
- `gridOf(c, r)` centers on `((cols-1)/2, (rows-1)/2)`.
- `corners()` uses `(cols/2, rows/2)` half-extents.
- `tileAt(p)` inverse-maps with both dims; returns `r*cols + c` (was `r*n+c`),
  range-checks against `cols, rows`.
- `gridToScreen()` affine unchanged in form (per-axis tile size is uniform), only
  the extents that feed it change.
- `GardenCamera.clamp(cols, rows, size)` uses rotated rectangular corners.

**`Garden` model (`logic.dart`):**
- Replace `int size` with `int cols, int rows`. Tile index = `r*cols + c`.
- `grow()` → `cols+=2; rows+=2`, re-index existing tiles into the recentred grid
  (shift `+1/+1`, same as v7's centered-ring logic but in 2D).
- Starting garden: `cols=4, rows=6`.
- `Economy.upgradeCost(cols, rows)` — formula tunable; default
  `2*(cols+rows)+1` so cost rises as the plot grows (analogue of the old
  `2n+1`). Cap: none (matches v6 "no size cap").
- Forest tiles are derived (world-minus-claimed), not stored per-tile.

**`GardenPainter`:**
- Draw the forest tiles (dark ground + tree props) as part of the projected
  ground/standing passes, replacing the flat screen-space `forest()` blit.
- Trees: low-poly billboards or simple `boxCorners` meshes reusing the v10 mesh
  pipeline; flat no-sun shading (consistent with v10).
- Claimed grass/soil-slab/roads/fences/flowers/critters render as today, just
  driven by `cols,rows` instead of `n`.

### B. Peek button — "just the garden" (req #2 part 1)

A bottom-**left** icon button in `GardenView`, mirroring the existing
bottom-right recenter button. Toggles a `peek` flag that hides ALL HUD on
`GardenScreen` (title, EXPAND, help, CUSTOMIZE/CLOSE) and both corner buttons,
leaving only the world. Tap again (or tap the scene) restores the HUD. Pure
Flutter, state lifted to `GardenScreen` (or `GardenView` exposing a callback).

### C. Camera mode + screenshot + background (req #2 part 2, req #3)

- **Entry:** a camera-mode icon button next to the peek button.
- **Framing:** enters camera mode — HUD hidden, existing twist-yaw / pinch-zoom /
  drag-pan for composition. Tilt fixed.
- **Capture:** wrap the scene in a `RepaintBoundary`; on capture call
  `boundary.toImage()` → PNG bytes. (Note: headless `flutter test` `toImage`
  hangs here — capture is verified on-device, not in unit tests.)
- **Post-capture actions:** *Set as garden backdrop* (store the PNG, see below),
  *Save / Share* (one `Share.shareXFiles` sheet → user saves to Photos / sets as
  wallpaper from there), *Cancel*.
- **Static garden backdrop:** captured PNG written to the app documents dir
  (`path_provider`), path stored in prefs; the garden section can display it as a
  static backdrop instead of (or framing) the live scene. Persists across
  launches.

### D. Live background behind the pomodoro timer (req #3)

- `SettingsScreen`: a new toggle **Home-screen mode: Clean | Garden**, stored in
  prefs (`AppStore`).
- When `Garden`, `HomeScreen` renders a **non-interactive** `GardenView` (its own
  Ticker for critters, gestures disabled) behind the timer widgets, dimmed for
  legibility. When `Clean`, the current theme background is used. This is the
  "engine doubles as a live wallpaper" deliverable; no OS wallpaper service.

### E. New dependencies (minimal, all CI/iOS-safe)

- `share_plus` — share sheet for export.
- `path_provider` — persist the static backdrop PNG.
- No gallery-saver and no wallpaper plugin (YAGNI; share sheet covers saving).

## Data flow

```
EXPAND ─▶ Garden.grow() (cols+=2,rows+=2, recenter) ─▶ AppStore notify ─▶ repaint
Camera capture ─▶ RepaintBoundary.toImage ─▶ PNG bytes
   ├─ Set as backdrop ─▶ write file (path_provider) ─▶ prefs path ─▶ garden section
   └─ Save/Share ─▶ share_plus sheet
Settings toggle ─▶ prefs homeMode ─▶ HomeScreen shows live GardenView or clean bg
```

## Testing (per the standing edge-test practice)

TDD where the logic is pure; visuals stay user-verified on-device (headless
`toImage` gotcha).

- **`Projector` (engine_test):** rectangular fit; `tileAt` ↔ `gridOf` inverse
  round-trips at several yaws for non-square `cols≠rows`; corner extents; clamp
  keeps a rectangular plot on-screen.
- **`Garden` (logic_test):** start = 4×6; `grow()` → 6×8 with existing tiles
  recentred (+1/+1) and indices remapped to `r*cols+c`; `propAt`/`groundAt`/
  `countPlanted` correct under rectangular indexing; `Economy.upgradeCost(cols,
  rows)` monotonic.
- **Forest/claimed:** a tile is claimed iff inside the centered `cols×rows`
  window; expansion converts the correct ring.
- **Background state:** prefs round-trip for `homeMode` and the backdrop path;
  default `homeMode = Clean`, no backdrop.
- **Smoke test:** boots app, opens garden, toggles peek, enters camera mode, sets
  Home mode = Garden — asserts no exception/overflow. (`GoldCoin.animate=false`
  and any new no-op hooks keep it settling, per v8/v9 pattern.)
- Update `TESTING.md` with cases covered, fixes, and the known gap (no golden
  test of the rendered world / camera capture).

## Deliverables (per the user's standing workflow)

- `log.md` — v11 entry (prompt + changes).
- `prompt.md` — refresh the recreation prompt to current state.
- `flutter/README.md` / root `README.md` — structure updates.
- `TESTING.md` — v11 results.
- A v11 memory in the Claude CLI memory store.
- Bump `pubspec.yaml` to `0.11.0+12`; commit & push `main` → CI builds APK +
  unsigned IPA, publishes `flutter-v11` + `latest-flutter` with release title
  `Flutter build (iOS + Android, vX.Y.Z)`.

## Out of scope (explicit YAGNI)

- True OS live-wallpaper service (Android `WallpaperService` / any iOS wallpaper).
- Adjustable camera tilt/pitch.
- Saving directly to the gallery without the share sheet; setting the phone
  wallpaper programmatically.
- Per-tile stored forest data (it's derived from claimed vs world).
- Showing the static photo behind the pomodoro timer.
