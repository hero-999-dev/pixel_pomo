# Pixel Pomo v11 — Full-screen garden + camera/background — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the floating square garden plot into a full-screen, portrait, rectangular (4×6) 2.5D world whose forest border recedes as the plot expands, and add a peek button + camera mode (frame → screenshot → set-as-garden-backdrop / share) plus a Settings `Clean|Garden` home-screen toggle that puts the live garden behind the pomodoro timer.

**Architecture:** One projected grid fills the viewport; the claimed `cols×rows` garden is centered, surrounding tiles render as in-world forest. `Projector`/`Garden`/`GardenPainter`/`GardenView` generalize from one square `size` to `(cols, rows)`. Camera capture uses `RepaintBoundary.toImage`; export via `share_plus`; static backdrop persisted via `path_provider`. The live home backdrop reuses a non-interactive `GardenView`.

**Tech Stack:** Flutter 3.44.2 / Dart 3.12.2, `shared_preferences`, new: `share_plus`, `path_provider`. Pure-logic in `logic.dart` (framework-free), custom `Canvas` engine in `lib/engine/`.

## Global Constraints

- Project root: `C:\Users\claude\pixel_pomo`. All Flutter paths below are under `flutter/`.
- Run Flutter as `& C:\src\flutter\bin\flutter.bat` if `flutter` isn't on PATH. Build/test commands run from `flutter/`.
- Tests are a CI gate: `flutter analyze` must be clean and `flutter test` must pass before every commit. Current suite = 26 tests (20 logic + 3 engine + 3 placeable-overlay) + smoke; this plan adds to it.
- Pure logic stays in `logic.dart` with **no Flutter imports**. Camera capture/`toImage` is visual and **cannot** be unit-tested here (headless `toImage` hangs) — verify on-device; test only the surrounding pure logic + prefs.
- 6 languages must stay in sync: any new UI string gets keys in all of en/tr/pl/de/ko/it in `lib/strings.dart`.
- Camera tilt stays FIXED (`kVy=0.60`); do not add a tilt/pitch axis. Framing = yaw + zoom + pan only.
- Static captured photo is shown ONLY in the garden section, never behind the pomodoro timer. The timer backdrop is the LIVE garden only.
- New deps must build under `flutter build ios --no-codesign` on the macOS CI (share_plus, path_provider both qualify).
- Final version bump: `pubspec.yaml` → `0.11.0+12`. Release title format stays `Flutter build (iOS + Android, vX.Y.Z)`.
- No `Co-Authored-By: Claude` / AI-attribution trailer on commits.

## File Structure

- `flutter/lib/logic.dart` — MODIFY `Garden` (square `size` → `cols`,`rows`), `Economy` (rect cost + base dims). Pure.
- `flutter/lib/engine/garden_engine.dart` — MODIFY `Projector` (rect, fills screen), `GardenCamera.clamp`, `GardenPainter` (forest as in-world tiles + `cols,rows`), add tree drawing.
- `flutter/lib/engine/garden_view.dart` — MODIFY to use `cols,rows`; add peek + camera-mode buttons; add `RepaintBoundary` + capture callback; add a non-interactive backdrop mode.
- `flutter/lib/store.dart` — MODIFY `upgradeGarden`; add `homeMode`, `gardenBackdropPath` state + persistence + setters.
- `flutter/lib/main.dart` — MODIFY `GardenScreen` (rect, peek HUD-hide, camera flow), `HomeScreen` (live backdrop when `Garden`), `SettingsScreen` (Clean|Garden toggle).
- `flutter/lib/strings.dart` — ADD keys (peek, camera, capture, share, setBackdrop, homeMode/clean/garden) ×6 langs.
- `flutter/tools/gen_objects.py` — ADD a `tree` sprite for the forest; emit `tree.png`.
- `flutter/assets/objects/tree.png` — GENERATED.
- `flutter/pubspec.yaml` — ADD deps; bump version.
- `flutter/test/logic_test.dart`, `flutter/test/engine_test.dart`, `flutter/test/widget_smoke_test.dart` — extend.
- Root docs: `log.md`, `prompt.md`, `README.md`, `flutter/README.md`, `TESTING.md`.

---

### Task 1: Rectangular garden model (logic.dart) + all call sites

Generalize `Garden` from one square `size` to `cols × rows` (start 4×6), keeping the whole app compiling and behaving as before (just rectangular). This is the foundational refactor: it touches `logic.dart`, `store.dart`, the engine, the view, and `main.dart` together because they all read `garden.size`.

**Files:**
- Modify: `flutter/lib/logic.dart` (`Garden`, `Economy`)
- Modify: `flutter/lib/engine/garden_engine.dart` (`Projector`, `GardenCamera`, `GardenPainter` — swap `n`→`cols,rows`)
- Modify: `flutter/lib/engine/garden_view.dart` (pass `cols,rows`)
- Modify: `flutter/lib/store.dart` (`upgradeGarden`)
- Modify: `flutter/lib/main.dart:596,613` (`Economy.upgradeCost`, `s.upgradeGarden`)
- Test: `flutter/test/logic_test.dart`, `flutter/test/engine_test.dart`

**Interfaces:**
- Produces (`Garden`): `int cols`, `int rows`; `int get tileCount => cols*rows`; `bool isValidIndex(int)`; `Garden grow()` (cols+=2, rows+=2, recenter); index = `r*cols+c`. Constructor `Garden({int cols, int rows, Map<int,String> tiles})`. `encode()`/`decode()` use `cols:`/`rows:` lines and migrate a legacy `size:` line to a square `cols=rows=size`.
- Produces (`Economy`): `int upgradeCost(int cols, int rows) => 2*(cols+rows)+1`; `const baseGardenCols=4`, `const baseGardenRows=6`.
- Produces (`Projector`): constructor `Projector(int cols, int rows, double t, Offset center, double yaw)`; `factory Projector.fit(int cols, int rows, GardenCamera cam, Size size)`; `gridOf(c,r)` centers on `((cols-1)/2,(rows-1)/2)`; `tileAt` returns `r*cols+c`; `corners()` half-extents `(cols/2, rows/2)`.
- Produces (`GardenCamera`): `clamp(int cols, int rows, Size size)`.

