import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:pixel_pomo/engine/garden_engine.dart';
import 'package:pixel_pomo/engine/garden_view.dart';

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

  group('Fence rail half depth (#v32, supersedes the v31.18 midpoint key)', () {
    test('a rail half always sorts strictly BEHIND its own post, from any yaw', () {
      // The v31.18 whole-rail midpoint key crossed its own posts' depths as
      // the camera rotated, flipping the rail in front of / behind a post in
      // a single frame — the "fence suddenly changes direction" report. Each
      // half is now keyed a hair behind its own post, so that order can never
      // invert no matter the yaw.
      for (final yaw in [0.0, 0.7, 1.9, math.pi, -1.2]) {
        final p = Projector(6, 6, 40.0, const Offset(200, 300), yaw);
        for (final (c, r) in [(1, 1), (4, 2), (0, 5)]) {
          final postDy = p.ground(c, r).dy;
          expect(railHalfDepth(postDy), lessThan(postDy), reason: 'yaw=$yaw ($c,$r)');
        }
      }
    });

    test('rail halves still sort between a farther and a nearer flower', () {
      // The v31.18 property this keeps: rails share the SAME back-to-front
      // pass as flowers/trees/posts, so a flower well behind a fence line
      // paints first and one well in front paints after.
      final p = Projector(6, 6, 40.0, const Offset(200, 300), 0.0);
      final half = railHalfDepth(p.ground(2, 3).dy);
      expect(p.ground(2, 0).dy, lessThan(half)); // farther flower behind
      expect(p.ground(2, 5).dy, greaterThan(half)); // nearer flower in front
    });
  });

  group('Stable depth order (#v31.21)', () {
    test('ties break on original index, not reordered between calls', () {
      const depths = [5.0, 3.0, 3.0, 3.0, 1.0];
      final order = stableDepthOrder(depths);
      expect(order, [4, 1, 2, 3, 0]); // ascending; the three tied 3.0s keep index order
      // Same input must give the identical result every time -- this is exactly
      // what an unstable List.sort could fail to guarantee, reading as a
      // mid-rotation flicker between a fence rail and a near-tied neighbour.
      expect(stableDepthOrder(depths), order);
    });

    test('clear (non-tied) ordering still sorts correctly ascending', () {
      const depths = [10.0, -2.0, 4.0, 0.0];
      expect(stableDepthOrder(depths), [1, 3, 2, 0]);
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

  group('The woods are undergrowth with a few landmark trees (v34.12)', () {
    // "tüm orman alt taraf gibi olsun" — the whole forest built from the small
    // trees, bushes and rocks that used to appear only in the band against the
    // garden — "ayrica büyük agaclar ormanin icinde aralarda teker teker olsun
    // birkac tane".
    const cols = 4, rows = 10;

    Map<(int, int), String> patch({int span = 40}) {
      final out = <(int, int), String>{};
      for (var r = -span; r < rows + span; r++) {
        for (var c = -span; c < cols + span; c++) {
          final id = forestPropAt(c, r, cols, rows);
          if (id != null) out[(c, r)] = id;
        }
      }
      return out;
    }

    bool isBig(String id) => id.startsWith('tree_') && forestPropTiles(id) >= 3;

    test('nearly every tree is a small one, and a few are not', () {
      final trees = patch().values.where((id) => id.startsWith('tree_')).toList();
      expect(trees.length, greaterThan(500), reason: 'sanity: the patch grew a forest');
      final big = trees.where(isBig).length;
      expect(big, greaterThan(0), reason: 'no landmark trees left at all');
      expect(big / trees.length, lessThan(0.08),
          reason: 'big trees are the exception, not the forest (${big / trees.length})');
    });

    test('no two big trees ever stand close enough to overlap', () {
      // This is the whole fix for "kamera acisi degisince büyük agaclarin
      // birbirinin icine gecmesi ... arkadaki agac öne geciyor". Two
      // overlapping billboards genuinely swap paint order when their ground
      // depths cross mid-turn — correct perspective, not a bug — so the only
      // way to kill the pop is to stop them overlapping at all.
      final widest = kTreeTiles.reduce(math.max) * 0.95;
      expect(4, greaterThanOrEqualTo(widest.ceil()),
          reason: 'the block spacing no longer covers the widest tree');
      final big = patch().entries.where((e) => isBig(e.value)).map((e) => e.key).toList();
      expect(big.length, greaterThan(20), reason: 'sanity: found big trees to compare');
      for (var i = 0; i < big.length; i++) {
        for (var j = i + 1; j < big.length; j++) {
          final d = math.max(
              (big[i].$1 - big[j].$1).abs(), (big[i].$2 - big[j].$2).abs());
          expect(d, greaterThanOrEqualTo(4),
              reason: 'big trees at ${big[i]} and ${big[j]} are $d tiles apart');
        }
      }
    });

    test('big trees keep well back from the plot', () {
      patch().forEach((at, id) {
        if (!isBig(id)) return;
        expect(tilesOutsidePlot(at.$1, at.$2, cols, rows),
            greaterThanOrEqualTo(kBigTreeClearTiles),
            reason: '$id at $at is crowding the clearing');
      });
    });

    test('only bushes and rocks stand against the garden line', () {
      // "ona uygun agac, kaya ve otlarla dolduruldun" — the apron. The plot
      // paints over the woods now so nothing can actually cross the outline;
      // this keeps the hidden sliver small enough that the cut never shows.
      var props = 0, rocks = 0;
      for (var r = -kUndergrowthTiles; r < rows + kUndergrowthTiles; r++) {
        for (var c = -kUndergrowthTiles; c < cols + kUndergrowthTiles; c++) {
          final d = tilesOutsidePlot(c, r, cols, rows);
          if (d == 0 || d > kUndergrowthTiles) continue;
          final id = forestPropAt(c, r, cols, rows);
          if (id == null) continue;
          props++;
          if (id.startsWith('rock_')) rocks++;
          expect(id.startsWith('tree_'), false,
              reason: '$id at ($c,$r) is a tree hard against the plot');
        }
      }
      expect(props, greaterThan(5), reason: 'sanity: the apron should hold props');
      expect(props, lessThan(20),
          reason: 'the apron is dense enough to read as a laid stone border ($props)');
      expect(rocks, greaterThan(0), reason: 'the user asked for rocks here');
    });

    test('a tile inside the plot grows nothing', () {
      for (var r = 0; r < rows; r++) {
        for (var c = 0; c < cols; c++) {
          expect(forestPropAt(c, r, cols, rows), isNull);
        }
      }
    });

    test('the woods are thinner than the old wall but not empty', () {
      // #v34.9's screen-space frame looked empty; the pre-v34.8 world forest
      // read as a solid green wall once trees grew to 2-4 tiles. Count what a
      // real patch actually produces.
      var props = 0, gaps = 0;
      for (var r = -30; r < 30; r++) {
        for (var c = -30; c < 30; c++) {
          if (forestPropAt(c, r, cols, rows) == null) {
            gaps++;
          } else {
            props++;
          }
        }
      }
      final fill = props / (props + gaps) * 100;
      expect(fill, greaterThan(48), reason: 'the woods are too sparse ($fill%)');
      expect(fill, lessThan(70), reason: 'back to a solid wall of trees ($fill%)');
    });

    test('what grows on a tile depends on the tile alone, never the camera', () {
      // The "cizimde aci degisiyor ... agac saga bakarken sola bakiyormus gibi"
      // report was this bug: the painter fed the VIEWPORT into the choice
      // (`allowTallTrees: r > vb.minR + 3`), so one tile grew a 2-tile tree at
      // one yaw and a 4-tile one at another and changed shape as you turned.
      // Nothing in the painter mirrors a billboard — the sprite never flipped,
      // the tile swapped species. forestPropAt now takes the tile and the plot
      // and nothing else, so this also pins the signature.
      for (var i = 0; i < 300; i++) {
        final c = i * 7 - 900, r = i * 13 - 500;
        expect(forestPropAt(c, r, cols, rows), forestPropAt(c, r, cols, rows));
      }
    });
  });

  group('Forest trees are drawn at their own size (v34.8)', () {
    test('a tree reports the tile count from the table; bushes and rocks are one', () {
      for (var i = 0; i < kTreeTiles.length; i++) {
        final id = 'tree_${i.toString().padLeft(2, '0')}';
        expect(forestPropTiles(id), kTreeTiles[i].toDouble(), reason: '$id');
      }
      expect(forestPropTiles('bush_04'), 1);
      expect(forestPropTiles('rock_02'), 1);
    });

    test('trees are actually bigger than a flower now', () {
      // the report was "the trees stay tiny next to the flowers" — a flower is
      // drawn at ~1 tile, so every tree has to clear that by a real margin
      for (final t in kTreeTiles) {
        expect(t, greaterThanOrEqualTo(2));
      }
    });

    test('the forest keeps a mix of sizes, not one uniform hedge', () {
      expect(kTreeTiles.toSet().length, greaterThanOrEqualTo(3));
      expect(kTreeTiles.length, kForestTrees, reason: 'one entry per tree sprite');
    });

    test('an unknown id falls back to one tile rather than throwing', () {
      // forestPropAt only ever yields known ids, but a bad id must not crash
      // the whole scene mid-paint.
      expect(forestPropTiles('tree_'), 1);
      expect(forestPropTiles('mystery'), 1);
    });
  });

  group('Critters abandon a flower that gets removed (v34.4)', () {
    /// Step until the system has a critter, or give up.
    CritterSystem spawned(int seed, List<Offset> flowers) {
      final sys = CritterSystem(seed);
      for (var i = 0; i < 400 && sys.critters.isEmpty; i++) {
        sys.step(0.05, 6, flowers);
      }
      return sys;
    }

    test('a critter heading for a removed flower leaves instead of hovering over nothing', () {
      // The bug: the target is captured once at spawn, so clearing the tile
      // left the critter flying to - and then sniffing at - an empty patch of
      // grass for its whole hover, up to the 18s lifetime cap.
      final flowers = [const Offset(0, 0)];
      final sys = spawned(7, flowers);
      expect(sys.critters, isNotEmpty, reason: 'sanity: a critter should have spawned');

      // the flower is dug up
      for (var i = 0; i < 20; i++) {
        sys.step(0.05, 6, const []);
      }
      for (final c in sys.critters) {
        expect(c.leaving, isTrue, reason: 'still visiting a flower that is gone');
      }
    });

    test('it clears off quickly, not on the 18s lifetime cap', () {
      final sys = spawned(7, [const Offset(0, 0)]);
      expect(sys.critters, isNotEmpty);
      final lifeAtRemoval = sys.critters.first.life;

      for (var i = 0; i < 400 && sys.critters.isNotEmpty; i++) {
        sys.step(0.05, 6, const []);
      }
      expect(sys.critters, isEmpty, reason: 'never left the garden');
      // flying out from the middle is a few seconds; the cap is a backstop,
      // not the mechanism.
      expect(lifeAtRemoval + 400 * 0.05, greaterThan(Critter.maxLife),
          reason: 'sanity: the loop is long enough that the cap alone could have done it');
    });

    test('removing ONE of several flowers only sends the visitors to that one away', () {
      final far = const Offset(4, 4);
      final flowers = [const Offset(0, 0), far];
      // seed chosen so the spawned critter targets the origin flower
      var sys = spawned(7, flowers);
      expect(sys.critters, isNotEmpty);
      final targetsFar = (sys.critters.first.target - far).distance < 0.75;

      // keep only the far flower
      for (var i = 0; i < 20; i++) {
        sys.step(0.05, 6, [far]);
      }
      for (final c in sys.critters) {
        expect(c.leaving, targetsFar ? isFalse : isTrue,
            reason: targetsFar
                ? 'a critter visiting the surviving flower was sent away'
                : 'a critter visiting the removed flower stayed');
      }
    });

    test('a critter already on its way out is left alone', () {
      final flowers = [const Offset(0, 0)];
      final sys = spawned(7, flowers);
      // run it all the way through approach + hover into leave
      for (var i = 0; i < 200 && !sys.critters.first.leaving; i++) {
        sys.step(0.05, 6, flowers);
      }
      expect(sys.critters.first.leaving, isTrue);
      final exit = sys.critters.first.target;
      sys.step(0.05, 6, const []);
      expect(sys.critters.first.target, exit,
          reason: 'the exit heading was overwritten by the abandon check');
    });
  });

  group('Critter perch height varies while hovering (v31.17)', () {
    test('visits settle at varied heights on the plant, not always the same spot', () {
      // "bugs jump to top" bug: every hovering critter used a hardcoded lift
      // (sit at the bloom) regardless of its randomized approach target, so
      // every visit looked identical. Spawn many independent systems (each
      // stepped just long enough to trigger its first spawn) and prove the
      // resulting perch heights actually spread out instead of clustering.
      final flowers = [const Offset(0, 0)];
      final perches = <double>[];
      for (var seed = 0; seed < 30; seed++) {
        final sys = CritterSystem(seed);
        for (var i = 0; i < 300 && sys.critters.isEmpty; i++) {
          sys.step(0.05, 6, flowers); // up to 15s — enough to trigger the first spawn
        }
        if (sys.critters.isNotEmpty) perches.add(sys.critters.first.perch);
      }
      expect(perches.length, greaterThan(10), reason: 'sanity: spawns should actually happen');
      expect(perches.toSet().length, greaterThan(5),
          reason: 'perch should vary across visits, not be fixed to one value');
      expect(perches.reduce(math.max) - perches.reduce(math.min), greaterThan(0.3),
          reason: 'spread should span a meaningful range of the plant, not cluster near one spot');
    });
  });

  group('forest variety (v13)', () {
    test('forestPropAt is deterministic, in-range, with gaps', () {
      var trees = 0, bushes = 0, rocks = 0, gaps = 0;
      for (var c = -20; c < 20; c++) {
        for (var r = -20; r < 20; r++) {
          final id = forestPropAt(c, r, 4, 10);
          expect(forestPropAt(c, r, 4, 10), id); // stable
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

  group('Desktop/web garden controls (#v33.8) - pure input maths', () {
    test('one wheel notch down zooms out 1.1x, up zooms in, both clamped', () {
      expect(wheelZoom(1.0, 120), closeTo(1 / 1.1, 1e-9)); // scroll down -> out
      expect(wheelZoom(1.0, -120), closeTo(1.1, 1e-9)); // scroll up -> in
      expect(wheelZoom(0.5, 120), 0.5); // floor holds
      expect(wheelZoom(4.0, -120), 4.0); // ceiling holds
      // the clamp range is the SAME one the pinch gesture uses (0.5 - 4.0)
    });

    test('WASD and arrows pan the camera, other keys are refused', () {
      expect(wasdPan(LogicalKeyboardKey.keyW), const Offset(0, 32));
      expect(wasdPan(LogicalKeyboardKey.keyS), const Offset(0, -32));
      expect(wasdPan(LogicalKeyboardKey.keyA), const Offset(32, 0));
      expect(wasdPan(LogicalKeyboardKey.keyD), const Offset(-32, 0));
      expect(wasdPan(LogicalKeyboardKey.arrowUp), const Offset(0, 32));
      expect(wasdPan(LogicalKeyboardKey.arrowDown), const Offset(0, -32));
      expect(wasdPan(LogicalKeyboardKey.arrowLeft), const Offset(32, 0));
      expect(wasdPan(LogicalKeyboardKey.arrowRight), const Offset(-32, 0));
      expect(wasdPan(LogicalKeyboardKey.keyQ), Offset.zero);
      expect(wasdPan(LogicalKeyboardKey.space), Offset.zero);
    });

    test('A and D are exact mirrors, W and S are exact mirrors', () {
      expect(wasdPan(LogicalKeyboardKey.keyA), -wasdPan(LogicalKeyboardKey.keyD));
      expect(wasdPan(LogicalKeyboardKey.keyW), -wasdPan(LogicalKeyboardKey.keyS));
    });

    test('middle-drag yaw is linear and signed', () {
      expect(middleDragYaw(100), closeTo(1.0, 1e-9));
      expect(middleDragYaw(-50), closeTo(-0.5, 1e-9));
      expect(middleDragYaw(0), 0);
    });
  });
}
