import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_pomo/engine/garden_engine.dart';

// Geometry for the v10 low-poly 3D fence pipeline. The garden has a fixed camera
// tilt and a hand-controlled compass yaw, so true vertical height must map
// straight up the screen and stay the same from every angle (uniform sky light,
// no moving sun). A fence post is a real 3D box, not a flat billboard, so it
// never collapses to a thin antenna when the camera turns.
void main() {
  group('Projector elevation (uniform, sun-free vertical)', () {
    test('raising a point moves it straight up by e*t, for any yaw', () {
      const t = 40.0;
      const center = Offset(200, 300);
      for (final yaw in [0.0, 0.5, 1.3, math.pi, -2.0]) {
        final p = Projector(6, 6, t, center, yaw);
        const g = Offset(1.5, -2.0);
        final ground = p.projectGrid(g);
        final raised = p.projectElevated(g, 0.75);
        expect(raised.dx, closeTo(ground.dx, 1e-9)); // no horizontal shift
        expect(raised.dy, closeTo(ground.dy - 0.75 * t, 1e-9)); // straight up by e*t
      }
    });
  });

  group('Fence post box geometry (real 3D, not a billboard)', () {
    final p = Projector(6, 6, 40.0, const Offset(200, 300), 0.7);
    const center = Offset.zero;

    test('returns 8 corners: a base ring and a top ring directly above it', () {
      final c = boxCorners(p, center, 0.1, 0.6);
      expect(c.length, 8);
      for (var i = 0; i < 4; i++) {
        expect(c[i + 4].dx, closeTo(c[i].dx, 1e-9)); // top directly above base
        expect(c[i + 4].dy, closeTo(c[i].dy - 0.6 * p.t, 1e-9)); // by height*t
      }
    });

    test('base ring is centred on the tile and spans real width from any angle', () {
      for (final yaw in [0.0, 0.7, 2.4, -1.1]) {
        final pp = Projector(6, 6, 40.0, const Offset(200, 300), yaw);
        final base = boxCorners(pp, center, 0.12, 0.6).sublist(0, 4);
        final cx = base.map((o) => o.dx).reduce((a, b) => a + b) / 4;
        final cy = base.map((o) => o.dy).reduce((a, b) => a + b) / 4;
        final groundCentre = pp.projectGrid(center);
        expect(cx, closeTo(groundCentre.dx, 1e-6));
        expect(cy, closeTo(groundCentre.dy, 1e-6));
        // a real footprint area from every angle — this is what fixes the
        // "fence collapses to a thin metallic antenna" bug under rotation.
        final spanX =
            base.map((o) => o.dx).reduce(math.max) - base.map((o) => o.dx).reduce(math.min);
        expect(spanX, greaterThan(2), reason: 'yaw=$yaw');
      }
    });
  });

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

    test('fit sizes the plot to most of the screen, centred (#v18)', () {
      final cam = GardenCamera();
      const size = Size(360, 720);
      final p = Projector.fit(4, 6, cam, size);
      expect(p.center.dx, closeTo(180, 0.001));
      final cs = p.corners();
      final minX = cs.map((o) => o.dx).reduce(math.min);
      final maxX = cs.map((o) => o.dx).reduce(math.max);
      // plot-based fit with a small forest margin → the plot fills most of the
      // width; the screen-filling forest covers the rest (#v18)
      expect(maxX - minX, greaterThan(size.width * 0.5));
      expect(maxX - minX, lessThan(size.width * 0.85));
    });
  });

  group('CritterSystem no stuck critters (v12)', () {
    test('a critter always despawns within its max lifetime', () {
      final sys = CritterSystem(7);
      final flowers = [const Offset(0, 0)];
      for (var i = 0; i < 4000; i++) {
        sys.step(0.05, 6, flowers); // 200s total
      }
      expect(sys.critters.length, lessThanOrEqualTo(CritterSystem.maxActive));
      for (final c in sys.critters) {
        expect(c.life, lessThanOrEqualTo(Critter.maxLife + 0.2));
      }
    });
  });

  group('forest variety (v13)', () {
    test('forestPropAt is deterministic, in-range, with gaps', () {
      var trees = 0, bushes = 0, rocks = 0, gaps = 0;
      for (var c = -20; c < 20; c++) {
        for (var r = -20; r < 20; r++) {
          final id = forestPropAt(c, r);
          expect(forestPropAt(c, r), id); // stable
          if (id == null) {
            gaps++;
            continue;
          }
          if (id.startsWith('tree_')) {
            trees++;
            expect(int.parse(id.substring(5)) < kForestTrees, true);
          } else if (id.startsWith('bush_')) {
            bushes++;
            expect(int.parse(id.substring(5)) < kForestBushes, true);
          } else if (id.startsWith('rock_')) {
            rocks++;
            expect(int.parse(id.substring(5)) < kForestRocks, true);
          } else {
            fail('unexpected $id');
          }
        }
      }
      expect(trees > bushes && bushes > rocks && gaps > 0, true);
    });
  });

  group('Projector forest fill (v12)', () {
    test('gridAt inverts ground for fractional coords at several yaws', () {
      const cols = 4, rows = 6, t = 40.0;
      const center = Offset(200, 400);
      for (final yaw in [0.0, 0.7, -1.3]) {
        final p = Projector(cols, rows, t, center, yaw);
        for (final g in [const Offset(0, 0), const Offset(2.5, 3.5), const Offset(-3, 8)]) {
          // gridOfD treats (g.dx,g.dy) as (col,row); gridAt must invert back to it
          final screen = p.projectGrid(p.gridOfD(g.dx, g.dy));
          final back = p.gridAt(screen);
          expect(back.dx, closeTo(g.dx, 1e-6));
          expect(back.dy, closeTo(g.dy, 1e-6));
        }
      }
    });

  });

  group('screen-filling forest + roam clamp (#v18)', () {
    test('isGardenTile classifies plot vs surrounding forest', () {
      expect(isGardenTile(0, 0, 10, 20), true);
      expect(isGardenTile(9, 19, 10, 20), true);
      expect(isGardenTile(-1, 0, 10, 20), false); // forest
      expect(isGardenTile(10, 0, 10, 20), false);
      expect(isGardenTile(0, 20, 10, 20), false);
    });

    test('visibleTileBounds spans beyond the plot to fill the screen', () {
      const size = Size(360, 720);
      final p = Projector.fit(10, 20, GardenCamera(), size);
      final b = p.visibleTileBounds(size);
      expect(b.minR < 0, true); // forest above the plot
      expect(b.maxR > 19, true); // forest below the plot
      expect(b.maxC - b.minC >= 10, true);
    });

    test('clamp bounds pan to a roam radius (no infinite roam)', () {
      const size = Size(360, 720);
      final cam = GardenCamera(panX: 1e6, panY: 1e6); // shove way out
      cam.clamp(10, 20, size);
      final p = Projector.fit(10, 20, cam, size);
      const roam = 20.0; // max(cols, rows)
      final maxX = (10 / 2 + roam) * p.t;
      final maxY = (20 / 2 + roam) * p.t * kVy;
      expect(cam.panX, closeTo(maxX, 1e-6));
      expect(cam.panY, closeTo(maxY, 1e-6));
    });
  });
}