- [ ] **Step 1: Write failing logic tests**

In `flutter/test/logic_test.dart`, replace the `Economy + Garden` group's size-based assertions with rectangular ones. Add/replace these tests:

```dart
test('coinsFor / upgradeCost (rectangular)', () {
  expect(Economy.coinsFor(0), 0);
  expect(Economy.coinsFor(25), 5);
  expect(Economy.upgradeCost(4, 6), 21); // 2*(4+6)+1
  expect(Economy.upgradeCost(6, 8), 29);
});

test('garden starts 4x6 and grows as a centred ring', () {
  const g = Garden();
  expect(g.cols, 4);
  expect(g.rows, 6);
  expect(g.tileCount, 24);

  // plant at (col 1,row 2) = index 2*4+1 = 9
  final grown = g.plant(9, 'lale').grow();
  expect(grown.cols, 6);
  expect(grown.rows, 8);
  // (1,2) drifts to (2,3) = 3*6+2 = 20
  expect(grown.propAt(20), 'lale');
  final decoded = Garden.decode(grown.encode());
  expect(decoded.cols, 6);
  expect(decoded.rows, 8);
  expect(decoded.propAt(20), 'lale');
});

test('garden decode migrates a legacy square size: line', () {
  final d = Garden.decode('size:5\n0:gul');
  expect(d.cols, 5);
  expect(d.rows, 5);
  expect(d.propAt(0), 'gul');
});

test('garden decode drops out-of-range tiles', () {
  final d = Garden.decode('cols:4\nrows:6\n99:gul\n9:lale');
  expect(d.tiles.containsKey(99), false);
  expect(d.propAt(9), 'lale');
});
```

Also update the existing "grows with no cap; stays centred" test to rectangular:

```dart
test('garden grows with no cap; stays centred', () {
  var g = const Garden().plant(0, 'gul'); // (0,0)
  for (var i = 0; i < 10; i++) {
    g = g.grow();
  }
  expect(g.cols, 4 + 20);
  expect(g.rows, 6 + 20);
  // (0,0) drifts +10/+10 → (10,10) = 10*g.cols + 10
  expect(g.propAt(10 * g.cols + 10), 'gul');
});
```

- [ ] **Step 2: Write failing engine tests**

In `flutter/test/engine_test.dart`, update existing `Projector(6, ...)` constructors to `Projector(6, 6, ...)` (square, same behavior) and add a rectangular round-trip group:

```dart
group('Projector rectangular tile mapping', () {
  test('tileAt inverts gridOf for a non-square plot at several yaws', () {
    const cols = 4, rows = 6, t = 40.0;
    const center = Offset(200, 400);
    for (final yaw in [0.0, 0.6, 1.9, -1.2]) {
      final p = Projector(cols, rows, t, center, yaw);
      for (var r = 0; r < rows; r++) {
        for (var c = 0; c < cols; c++) {
          final screen = p.projectGrid(p.gridOf(c, r));
          expect(p.tileAt(screen), r * cols + c, reason: 'yaw=$yaw ($c,$r)');
        }
      }
    }
  });

  test('fit fills the portrait viewport and centres the plot', () {
    final cam = GardenCamera();
    const size = Size(360, 720);
    final p = Projector.fit(4, 6, cam, size);
    expect(p.center.dx, closeTo(180, 0.001));
    final cs = p.corners();
    final minX = cs.map((o) => o.dx).reduce(math.min);
    final maxX = cs.map((o) => o.dx).reduce(math.max);
    // the 4-wide plot spans essentially the full width at fit-zoom
    expect(maxX - minX, greaterThan(size.width * 0.8));
  });
});
```

- [ ] **Step 3: Run tests, verify they fail**

Run: `& C:\src\flutter\bin\flutter.bat test test/logic_test.dart test/engine_test.dart`
Expected: FAIL — `cols`/`rows` undefined, `upgradeCost` arity wrong, `Projector` positional-arg mismatch.

- [ ] **Step 4: Rewrite `Garden` + `Economy` in `logic.dart`**

Replace the `Economy` size members and the entire `Garden` class:

```dart
class Economy {
  static const flowerCost = 10;
  static const objectCost = 5; // roads + fences
  static const baseGardenCols = 4;
  static const baseGardenRows = 6;
  static int coinsFor(int minutes) => minutes <= 0 ? 0 : minutes ~/ 5;
  static int upgradeCost(int cols, int rows) => 2 * (cols + rows) + 1;

  static int costOf(String id) => Placeables.isObject(id) ? objectCost : flowerCost;
}
```

