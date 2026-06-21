// ─────────────────────────────────────────────────────────────────────────
//  PixelPomo Garden Engine — a tiny, purpose-built 2.5D scene renderer.
//
//  Not a general game engine (no Unity/Flame): just what a living pixel garden
//  needs — a 2.5D projection with a fixed tilt but a hand-controllable compass
//  rotation (look from N/E/S/W like Google Maps), a contiguous grass field with
//  a raised soil slab for depth, flat roads, ground-connected fences, and a few
//  tiny critters that drift in (in garden space, so they rotate with the map),
//  visit a flower, and leave.
//
//  The camera zooms, pans (clamped so the garden can't leave the screen) and
//  yaws. Pure rendering + camera math live here; it reads a [Garden] from
//  logic.dart and a [SpriteBank].
// ─────────────────────────────────────────────────────────────────────────
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../logic.dart';

/// Fixed vertical squash of the ground plane — this constant *is* the 2.5D
/// depth (1.0 would be flat top-down). The viewing angle around the vertical
/// axis is the camera's [GardenCamera.yaw]; the tilt itself stays fixed.
const double kVy = 0.60;

/// Number of frames in a directional atlas — must match `FRAMES` in
/// tools/gen_objects.py. Only **critters** still ship as an 8-frame strip (so a
/// bee faces its travel heading); the painter slices out the matching frame.
/// Flowers are single billboards and fences are 3D meshes — neither uses this.
const int kDirFrames = 8;

/// Forest sprite pool sizes — must match the counts emitted by tools/gen_objects.py.
const int kForestTrees = 20, kForestBushes = 10, kForestRocks = 5;

/// Is garden tile (c,r) inside the plantable plot (true) or the surrounding
/// screen-filling forest (false)? (#v18)
bool isGardenTile(int c, int r, int cols, int rows) => c >= 0 && c < cols && r >= 0 && r < rows;

int _hash2(int c, int r) {
  var h = (c * 73856093) ^ (r * 19349663);
  h ^= h >> 13;
  return h & 0x7fffffff;
}

/// Deterministic, varied forest prop for an unclaimed tile (or null = grass gap).
/// Weighting: mostly trees, some bushes, few rocks, occasional gap — stable so
/// the forest never shimmers between frames (#5).
String? forestPropAt(int c, int r) {
  final h = _hash2(c, r);
  final bucket = h % 100;
  final pick = h ~/ 100;
  String id(String kind, int n) => '${kind}_${(pick % n).toString().padLeft(2, '0')}';
  if (bucket < 18) return null; // grass gap
  if (bucket < 80) return id('tree', kForestTrees);
  if (bucket < 95) return id('bush', kForestBushes);
  return id('rock', kForestRocks);
}

/// Flat ambient palette per fence id as `(side, top, rail)`. The top face is a
/// touch brighter than the sides — light from the sky, baked to the geometry, so
/// it stays put as the camera yaws (a fixed sky glow, never a directional sun).
const Map<String, (int side, int top, int rail)> _fence3d = {
  'fence_wood': (0xFF8B5A2B, 0xFFA9743E, 0xFFA9743E),
  'fence_dark': (0xFF3D2814, 0xFF5A3A1E, 0xFF5A3A1E),
  'fence_stone': (0xFF6E6E6E, 0xFF9A9A9A, 0xFF9A9A9A),
};

/// The 8 screen-space corners of an upright box at garden [c] (tile units), with
/// a square footprint of half-width [half] tiles rising [height] tiles. Indices
/// 0..3 are the base ring (CW), 4..7 the matching top ring directly above. This
/// is the low-poly primitive every standing 3D object (fence posts now, trees /
/// houses next) is built from — real geometry that rotates correctly and keeps a
/// solid footprint from every angle, instead of a flat sprite that thins out.
List<Offset> boxCorners(Projector p, Offset c, double half, double height) {
  final base = <Offset>[
    p.projectGrid(Offset(c.dx - half, c.dy - half)),
    p.projectGrid(Offset(c.dx + half, c.dy - half)),
    p.projectGrid(Offset(c.dx + half, c.dy + half)),
    p.projectGrid(Offset(c.dx - half, c.dy + half)),
  ];
  return [...base, for (final b in base) b.translate(0, -height * p.t)];
}

