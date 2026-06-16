// ─────────────────────────────────────────────────────────────────────────
//  PixelPomo Garden Engine — a tiny, purpose-built 2.5D scene renderer.
//
//  Not a general game engine (no Unity/Flame): just the few things a living
//  pixel garden needs — an oblique "look-from-above" projection you can tilt,
//  pinch-zoom and pan; a contiguous grass field with no gaps; sim-game style
//  auto-connecting roads & fences; and a flock of wandering pixel bugs.
//
//  Pure rendering + camera math live here; it reads a [Garden] from logic.dart
//  and an immutable [SpriteBank]. The widget [GardenView] owns the camera and
//  the animation ticker.
// ─────────────────────────────────────────────────────────────────────────
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../logic.dart';

// ---- sprite bank ------------------------------------------------------------

/// Decoded PNGs from assets/objects/, keyed by id ('grass','bug','road',
/// 'fence', and every flower id). Loaded once, reused for the scene's life.
class SpriteBank {
  final Map<String, ui.Image> images;
  const SpriteBank(this.images);

  ui.Image? grass() => images['grass'];
  ui.Image? bug() => images['bug'];
  ui.Image? object(String id) => images[id];
  ui.Image? flower(String id) => images['flower_$id'];

  static Future<SpriteBank> load() async {
    final names = <String>['grass', 'bug', 'road', 'fence'];
    final out = <String, ui.Image>{};
    Future<void> grab(String key, String asset) async {
      final data = await rootBundle.load('assets/objects/$asset');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      out[key] = (await codec.getNextFrame()).image;
    }

    await Future.wait([
      for (final n in names) grab(n, '$n.png'),
      for (final f in Flowers.all) grab('flower_${f.id}', 'flower_${f.id}.png'),
    ]);
    return SpriteBank(out);
  }
}

// ---- camera -----------------------------------------------------------------

/// The viewing transform. [pitch] 0 = straight top-down (a flat square grid),
/// 1 = strongly tilted oblique view where objects stand up — "change the angle
/// you look from above". Oblique (no yaw) keeps the plot a rectangle and makes
/// the screen↔tile inverse exact, so taps land on the right tile.
class GardenCamera {
  double zoom;
  double panX;
  double panY;
  double pitch; // 0..1

  GardenCamera({this.zoom = 1, this.panX = 0, this.panY = 0, this.pitch = 0.6});

  /// Vertical squash of the ground plane (1 = top-down square).
  double get _vy => _lerp(1.0, 0.46, pitch);

  /// How far objects rise off the ground (tile fraction) as we tilt.
  double get _heightFactor => _lerp(0.0, 0.95, pitch);

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

// ---- bugs -------------------------------------------------------------------

/// A wandering pixel critter. Each gets a random start, speed, hue tint and a
/// meandering steer so no two trace the same path ("random patterns").
class Bug {
  double x, y; // screen px
  double angle; // radians, heading
  final double speed;
  final double wobble; // steering noise frequency
  double phase;
  final double scale;
  final Color tint;

  Bug(this.x, this.y, this.angle, this.speed, this.wobble, this.phase, this.scale, this.tint);

  factory Bug.random(math.Random r, Size bounds) {
    const tints = [
      Color(0xFF2B2B2B), Color(0xFF3A2E1A), Color(0xFF243A1A), Color(0xFF1A2A3A),
    ];
    return Bug(
      r.nextDouble() * bounds.width,
      r.nextDouble() * bounds.height,
      r.nextDouble() * math.pi * 2,
      26 + r.nextDouble() * 38, // px/sec
      0.6 + r.nextDouble() * 1.8,
      r.nextDouble() * math.pi * 2,
      0.8 + r.nextDouble() * 0.9,
      tints[r.nextInt(tints.length)],
    );
  }

