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

  group('WorldGrid claimed vs forest', () {
    test('claimed window is centred inside the forest margin', () {
      const w = WorldGrid(cols: 4, rows: 6, margin: 2);
      expect(w.worldCols, 8);
      expect(w.worldRows, 10);
      // corners are forest
      expect(w.isClaimed(0, 0), false);
      expect(w.isClaimed(7, 9), false);
      // centre 4x6 block (cols 2..5, rows 2..7) is claimed
      expect(w.isClaimed(2, 2), true);
      expect(w.isClaimed(5, 7), true);
      expect(w.isClaimed(1, 2), false); // just outside claimed, in margin
      // claimed index round-trips: world (5,7) → claimed (3,5) → 5*4+3 = 23
      expect(w.claimedIndex(2, 2), 0);
      expect(w.claimedIndex(5, 7), 23);
      expect(w.claimedIndex(0, 0), -1);
    });

    test('forest stays a constant-thickness ring as the plot grows', () {
      const before = WorldGrid(cols: 4, rows: 6, margin: 2);
      const after = WorldGrid(cols: 6, rows: 8, margin: 2);
      // forest is always a `margin`-thick border around the claimed centre, so
      // each EXPAND converts the inner forest ring to grass while the woods stay.
      expect(before.worldCols - before.cols, 2 * before.margin);
      expect(after.worldCols - after.cols, 2 * after.margin);
      expect(after.cols, before.cols + 2); // claimed grew by one ring
      // the claimed window stays centred (top-left claimed tile is at margin)
      expect(before.isClaimed(before.margin, before.margin), true);
      expect(after.isClaimed(after.margin, after.margin), true);
    });
  });
}