// ---- sprite bank ------------------------------------------------------------

/// Decoded PNGs from assets/objects/, keyed by id. Critters are 8-frame
/// directional **atlases**; flowers (`flower_<id>`), the ground (`grass`), the
/// `forest` surround and every road are single tiles. Fences aren't loaded here
/// at all — they render as 3D meshes. Loaded once, reused for the scene.
class SpriteBank {
  final Map<String, ui.Image> images;
  const SpriteBank(this.images);

  ui.Image? grass() => images['grass'];
  ui.Image? forest() => images['forest'];
  ui.Image? tree() => images['tree'];
  ui.Image? forestProp(String id) => images[id]; // tree_NN / bush_NN / rock_NN
  ui.Image? object(String id) => images[id]; // roads
  ui.Image? flower(String id) => images['flower_$id'];
  ui.Image? critter(String kind) => images[kind];

  static Future<SpriteBank> load() async {
    final out = <String, ui.Image>{};
    Future<void> grab(String key, String asset) async {
      final data = await rootBundle.load('assets/objects/$asset');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      out[key] = (await codec.getNextFrame()).image;
    }

    await Future.wait([
      grab('grass', 'grass.png'),
      grab('forest', 'forest.png'),
      grab('tree', 'tree.png'),
      for (var i = 0; i < kForestTrees; i++)
        grab('tree_${i.toString().padLeft(2, '0')}', 'tree_${i.toString().padLeft(2, '0')}.png'),
      for (var i = 0; i < kForestBushes; i++)
        grab('bush_${i.toString().padLeft(2, '0')}', 'bush_${i.toString().padLeft(2, '0')}.png'),
      for (var i = 0; i < kForestRocks; i++)
        grab('rock_${i.toString().padLeft(2, '0')}', 'rock_${i.toString().padLeft(2, '0')}.png'),
      for (final k in CritterSystem.kinds) grab(k, '$k.png'),
      for (final id in Placeables.roadIds) grab(id, '$id.png'),
      // fences render as low-poly 3D meshes, not sprites; their PNGs are only
      // used as shop thumbnails (loaded there via Image.asset).
      for (final f in Flowers.all) grab('flower_${f.id}', 'flower_${f.id}.png'),
    ]);
    return SpriteBank(out);
  }
}

// ---- camera -----------------------------------------------------------------

/// Zoom + pan + yaw. [clamp] keeps the garden inside the viewport so it always
/// stays fixed on screen (you can't drag the map away).
class GardenCamera {
  double zoom;
  double panX;
  double panY;
  double yaw; // radians, rotation around the vertical axis

  GardenCamera({this.zoom = 1, this.panX = 0, this.panY = 0, this.yaw = 0});

  void reset() {
    zoom = 1;
    panX = 0;
    panY = 0;
    yaw = 0;
  }

  /// Bound pan to a roam radius around the plot: you can wander up to a plot-size
  /// into the surrounding (screen-filling) forest, but the garden can't be lost —
  /// bounded, not the infinite roam of older versions (#v18).
  void clamp(int cols, int rows, Size size) {
    final p = Projector.fit(cols, rows, this, size);
    final roam = (cols > rows ? cols : rows).toDouble();
    final maxX = (cols / 2 + roam) * p.t;
    final maxY = (rows / 2 + roam) * p.t * kVy;
    panX = panX.clamp(-maxX, maxX);
    panY = panY.clamp(-maxY, maxY);
  }
}

// ---- projection -------------------------------------------------------------