  void step(double dt, Size bounds, math.Random r) {
    phase += dt * wobble;
    // gently steer, with the occasional sharp turn for variety
    angle += math.sin(phase) * dt * 2.4;
    if (r.nextDouble() < dt * 0.4) angle += (r.nextDouble() - 0.5) * 1.6;
    x += math.cos(angle) * speed * dt;
    y += math.sin(angle) * speed * dt * 0.7; // flatter horizontal drift
    // wrap with a small margin so they fly in and out of view
    const m = 16.0;
    if (x < -m) x = bounds.width + m;
    if (x > bounds.width + m) x = -m;
    if (y < -m) y = bounds.height + m;
    if (y > bounds.height + m) y = -m;
  }
}

/// Owns the flock and steps it. Bug count scales with the plot size.
class BugSystem {
  final math.Random _r;
  final List<Bug> bugs = [];
  Size _bounds = Size.zero;
  int _target = 0;
  double time = 0; // seconds elapsed, read live by the painter each frame

  BugSystem([int? seed]) : _r = math.Random(seed);

  void configure(Size bounds, int gardenSize) {
    _bounds = bounds;
    _target = (gardenSize * gardenSize / 3).clamp(6, 22).round();
    while (bugs.length < _target) {
      bugs.add(Bug.random(_r, bounds));
    }
    if (bugs.length > _target) bugs.removeRange(_target, bugs.length);
  }

  void step(double dt) {
    final clamped = dt.clamp(0.0, 0.05); // ignore long frame gaps
    time += clamped;
    if (_bounds == Size.zero) return;
    for (final b in bugs) {
      b.step(clamped, _bounds, _r);
    }
  }
}

// ---- painter ----------------------------------------------------------------

class GardenPainter extends CustomPainter {
  final Garden garden;
  final GardenCamera cam;
  final SpriteBank sprites;
  final BugSystem bugSystem;
  final int groundColor;
  final int soilColor;

  GardenPainter({
    required this.garden,
    required this.cam,
    required this.sprites,
    required this.bugSystem,
    required this.groundColor,
    required this.soilColor,
    required Listenable repaint,
  }) : super(repaint: repaint);

  /// Live animation clock (advanced by the ticker via [BugSystem]).
  double get time => bugSystem.time;

  int get _n => garden.size;
  double _tile(Size size) {
    // base tile fits the whole plot inside the view, then the camera zoom scales it
    final fit = math.min(size.width, size.height) / (_n + 1);
    return fit * cam.zoom;
  }

  Offset _center(Size size) =>
      Offset(size.width / 2 + cam.panX, size.height / 2 + cam.panY);

  /// Ground-plane projection of tile (c,r) centre.
  Offset _project(int c, int r, Size size, double t) {
    final cx = _center(size);
    final gx = c - (_n - 1) / 2.0;
    final gy = r - (_n - 1) / 2.0;
    return Offset(cx.dx + gx * t, cx.dy + gy * t * cam._vy);
  }

  /// Inverse of [_project] (ground, ignoring object height) → tile index, or -1.
  int tileAt(Offset p, Size size) {
    final t = _tile(size);
    final cx = _center(size);
    final gx = (p.dx - cx.dx) / t;
    final gy = (p.dy - cx.dy) / (t * cam._vy);
    final c = (gx + (_n - 1) / 2.0).round();
    final r = (gy + (_n - 1) / 2.0).round();
    if (c < 0 || r < 0 || c >= _n || r >= _n) return -1;
    return r * _n + c;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = _tile(size);
    final cx = _center(size);
    final halfW = _n * t / 2;
    final halfH = _n * t * cam._vy / 2;
    final plane = Rect.fromLTRB(cx.dx - halfW, cx.dy - halfH, cx.dx + halfW, cx.dy + halfH);

    // 1) raised soil slab under the front edge → the 2.5D platform thickness
    final slab = (t * 0.5 * cam._heightFactor) + 6;
    final soil = Paint()..color = Color(soilColor);
    canvas.drawRect(Rect.fromLTRB(plane.left, plane.bottom, plane.right, plane.bottom + slab), soil);
    canvas.drawRect(
        Rect.fromLTRB(plane.left, plane.bottom + slab - 3, plane.right, plane.bottom + slab),
        Paint()..color = Color(soilColor).withValues(alpha: 0.55));

    // 2) contiguous grass field (tiled PNG, no gaps), clipped to the plane
    final grass = sprites.grass();
    canvas.save();
    canvas.clipRect(plane);
    if (grass != null) {
      paintImage(
        canvas: canvas,
        rect: plane,
        image: grass,
        fit: BoxFit.none,
        repeat: ImageRepeat.repeat,
        scale: grass.width / (t * 0.9),
        filterQuality: FilterQuality.none,
        alignment: Alignment.topLeft,
      );
    } else {
      canvas.drawRect(plane, Paint()..color = Color(groundColor));
    }
    canvas.restore();

    // thin outline on the grass top for a crisp slab edge
    canvas.drawRect(
        plane,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Color(soilColor).withValues(alpha: 0.7));

    // 3) tiles back-to-front (row ascending), objects then flowers
    for (var r = 0; r < _n; r++) {
      for (var c = 0; c < _n; c++) {
        final index = r * _n + c;
        final id = garden.flowerAt(index);
        if (id == null) continue;
        final base = _project(c, r, size, t);
        if (Placeables.isObject(id)) {
          _paintObject(canvas, id, index, base, t);
        } else {
          _paintFlower(canvas, id, base, t, index);
        }
      }
    }

    // 4) bugs on top of everything
    _paintBugs(canvas);
  }

