// ─────────────────────────────────────────────────────────────────────────
//  PixelPomo Garden Engine — a tiny, purpose-built 2.5D scene renderer.
//
//  Not a general game engine (no Unity/Flame): just what a living pixel garden
//  needs — a 2.5D projection with a fixed tilt but a hand-controllable compass
//  rotation (look from N/E/S/W like Google Maps), a contiguous grass field with
//  a raised soil slab for depth, flat roads, standing fences, and a few tiny
//  critters that drift in, visit a flower, and leave.
//
//  The camera zooms, pans (clamped so the garden can't leave the screen) and
//  yaws (two-finger twist). Pure rendering + camera math live here; it reads a
//  [Garden] from logic.dart and a [SpriteBank].
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

  void clamp(int n, Size size) {
    final p = Projector.fit(n, this, size);
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
}

// ---- projection -------------------------------------------------------------

/// Maps tile (col,row) → screen point and back, with the camera's yaw applied.
/// Fits the whole plot in view at zoom 1; the inverse is exact so taps land on
/// the right tile from any rotation.
class Projector {
  final int n;
  final double t; // tile size in px (already includes zoom)
  final Offset center;
  final double yaw;
  late final double _cos = math.cos(yaw);
  late final double _sin = math.sin(yaw);

  Projector(this.n, this.t, this.center, this.yaw);

  factory Projector.fit(int n, GardenCamera cam, Size size) {
    final fit = math.min(size.width, size.height) / (n + 1);
    final t = fit * cam.zoom;
    return Projector(
        n, t, Offset(size.width / 2 + cam.panX, size.height / 2 + cam.panY), cam.yaw);
  }

  /// Soil-slab thickness (the 2.5D platform edge) for a given tile size.
  static double slabFor(double t) => t * 0.32 + 6;

  Offset _proj(double gx, double gy) {
    final rx = gx * _cos - gy * _sin;
    final ry = gx * _sin + gy * _cos;
    return Offset(center.dx + rx * t, center.dy + ry * t * kVy);
  }

  Offset ground(int c, int r) => _proj(c - (n - 1) / 2.0, r - (n - 1) / 2.0);
  Offset groundIndex(int i) => ground(i % n, i ~/ n);

  int tileAt(Offset p) {
    final dx = (p.dx - center.dx) / t;
    final dy = (p.dy - center.dy) / (t * kVy);
    final gx = dx * _cos + dy * _sin; // inverse rotation
    final gy = -dx * _sin + dy * _cos;
    final c = (gx + (n - 1) / 2.0).round();
    final r = (gy + (n - 1) / 2.0).round();
    if (c < 0 || r < 0 || c >= n || r >= n) return -1;
    return r * n + c;
  }

  /// The 4 plot corners in screen space (for the slab + bounds), CW.
  List<Offset> corners() {
    final h = n / 2.0;
    return [_proj(-h, -h), _proj(h, -h), _proj(h, h), _proj(-h, h)];
  }

  /// Affine that maps grid coords (tile units, centred) → screen, so the ground
  /// layer can be drawn axis-aligned and the canvas handles yaw + squash.
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
    final slab = Projector.slabFor(t);
    final cs = p.corners();

    // 1) soil slab — extrude each plot edge downward for the 2.5D thickness.
    final soil = Paint()..color = Color(soilColor);
    final soilDim = Paint()..color = Color(soilColor).withValues(alpha: 0.55);
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
    // a darker lip along the very bottom of the slab
    for (var i = 0; i < 4; i++) {
      final a = cs[i], b = cs[(i + 1) % 4];
      canvas.drawPath(
          Path()
            ..moveTo(a.dx, a.dy + slab - 3)
            ..lineTo(b.dx, b.dy + slab - 3)
            ..lineTo(b.dx, b.dy + slab)
            ..lineTo(a.dx, a.dy + slab)
            ..close(),
          soilDim);
    }

    // 2) ground layer (grass + flat roads) drawn in grid space under the
    //    yaw+squash affine, clipped to the plot quad — no gaps, rotates cleanly.
    final grass = sprites.grass();
    final plot = Path()
      ..moveTo(cs[0].dx, cs[0].dy)
      ..lineTo(cs[1].dx, cs[1].dy)
      ..lineTo(cs[2].dx, cs[2].dy)
      ..lineTo(cs[3].dx, cs[3].dy)
      ..close();
    canvas.save();
    canvas.clipPath(plot);
    canvas.transform(p.gridToScreen());
    final half = _n / 2.0;
    final gridRect = Rect.fromLTWH(-half, -half, _n.toDouble(), _n.toDouble());
    if (grass != null) {
      paintImage(
        canvas: canvas,
        rect: gridRect,
        image: grass,
        fit: BoxFit.none,
        repeat: ImageRepeat.repeat,
        scale: grass.width.toDouble(), // one grass tile == one grid unit
        filterQuality: FilterQuality.none,
        alignment: Alignment.topLeft,
      );
    } else {
      canvas.drawRect(gridRect, Paint()..color = Color(groundColor));
    }
    for (var r = 0; r < _n; r++) {
      for (var c = 0; c < _n; c++) {
        final id = garden.flowerAt(r * _n + c);
        if (id == null || !Placeables.isRoad(id)) continue;
        final img = sprites.object(id);
        final dst = Rect.fromCenter(
            center: Offset(c - (_n - 1) / 2.0, r - (_n - 1) / 2.0), width: 1, height: 1);
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
    canvas.restore();

    // crisp plot outline
    canvas.drawPath(
        plot,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Color(soilColor).withValues(alpha: 0.7));

    // 3) standing things (fences + flowers) sorted back-to-front by screen-y so
    //    nearer ones overlap — correct from any rotation.
    final standing = <(double, int, String)>[];
    for (var r = 0; r < _n; r++) {
      for (var c = 0; c < _n; c++) {
        final index = r * _n + c;
        final id = garden.flowerAt(index);
        if (id == null || Placeables.isRoad(id)) continue;
        standing.add((p.ground(c, r).dy, index, id));
      }
    }
    standing.sort((a, b) => a.$1.compareTo(b.$1));
    for (final (_, index, id) in standing) {
      final base = p.groundIndex(index);
      if (Placeables.isFence(id)) {
        _paintStanding(canvas, sprites.object(id), base, t, height: t, sway: 0);
      } else {
        final sway = math.sin(time * 1.6 + index) * 1.4;
        _paintStanding(canvas, sprites.flower(id), base, t, height: t * 1.05, sway: sway);
      }
    }

    // 4) critters on top of everything
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