/// Maps garden coords (tile units, centred) → screen and back, with the camera's
/// yaw applied. Fits the whole plot in view at zoom 1; the inverse is exact so
/// taps land on the right tile from any rotation.
class Projector {
  final int cols;
  final int rows;
  final double t; // tile size in px (already includes zoom)
  final Offset center;
  final double yaw;
  late final double _cos = math.cos(yaw);
  late final double _sin = math.sin(yaw);

  Projector(this.cols, this.rows, this.t, this.center, this.yaw);

  /// Fit the plot into the viewport leaving a small forest margin (`kFitMargin`
  /// tiles); the surrounding forest is then drawn screen-filling on every visible
  /// tile, so it covers the whole portrait screen around the plot (#v18).
  static const double kFitMargin = 2.0;
  factory Projector.fit(int cols, int rows, GardenCamera cam, Size size) {
    final fitW = size.width / (cols + kFitMargin);
    final fitH = size.height / ((rows + kFitMargin) * kVy);
    final t = math.min(fitW, fitH) * cam.zoom;
    return Projector(cols, rows, t,
        Offset(size.width / 2 + cam.panX, size.height / 2 + cam.panY), cam.yaw);
  }

  static double slabFor(double t) => t * 0.32 + 6;

  double get planeW => cols * t;
  double get planeH => rows * t * kVy;

  /// Project a continuous garden coordinate (in tile units, plot centred at 0).
  Offset projectGrid(Offset g) {
    final rx = g.dx * _cos - g.dy * _sin;
    final ry = g.dx * _sin + g.dy * _cos;
    return Offset(center.dx + rx * t, center.dy + ry * t * kVy);
  }

  /// Project a garden coordinate raised [e] tile-heights off the ground. The
  /// camera tilt is fixed, so true vertical maps **straight up the screen** by
  /// `e * t` and is identical from every compass [yaw] — a post is equally tall
  /// from all sides (uniform sky light, no moving sun).
  Offset projectElevated(Offset g, double e) => projectGrid(g).translate(0, -e * t);

  /// Garden coordinate of tile (col,row)'s centre.
  Offset gridOf(int c, int r) =>
      Offset(c - (cols - 1) / 2.0, r - (rows - 1) / 2.0);
  /// Continuous garden coord for fractional (col,row).
  Offset gridOfD(double c, double r) => Offset(c - (cols - 1) / 2.0, r - (rows - 1) / 2.0);
  Offset ground(int c, int r) => projectGrid(gridOf(c, r));
  Offset groundIndex(int i) => ground(i % cols, i ~/ cols);

  /// Inverse of [ground]: continuous (col,row) in claimed-index space for a
  /// screen point — finds which tiles are visible so the forest can fill the
  /// whole screen (#1).
  Offset gridAt(Offset p) {
    final dx = (p.dx - center.dx) / t;
    final dy = (p.dy - center.dy) / (t * kVy);
    final gx = dx * _cos + dy * _sin;
    final gy = -dx * _sin + dy * _cos;
    return Offset(gx + (cols - 1) / 2.0, gy + (rows - 1) / 2.0);
  }

  /// Integer tile range (1-tile bleed) covering the whole screen, so the forest
  /// can be drawn on every visible tile around the plot (#v18).
  ({int minC, int maxC, int minR, int maxR}) visibleTileBounds(Size size) {
    final corners = [
      gridAt(const Offset(0, 0)),
      gridAt(Offset(size.width, 0)),
      gridAt(Offset(size.width, size.height)),
      gridAt(Offset(0, size.height)),
    ];
    var minC = double.infinity, maxC = -double.infinity, minR = double.infinity, maxR = -double.infinity;
    for (final c in corners) {
      minC = math.min(minC, c.dx); maxC = math.max(maxC, c.dx);
      minR = math.min(minR, c.dy); maxR = math.max(maxR, c.dy);
    }
    return (minC: minC.floor() - 1, maxC: maxC.ceil() + 1, minR: minR.floor() - 1, maxR: maxR.ceil() + 1);
  }