  void _paintObject(Canvas canvas, String id, int index, Offset base, double t) {
    final mask = Placeables.connects(id) ? garden.connectionMask(index) : 0;
    final img = sprites.object(id);
    final tileRect = Rect.fromCenter(center: base, width: t, height: t * cam._vy);
    // lay the object flat on the ground
    if (img != null) {
      paintImage(
        canvas: canvas,
        rect: tileRect,
        image: img,
        fit: BoxFit.fill,
        filterQuality: FilterQuality.none,
      );
    } else {
      canvas.drawRect(tileRect, Paint()..color = const Color(0xFFB7A687));
    }
    // connectors: bridge the gap toward each same-kind neighbour so the path/
    // fence reads as continuous like in a simulation game
    if (mask != 0) {
      final conn = Paint()
        ..color = (id == Placeables.road ? const Color(0xFF8C7C5E) : const Color(0xFFA9743E));
      final w = t * 0.34;
      final hv = t * cam._vy;
      if (mask & 1 != 0) canvas.drawRect(Rect.fromCenter(center: base.translate(0, -hv / 2), width: w, height: hv * 0.5), conn);
      if (mask & 4 != 0) canvas.drawRect(Rect.fromCenter(center: base.translate(0, hv / 2), width: w, height: hv * 0.5), conn);
      if (mask & 2 != 0) canvas.drawRect(Rect.fromCenter(center: base.translate(t / 2, 0), width: t * 0.5, height: w * cam._vy), conn);
      if (mask & 8 != 0) canvas.drawRect(Rect.fromCenter(center: base.translate(-t / 2, 0), width: t * 0.5, height: w * cam._vy), conn);
    }
  }

  void _paintFlower(Canvas canvas, String id, Offset base, double t, int index) {
    final img = sprites.flower(id);
    final h = t * 1.05;
    // stand the flower up off the ground as the camera tilts; gentle idle sway
    final rise = t * cam._heightFactor;
    final sway = math.sin(time * 1.6 + index) * 1.5 * cam._heightFactor;
    final center = base.translate(sway, -rise - h / 2 + t * cam._vy / 2);
    final rect = Rect.fromCenter(center: center, width: t * 0.92, height: h);
    // soft contact shadow on the ground
    canvas.drawOval(
        Rect.fromCenter(center: base.translate(0, t * cam._vy * 0.18), width: t * 0.5, height: t * cam._vy * 0.34),
        Paint()..color = const Color(0x33000000));
    if (img != null) {
      paintImage(canvas: canvas, rect: rect, image: img, fit: BoxFit.contain, filterQuality: FilterQuality.none);
    }
  }

  void _paintBugs(Canvas canvas) {
    final img = sprites.bug();
    for (final b in bugSystem.bugs) {
      final s = 11.0 * b.scale;
      final bob = math.sin((time + b.phase) * 8) * 1.5;
      final rect = Rect.fromCenter(center: Offset(b.x, b.y + bob), width: s, height: s);
      if (img != null) {
        paintImage(
          canvas: canvas,
          rect: rect,
          image: img,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.none,
          colorFilter: ColorFilter.mode(b.tint.withValues(alpha: 0.85), BlendMode.modulate),
        );
      } else {
        canvas.drawRect(rect.deflate(s * 0.3), Paint()..color = b.tint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant GardenPainter old) => true; // driven by ticker
}
