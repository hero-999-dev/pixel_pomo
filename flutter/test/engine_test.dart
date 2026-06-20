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

    test('fit frames the plot inside the bounded forest world, centred', () {
      final cam = GardenCamera();
      const size = Size(360, 720);
      final p = Projector.fit(4, 6, cam, size);
      expect(p.center.dx, closeTo(180, 0.001));
      final cs = p.corners();
      final minX = cs.map((o) => o.dx).reduce(math.min);
      final maxX = cs.map((o) => o.dx).reduce(math.max);
      // the world is plot + a kForestBorder ring each side, so the plot is a
      // framed clearing taking a defined slice of the screen, not most of it (#4)
      expect(maxX - minX, greaterThan(size.width * 0.2));
      expect(maxX - minX, lessThan(size.width * 0.5));
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

  group('bounded forest world (v14)', () {
    test('worldOf adds a fixed border; isGardenTile classifies', () {
      final (wc, wr) = worldOf(10, 16);
      expect(wc, 10 + 2 * kForestBorder);
      expect(wr, 16 + 2 * kForestBorder);
      expect(isGardenTile(0, 0, 10, 16), true); // garden plot is 0..cols-1
      expect(isGardenTile(9, 15, 10, 16), true);
      expect(isGardenTile(-1, 0, 10, 16), false); // forest border
      expect(isGardenTile(10, 0, 10, 16), false);
      expect(isGardenTile(-kForestBorder - 1, 0, 10, 16), false); // beyond the border
    });

    test('clamp keeps pan inside the world; never past the forest edge', () {
      const size = Size(360, 720);
      final cam = GardenCamera(panX: 1e6, panY: 1e6); // shove way out
      cam.clamp(10, 16, size);
      final p = Projector.fit(10, 16, cam, size);
      final maxX = math.max(0.0, (10 / 2 + kForestBorder) * p.t - size.width / 2);
      final maxY = math.max(0.0, (16 / 2 + kForestBorder) * p.t * kVy - size.height / 2);
      expect(cam.panX, closeTo(maxX, 1e-6));
      expect(cam.panY, closeTo(maxY, 1e-6));
    });
  });
}