  int tileAt(Offset p) {
    final dx = (p.dx - center.dx) / t;
    final dy = (p.dy - center.dy) / (t * kVy);
    final gx = dx * _cos + dy * _sin; // inverse rotation
    final gy = -dx * _sin + dy * _cos;
    final c = (gx + (cols - 1) / 2.0).round();
    final r = (gy + (rows - 1) / 2.0).round();
    if (c < 0 || r < 0 || c >= cols || r >= rows) return -1;
    return r * cols + c;
  }

  /// The 4 plot corners in screen space (for the slab + bounds + grid), CW.
  List<Offset> corners() {
    final hx = cols / 2.0, hy = rows / 2.0;
    return [
      projectGrid(Offset(-hx, -hy)),
      projectGrid(Offset(hx, -hy)),
      projectGrid(Offset(hx, hy)),
      projectGrid(Offset(-hx, hy)),
    ];
  }

  /// Affine mapping garden coords → screen, so the ground layer can be drawn
  /// axis-aligned and the canvas handles yaw + squash.
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

// ---- critters (garden-space) ------------------------------------------------

enum _CState { approach, hover, leave }

/// A tiny visiting creature (bee / butterfly / ladybug). It lives in **garden
/// coordinates** — so it rotates/zooms with the map — entering from a plot edge,
/// flying to a flower, hovering as if sniffing, then leaving and despawning.
class Critter {
  /// Hard cap on how long a critter may live, in seconds, regardless of state —
  /// guarantees one can never get stuck (e.g. among the trees) forever (#3).
  static const double maxLife = 18.0;

  final String kind;
  Offset pos; // garden coords (tile units)
  Offset target; // garden coords
  _CState state = _CState.approach;
  double timer = 0;
  double life = 0; // total seconds alive
  final double speed; // tiles/sec
  final double phase; // flight-wobble offset
  final double hoverFor;

  Critter(this.kind, this.pos, this.target, this.speed, this.phase, this.hoverFor);
}

/// Owns the (at most 2) active critters and spawns them occasionally. Works
/// purely in garden coords; the painter projects each critter to the screen.
class CritterSystem {
  static const kinds = ['bee', 'butterfly', 'ladybug'];
  static const maxActive = 2;

  final math.Random _r;
  final List<Critter> critters = [];
  double time = 0;
  double _spawnIn;

  CritterSystem([int? seed])
      : _r = math.Random(seed),
        _spawnIn = 2 {
    _spawnIn = 2 + _r.nextDouble() * 3;
  }

  /// [flowers] are flower-tile centres in garden coords; [n] is the plot size.
  void step(double dt, int n, List<Offset> flowers) {
    final d = dt.clamp(0.0, 0.05);
    time += d;
    _spawnIn -= d;
    final half = n / 2.0 + 0.8;
    if (_spawnIn <= 0) {
      _spawnIn = 6 + _r.nextDouble() * 8; // a visitor every ~6–14s
      if (critters.length < maxActive && flowers.isNotEmpty) {
        _spawn(half, flowers);
      }
    }
    for (final c in critters) {
      c.life += d;
      _stepOne(c, d, half);
    }
    // despawn on exit OR once past the hard lifetime cap, so none can stick (#3)
    critters.removeWhere((c) =>
        c.life > Critter.maxLife ||
        (c.state == _CState.leave &&
            (c.pos.dx.abs() > half + 0.5 || c.pos.dy.abs() > half + 0.5)));
  }

