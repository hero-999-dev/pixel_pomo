import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_pomo/engine/garden_engine.dart';

/// The rotation "pop" (#v35.4).
///
/// Two overlapping billboards swapping paint order as their ground depths cross
/// is correct perspective and cannot be removed. What made it read as a glitch
/// was that every prop stood exactly on its tile's centre, so a whole ROW of
/// them shared one depth to the pixel and crossed the row behind it on the SAME
/// frame — a dozen trees flipping at once.
///
/// So the thing to measure is not how many swaps happen, it is **how many land
/// on one frame**. The first version of this measurement counted every pair
/// flip and showed almost no difference (1847 -> 1651 worst frame), because it
/// averaged in thousands of flips between props on opposite sides of the screen
/// that nobody can see. Counting only pairs whose sprites actually OVERLAP
/// tells the real story.
void main() {
  const cols = 11, rows = 11;
  const size = Size(380, 800);

  /// Worst number of *visible* depth-order swaps on any single frame of a
  /// 45-degree camera sweep, plus the total.
  (int worst, int total) sweep({required bool jitter}) {
    final cam = GardenCamera();
    List<(int, int)>? tiles;
    List<int>? prev;
    var worst = 0, total = 0;

    for (var step = 0; step <= 120; step++) {
      cam.yaw = step * math.pi / 240;
      final p = Projector.fit(cols, rows, cam, size);
      if (tiles == null) {
        final vb = p.visibleTileBounds(size);
        tiles = [
          for (var r = vb.minR; r <= vb.maxR; r++)
            for (var c = vb.minC; c <= vb.maxC; c++)
              if (forestPropAt(c, r, cols, rows) case final fp?)
                if (forestPropTiles(fp) < 3) (c, r), // landmarks stay on lattice
        ];
      }
      Offset anchorOf((int, int) t) {
        if (!jitter) return p.ground(t.$1, t.$2);
        final j = forestJitter(t.$1, t.$2);
        return p.projectGrid(p.gridOfD(t.$1 + j.dx, t.$2 + j.dy));
      }

      final rects = [
        for (final t in tiles)
          () {
            final fp = forestPropAt(t.$1, t.$2, cols, rows)!;
            final w = forestPropWidth(fp) * p.t, h = forestPropHeight(fp) * p.t;
            final a = anchorOf(t);
            return Rect.fromLTWH(a.dx - w / 2, a.dy - h, w, h);
          }()
      ];
      final order = stableDepthOrder([for (final t in tiles) anchorOf(t).dy]);
      final rank = List<int>.filled(order.length, 0);
      for (var i = 0; i < order.length; i++) {
        rank[order[i]] = i;
      }
      if (prev != null) {
        final prank = List<int>.filled(prev.length, 0);
        for (var i = 0; i < prev.length; i++) {
          prank[prev[i]] = i;
        }
        var swaps = 0;
        for (var i = 0; i < order.length; i++) {
          for (var k = i + 1; k < order.length; k++) {
            if ((rank[i] < rank[k]) == (prank[i] < prank[k])) continue;
            if (rects[i].overlaps(rects[k])) swaps++;
          }
        }
        worst = math.max(worst, swaps);
        total += swaps;
      }
      prev = order;
    }
    return (worst, total);
  }

  test('the camera sweep never flips a crowd of trees on one frame', () {
    final (jitterWorst, jitterTotal) = sweep(jitter: true);
    final (latticeWorst, _) = sweep(jitter: false);

    // Measured: on the lattice 131 of 141 visible swaps land on a single frame
    // (median 0 — nothing, nothing, everything). Jittered it is 11 worst and a
    // median of 4, spread across the whole turn.
    expect(jitterWorst, lessThan(30),
        reason: '$jitterWorst trees swap on one frame — that is the pop');
    expect(jitterWorst * 4, lessThan(latticeWorst),
        reason: 'jitter ($jitterWorst) is no better than the lattice '
            '($latticeWorst) at spreading the swaps out');
    // More swaps overall is the POINT: many small continuous changes read as
    // parallax, one simultaneous change reads as a glitch.
    expect(jitterTotal, greaterThan(latticeWorst),
        reason: 'sanity: the sweep should produce swaps to spread');
  });
}