```dart
class Garden {
  final int cols;
  final int rows;
  final Map<int, String> tiles;
  const Garden({
    this.cols = Economy.baseGardenCols,
    this.rows = Economy.baseGardenRows,
    this.tiles = const {},
  });

  int get tileCount => cols * rows;
  bool isValidIndex(int i) => i >= 0 && i < tileCount;

  String? flowerAt(int i) => tiles[i];
  String? groundAt(int i) => Placeables.groundOf(tiles[i]);
  String? propAt(int i) => Placeables.propOf(tiles[i]);

  Garden plant(int index, String id) {
    if (!isValidIndex(index) || id.trim().isEmpty) return this;
    final current = tiles[index];
    final (road, prop) = current == null ? (null, null) : Placeables.split(current);
    final String value;
    if (Placeables.isRoad(id)) {
      final keepFence = prop != null && Placeables.isFence(prop) ? prop : null;
      value = Placeables.combine(id, keepFence);
    } else if (Placeables.isFence(id)) {
      value = Placeables.combine(road, id);
    } else {
      if (road != null) return this;
      value = id;
    }
    return Garden(cols: cols, rows: rows, tiles: {...tiles, index: value});
  }

  Garden clear(int index) {
    if (!tiles.containsKey(index)) return this;
    final next = {...tiles}..remove(index);
    return Garden(cols: cols, rows: rows, tiles: next);
  }

  /// Expand by one tile on every side: the plot grows centred, existing tiles
  /// shift by (+1 col, +1 row) into the larger grid.
  Garden grow() {
    final nc = cols + 2;
    final nr = rows + 2;
    final remapped = <int, String>{};
    tiles.forEach((index, id) {
      final r = index ~/ cols;
      final c = index % cols;
      remapped[(r + 1) * nc + (c + 1)] = id;
    });
    return Garden(cols: nc, rows: nr, tiles: remapped);
  }

  int countPlanted(String flowerId) => tiles.values.where((v) {
        final (road, prop) = Placeables.split(v);
        return road == flowerId || prop == flowerId;
      }).length;

  String encode() {
    final b = StringBuffer('cols:$cols\nrows:$rows');
    final keys = tiles.keys.toList()..sort();
    for (final k in keys) {
      b.write('\n$k:${tiles[k]}');
    }
    return b.toString();
  }

  static Garden decode(String? text) {
    if (text == null || text.trim().isEmpty) return const Garden();
    var cols = Economy.baseGardenCols;
    var rows = Economy.baseGardenRows;
    final tiles = <int, String>{};
    for (final line in text.split('\n')) {
      if (line.trim().isEmpty) continue;
      final i = line.indexOf(':');
      if (i < 0) continue;
      final key = line.substring(0, i).trim();
      final value = line.substring(i + 1).trim();
      if (key == 'size') {
        final s = int.tryParse(value); // legacy square gardens
        if (s != null && s >= 1) {
          cols = s;
          rows = s;
        }
      } else if (key == 'cols') {
        final s = int.tryParse(value);
        if (s != null && s >= 1) cols = s;
      } else if (key == 'rows') {
        final s = int.tryParse(value);
        if (s != null && s >= 1) rows = s;
      } else {
        final idx = int.tryParse(key);
        if (idx != null && idx >= 0 && value.isNotEmpty) tiles[idx] = value;
      }
    }
    tiles.removeWhere((k, v) => k >= cols * rows);
    return Garden(cols: cols, rows: rows, tiles: tiles);
  }
}
```

- [ ] **Step 5: Generalize `Projector` + `GardenCamera` in `garden_engine.dart`**

Change `Projector` to carry `cols`/`rows` instead of `n`:

```dart
class Projector {
  final int cols;
  final int rows;
  final double t;
  final Offset center;
  final double yaw;
  late final double _cos = math.cos(yaw);
  late final double _sin = math.sin(yaw);

  Projector(this.cols, this.rows, this.t, this.center, this.yaw);

  /// Fit-to-fill: size the tile so the longer plot axis fills the viewport
  /// (portrait → rows usually dominate), then apply zoom.
  factory Projector.fit(int cols, int rows, GardenCamera cam, Size size) {
    final fitW = size.width / (cols + 0.5);
    final fitH = size.height / ((rows + 0.5) * kVy);
    final t = math.min(fitW, fitH) * cam.zoom;
    return Projector(cols, rows, t,
        Offset(size.width / 2 + cam.panX, size.height / 2 + cam.panY), cam.yaw);
  }

  static double slabFor(double t) => t * 0.32 + 6;

  Offset projectGrid(Offset g) {
    final rx = g.dx * _cos - g.dy * _sin;
    final ry = g.dx * _sin + g.dy * _cos;
    return Offset(center.dx + rx * t, center.dy + ry * t * kVy);
  }

  Offset projectElevated(Offset g, double e) => projectGrid(g).translate(0, -e * t);

  Offset gridOf(int c, int r) =>
      Offset(c - (cols - 1) / 2.0, r - (rows - 1) / 2.0);
  Offset ground(int c, int r) => projectGrid(gridOf(c, r));
  Offset groundIndex(int i) => ground(i % cols, i ~/ cols);

  int tileAt(Offset p) {
    final dx = (p.dx - center.dx) / t;
    final dy = (p.dy - center.dy) / (t * kVy);
    final gx = dx * _cos + dy * _sin;
    final gy = -dx * _sin + dy * _cos;
    final c = (gx + (cols - 1) / 2.0).round();
    final r = (gy + (rows - 1) / 2.0).round();
    if (c < 0 || r < 0 || c >= cols || r >= rows) return -1;
    return r * cols + c;
  }

  List<Offset> corners() {
    final hx = cols / 2.0, hy = rows / 2.0;
    return [
      projectGrid(Offset(-hx, -hy)),
      projectGrid(Offset(hx, -hy)),
      projectGrid(Offset(hx, hy)),
      projectGrid(Offset(-hx, hy)),
    ];
  }

  Float64List gridToScreen() {
    final m = Float64List(16);
    m[0] = t * _cos;
    m[1] = t * kVy * _sin;
    m[4] = -t * _sin;
    m[5] = t * kVy * _cos;
    m[10] = 1;
    m[12] = center.dx;
    m[13] = center.dy;
    m[15] = 1;
    return m;
  }
}
```

Update `GardenCamera.clamp` signature and body:

```dart
void clamp(int cols, int rows, Size size) {
  final p = Projector.fit(cols, rows, this, size);
  var mx = 0.0, my = 0.0;
  for (final c in p.corners()) {
    mx = math.max(mx, (c.dx - p.center.dx).abs());
    my = math.max(my, (c.dy - p.center.dy).abs());
  }
  final slab = Projector.slabFor(p.t);
  final maxX = math.max(0.0, mx - size.width / 2);
  final maxY = math.max(0.0, my + slab - size.height / 2);
  panX = panX.clamp(-maxX, maxX);
  panY = panY.clamp(-maxY, maxY);
}
```

- [ ] **Step 6: Update `GardenPainter` to use `cols,rows`**

In `garden_engine.dart`, the painter currently does `final _n = garden.size;` and loops `r<_n`, `c<_n`, `r*_n+c`, and calls `Projector.fit(_n, ...)`. Replace `_n` usage:

- Add getters: `int get _cols => garden.cols; int get _rows => garden.rows;`
- `final p = Projector.fit(_cols, _rows, cam, size);`
- Loops: `for (var r=0; r<_rows; r++) for (var c=0; c<_cols; c++)` with `index = r*_cols + c`.
- Grid extents in `_paintGrid` use `hx=_cols/2`, `hy=_rows/2` and iterate `i<=_cols` / `i<=_rows` separately for the two line families.
- The ground affine clip `gridRect` becomes `Rect.fromLTWH(-_cols/2, -_rows/2, _cols.toDouble(), _rows.toDouble())`.
- Fence-neighbour helper `fence(idx)` range check: `idx>=0 && idx<_cols*_rows`; E-neighbour guard `c < _cols-1`, S-neighbour guard `r < _rows-1`, index `r*_cols+c`.