  void _spawn(double half, List<Offset> flowers) {
    double rnd() => (_r.nextDouble() * 2 - 1) * half;
    final start = switch (_r.nextInt(4)) {
      0 => Offset(rnd(), -half),
      1 => Offset(half, rnd()),
      2 => Offset(rnd(), half),
      _ => Offset(-half, rnd()),
    };
    critters.add(Critter(
      kinds[_r.nextInt(kinds.length)],
      start,
      flowers[_r.nextInt(flowers.length)],
      1.0 + _r.nextDouble() * 0.8, // tiles/sec
      _r.nextDouble() * math.pi * 2,
      2.0 + _r.nextDouble() * 2.5,
    ));
  }

  void _stepOne(Critter c, double dt, double half) {
    c.timer += dt;
    final to = c.target - c.pos;
    final dist = to.distance;
    switch (c.state) {
      case _CState.approach:
        if (dist < 0.18) {
          c.state = _CState.hover;
          c.timer = 0;
        } else {
          c.pos += to / dist * c.speed * dt;
        }
        break;
      case _CState.hover:
        if (c.timer >= c.hoverFor) {
          c.state = _CState.leave;
          c.timer = 0;
          final ex = c.pos.dx < 0 ? -(half + 1) : (half + 1);
          c.target = Offset(ex, c.pos.dy);
        }
        break;
      case _CState.leave:
        // always progress, even if the exit target is ~where we already are,
        // so a critter can never freeze in place (#3)
        final dir = dist > 1e-3 ? to / dist : const Offset(1, 0);
        c.pos += dir * c.speed * 1.4 * dt;
        break;
    }
  }
}

// ---- painter ----------------------------------------------------------------

class GardenPainter extends CustomPainter {
  final Garden garden;
  final GardenCamera cam;
  final SpriteBank sprites;
  final CritterSystem critterSystem;
  final bool customizing;
  final int groundColor;
  final int soilColor;

  GardenPainter({
    required this.garden,
    required this.cam,
    required this.sprites,
    required this.critterSystem,
    required this.customizing,
    required this.groundColor,
    required this.soilColor,
    required Listenable repaint,
  }) : super(repaint: repaint);

  double get time => critterSystem.time;
  int get _cols => garden.cols;
  int get _rows => garden.rows;

  @override
  void paint(Canvas canvas, Size size) {
    // One screen-filling 2.5D world (#1): the claimed plot is the grass clearing;
    // the projector is sized to the plot, and the forest is drawn over every
    // visible tile outside it, so the woods fill the whole screen at any pan/zoom.
    final p = Projector.fit(_cols, _rows, cam, size);
    final t = p.t;
    final slab = Projector.slabFor(t);

    // claimed plot corners (the plot is centred at the world centre, so its
    // half-extents are simply ±cols/2, ±rows/2 in centred-grid units)
    final hx = _cols / 2.0, hy = _rows / 2.0;
    final cs = [
      p.projectGrid(Offset(-hx, -hy)),
      p.projectGrid(Offset(hx, -hy)),
      p.projectGrid(Offset(hx, hy)),
      p.projectGrid(Offset(-hx, hy)),
    ];

    // 0) forest floor — dark woodland ground over the whole screen so the garden
    //    is a clearing critters drift into.
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF12301A));

    // 1) soil slab — extrude each claimed-plot edge downward for 2.5D thickness.
    final soil = Paint()..color = Color(soilColor);
    for (var i = 0; i < 4; i++) {
      final a = cs[i], b = cs[(i + 1) % 4];
      canvas.drawPath(
          Path()
            ..moveTo(a.dx, a.dy)
            ..lineTo(b.dx, b.dy)
            ..lineTo(b.dx, b.dy + slab)
            ..lineTo(a.dx, a.dy + slab)
            ..close(),
          soil);
    }

