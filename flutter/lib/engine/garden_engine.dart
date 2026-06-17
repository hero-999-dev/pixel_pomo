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

/// Solid (post, rail) colours per fence id — fences are drawn as a connected
/// ground network (not billboards), so they're filled rects, not the sprite.
const Map<String, (int, int)> _fencePalette = {
  'fence_wood': (0xFF8B5A2B, 0xFFA9743E),
  'fence_dark': (0xFF3D2814, 0xFF5A3A1E),
  'fence_stone': (0xFF6E6E6E, 0xFF9A9A9A),
};

// ---- sprite bank ------------------------------------------------------------

/// Decoded PNGs from assets/objects/, keyed by id ('grass', the critter kinds,
/// every road id, and 'flower_<id>'). Fences are drawn from [_fencePalette], not
/// loaded here. Loaded once, reused for the scene.
class SpriteBank {
  final Map<String, ui.Image> images;
  const SpriteBank(this.images);

  ui.Image? grass() => images['grass'];
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
      for (final k in CritterSystem.kinds) grab(k, '$k.png'),
      for (final id in Placeables.roadIds) grab(id, '$id.png'),
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

/// Maps garden coords (tile units, centred) → screen and back, with the camera's
/// yaw applied. Fits the whole plot in view at zoom 1; the inverse is exact so
/// taps land on the right tile from any rotation.
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

  static double slabFor(double t) => t * 0.32 + 6;

  double get planeW => n * t;
  double get planeH => n * t * kVy;

  /// Project a continuous garden coordinate (in tile units, plot centred at 0).
  Offset projectGrid(Offset g) {
    final rx = g.dx * _cos - g.dy * _sin;
    final ry = g.dx * _sin + g.dy * _cos;
    return Offset(center.dx + rx * t, center.dy + ry * t * kVy);
  }

  /// Garden coordinate of tile (col,row)'s centre.
  Offset gridOf(int c, int r) => Offset(c - (n - 1) / 2.0, r - (n - 1) / 2.0);
  Offset ground(int c, int r) => projectGrid(gridOf(c, r));
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

  /// The 4 plot corners in screen space (for the slab + bounds + grid), CW.
  List<Offset> corners() {
    final h = n / 2.0;
    return [
      projectGrid(Offset(-h, -h)),
      projectGrid(Offset(h, -h)),
      projectGrid(Offset(h, h)),
      projectGrid(Offset(-h, h)),
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
  final String kind;
  Offset pos; // garden coords (tile units)
  Offset target; // garden coords
  _CState state = _CState.approach;
  double timer = 0;
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
      _stepOne(c, d, half);
    }
    critters.removeWhere((c) =>
        c.state == _CState.leave &&
        (c.pos.dx.abs() > half + 0.5 || c.pos.dy.abs() > half + 0.5));
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
        if (dist > 0.01) c.pos += to / dist * c.speed * 1.4 * dt;
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
  int get _n => garden.size;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Projector.fit(_n, cam, size);
    final t = p.t;
    final slab = Projector.slabFor(t);
    final cs = p.corners();

    // 1) soil slab — extrude each plot edge downward for the 2.5D thickness.
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

    // 2) ground layer (grass + flat roads + connected fences) in garden space,
    //    under the yaw+squash affine, clipped to the plot — rotates cleanly.
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
    _paintFences(canvas);
    canvas.restore();

    // crisp plot outline
    canvas.drawPath(
        plot,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Color(soilColor).withValues(alpha: 0.7));

    // 3) customize gridlines (screen space, uniform width) so it's clear which
    //    tile you'll tap.
    if (customizing) _paintGrid(canvas, p);

    // 4) flowers stand up as billboards, sorted back-to-front by screen depth.
    final standing = <(double, int, String)>[];
    for (var r = 0; r < _n; r++) {
      for (var c = 0; c < _n; c++) {
        final index = r * _n + c;
        final id = garden.flowerAt(index);
        if (id == null || Placeables.isObject(id)) continue;
        standing.add((p.ground(c, r).dy, index, id));
      }
    }
    standing.sort((a, b) => a.$1.compareTo(b.$1));
    for (final (_, index, id) in standing) {
      final sway = math.sin(time * 1.6 + index) * 1.4;
      _paintFlower(canvas, sprites.flower(id), p.groundIndex(index), t, sway);
    }

    // 5) critters on top of everything (projected from garden coords)
    _paintCritters(canvas, p, t);
  }

