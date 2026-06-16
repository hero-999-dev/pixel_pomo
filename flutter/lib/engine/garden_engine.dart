// ─────────────────────────────────────────────────────────────────────────
//  PixelPomo Garden Engine — a tiny, purpose-built 2.5D scene renderer.
//
//  Not a general game engine (no Unity/Flame): just what a living pixel garden
//  needs — a FIXED oblique "2.5D" projection (no angle controls), a contiguous
//  grass field with a raised soil slab for depth, flat roads, standing fences,
//  and a few tiny critters that drift in, visit a flower, and leave.
//
//  The camera only zooms and pans, and pan is clamped so the garden can never
//  be flung off-screen — it stays put as "your map". Pure rendering + camera
//  math live here; it reads a [Garden] from logic.dart and a [SpriteBank].
// ─────────────────────────────────────────────────────────────────────────
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../logic.dart';

/// Fixed vertical squash of the ground plane — this single constant *is* the
/// 2.5D depth (1.0 would be a flat top-down square). There is no tilt control.
const double kVy = 0.60;

// ---- sprite bank ------------------------------------------------------------

/// Decoded PNGs from assets/objects/, keyed by id ('grass', the critter kinds,
/// every road/fence id, and 'flower_<id>'). Loaded once, reused for the scene.
class SpriteBank {
  final Map<String, ui.Image> images;
  const SpriteBank(this.images);

  ui.Image? grass() => images['grass'];
  ui.Image? object(String id) => images[id]; // roads + fences share their id
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
      for (final k in CritterSystem.kinds) grab(k, '$k.png'),
      for (final id in Placeables.objectIds) grab(id, '$id.png'),
      for (final f in Flowers.all) grab('flower_${f.id}', 'flower_${f.id}.png'),
    ]);
    return SpriteBank(out);
  }
}

// ---- camera -----------------------------------------------------------------

/// Zoom + pan only. [clamp] keeps the garden inside the viewport so it always
/// stays fixed on screen (you can't drag the map away).
class GardenCamera {
  double zoom;
  double panX;
  double panY;

  GardenCamera({this.zoom = 1, this.panX = 0, this.panY = 0});

  void reset() {
    zoom = 1;
    panX = 0;
    panY = 0;
  }

  void clamp(int n, Size size) {
    final p = Projector.fit(n, this, size);
    final slab = Projector.slabFor(p.t);
    final maxX = math.max(0.0, (p.planeW - size.width) / 2);
    final maxY = math.max(0.0, (p.planeH + slab - size.height) / 2);
    panX = panX.clamp(-maxX, maxX);
    panY = panY.clamp(-maxY, maxY);
  }
}

// ---- projection -------------------------------------------------------------

/// Maps tile (col,row) → screen point and back. Fits the whole plot in view at
/// zoom 1, then the camera's zoom/pan scale and shift it. The inverse is exact,
/// so taps land on the right tile.
class Projector {
  final int n;
  final double t; // tile width in px (already includes zoom)
  final Offset center;

  Projector(this.n, this.t, this.center);

  factory Projector.fit(int n, GardenCamera cam, Size size) {
    final fit = math.min(size.width, size.height) / (n + 1);
    final t = fit * cam.zoom;
    return Projector(n, t, Offset(size.width / 2 + cam.panX, size.height / 2 + cam.panY));
  }

  /// Soil-slab thickness (the 2.5D platform edge) for a given tile size.
  static double slabFor(double t) => t * 0.32 + 6;

  double get planeW => n * t;
  double get planeH => n * t * kVy;
  Rect get plane => Rect.fromCenter(center: center, width: planeW, height: planeH);

  Offset ground(int c, int r) => Offset(
        center.dx + (c - (n - 1) / 2.0) * t,
        center.dy + (r - (n - 1) / 2.0) * t * kVy,
      );

  Offset groundIndex(int i) => ground(i % n, i ~/ n);

  int tileAt(Offset p) {
    final c = ((p.dx - center.dx) / t + (n - 1) / 2.0).round();
    final r = ((p.dy - center.dy) / (t * kVy) + (n - 1) / 2.0).round();
    if (c < 0 || r < 0 || c >= n || r >= n) return -1;
    return r * n + c;
  }
}

// ---- critters ---------------------------------------------------------------

enum _CState { approach, hover, leave }

/// A tiny visiting creature (bee / butterfly / ladybug). It enters from a screen
/// edge, flies to a flower, hovers as if sniffing, then leaves and despawns.
class Critter {
  final String kind;
  Offset pos;
  Offset target;
  _CState state = _CState.approach;
  double timer = 0; // seconds in the current state
  final double speed; // px/sec
  final double phase; // flight-wobble offset
  final double hoverFor; // seconds to linger on the flower

  Critter(this.kind, this.pos, this.target, this.speed, this.phase, this.hoverFor);
}