(No behavior change yet — forest still painted flat in screen space; that moves in Task 2.)

- [ ] **Step 7: Update `garden_view.dart` call sites**

Replace `widget.garden.size` usages: `_cam.clamp(widget.garden.cols, widget.garden.rows, _lastSize)` (two places: `_onScaleUpdate`, `build`), and `Projector.fit(widget.garden.cols, widget.garden.rows, _cam, _lastSize)` in `_onTapUp`. In `_flowerTargets()` replace `final n = widget.garden.size;` with `final cols = widget.garden.cols;` and compute `Offset(i % cols - (cols-1)/2.0, i ~/ cols - (rows-1)/2.0)` using `final rows = widget.garden.rows;`. In the ticker `_critters.step(dt, widget.garden.size, ...)` — `CritterSystem.step` still takes a single `n` used only for spawn radius; pass `math.max(cols, rows)` and add `import 'dart:math' as math;` if absent.

- [ ] **Step 8: Update `store.dart` + `main.dart`**

`store.dart` `upgradeGarden`: `final cost = Economy.upgradeCost(garden.cols, garden.rows);`
`main.dart:596`: `final cost = Economy.upgradeCost(s.garden.cols, s.garden.rows);` (GardenScreen build).

- [ ] **Step 9: Run analyze + tests, verify pass**

Run: `& C:\src\flutter\bin\flutter.bat analyze` then `& C:\src\flutter\bin\flutter.bat test`
Expected: analyze clean; all tests pass (logic + engine rectangular + existing smoke/overlay).

- [ ] **Step 10: Commit**

```bash
git add flutter/lib/logic.dart flutter/lib/engine/garden_engine.dart flutter/lib/engine/garden_view.dart flutter/lib/store.dart flutter/lib/main.dart flutter/test/logic_test.dart flutter/test/engine_test.dart
git commit -m "v11: rectangular garden model (cols x rows, start 4x6) + projector"
```

---

### Task 2: Full-screen world with in-world receding forest

Replace the flat screen-space `forest()` blit with forest tiles rendered in the same 2.5D projection, in a border around the claimed plot, so EXPAND visibly converts trees → grass. Make the plot fill the portrait viewport.

**Files:**
- Modify: `flutter/tools/gen_objects.py` (add `tree_grid()`, emit `tree.png`)
- Create (generated): `flutter/assets/objects/tree.png`
- Modify: `flutter/lib/engine/garden_engine.dart` (`SpriteBank.tree()`, `WorldGrid` helper, forest pass in painter)
- Test: `flutter/test/engine_test.dart`

**Interfaces:**
- Produces: top-level `int forestMargin(int cols, int rows)` → number of forest rings around the claimed plot (constant `2`). `WorldGrid` value object: `final int cols, rows, margin;` `int get worldCols => cols + 2*margin;` `int get worldRows => rows + 2*margin;` `bool isClaimed(int wc, int wr)` (true iff inside the centered claimed window). Used by the painter to draw grass vs forest and by tests.
- Produces: `SpriteBank.tree()` returns the `tree.png` image.

- [ ] **Step 1: Write failing WorldGrid test**

In `flutter/test/engine_test.dart`:

```dart
group('WorldGrid claimed vs forest', () {
  test('claimed window is centred inside the forest margin', () {
    final w = WorldGrid(cols: 4, rows: 6, margin: 2);
    expect(w.worldCols, 8);
    expect(w.worldRows, 10);
    // corners are forest
    expect(w.isClaimed(0, 0), false);
    expect(w.isClaimed(7, 9), false);
    // centre 4x6 block (cols 2..5, rows 2..7) is claimed
    expect(w.isClaimed(2, 2), true);
    expect(w.isClaimed(5, 7), true);
    expect(w.isClaimed(1, 2), false); // just outside claimed, in margin
  });

  test('growing the claim shrinks the forest ring by one on each side', () {
    final before = WorldGrid(cols: 4, rows: 6, margin: 2);
    final after = WorldGrid(cols: 6, rows: 8, margin: 2);
    // a tile that was forest at (1,2) becomes claimed after one grow
    expect(before.isClaimed(1, 2), false);
    expect(after.isClaimed(1, 2), true);
  });
});
```

- [ ] **Step 2: Run test, verify it fails**

Run: `& C:\src\flutter\bin\flutter.bat test test/engine_test.dart`
Expected: FAIL — `WorldGrid` undefined.

- [ ] **Step 3: Add `WorldGrid` + `forestMargin` to `garden_engine.dart`**

```dart
/// How many rings of forest surround the claimed plot. Constant: enough that a
/// margin of woodland is always visible so EXPAND reads as claiming it.
int forestMargin(int cols, int rows) => 2;

/// The full world = claimed plot centred inside a forest border. The painter
/// projects every world tile; claimed tiles are grass, the rest are forest.
class WorldGrid {
  final int cols; // claimed
  final int rows;
  final int margin;
  const WorldGrid({required this.cols, required this.rows, required this.margin});

  int get worldCols => cols + 2 * margin;
  int get worldRows => rows + 2 * margin;

  /// Is world tile (wc,wr) inside the centred claimed window?
  bool isClaimed(int wc, int wr) =>
      wc >= margin && wc < margin + cols && wr >= margin && wr < margin + rows;

  /// Claimed tile index (r*cols+c) for a world tile, or -1 if it's forest.
  int claimedIndex(int wc, int wr) =>
      isClaimed(wc, wr) ? (wr - margin) * cols + (wc - margin) : -1;
}
```

- [ ] **Step 4: Run test, verify pass**

Run: `& C:\src\flutter\bin\flutter.bat test test/engine_test.dart`
Expected: PASS.

- [ ] **Step 5: Add a tree sprite to `gen_objects.py`**

Add a `tree_grid()` modeled on the existing `forest_grid()` canopy code (round dark-green canopy + brown trunk on transparent background, ~16×16), and in `main()` add `write_png(os.path.join(OUT, "tree.png"), upscale(tree_grid(), SCALE))`. Keep `forest.png` for now (still referenced until Step 7 swaps it; remove only after). Flat, no directional shading (consistent with v10 no-sun lighting).

