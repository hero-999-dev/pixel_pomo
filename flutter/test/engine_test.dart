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

    test('taller trees keep their distance, by size', () {
      // 3-tile trees may come as close as kMidTreeClearTiles so the middle
      // distances aren't one repeated silhouette (#v34.15); a full 4-tile tree
      // leans 1.8 tiles over the plot from there, so it stays further back.
      patch().forEach((at, id) {
        if (!isBig(id)) return;
        final d = tilesOutsidePlot(at.$1, at.$2, cols, rows);
        final need = forestPropTiles(id) >= 4 ? kBigTreeClearTiles : kMidTreeClearTiles;
        expect(d, greaterThanOrEqualTo(need),
            reason: '$id (${forestPropTiles(id)} tiles) at $at is $d out, needs $need');
      });
    });

    test('the woods have more than one tree size in them', () {
      // "hala cesitlilikle görsel olarak problem var" — before #v34.15 every
      // tree within six tiles of the plot was a 2-tile one.
      final sizes = patch(span: 12)
          .values
          .where((id) => id.startsWith('tree_'))
          .map(forestPropTiles)
          .toSet();
      expect(sizes.length, greaterThan(1),
          reason: 'every tree near the clearing is the same size');
    });

    test('the ring is small trees, bushes and rocks — and only those', () {
      // "bahcenin disindaki 3 tilein kücük agaclarla, calilarla, kayalarla
      // cevrili olmasi, sonrasinda orman baslasin".
      var trees = 0, bushes = 0, rocks = 0;
      for (var r = -kUndergrowthTiles; r < rows + kUndergrowthTiles; r++) {
        for (var c = -kUndergrowthTiles; c < cols + kUndergrowthTiles; c++) {
          final d = tilesOutsidePlot(c, r, cols, rows);
          if (d == 0 || d > kUndergrowthTiles) continue;
          final id = forestPropAt(c, r, cols, rows);
          if (id == null) continue;
          if (id.startsWith('tree_')) {
            trees++;
            expect(forestPropTiles(id), 2, reason: '$id at ($c,$r) is a big tree in the ring');
          } else if (id.startsWith('bush_')) {
            bushes++;
          } else {
            rocks++;
          }
        }
      }
      expect(trees, greaterThan(0), reason: 'the ring has no small trees in it');
      expect(bushes, greaterThan(0), reason: 'the ring has no bushes in it');
      expect(rocks, greaterThan(0), reason: 'the ring has no rocks in it');
    });

    test('the innermost ring tile grows trees on the flanks only', () {
      // "kücük agaclar koyabilirsin 1. hatta ama cok kücük, yan taraflarda
      // olsun, alt tarafda ve üst tarafta olmasin" (#v34.16). A prop one tile
      // in FRONT of the clearing reaches 1.5 tiles up over its edge; the same
      // prop on the flank stands alongside instead and only overlaps by half a
      // sprite width.
      var flankTrees = 0, edgeTiles = 0;
      for (var r = -1; r <= rows; r++) {
        for (var c = -1; c <= cols; c++) {
          if (tilesOutsidePlot(c, r, cols, rows) != 1) continue;
          final id = forestPropAt(c, r, cols, rows);
          if (id == null) continue;
          if (isPlotSideTile(c, r, cols, rows)) {
            if (id.startsWith('tree_')) flankTrees++;
          } else {
            edgeTiles++;
            expect(id.startsWith('tree_'), false,
                reason: '$id at ($c,$r) is a tree on the near/far edge, '
                    'where it leans 1.5 tiles over the clearing');
          }
        }
      }
      expect(flankTrees, greaterThan(0), reason: 'no trees on the flanks at all');
      expect(edgeTiles, greaterThan(0), reason: 'sanity: near/far edge tiles exist');
    });

    test('the flank trees are the narrow ones', () {
      // "ilk hatta sag solda genis agac degilde, böyle ince uzun tarza agac"
      // (#v34.17). A flank prop overlaps the clearing sideways, so how much of
      // its drawn rect the artwork actually fills is the thing that matters —
      // every 2-tile tree is drawn the same width, but a poplar fills 41% of it
      // against a broadleaf's 72%. The sprite gate checks kNarrowTrees really
      // are the narrow sprites; this checks the flank uses only those.
      var found = 0;
      for (var r = 0; r < rows; r++) {
        for (final c in [-1, cols]) {
          final id = forestPropAt(c, r, cols, rows);
          if (id == null || !id.startsWith('tree_')) continue;
          found++;
          expect(kNarrowTrees, contains(int.parse(id.substring(5))),
              reason: '$id at ($c,$r) is a wide tree on the flank');
        }
      }
      expect(found, greaterThan(0), reason: 'sanity: the flanks grew some trees');
    });

    test('no two rocks sit side by side along the rim', () {
      // "2 tas yana gelmesin" — at one tile out the eye reads the rim as a
      // line, so a repeated sprite in it is obvious in a way it never is out
      // in the woods.
      for (var r = -1; r <= rows; r++) {
        for (var c = -1; c <= cols; c++) {
          if (tilesOutsidePlot(c, r, cols, rows) != 1) continue;
          final me = forestPropAt(c, r, cols, rows);
          if (me == null || !me.startsWith('rock_')) continue;
          for (final (nc, nr) in [(c - 1, r), (c + 1, r), (c, r - 1), (c, r + 1)]) {
            if (tilesOutsidePlot(nc, nr, cols, rows) != 1) continue;
            final other = forestPropAt(nc, nr, cols, rows);
            expect(other?.startsWith('rock_') ?? false, false,
                reason: 'rocks touching at ($c,$r) and ($nc,$nr)');
          }
        }
      }
    });

    test('a hole in the rim is never backed by a second one', () {
      // "üstte 2 ve 3. satir ayni anda bosalmis kötü duruyor" — one gap reads
      // as a clearing edge, two stacked reads as a bald patch.
      for (var r = -1; r <= rows; r++) {
        for (var c = -1; c <= cols; c++) {
          if (tilesOutsidePlot(c, r, cols, rows) != 1) continue;
          if (forestPropAt(c, r, cols, rows) != null) continue;
          final out = c < 0
              ? (c - 1, r)
              : c > cols - 1
                  ? (c + 1, r)
                  : r < 0
                      ? (c, r - 1)
                      : (c, r + 1);
          expect(forestPropAt(out.$1, out.$2, cols, rows), isNotNull,
              reason: 'the rim is bald at ($c,$r) and behind it');
        }
      }
    });

    test('the near and far rim is a mix, not one repeated plant', () {
      // "üst tarafta birinci satirda gereginden fazla kücük agac oluyor ... sol
      // ve sag taraf gibi yapalim" (#v35.3). These edges used to be 80% bush,
      // and a bush IS a squat little tree, so the whole row read as the same
      // plant over and over. They get the flanks' mix minus the trees now — a
      // 2-tile tree one tile out still reaches 1.5 tiles up over the clearing,
      // which is why the trees stay on the flanks only.
      var bushes = 0, rocks = 0, trees = 0;
      for (var r = -1; r <= rows; r++) {
        for (var c = -1; c <= cols; c++) {
          if (tilesOutsidePlot(c, r, cols, rows) != 1) continue;
          if (isPlotSideTile(c, r, cols, rows)) continue;
          final id = forestPropAt(c, r, cols, rows);
          if (id == null) continue;
          if (id.startsWith('bush_')) bushes++;
          if (id.startsWith('rock_')) rocks++;
          if (id.startsWith('tree_')) trees++;
        }
      }
      expect(trees, 0, reason: 'a tree here leans 1.5 tiles over the clearing');
      expect(rocks, greaterThan(0), reason: 'the rim has no rocks in it at all');
      expect(bushes, greaterThan(rocks), reason: 'the rim is mostly rock now');
    });

    test('identical props almost never touch', () {
      // "ayni tür kücük cali ve agaclarin, kayalarin aynisinin yanyana olmasini
      // istemiyorum" — two identical sprites side by side read as a tiling
      // artefact rather than as a forest, and the eye finds every one.
      //
      // The bound is 2%, not 0. Variants are corrected against a neighbour's
      // once-corrected value, which leaves the case where the neighbour was
      // itself moved onto this tile's pick; measured, that is ~1% of adjacent
      // pairs against 10-20% for a plain hash. Driving it to exactly zero needs
      // a scan order, and a scan order would stop the forest being a pure
      // function of the tile — the property that keeps it from changing as the
      // camera moves (#v34.12). This bound is the trade, stated out loud.
      var pairs = 0, twins = 0;
      for (var r = -30; r < rows + 30; r++) {
        for (var c = -30; c < cols + 30; c++) {
          final me = forestPropAt(c, r, cols, rows);
          if (me == null) continue;
          for (final (nc, nr) in [(c + 1, r), (c, r + 1)]) {
            final other = forestPropAt(nc, nr, cols, rows);
            if (other == null) continue;
            pairs++;
            if (other == me) twins++;
          }
        }
      }
      expect(pairs, greaterThan(2000), reason: 'sanity: enough pairs to measure');
      expect(twins / pairs, lessThan(0.02),
          reason: '${(twins / pairs * 100).toStringAsFixed(1)}% of neighbouring '
              'props are identical twins');
    });

    test('the forest backdrop samples deep woods, with no clearing in it', () {
      // #v35.0 — the FOREST home backdrop draws the same woods from
      // kForestBackdropOffset away, so every tile on screen is deep forest:
      // no plot-shaped hole, no undergrowth rim, and no second code path.
      var props = 0, tiles = 0, rimProps = 0;
      for (var r = -20; r < 20; r++) {
        for (var c = -20; c < 20; c++) {
          final oc = c + kForestBackdropOffset, or = r + kForestBackdropOffset;
          expect(tilesOutsidePlot(oc, or, cols, rows),
              greaterThan(kUndergrowthTiles),
              reason: 'the offset does not clear the clearing rim');
          tiles++;
          final id = forestPropAt(oc, or, cols, rows);
          if (id != null) props++;
          if (id != null && id.startsWith('rock_')) rimProps++;
        }
      }
      expect(props / tiles, greaterThan(0.5), reason: 'the backdrop has holes in it');
      expect(rimProps, greaterThan(0), reason: 'sanity: deep woods still have rocks');
    });

    test('the innermost ring tile is denser than the woods', () {
      // "birinci hatta bazen cok bosluk oluyor" — a hole at one tile out is a
      // hole in the clearing's own rim, so it runs at its own lower gap rate.
      var props = 0, tiles = 0;
      for (var r = -1; r <= rows; r++) {
        for (var c = -1; c <= cols; c++) {
          if (tilesOutsidePlot(c, r, cols, rows) != 1) continue;
          tiles++;
          if (forestPropAt(c, r, cols, rows) != null) props++;
        }
      }
      final fill = props / tiles;
      expect(fill, greaterThan(1 - kForestGapPercent / 100),
          reason: 'the inner ring is no denser than the woods ($fill)');
    });

    test('a flank prop never reaches far across the clearing sideways', () {
      // The flank's exemption from the vertical-lean bound is only sound
      // because its SIDEWAYS overlap is small. A tile one out has its centre
      // 0.5 tiles beyond the plot edge, so a sprite of width w overlaps by
      // w/2 - 0.5. Keep that under half a tile, or a flank tree covers a real
      // strip of the garden instead of brushing its edge.
      for (var r = 0; r < rows; r++) {
        for (final c in [-1, cols]) {
          final id = forestPropAt(c, r, cols, rows);
          if (id == null) continue;
          final over = forestPropWidth(id) / 2 - 0.5;
          expect(over, lessThan(0.5),
              reason: '$id at ($c,$r) reaches ${over.toStringAsFixed(2)} '
                  'tiles sideways into the clearing');
        }
      }
    });

    test('a flank tile is beside the plot, a near/far tile is not', () {
      // the classifier itself, since the rule above rests entirely on it
      expect(isPlotSideTile(-1, 0, 4, 10), isTrue); // left of the plot
      expect(isPlotSideTile(4, 9, 4, 10), isTrue); // right of it
      expect(isPlotSideTile(0, -1, 4, 10), isFalse); // behind it
      expect(isPlotSideTile(2, 10, 4, 10), isFalse); // in front of it
      expect(isPlotSideTile(-1, -1, 4, 10), isFalse); // diagonal corner
      expect(isPlotSideTile(1, 5, 4, 10), isFalse); // inside the plot
    });

    test('nothing near the plot can lean more than a canopy tip over it', () {
      // The woods paint ON TOP of the clearing again (#v34.12b) — a tree that
      // vanishes behind the garden is worse than one that crosses its line —
      // so the outline is protected by height, not by paint order. A billboard
      // rises `h` tiles while one tile of distance buys only `kVy` tiles of
      // screen separation, so a prop at distance `d` reaches `h - d * kVy`
      // tiles past the plot's edge on whichever side faces the camera.
      //
      // The bound is 1.0 — under a tile, i.e. a canopy tip passing in front of
      // the clearing, never a whole tree planted over it. It is NOT zero on
      // purpose: clearing it entirely means no small trees within 4 tiles, and
      // the ring is supposed to be built from small trees. What it does catch
      // is the thing that actually looked broken — a 3- or 4-tile tree against
      // the plot, which reaches 2.6 to 3.6 tiles over and swallows the edge.
      for (var r = -12; r < rows + 12; r++) {
        for (var c = -12; c < cols + 12; c++) {
          final d = tilesOutsidePlot(c, r, cols, rows);
          if (d == 0 || d > kUndergrowthTiles) continue;
          // A flank prop stands ALONGSIDE the clearing, not in front of it, so
          // its upward reach never crosses the edge and the vertical bound is
          // simply the wrong measure there (#v34.16). Its horizontal overlap is
          // bounded by the sprite width instead, and checked below.
          if (isPlotSideTile(c, r, cols, rows)) continue;
          final id = forestPropAt(c, r, cols, rows);
          if (id == null) continue;
          final h = forestPropHeight(id); // the painter's own number, not a copy
          expect(h - d * kVy, lessThan(1.0),
              reason: '$id at ($c,$r), $d tiles out, leans '
                  '${(h - d * kVy).toStringAsFixed(2)} tiles over the garden');
        }
      }
    });

    test('the ring is as full as the woods, not a bare moat', () {
      // First cut graded the ring hard by height and left the innermost tile
      // rocks-only; at yaw 0 every tile beside the plot is at distance 1, so
      // each side became an evenly spaced column of pebbles with a bare band
      // behind it. The ring has to read as undergrowth.
      var props = 0, tiles = 0;
      for (var r = -kUndergrowthTiles; r < rows + kUndergrowthTiles; r++) {
        for (var c = -kUndergrowthTiles; c < cols + kUndergrowthTiles; c++) {
          final d = tilesOutsidePlot(c, r, cols, rows);
          if (d == 0 || d > kUndergrowthTiles) continue;
          tiles++;
          if (forestPropAt(c, r, cols, rows) != null) props++;
        }
      }
      expect(props / tiles, greaterThan(0.5),
          reason: 'the ring is a moat, not undergrowth (${props / tiles})');
    });

    test('the woods proper start right after the ring', () {
      // "sonrasinda orman baslasin" — the band immediately outside the ring
      // must actually be forest, not more thinned-out rim.
      var props = 0, tiles = 0;
      for (var r = -14; r < rows + 14; r++) {
        for (var c = -14; c < cols + 14; c++) {
          if (tilesOutsidePlot(c, r, cols, rows) != kUndergrowthTiles + 1) continue;
          tiles++;
          if (forestPropAt(c, r, cols, rows) != null) props++;
        }
      }
      expect(props / tiles, greaterThan(0.5),
          reason: 'the first forest row is still rim-thin (${props / tiles})');
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
      // The floor went 48 -> 60 in #v34.15: the same share of filled tiles
      // covers far less screen now that the woods are 2-tile trees and 0.85
      // bushes instead of 3- and 4-tile ones, and it started reading as holes
      // — "alt tarafta fazla bosluklar oluyor". Density is a property of what
      // stands on the tiles, not of the tile count alone.
      expect(fill, greaterThan(60), reason: 'the woods are full of holes ($fill%)');
      expect(fill, lessThan(78), reason: 'back to a solid wall of trees ($fill%)');
    });

    test('a bush is drawn shorter than a flower, and a rock shorter still', () {
      // The one-tile props had 2-3 empty pixel rows under their art while
      // trees and flowers had none, so the renderer — which puts the canvas
      // bottom on the ground — hung them in the air ("calilar sanki havadaymis
      // gibi duruyor"). Removing that padding makes the art fill its canvas,
      // which would also make them stand TALLER on screen than they used to,
      // so the drawn height came down to compensate. Both halves have to move
      // together: the sprite gate pins the padding, this pins the height.
      expect(forestPropHeight('bush_03'), lessThan(1.05));
      expect(forestPropHeight('rock_01'), lessThan(forestPropHeight('bush_03')));
      expect(forestPropHeight('tree_00'), 2 * 1.05);
      expect(forestPropWidth('bush_03'), kBushWidth);
      // a bush one tile out must stay well under the plot's edge
      expect(kBushHeight - kVy, lessThan(0.3));
      expect(kRockHeight - kVy, lessThanOrEqualTo(0.0));
    });

    test('white daisies come up 3x as often as each colour', () {
      // "beyaz cicek oranini 3 kat daha arttir" (#v35.6). The colours stay
      // even with each other; only white is weighted.
      final counts = List<int>.filled(kGrassBloomPetals.length, 0);
      const n = 21000;
      for (var i = 0; i < n; i++) {
        counts[grassBloomTint(i * 7919 % 0x7fffffff)]++;
      }
      final share = n / (kGrassBloomWhiteWeight + kGrassBloomPetals.length - 1);
      expect((counts[0] - share * kGrassBloomWhiteWeight).abs() /
              (share * kGrassBloomWhiteWeight),
          lessThan(0.15),
          reason: 'white came up ${counts[0]} of $n, expected about '
              '${share * kGrassBloomWhiteWeight}');
      for (var i = 1; i < counts.length; i++) {
        expect((counts[i] - share).abs() / share, lessThan(0.15),
            reason: 'petal $i came up ${counts[i]} times, expected about $share');
      }
      expect(kGrassBloomPetals.first, 0xFFFFFFFF,
          reason: 'index 0 is white — the one every other colour is a variant of');
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

    test('zooming keeps the point under the finger under the finger', () {
      // "ormana dogru yaklastirmak istiyorum, bahceye dogru gidiyor" — the
      // projector centres the world on size/2 + pan and scales the tile size by
      // the zoom, so zoom on its own magnifies about the SCREEN CENTRE, which
      // is exactly where the plot sits. Assert the invariant that fixes it:
      // whatever world point was under the focal point stays under it.
      const size = Size(400, 800);
      final centre = Offset(size.width / 2, size.height / 2);

      /// Where a world offset `g` (in pre-zoom screen pixels from the centre)
      /// lands, given a pan and a zoom.
      Offset onScreen(Offset g, Offset pan, double zoom) => centre + pan + g * zoom;

      for (final focal in [const Offset(40, 90), const Offset(370, 700), centre]) {
        for (final pan in [Offset.zero, const Offset(35, -60)]) {
          for (final (from, to) in [(1.0, 2.0), (2.0, 1.0), (1.0, 4.0), (3.0, 0.5)]) {
            // the world point currently under the focal point
            final g = (focal - centre - pan) / from;
            final pan2 = zoomAboutFocal(pan, size, focal, from, to);
            final after = onScreen(g, pan2, to);
            expect(after.dx, closeTo(focal.dx, 1e-9),
                reason: 'focal $focal pan $pan zoom $from->$to drifted in x');
            expect(after.dy, closeTo(focal.dy, 1e-9),
                reason: 'focal $focal pan $pan zoom $from->$to drifted in y');
          }
        }
      }
    });

    test('zooming at the screen centre is the old centre-anchored behaviour', () {
      // the regression the fix must NOT introduce: a pinch centred on the
      // middle of the screen should still behave exactly as it always did
      const size = Size(400, 800);
      expect(zoomAboutFocal(Offset.zero, size, const Offset(200, 400), 1, 2), Offset.zero);
    });

    test('a zero or negative starting zoom is refused, not divided by', () {
      expect(zoomAboutFocal(const Offset(5, 5), const Size(400, 800),
          const Offset(10, 10), 0, 2), const Offset(5, 5));
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