  void _paintRoads(Canvas canvas) {
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
  }

  /// Fences as a connected ground network: a post per tile + rails toward each
  /// same-fence neighbour (so they join both horizontally and vertically, like
  /// roads) — all in garden space, so they rotate with the map.
  void _paintFences(Canvas canvas) {
    bool same(int idx, String id) =>
        idx >= 0 && idx < _n * _n && garden.flowerAt(idx) == id;
    for (var r = 0; r < _n; r++) {
      for (var c = 0; c < _n; c++) {
        final id = garden.flowerAt(r * _n + c);
        if (id == null || !Placeables.isFence(id)) continue;
        final (postC, railC) = _fencePalette[id]!;
        final gx = c - (_n - 1) / 2.0, gy = r - (_n - 1) / 2.0;
        final rail = Paint()..color = Color(railC);
        final n = same((r - 1) * _n + c, id) && r > 0;
        final s = same((r + 1) * _n + c, id) && r < _n - 1;
        final e = same(r * _n + c + 1, id) && c < _n - 1;
        final w = same(r * _n + c - 1, id) && c > 0;
        if (e) canvas.drawRect(Rect.fromLTWH(gx, gy - 0.07, 0.5, 0.14), rail);
        if (w) canvas.drawRect(Rect.fromLTWH(gx - 0.5, gy - 0.07, 0.5, 0.14), rail);
        if (s) canvas.drawRect(Rect.fromLTWH(gx - 0.07, gy, 0.14, 0.5), rail);
        if (n) canvas.drawRect(Rect.fromLTWH(gx - 0.07, gy - 0.5, 0.14, 0.5), rail);
        if (!n && !s && !e && !w) {
          canvas.drawRect(Rect.fromCenter(center: Offset(gx, gy), width: 0.6, height: 0.14), rail);
        }
        canvas.drawRect(
            Rect.fromCenter(center: Offset(gx, gy), width: 0.28, height: 0.28),
            Paint()..color = Color(postC));
      }
    }
  }

  void _paintGrid(Canvas canvas, Projector p) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0x66FFFFFF);
    final h = _n / 2.0;
    for (var i = 0; i <= _n; i++) {
      final g = -h + i;
      canvas.drawLine(p.projectGrid(Offset(g, -h)), p.projectGrid(Offset(g, h)), line);
      canvas.drawLine(p.projectGrid(Offset(-h, g)), p.projectGrid(Offset(h, g)), line);
    }
  }

  void _paintFlower(Canvas canvas, ui.Image? img, Offset anchor, double t, double sway) {
    canvas.drawOval(
        Rect.fromCenter(
            center: anchor.translate(0, t * kVy * 0.16), width: t * 0.5, height: t * kVy * 0.34),
        Paint()..color = const Color(0x33000000));
    if (img == null) return;
    final h = t * 1.05;
    final bottom = anchor.dy + t * kVy * 0.30;
    final rect = Rect.fromCenter(
        center: Offset(anchor.dx + sway, bottom - h / 2), width: t * 0.9, height: h);
    paintImage(canvas: canvas, rect: rect, image: img, fit: BoxFit.contain, filterQuality: FilterQuality.none);
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
        paintImage(canvas: canvas, rect: rect, image: img, fit: BoxFit.contain, filterQuality: FilterQuality.none);
      } else {
        canvas.drawRect(rect.deflate(s * 0.3), Paint()..color = const Color(0xFF2B2B2B));
      }
    }
  }

  @override
  bool shouldRepaint(covariant GardenPainter old) => true; // driven by ticker
}