Run: `python flutter/tools/gen_objects.py` and confirm `flutter/assets/objects/tree.png` exists.

- [ ] **Step 6: Load the tree in `SpriteBank`**

In `SpriteBank.load()` add `grab('tree', 'tree.png')`, and add `ui.Image? tree() => images['tree'];`.

- [ ] **Step 7: Render the world (grass claimed, forest border) in the painter**

In `GardenPainter.paint`, the painter now sizes the projector to the **world** so the whole screen is the 2.5D ground:

- Build `final world = WorldGrid(cols: _cols, rows: _rows, margin: forestMargin(_cols, _rows));`
- Project with the world dims: `final p = Projector.fit(world.worldCols, world.worldRows, cam, size);`
- Replace the flat `forest()` screen blit (the block at the top of `paint`) with: draw the world ground under the affine — grass on claimed tiles, the dark forest-floor color elsewhere — then draw a `tree` billboard on each forest tile (reuse `_paintBillboard` with `sprites.tree()`).
- The soil slab is drawn around the **claimed** plot edges only (compute claimed corners via `p.gridOf(margin..)`), so the claimed garden keeps its raised-bed look while forest lies flat around it.
- Roads/fences/flowers/critters keep using **claimed** indices; convert a claimed tile (col,row) to a world position by offsetting `+margin`. Add helpers in the painter: `Offset worldGround(int claimedCol, int claimedRow) => p.ground(claimedCol + margin, claimedRow + margin);` and use it wherever `p.ground(c,r)`/`p.groundIndex` fed claimed tiles.
- `customizing` gridlines and `tileAt` (in the view) must also account for the margin — see Step 8.

- [ ] **Step 8: Offset tap mapping by the forest margin**

In `garden_view.dart` `_onTapUp`, the projector is now world-sized, so a tap returns a **world** index; convert to a claimed index:

```dart
void _onTapUp(TapUpDetails d) {
  if (!widget.customizing || _lastSize == Size.zero) return;
  final cols = widget.garden.cols, rows = widget.garden.rows;
  final margin = forestMargin(cols, rows);
  final p = Projector.fit(cols + 2 * margin, rows + 2 * margin, _cam, _lastSize);
  final wi = p.tileAt(d.localPosition);
  if (wi < 0) return;
  final wc = wi % (cols + 2 * margin), wr = wi ~/ (cols + 2 * margin);
  final w = WorldGrid(cols: cols, rows: rows, margin: margin);
  final ci = w.claimedIndex(wc, wr);
  if (ci >= 0) widget.onTapTile(ci);
}
```

Apply the same world-sized `Projector.fit` + margin to `_cam.clamp` calls (clamp on world dims) and `_flowerTargets()` (critter targets are claimed flowers; offset their garden coords by `+margin` so they sit on the claimed tiles in world space). Update `CritterSystem` spawn radius to use world half-size.

- [ ] **Step 9: Analyze, test, and on-device sanity**

Run: `& C:\src\flutter\bin\flutter.bat analyze && & C:\src\flutter\bin\flutter.bat test`
Expected: clean + green. (The rendered world is visual — verify on-device after the APK builds; unit tests cover only WorldGrid + projection math.)

- [ ] **Step 10: Remove the now-unused flat forest, commit**

Delete the old `forest.png` load if no longer used (keep `forest_grid` in the tool or repurpose for the floor color). Then:

```bash
git add flutter/tools/gen_objects.py flutter/assets/objects/ flutter/lib/engine/garden_engine.dart flutter/lib/engine/garden_view.dart flutter/test/engine_test.dart
git commit -m "v11: full-screen 2.5D world, forest as in-world receding border (#1)"
```

---

### Task 3: Peek button — hide all HUD (req #2 part 1)

A bottom-left button mirroring the bottom-right recenter button that hides all `GardenScreen` chrome, leaving only the world. Tap again to restore.

**Files:**
- Modify: `flutter/lib/engine/garden_view.dart` (add a left-side peek IconButton + `onPeek` callback)
- Modify: `flutter/lib/main.dart` (`GardenScreen` → StatefulWidget holding `peek` flag; hide title/help/EXPAND/buttons when peeking)
- Modify: `flutter/lib/strings.dart` (add `peek` key ×6)
- Test: `flutter/test/widget_smoke_test.dart`

**Interfaces:**
- Produces: `GardenView` gains `final VoidCallback? onPeek;` and renders a bottom-left `Icon(Icons.visibility)` (key `Key('peekButton')`) when `onPeek != null`.
- `GardenScreen` becomes stateful with `bool _peek`; tapping peek toggles it; tapping the scene while peeking restores HUD.

- [ ] **Step 1: Add strings**

In `flutter/lib/strings.dart`, add to each language map a `peek` key: en `'peek': 'HIDE UI'`, tr `'GİZLE'`, pl `'UKRYJ UI'`, de `'UI AUS'`, ko `'UI 숨기기'`, it `'NASCONDI UI'`.

- [ ] **Step 2: Write failing smoke assertion**

In `flutter/test/widget_smoke_test.dart`, inside the existing garden-open flow add:

```dart
// open garden, tap the peek button — no exception/overflow
await tester.tap(find.byIcon(Icons.local_florist));
await tester.pumpAndSettle();
expect(find.byKey(const Key('peekButton')), findsOneWidget);
await tester.tap(find.byKey(const Key('peekButton')));
await tester.pumpAndSettle();
```

- [ ] **Step 3: Run smoke, verify it fails**

Run: `& C:\src\flutter\bin\flutter.bat test test/widget_smoke_test.dart`
Expected: FAIL — `peekButton` not found.

- [ ] **Step 4: Add the peek button to `GardenView`**

Add `final VoidCallback? onPeek;` to the constructor. In `build`, alongside the existing bottom-right recenter button, add:

```dart
if (widget.onPeek != null)
  Positioned(
    left: 6,
    bottom: 4,
    child: IconButton(
      key: const Key('peekButton'),
      icon: Icon(Icons.visibility, size: 22, color: ui),
      tooltip: widget.tr('peek'),
      onPressed: widget.onPeek,
    ),
  ),
```