    // 2) grass + flat roads, clipped to the claimed plot, under the yaw+squash
    //    affine — rotates cleanly. (The claimed region is centred, so its rect in
    //    centred-grid units is exactly [-cols/2..cols/2]×[-rows/2..rows/2].)
    final plot = Path()
      ..moveTo(cs[0].dx, cs[0].dy)
      ..lineTo(cs[1].dx, cs[1].dy)
      ..lineTo(cs[2].dx, cs[2].dy)
      ..lineTo(cs[3].dx, cs[3].dy)
      ..close();
    canvas.save();
    canvas.clipPath(plot);
    canvas.transform(p.gridToScreen());
    final gridRect = Rect.fromLTWH(-hx, -hy, _cols.toDouble(), _rows.toDouble());
    final grass = sprites.grass();
    if (grass != null) {
      paintImage(
        canvas: canvas,
        rect: gridRect,
        image: grass,
        fit: BoxFit.none,
        repeat: ImageRepeat.repeat,
        scale: grass.width.toDouble(), // one grass tile == one garden unit
        filterQuality: FilterQuality.none,
        alignment: Alignment.topLeft,
      );
    } else {
      canvas.drawRect(gridRect, Paint()..color = Color(groundColor));
    }
    _paintRoads(canvas);
    canvas.restore();

    // crisp plot outline
    canvas.drawPath(
        plot,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Color(soilColor).withValues(alpha: 0.7));

    // a few wild decorative blooms scattered on empty grass tiles (#v18)
    _paintGrassFlowers(canvas, p);

    // 3) customize gridlines over the claimed plot.
    if (customizing) _paintGrid(canvas, p);

    // 4a) fence rails between adjacent claimed posts.
    _paintFenceRails(canvas, p);

    // 4b) standing things, depth-sorted back-to-front by screen-y: forest trees
    //     on every VISIBLE tile outside the claimed plot (so the woods fill the
    //     screen — no void) + claimed props. Fences are low-poly 3D posts; trees
    //     and flowers are flat billboards grounded with a contact shadow.
    final vb = p.visibleTileBounds(size); // forest on every visible tile → fills the screen (#v18)
    final standing = <(double, int, int, String)>[]; // (depthY, col, row, id)
    for (var r = vb.minR; r <= vb.maxR; r++) {
      for (var c = vb.minC; c <= vb.maxC; c++) {
        if (isGardenTile(c, r, _cols, _rows)) {
          final prop = garden.propAt(r * _cols + c);
          if (prop != null) standing.add((p.ground(c, r).dy, c, r, prop));
        } else {
          // a varied forest prop (tree/bush/rock) or a grass gap (#5)
          final fp = forestPropAt(c, r);
          if (fp != null) standing.add((p.ground(c, r).dy, c, r, fp));
        }
      }
    }
    standing.sort((a, b2) => a.$1.compareTo(b2.$1));
    for (final (_, c, r, id) in standing) {
      final anchor = p.ground(c, r);
      final claimed = c >= 0 && c < _cols && r >= 0 && r < _rows;
      if (!claimed) {
        final isRock = id.startsWith('rock_');
        _paintBillboard(canvas, sprites.forestProp(id), anchor, p.t,
            height: isRock ? 0.6 : 1.2, width: isRock ? 0.8 : 1.05);
      } else if (Placeables.isFence(id)) {
        _paintFencePost(canvas, p, c, r, id);
      } else {
        // flowers stand still — no wind sway (#v20 item 2)
        _paintBillboard(canvas, sprites.flower(id), anchor, p.t);
      }
    }