/// Owns the (at most 2) active critters and spawns them occasionally. Needs the
/// current flower screen positions each step so visitors actually head to blooms.
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

  void step(double dt, Size bounds, List<Offset> flowers) {
    final d = dt.clamp(0.0, 0.05);
    time += d;
    _spawnIn -= d;
    if (_spawnIn <= 0) {
      _spawnIn = 6 + _r.nextDouble() * 8; // a visitor every ~6–14s
      if (critters.length < maxActive && flowers.isNotEmpty && bounds != Size.zero) {
        _spawn(bounds, flowers);
      }
    }
    for (final c in critters) {
      _stepOne(c, d, bounds);
    }
    final viewport = (Offset.zero & bounds).inflate(48);
    critters.removeWhere((c) => c.state == _CState.leave && !viewport.contains(c.pos));
  }

  void _spawn(Size b, List<Offset> flowers) {
    final start = switch (_r.nextInt(4)) {
      0 => Offset(_r.nextDouble() * b.width, -24),
      1 => Offset(b.width + 24, _r.nextDouble() * b.height),
      2 => Offset(_r.nextDouble() * b.width, b.height + 24),
      _ => Offset(-24, _r.nextDouble() * b.height),
    };
    final target = flowers[_r.nextInt(flowers.length)];
    critters.add(Critter(
      kinds[_r.nextInt(kinds.length)],
      start,
      target,
      36 + _r.nextDouble() * 28,
      _r.nextDouble() * math.pi * 2,
      2.0 + _r.nextDouble() * 2.5,
    ));
  }

  void _stepOne(Critter c, double dt, Size b) {
    c.timer += dt;
    final to = c.target - c.pos;
    final dist = to.distance;
    switch (c.state) {
      case _CState.approach:
        if (dist < 6) {
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
          // exit toward the nearest screen edge
          final ex = c.pos.dx < b.width / 2 ? -60.0 : b.width + 60.0;
          c.target = Offset(ex, c.pos.dy - 30);
        }
        break;
      case _CState.leave:
        if (dist > 0.1) c.pos += to / dist * c.speed * 1.4 * dt;
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
  final int groundColor;
  final int soilColor;

  GardenPainter({
    required this.garden,
    required this.cam,
    required this.sprites,
    required this.critterSystem,
    required this.groundColor,
    required this.soilColor,
    required Listenable repaint,
  }) : super(repaint: repaint);

  double get time => critterSystem.time;
  int get _n => garden.size;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Projector.fit(_n, cam, size);
    final t = p.t;
    final plane = p.plane;
    final slab = Projector.slabFor(t);

    // 1) raised soil slab under the front edge → the 2.5D platform thickness
    final soil = Paint()..color = Color(soilColor);
    canvas.drawRect(
        Rect.fromLTRB(plane.left, plane.bottom, plane.right, plane.bottom + slab), soil);
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
        scale: grass.width / t,
        filterQuality: FilterQuality.none,
        alignment: Alignment.topLeft,
      );
    } else {
      canvas.drawRect(plane, Paint()..color = Color(groundColor));
    }

    // 3) flat surfaces (roads) sit on the ground, drawn one full texture per tile
    for (var r = 0; r < _n; r++) {
      for (var c = 0; c < _n; c++) {
        final id = garden.flowerAt(r * _n + c);
        if (id == null || !Placeables.isRoad(id)) continue;
        final img = sprites.object(id);
        final rect = Rect.fromCenter(center: p.ground(c, r), width: t, height: t * kVy);
        if (img != null) {
          paintImage(canvas: canvas, rect: rect, image: img, fit: BoxFit.fill, filterQuality: FilterQuality.none);
        } else {
          canvas.drawRect(rect, Paint()..color = const Color(0xFFB7A687));
        }
      }
    }
    canvas.restore();

    // crisp slab-top outline
    canvas.drawRect(
        plane,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Color(soilColor).withValues(alpha: 0.7));

    // 4) standing things (fences + flowers) back-to-front so nearer rows overlap
    for (var r = 0; r < _n; r++) {
      for (var c = 0; c < _n; c++) {
        final index = r * _n + c;
        final id = garden.flowerAt(index);
        if (id == null || Placeables.isRoad(id)) continue;
        if (Placeables.isFence(id)) {
          _paintStanding(canvas, sprites.object(id), p.ground(c, r), t, height: t, sway: 0);
        } else {
          final sway = math.sin(time * 1.6 + index) * 1.4;
          _paintStanding(canvas, sprites.flower(id), p.ground(c, r), t, height: t * 1.05, sway: sway);
        }
      }
    }

    // 5) critters on top of everything
    _paintCritters(canvas, t);
  }

  /// Draw a billboard sprite standing up with its base resting on the tile
  /// (toward the front), plus a soft contact shadow — so nothing floats.
  void _paintStanding(Canvas canvas, ui.Image? img, Offset anchor, double t,
      {required double height, required double sway}) {
    canvas.drawOval(
        Rect.fromCenter(
            center: anchor.translate(0, t * kVy * 0.16), width: t * 0.5, height: t * kVy * 0.34),
        Paint()..color = const Color(0x33000000));
    if (img == null) return;
    final bottom = anchor.dy + t * kVy * 0.30;
    final rect = Rect.fromCenter(
        center: Offset(anchor.dx + sway, bottom - height / 2), width: t * 0.9, height: height);
    paintImage(canvas: canvas, rect: rect, image: img, fit: BoxFit.contain, filterQuality: FilterQuality.none);
  }

  void _paintCritters(Canvas canvas, double t) {
    final s = (t * 0.42).clamp(12.0, 30.0);
    for (final c in critterSystem.critters) {
      final img = sprites.critter(c.kind);
      // gentle flight wobble; ladybugs sit calmer
      final amp = c.kind == 'ladybug' ? 0.6 : 2.2;
      final bob = math.sin((time + c.phase) * 9) * amp;
      final rect = Rect.fromCenter(center: c.pos.translate(0, bob), width: s, height: s);
      if (img != null) {
        paintImage(canvas: canvas, rect: rect, image: img, fit: BoxFit.contain, filterQuality: FilterQuality.none);
      } else {
        canvas.drawRect(rect.deflate(s * 0.3), Paint()..color = const Color(0xFF2B2B2B));
      }
    }
  }

  @override
  bool shouldRepaint(covariant GardenPainter old) => true; // driven by ticker
}