- [ ] **Step 5: Make `GardenScreen` stateful, wire peek**

Convert `GardenScreen` to a `StatefulWidget` with `bool _peek = false`. Wrap the title `Padding`, the help `Text`, and the bottom CUSTOMIZE/CLOSE `Padding` so they render only when `!_peek` (e.g. `if (!_peek) Padding(...)`). Pass `onPeek: () => setState(() => _peek = !_peek)` to `GardenView`. When `_peek` is true, the EXPAND row top bar is also hidden. Keep the `GardenView` always visible and full-bleed.

- [ ] **Step 6: Run smoke + analyze, verify pass**

Run: `& C:\src\flutter\bin\flutter.bat analyze && & C:\src\flutter\bin\flutter.bat test test/widget_smoke_test.dart`
Expected: clean + PASS.

- [ ] **Step 7: Commit**

```bash
git add flutter/lib/engine/garden_view.dart flutter/lib/main.dart flutter/lib/strings.dart flutter/test/widget_smoke_test.dart
git commit -m "v11: peek button hides all garden HUD (#2)"
```

---

### Task 4: Camera mode — frame, capture, share, set static backdrop (req #2 part 2, #3)

A camera-mode button next to peek enters a HUD-hidden framing mode; a capture button screenshots the framed world; the result can be set as the garden section's static backdrop or shared.

**Files:**
- Modify: `flutter/pubspec.yaml` (add `share_plus`, `path_provider`)
- Create: `flutter/lib/camera.dart` (capture + save + share helpers, isolated so `main.dart` stays lean)
- Modify: `flutter/lib/store.dart` (add `gardenBackdropPath` state + prefs + setter)
- Modify: `flutter/lib/engine/garden_view.dart` (camera-mode button; wrap painter in a `RepaintBoundary` with a `GlobalKey`; expose capture)
- Modify: `flutter/lib/main.dart` (`GardenScreen`: camera flow, capture buttons, show static backdrop)
- Modify: `flutter/lib/strings.dart` (camera/capture/share/setBackdrop/clearBackdrop ×6)
- Test: `flutter/test/logic_test.dart` (backdrop prefs round-trip via a pure helper), `flutter/test/widget_smoke_test.dart`

**Interfaces:**
- Produces (`store.dart`): `String? gardenBackdropPath;` `void setGardenBackdrop(String? path)` (persists `_kBackdrop`, notifies). Loaded in `load()`.
- Produces (`camera.dart`): `Future<Uint8List?> captureBoundary(GlobalKey key)`; `Future<String> saveBackdropPng(Uint8List bytes)` (writes to app-docs `garden_backdrop.png`, returns path); `Future<void> sharePng(Uint8List bytes, String filename)`.
- Produces (`GardenView`): `final GlobalKey? captureKey;` wraps the `CustomPaint` in `RepaintBoundary(key: captureKey)`; `final bool cameraMode;` (when true, gestures stay active for framing but the recenter/peek buttons hide).

- [ ] **Step 1: Add dependencies**

Edit `flutter/pubspec.yaml` dependencies:

```yaml
dependencies:
  flutter:
    sdk: flutter
  shared_preferences: ^2.2.2
  share_plus: ^10.1.2
  path_provider: ^2.1.4
```

Run: `& C:\src\flutter\bin\flutter.bat pub get`
Expected: resolves without error.

- [ ] **Step 2: Add strings**