    // 5) critters on top of everything (projected from claimed garden coords)
    _paintCritters(canvas, p, t);
  }

  // ---- decorative grass daisies (#v19) --------------------------------------
  int _grassFlowerHash(int c, int r) {
    var h = (c * 0x1f1f1f1f) ^ (r * 0x2c2c2c2c) ^ 0x5bd1e995;
    h ^= h >> 15;
    return h & 0x7fffffff;
  }

  /// Scatter **sparse white daisies** on empty grass tiles (no planted prop /
  /// road), so the clearing has life without looking like a quilt. Deterministic,
  /// so they don't shimmer between frames (#v19).
  void _paintGrassFlowers(Canvas canvas, Projector p) {
    for (var r = 0; r < _rows; r++) {
      for (var c = 0; c < _cols; c++) {
        if (garden.tiles.containsKey(r * _cols + c)) continue; // skip planted/road
        if (_grassFlowerHash(c, r) % 100 >= 5) continue; // ~5% of empty tiles — sparse
        _paintBloom(canvas, p.ground(c, r), p.t);
      }
    }
  }

  /// A small **flat** pixel daisy lying on the grass (white petals + yellow eye) —
  /// not a billboard object; matches the 2D flowered-grass look the user sent (#v20).
  void _paintBloom(Canvas canvas, Offset a, double t) {
    final s = t * 0.085;
    final white = Paint()..color = const Color(0xFFFFFFFF);
    final eye = Paint()..color = const Color(0xFFF2C94C);
    void px(double dx, double dy, Paint p) => canvas.drawRect(
        Rect.fromCenter(center: a.translate(dx, dy * kVy), width: s, height: s * kVy), p);
    px(0, -s, white); // petals, flattened onto the ground by kVy
    px(0, s, white);
    px(-s, 0, white);
    px(s, 0, white);
    px(0, 0, eye); // yellow centre
  }

  void _paintRoads(Canvas canvas) {
    for (var r = 0; r < _rows; r++) {
      for (var c = 0; c < _cols; c++) {
        final id = garden.groundAt(r * _cols + c);
        if (id == null) continue;
        final img = sprites.object(id);
        final dst = Rect.fromCenter(
            center: Offset(c - (_cols - 1) / 2.0, r - (_rows - 1) / 2.0), width: 1, height: 1);
        if (img != null) {
          canvas.drawImageRect(
              img,
              Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
              dst,
              Paint()..filterQuality = FilterQuality.none);
        } else {
          canvas.drawRect(dst, Paint()..color = const Color(0xFFB7A687));
        }
      }
    }
  }

  /// Raised 3D rails between adjacent fence posts. A post links to **any** fence
  /// neighbour regardless of material (#1), so a wood fence joins a stone one.
  /// Each tile only draws toward its E and S neighbour (so every shared edge is
  /// drawn once). Each rail is a flat ribbon at a fixed height in garden space,
  /// so it rotates with the map and keeps a steady thickness from every angle —
  /// no more vanishing into a thin antenna under rotation.
  void _paintFenceRails(Canvas canvas, Projector p) {
    bool fence(int idx) =>
        idx >= 0 && idx < _cols * _rows && Placeables.isFence(garden.propAt(idx) ?? '');
    for (var r = 0; r < _rows; r++) {
      for (var c = 0; c < _cols; c++) {
        final index = r * _cols + c;
        final id = garden.propAt(index);
        if (id == null || !Placeables.isFence(id)) continue;
        final rail = Color(_fence3d[id]!.$3);
        final a = p.gridOf(c, r);
        void link(int nc, int nr) {
          final b = p.gridOf(nc, nr);
          for (final e in const [0.50, 0.28]) {
            _fillQuad(canvas, p.projectElevated(a, e + 0.05), p.projectElevated(b, e + 0.05),
                p.projectElevated(b, e - 0.05), p.projectElevated(a, e - 0.05), rail);
          }
        }
        if (c < _cols - 1 && fence(r * _cols + c + 1)) link(c + 1, r);
        if (r < _rows - 1 && fence((r + 1) * _cols + c)) link(c, r + 1);
      }
    }
  }

  /// One fence as a low-poly 3D post (the first object on the reusable mesh
  /// pipeline): an upright [boxCorners] box with a brighter top face. The four
  /// side faces share one flat colour, so their draw order is irrelevant; the
  /// top is drawn last so it always reads correctly however the box is turned.
  void _paintFencePost(Canvas canvas, Projector p, int c, int r, String id) {
    final pal = _fence3d[id]!;
    final gc = p.gridOf(c, r);
    final ground = p.projectGrid(gc);
    canvas.drawOval(
        Rect.fromCenter(
            center: ground.translate(0, p.t * kVy * 0.10),
            width: p.t * 0.34,
            height: p.t * kVy * 0.30),
        Paint()..color = const Color(0x33000000));
    final box = boxCorners(p, gc, 0.10, 0.66);
    for (var i = 0; i < 4; i++) {
      final j = (i + 1) % 4;
      _fillQuad(canvas, box[i], box[j], box[j + 4], box[i + 4], Color(pal.$1));
    }
    _fillQuad(canvas, box[4], box[5], box[6], box[7], Color(pal.$2));
  }

  /// Fill a flat-shaded quad (one low-poly face). Pixel-crisp, no anti-aliasing.
  void _fillQuad(Canvas canvas, Offset a, Offset b, Offset c, Offset d, Color color) {
    canvas.drawPath(
        Path()
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy)
          ..lineTo(c.dx, c.dy)
          ..lineTo(d.dx, d.dy)
          ..close(),
        Paint()
          ..color = color
          ..isAntiAlias = false);
  }

  void _paintGrid(Canvas canvas, Projector p) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0x66FFFFFF);
    final hx = _cols / 2.0, hy = _rows / 2.0;
    for (var i = 0; i <= _cols; i++) {
      final g = -hx + i;
      canvas.drawLine(p.projectGrid(Offset(g, -hy)), p.projectGrid(Offset(g, hy)), line);
    }
    for (var i = 0; i <= _rows; i++) {
      final g = -hy + i;
      canvas.drawLine(p.projectGrid(Offset(-hx, g)), p.projectGrid(Offset(hx, g)), line);
    }
  }

  /// Draw a flower as a flat, camera-facing billboard. Flowers are radially
  /// symmetric, so one sprite looks the same from every angle — no directional
  /// atlas to slice, no wasted memory, no fake snapping.
  void _paintBillboard(Canvas canvas, ui.Image? img, Offset anchor, double t,
      {double height = 1.05, double width = 0.9, double sway = 0}) {
    canvas.drawOval(
        Rect.fromCenter(
            center: anchor.translate(0, t * kVy * 0.16), width: t * 0.5, height: t * kVy * 0.34),
        Paint()..color = const Color(0x33000000));
    if (img == null) return;
    final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    final h = t * height;
    final bottom = anchor.dy + t * kVy * 0.30;
    final dst = Rect.fromCenter(
        center: Offset(anchor.dx + sway, bottom - h / 2), width: t * width, height: h);
    canvas.drawImageRect(img, src, dst, Paint()..filterQuality = FilterQuality.none);
  }

  void _paintCritters(Canvas canvas, Projector p, double t) {
    final s = (t * 0.42).clamp(12.0, 30.0);
    for (final c in critterSystem.critters) {
      final img = sprites.critter(c.kind);
      final amp = c.kind == 'ladybug' ? 0.6 : 2.2;
      final bob = math.sin((time + c.phase) * 9) * amp;
      final at = p.projectGrid(c.pos).translate(0, bob - t * 0.25); // hover above ground
      final rect = Rect.fromCenter(center: at, width: s, height: s);
      if (img != null) {
        // always the same facet (frame 0) so the critter keeps ONE shape and
        // doesn't morph as the camera rotates (#v20). The atlas is still 8-wide.
        const frame = 0;
        final cellW = img.width / kDirFrames;
        canvas.drawImageRect(
            img,
            Rect.fromLTWH(frame * cellW, 0, cellW, img.height.toDouble()),
            rect,
            Paint()..filterQuality = FilterQuality.none);
      } else {
        canvas.drawRect(rect.deflate(s * 0.3), Paint()..color = const Color(0xFF2B2B2B));
      }
    }
  }

  @override
  bool shouldRepaint(covariant GardenPainter old) => true; // driven by ticker
}
