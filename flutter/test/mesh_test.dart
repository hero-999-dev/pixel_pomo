import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_pomo/engine/garden_engine.dart';
import 'package:pixel_pomo/logic.dart';

// The v36 box-mesh pipeline. v10 built ONE 3D object — the fence post — out of
// `boxCorners` + a quad fill, and left a note that trees and houses were next.
// This is that generalisation: an object is now a list of boxes loaded from a
// JSON file, so a shape can be authored in Blockbench and converted rather than
// hand-written into the painter. A house is the first consumer, because a house
// is the one thing that genuinely cannot be a billboard — turn the camera and a
// flat one reads as a sheet of paper.
void main() {
  Projector proj([double yaw = 0.0]) =>
      Projector(6, 10, 40.0, const Offset(200, 300), yaw);

  group('boxCornersAt — the general box primitive', () {
    test('gives 8 corners, the top ring exactly height*t above the base ring', () {
      final p = proj(0.7);
      final c = boxCornersAt(p, Offset.zero, 0.3, 0.2, 0.0, 0.8);
      expect(c.length, 8);
      for (var i = 0; i < 4; i++) {
        expect(c[i + 4].dx, closeTo(c[i].dx, 1e-9));
        expect(c[i + 4].dy, closeTo(c[i].dy - 0.8 * p.t, 1e-9));
      }
    });

    test('a raised box starts at its own elevation, not on the ground', () {
      // This is what lets a roof sit on top of walls instead of inside them.
      final p = proj(0.4);
      final ground = boxCornersAt(p, Offset.zero, 0.3, 0.3, 0.0, 0.5);
      final raised = boxCornersAt(p, Offset.zero, 0.3, 0.3, 0.5, 0.4);
      for (var i = 0; i < 4; i++) {
        // the raised box's base ring sits exactly where the lower box's top was
        expect(raised[i].dx, closeTo(ground[i + 4].dx, 1e-9));
        expect(raised[i].dy, closeTo(ground[i + 4].dy, 1e-9));
      }
    });

    test('a non-square footprint stays centred and keeps both spans, at any yaw', () {
      // The v10 primitive was square-only (one `half`). A house needs a wall
      // that is long in one axis and thin in the other.
      for (final yaw in [0.0, 0.6, 2.2, -1.4]) {
        final p = proj(yaw);
        final base = boxCornersAt(p, Offset.zero, 0.45, 0.08, 0, 0.5).sublist(0, 4);
        final cx = base.map((o) => o.dx).reduce((a, b) => a + b) / 4;
        final cy = base.map((o) => o.dy).reduce((a, b) => a + b) / 4;
        final centre = p.projectGrid(Offset.zero);
        expect(cx, closeTo(centre.dx, 1e-6), reason: 'yaw=$yaw');
        expect(cy, closeTo(centre.dy, 1e-6), reason: 'yaw=$yaw');
        // it is a real slab from every angle — never collapses to a line
        final spanX =
            base.map((o) => o.dx).reduce(math.max) - base.map((o) => o.dx).reduce(math.min);
        final spanY =
            base.map((o) => o.dy).reduce(math.max) - base.map((o) => o.dy).reduce(math.min);
        expect(spanX, greaterThan(1), reason: 'yaw=$yaw');
        expect(spanY, greaterThan(1), reason: 'yaw=$yaw');
      }
    });

    test('the old square boxCorners is exactly the general one, unchanged', () {
      // v10's fence geometry is tested in engine_test.dart and must keep
      // passing byte-for-byte — the refactor is not allowed to move a pixel.
      final p = proj(1.1);
      final old = boxCorners(p, const Offset(1, -2), 0.12, 0.66);
      final general = boxCornersAt(p, const Offset(1, -2), 0.12, 0.12, 0.0, 0.66);
      for (var i = 0; i < 8; i++) {
        expect(old[i].dx, closeTo(general[i].dx, 1e-12));
        expect(old[i].dy, closeTo(general[i].dy, 1e-12));
      }
    });
  });

  group('BoxMesh JSON — the format the Blockbench converter writes', () {
    const raw = '''
      {"id":"test_hut","tiles":1,
       "boxes":[
         {"x":0,"y":0,"z":0,"w":0.8,"d":0.8,"h":0.5,"side":"8B5A2B","top":"A9743E"},
         {"x":0,"y":0,"z":0.5,"w":0.95,"d":0.95,"h":0.3,"side":"7A2C22","top":"9C3A2C"}
       ]}''';

    test('decodes ids, footprint and every box field', () {
      final m = BoxMesh.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      expect(m.id, 'test_hut');
      expect(m.tiles, 1);
      expect(m.boxes.length, 2);
      final roof = m.boxes[1];
      expect(roof.z, 0.5);
      expect(roof.w, 0.95);
      expect(roof.h, 0.3);
      expect(roof.side, 0xFF7A2C22, reason: 'hex string becomes an opaque ARGB int');
      expect(roof.top, 0xFF9C3A2C);
    });

    test('a mesh with no boxes is refused rather than drawn as nothing', () {
      expect(() => BoxMesh.fromJson(jsonDecode('{"id":"x","tiles":1,"boxes":[]}')),
          throwsFormatException);
    });

    test('height reports the tallest point, for the depth/lean bounds', () {
      final m = BoxMesh.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      expect(m.height, closeTo(0.8, 1e-9)); // roof base 0.5 + roof height 0.3
    });
  });

  group('Mesh draw order — boxes paint back to front', () {
    BoxMesh twoWalls() => BoxMesh.fromJson(jsonDecode('''
      {"id":"walls","tiles":1,"boxes":[
        {"x":0,"y":-0.4,"z":0,"w":0.8,"d":0.1,"h":0.6,"side":"111111","top":"222222"},
        {"x":0,"y":0.4,"z":0,"w":0.8,"d":0.1,"h":0.6,"side":"333333","top":"444444"}
      ]}''') as Map<String, dynamic>);

    test('the far wall is always painted before the near one, from any yaw', () {
      // Without this a house turns inside out as you twist the garden: the back
      // wall paints over the front one for half of the compass.
      final mesh = twoWalls();
      for (final yaw in [0.0, 0.9, 2.0, math.pi, -2.5, -0.3]) {
        final p = proj(yaw);
        final order = meshDrawOrder(p, Offset.zero, mesh);
        final depths = [
          for (final b in mesh.boxes) p.projectGrid(Offset(b.x, b.y)).dy,
        ];
        expect(depths[order.first], lessThanOrEqualTo(depths[order.last]),
            reason: 'yaw=$yaw painted the near box first');
      }
    });

    test('boxes stacked on one spot keep their authored order, bottom up', () {
      // Walls then roof share a footprint, so their depths tie. A stable sort
      // keeps the file's own order, which is why the format is authored
      // bottom-up — the roof must land on top of the walls, not behind them.
      final stacked = BoxMesh.fromJson(jsonDecode('''
        {"id":"stack","tiles":1,"boxes":[
          {"x":0,"y":0,"z":0,"w":0.8,"d":0.8,"h":0.5,"side":"111111","top":"222222"},
          {"x":0,"y":0,"z":0.5,"w":0.9,"d":0.9,"h":0.3,"side":"333333","top":"444444"}
        ]}''') as Map<String, dynamic>);
      expect(meshDrawOrder(proj(1.3), Offset.zero, stacked), [0, 1]);
    });
  });

  group('The house in the catalogue', () {
    test('a house is a placeable object, and not a fence, road or flower', () {
      expect(Placeables.houseIds, isNotEmpty);
      final id = Placeables.houseIds.first;
      expect(Placeables.isHouse(id), isTrue);
      expect(Placeables.isObject(id), isTrue);
      expect(Placeables.isFence(id), isFalse);
      expect(Placeables.isRoad(id), isFalse);
      expect(Placeables.isFlower(id), isFalse,
          reason: 'a house must not be counted as a flower — bees would visit it');
    });

    test('a house costs more than a fence panel', () {
      final id = Placeables.houseIds.first;
      expect(Economy.costOf(id), Economy.houseCost);
      expect(Economy.houseCost, greaterThan(Economy.objectCost));
      expect(Economy.sellPrice(id), Economy.houseCost ~/ 2);
    });
  });

  group('Placing a house', () {
    const g = Garden(cols: 4, rows: 4);
    final house = Placeables.houseIds.first;

    test('stands on bare grass', () {
      expect(g.plant(5, house).propAt(5), house);
    });

    test('is refused on a road — a house is not a fence', () {
      // A fence deliberately layers onto a road. A house on a road would be a
      // cottage in the middle of a path, so it follows the flower rule instead.
      final withRoad = g.plant(5, 'road_stone');
      expect(withRoad.plant(5, house).propAt(5), isNull);
      expect(withRoad.plant(5, house).groundAt(5), 'road_stone');
    });

    test('a road laid over a house clears it, as it does a flower', () {
      final withHouse = g.plant(5, house);
      final paved = withHouse.plant(5, 'road_dirt');
      expect(paved.groundAt(5), 'road_dirt');
      expect(paved.propAt(5), isNull);
    });

    test('planting a flower on a house tile replaces it, not stacks on it', () {
      expect(g.plant(5, house).plant(5, 'lale').propAt(5), 'lale');
    });
  });
}