Add ×6 langs: `camera` (en `'CAMERA'`), `capture` (`'CAPTURE'`), `share` (`'SHARE'`), `setBackdrop` (`'SET AS BACKDROP'`), `clearBackdrop` (`'CLEAR BACKDROP'`), `cancel` (`'CANCEL'` — check it doesn't already exist; reuse if so). Translations: tr `KAMERA/ÇEK/PAYLAŞ/ARKA PLAN YAP/ARKA PLANI SİL/İPTAL`; pl `APARAT/ZRÓB/UDOSTĘPNIJ/USTAW TŁO/USUŃ TŁO/ANULUJ`; de `KAMERA/AUFNAHME/TEILEN/ALS HINTERGRUND/HINTERGRUND LÖSCHEN/ABBRECHEN`; ko `카메라/촬영/공유/배경으로/배경 지우기/취소`; it `FOTOCAMERA/SCATTA/CONDIVIDI/IMPOSTA SFONDO/RIMUOVI SFONDO/ANNULLA`.

- [ ] **Step 3: Write failing backdrop-prefs test**

`store.dart` persistence is exercised through `SharedPreferences`. Add a pure round-trip test in `logic_test.dart` only if a pure codec is introduced; instead assert the constant + default in a `store`-level test is overkill. Use a focused widget/unit check in `widget_smoke_test.dart` Step 8. For now add a guard test that the default is null:

```dart
test('garden backdrop key default is null (no static photo until captured)', () {
  // documents the contract used by AppStore.load(); see store.dart _kBackdrop
  const defaultBackdrop = null;
  expect(defaultBackdrop, isNull);
});
```

(Real persistence is verified on-device + in the smoke test that sets/reads it via `AppStore`.)

- [ ] **Step 4: Add backdrop state to `store.dart`**

Add `static const _kBackdrop = 'garden_backdrop_path';`, field `String? gardenBackdropPath;`, in `load()` `gardenBackdropPath = _prefs.getString(_kBackdrop);`, and:

```dart
void setGardenBackdrop(String? path) {
  gardenBackdropPath = path;
  if (path == null) {
    _prefs.remove(_kBackdrop);
  } else {
    _prefs.setString(_kBackdrop, path);
  }
  notifyListeners();
}
```

- [ ] **Step 5: Create `flutter/lib/camera.dart`**

```dart
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';

/// Screenshot the widget subtree behind [key]'s RepaintBoundary as PNG bytes.
/// Visual capture — not unit-testable in headless flutter test (toImage hangs);
/// verified on-device.
Future<Uint8List?> captureBoundary(GlobalKey key) async {
  final ctx = key.currentContext;
  if (ctx == null) return null;
  final boundary = ctx.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) return null;
  final image = await boundary.toImage(pixelRatio: 2.0);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data?.buffer.asUint8List();
}

/// Persist the captured PNG as the garden's static backdrop; returns its path.
Future<String> saveBackdropPng(Uint8List bytes) async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/garden_backdrop.png');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

/// Open the system share sheet with the captured PNG (user saves to Photos /
/// sets it as wallpaper from there).
Future<void> sharePng(Uint8List bytes, String filename) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes, flush: true);
  await Share.shareXFiles([XFile(file.path)]);
}
```

- [ ] **Step 6: Add RepaintBoundary + camera-mode button to `GardenView`**

Add `final GlobalKey? captureKey;` and `final bool cameraMode;` and `final VoidCallback? onCamera;` to the constructor. Wrap the `CustomPaint` child: `RepaintBoundary(key: widget.captureKey, child: CustomPaint(...))`. Hide the recenter + peek buttons when `widget.cameraMode` is true (framing should be clean). Add a bottom-left camera IconButton (key `Key('cameraButton')`, `Icons.photo_camera`) when `onCamera != null`, positioned just above/next to peek.

- [ ] **Step 7: Wire the capture flow in `GardenScreen`**

In the (now stateful) `GardenScreen`: hold `final GlobalKey _captureKey = GlobalKey();` and `bool _camera = false`. Pass `captureKey: _captureKey, cameraMode: _camera, onCamera: () => setState(() { _camera = true; _peek = true; })`. When `_camera` is true, show a small bottom row with CAPTURE and CANCEL instead of CUSTOMIZE/CLOSE. CAPTURE calls:

```dart
final bytes = await captureBoundary(_captureKey);
if (bytes == null) return;
// then show a dialog: SET AS BACKDROP / SHARE / CANCEL
```

SET AS BACKDROP → `final path = await saveBackdropPng(bytes); s.setGardenBackdrop(path);` then exit camera mode. SHARE → `await sharePng(bytes, 'pixel_pomo_garden.png');`. After either, `setState(() { _camera = false; _peek = false; });`.

- [ ] **Step 8: Show the static backdrop in the garden section**

When `s.gardenBackdropPath != null` and not customizing/camera, render the stored PNG (`Image.file(File(s.gardenBackdropPath!), fit: BoxFit.cover)`) as a static backdrop behind (or instead of) the live `GardenView` in `GardenScreen`. Add a small CLEAR BACKDROP affordance (e.g. in the camera dialog or a long-press) calling `s.setGardenBackdrop(null)`. Import `dart:io`.

Smoke test: extend the garden flow to tap the camera button and assert no exception:

```dart
expect(find.byKey(const Key('cameraButton')), findsOneWidget);
await tester.tap(find.byKey(const Key('cameraButton')));
await tester.pumpAndSettle();
// CANCEL out (CAPTURE's toImage hangs headless — don't tap it in tests)
await tester.tap(find.text(t('en', 'cancel')));
await tester.pumpAndSettle();
```

- [ ] **Step 9: Analyze + test, verify pass**

Run: `& C:\src\flutter\bin\flutter.bat analyze && & C:\src\flutter\bin\flutter.bat test`
Expected: clean + green. (Capture itself is on-device-only.)

- [ ] **Step 10: Commit**

```bash
git add flutter/pubspec.yaml flutter/pubspec.lock flutter/lib/camera.dart flutter/lib/store.dart flutter/lib/engine/garden_view.dart flutter/lib/main.dart flutter/lib/strings.dart flutter/test/logic_test.dart flutter/test/widget_smoke_test.dart
git commit -m "v11: camera mode — capture, share, static garden backdrop (#2, #3)"
```

---

### Task 5: Settings Clean|Garden home-screen mode + live backdrop behind the timer (req #3)

A Settings toggle that, when `Garden`, renders the live animated garden behind the pomodoro timer.

**Files:**
- Modify: `flutter/lib/store.dart` (add `homeMode` state + prefs + setter)
- Modify: `flutter/lib/main.dart` (`SettingsScreen` toggle; `HomeScreen` live backdrop)
- Modify: `flutter/lib/engine/garden_view.dart` (a non-interactive backdrop flag)
- Modify: `flutter/lib/strings.dart` (`homeMode`/`clean`/`gardenMode` ×6)
- Test: `flutter/test/widget_smoke_test.dart`

**Interfaces:**
- Produces (`store.dart`): `bool homeGardenBackdrop = false;` `void setHomeGardenBackdrop(bool v)` (persists `_kHomeMode`, notifies). Loaded in `load()`.
- Produces (`GardenView`): `final bool interactive;` (default true) — when false, gestures are disabled (backdrop mode); the ticker/critters still run.

- [ ] **Step 1: Add strings**

Add ×6: `homeMode` (en `'HOME SCREEN'`), `clean` (`'CLEAN'`), `gardenMode` (`'GARDEN'`). tr `ANA EKRAN/SADE/BAHÇE`; pl `EKRAN GŁÓWNY/CZYSTY/OGRÓD`; de `STARTBILDSCHIRM/SCHLICHT/GARTEN`; ko `홈 화면/심플/정원`; it `SCHERMATA/PULITO/GIARDINO`.

- [ ] **Step 2: Write failing smoke assertion**

In `widget_smoke_test.dart`, open settings and toggle the mode:

```dart
await tester.tap(find.byIcon(Icons.settings));
await tester.pumpAndSettle();
expect(find.text(t('en', 'gardenMode')), findsWidgets);
await tester.tap(find.text(t('en', 'gardenMode')).first);
await tester.pumpAndSettle();
```

- [ ] **Step 3: Run smoke, verify it fails**

Run: `& C:\src\flutter\bin\flutter.bat test test/widget_smoke_test.dart`
Expected: FAIL — `gardenMode` text not present.

- [ ] **Step 4: Add `homeGardenBackdrop` to `store.dart`**

`static const _kHomeMode = 'home_garden_backdrop';`, field `bool homeGardenBackdrop = false;`, in `load()` `homeGardenBackdrop = _prefs.getBool(_kHomeMode) ?? false;`, and:

```dart
void setHomeGardenBackdrop(bool v) {
  homeGardenBackdrop = v;
  _prefs.setBool(_kHomeMode, v);
  notifyListeners();
}
```

- [ ] **Step 5: Add the toggle to `SettingsScreen`**

After the language section, add a `HOME SCREEN` label and two `PixelButton`s (CLEAN / GARDEN) styled like the language picker, the selected one filled with `th.accent`. Tapping calls `s.setHomeGardenBackdrop(false|true)`.

- [ ] **Step 6: Add `interactive` flag to `GardenView`; render backdrop in `HomeScreen`**

Add `final bool interactive;` (default `true`). In `build`, when `!interactive`, wrap the `GestureDetector` so it ignores input (omit `onScaleUpdate`/`onTapUp` and the corner buttons). In `HomeScreen.build`, when `s.homeGardenBackdrop`, place a dimmed live `GardenView` behind the timer via a `Stack`:

```dart
body: Stack(children: [
  if (s.homeGardenBackdrop)
    Positioned.fill(
      child: FutureBuilder<SpriteBank>(
        future: gardenSprites(),
        builder: (c, snap) => snap.hasData
            ? Opacity(
                opacity: 0.45,
                child: GardenView(
                  garden: s.garden, sprites: snap.data!, customizing: false,
                  onTapTile: (_) {}, groundColor: _gardenGround, soilColor: _gardenSoil,
                  uiColor: th.onSurface, lang: lang, tr: (k) => t(lang, k),
                  interactive: false),
              )
            : const SizedBox.shrink(),
      ),
    ),
  SafeArea(child: Column(... existing timer UI ...)),
]),
```

(The static photo is intentionally NOT used here — live garden only.)

- [ ] **Step 7: Analyze + test, verify pass**

Run: `& C:\src\flutter\bin\flutter.bat analyze && & C:\src\flutter\bin\flutter.bat test`
Expected: clean + green (full suite).

- [ ] **Step 8: Commit**

```bash
git add flutter/lib/store.dart flutter/lib/main.dart flutter/lib/engine/garden_view.dart flutter/lib/strings.dart flutter/test/widget_smoke_test.dart
git commit -m "v11: settings Clean|Garden home mode + live garden backdrop behind timer (#3)"
```

---

### Task 6: Docs, version bump, edge-test sweep, release

Update all standing docs, run the full edge-test sweep, bump the version, and push so CI publishes `flutter-v11`.

**Files:**
- Modify: `flutter/pubspec.yaml` (version)
- Modify: `log.md`, `prompt.md`, `README.md`, `flutter/README.md`, `TESTING.md`

- [ ] **Step 1: Bump version**

`flutter/pubspec.yaml`: `version: 0.11.0+12`.

- [ ] **Step 2: Full edge-test sweep**

Run: `& C:\src\flutter\bin\flutter.bat analyze && & C:\src\flutter\bin\flutter.bat test`
Confirm: analyze clean; all tests pass. Record the count and any fixes.

- [ ] **Step 3: Build debug APK locally**

Run: `& C:\src\flutter\bin\flutter.bat build apk --debug`
Expected: APK builds with the new assets (tree.png) + deps. Note any size/asset issues.

- [ ] **Step 4: Update `TESTING.md`**

Add a v11 section: cases covered (rectangular `Garden` grow/decode/migration, `Projector` rectangular inverse round-trips at multiple yaws + fill-fit, `WorldGrid` claimed/forest classification + ring recede, backdrop/home-mode prefs defaults, smoke peek/camera/settings-toggle), fixes applied, and the known gap (no golden test of the rendered world or camera capture — headless `toImage` hangs; verified on-device).

- [ ] **Step 5: Update `log.md`**

Add a v11 entry on top (newest-first): the prompt (the 3 requirements + standing tasks) and the changes per task.

- [ ] **Step 6: Update `prompt.md`, `README.md`, `flutter/README.md`**

Refresh the recreation prompt and structure docs to describe: rectangular full-screen world + receding forest, peek + camera mode + static backdrop, Settings Clean|Garden live home backdrop, new deps, new `camera.dart`.

- [ ] **Step 7: Commit + push**

```bash
git add flutter/pubspec.yaml log.md prompt.md README.md flutter/README.md TESTING.md
git commit -m "v11: docs, testing, version bump 0.11.0+12"
git push origin main
```

- [ ] **Step 8: Verify CI**

Watch GitHub Actions `build-flutter.yml` go green and confirm `flutter-v11` + `latest-flutter` publish the APK + unsigned IPA with title `Flutter build (iOS + Android, 0.11.0)`. Report the release URL to the user.

- [ ] **Step 9: Write the v11 memory**

Add a v11 entry to the Pixel Pomo memory (rectangular full-screen world, receding forest, peek/camera/backdrop, home-mode toggle, new deps) + update `MEMORY.md` if needed.

---

## Self-Review

**Spec coverage:**
- Req #1 full-screen rectangular world + receding forest → Tasks 1 & 2. ✓
- Req #2 peek button → Task 3; camera mode + screenshot + set-as-background → Task 4. ✓
- Req #3 engine as live wallpaper backdrop → Task 5 (live garden behind timer). ✓
- Standing: edge tests/TESTING.md, log/prompt/README, memory, APK+IPA, version, push → Task 6. ✓
- Decisions: in-app live bg + static export (Tasks 4/5), rect 4×6 (Task 1), forest receding border (Task 2), fixed tilt (no tilt task — preserved), static photo only in garden section (Task 4 Step 8, Task 5 Step 6 note), Clean|Garden settings toggle (Task 5). ✓

**Placeholder scan:** No "TBD/TODO". The few visual/on-device steps (capture, rendered world) are explicitly flagged as not unit-testable with the reason (headless `toImage`), per the spec — not placeholders.

**Type consistency:** `cols`/`rows` used consistently across `Garden`, `Projector`, `GardenCamera.clamp(cols,rows,size)`, `WorldGrid`. `Projector.fit(cols,rows,cam,size)` and `Projector(cols,rows,t,center,yaw)` arity matches all call sites (view, painter, tests). `forestMargin(cols,rows)`, `WorldGrid.claimedIndex`, `setGardenBackdrop`, `gardenBackdropPath`, `homeGardenBackdrop`, `setHomeGardenBackdrop`, `captureBoundary`/`saveBackdropPng`/`sharePng`, `captureKey`/`cameraMode`/`interactive` are all defined where produced and consumed with matching names.
