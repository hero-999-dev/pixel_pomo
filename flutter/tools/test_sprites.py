"""Tests for the generated forest sprites.

Run:  python -m unittest discover -s tools -p 'test_*.py'   (from flutter/)

Two things are checked here that nothing else can:

1. **The tree size table is mirrored in three places** — Python generates the
   sprite at 16px per tile, Dart draws it at that many tiles, and the Kotlin
   wallpaper draws it again independently. A mismatch is silent: the tree just
   renders at the wrong scale or the wrong pixel density in one renderer. This
   project has shipped that class of bug more than once (#v32's critter easing
   was Dart-only, #v34.2's manifest was activity-only), so the constant is
   asserted equal across all three files rather than trusted to review.

2. **Every tree is one connected, grounded shape.** The generator derives the
   trunk from the canopy's measured extent; when it guessed a fraction instead,
   half the trees came out as a crown floating over a detached trunk, which is
   invisible in a diff and obvious on a phone.
"""
import os
import re
import sys
import unittest
from collections import deque

HERE = os.path.dirname(os.path.abspath(__file__))
FLUTTER = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import gen_objects as g  # noqa: E402


def _ints(text):
    return [int(x) for x in re.findall(r"-?\d+", text)]


class TreeTableIsMirrored(unittest.TestCase):
    def _table(self, path, pattern):
        with open(path, encoding="utf-8") as fh:
            src = fh.read()
        m = re.search(pattern, src)
        self.assertIsNotNone(m, f"table not found in {os.path.basename(path)}")
        return _ints(m.group(1))

    def test_python_dart_and_kotlin_agree(self):
        dart = self._table(
            os.path.join(FLUTTER, "lib", "engine", "garden_engine.dart"),
            r"const List<int> kTreeTiles = \[([^\]]*)\]")
        kotlin = self._table(
            os.path.join(FLUTTER, "android_overlay", "kotlin", "com", "pixelpomo",
                         "pixel_pomo", "GardenRenderer.kt"),
            r"val treeTiles = intArrayOf\(([^)]*)\)")
        self.assertEqual(g.TREE_TILES, dart, "gen_objects.py and garden_engine.dart disagree")
        self.assertEqual(g.TREE_TILES, kotlin, "gen_objects.py and GardenRenderer.kt disagree")

    def test_the_table_covers_every_tree(self):
        self.assertEqual(len(g.TREE_TILES), 20, "one entry per tree_NN sprite")
        self.assertTrue(all(t in (2, 3, 4) for t in g.TREE_TILES), "sizes are 2, 3 or 4 tiles")
        # a forest of one size is a hedge; make sure the mix survives an edit
        self.assertGreaterEqual(len(set(g.TREE_TILES)), 3, "the trees are all the same size")


class TreesAreWellFormed(unittest.TestCase):
    @staticmethod
    def _components(grid):
        n = len(grid)
        seen = [[False] * n for _ in range(n)]
        sizes = []
        for r in range(n):
            for c in range(n):
                if grid[r][c][3] and not seen[r][c]:
                    q, size = deque([(r, c)]), 0
                    seen[r][c] = True
                    while q:
                        y, x = q.popleft()
                        size += 1
                        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                            ny, nx = y + dy, x + dx
                            if 0 <= ny < n and 0 <= nx < n and grid[ny][nx][3] and not seen[ny][nx]:
                                seen[ny][nx] = True
                                q.append((ny, nx))
                    sizes.append(size)
        return sizes

    def test_every_tree_is_one_piece_standing_on_the_ground(self):
        for seed in range(1, len(g.TREE_TILES) + 1):
            with self.subTest(tree=seed):
                grid = g._tree_variant(seed)
                n = len(grid)
                pieces = self._components(grid)
                self.assertEqual(len(pieces), 1,
                                 f"tree {seed} is in {len(pieces)} pieces {sorted(pieces)[-3:]} "
                                 f"— a crown floating over a detached trunk")
                self.assertTrue(any(grid[n - 1][c][3] for c in range(n)),
                                f"tree {seed} does not reach the ground")

    def test_no_tree_is_cut_off_by_its_own_canvas(self):
        # "bazi agaclarin kafasi tamamn cizilmemis" — the pine's top tier
        # reached y<0, so the canopy was flat-cut by the canvas edge and the
        # tree had no head. Nothing may touch any edge; the ground row is where
        # the trunk stands and is checked separately.
        for seed in range(1, len(g.TREE_TILES) + 1):
            with self.subTest(tree=seed):
                grid = g._tree_variant(seed)
                n = len(grid)
                self.assertFalse(any(px[3] for px in grid[0]),
                                 f"tree {seed}'s canopy is cut off by the top edge")
                for r in range(n):
                    self.assertFalse(grid[r][0][3], f"tree {seed} touches the left edge")
                    self.assertFalse(grid[r][n - 1][3], f"tree {seed} touches the right edge")

    def test_the_forest_keeps_some_dark_trees(self):
        # #v34.9 — the user asked for the old deep-green trees back in the mix,
        # so the tree line has weight instead of being all bright canopy.
        dark = 0
        for seed in range(1, len(g.TREE_TILES) + 1):
            canopy = [px for row in g._tree_variant(seed) for px in row
                      if px[3] and px[1] > px[0] and px[1] > px[2]]
            if canopy and sum(px[1] for px in canopy) / len(canopy) < 75:
                dark += 1
        self.assertGreaterEqual(dark, 3, "no dark trees left in the mix")
        self.assertLess(dark, len(g.TREE_TILES), "every tree went dark")

    def test_the_canvas_is_sized_from_the_table(self):
        # 16px per tile keeps pixel density even with the 16px flowers; a tree
        # generated at a fixed size would blur as it got bigger on screen.
        for seed in range(1, len(g.TREE_TILES) + 1):
            with self.subTest(tree=seed):
                tiles = g.TREE_TILES[(seed - 1) % len(g.TREE_TILES)]
                self.assertEqual(len(g._tree_variant(seed)), tiles * g.TREE_PX_PER_TILE)

    def test_a_tree_has_both_canopy_and_trunk(self):
        for seed in range(1, len(g.TREE_TILES) + 1):
            with self.subTest(tree=seed):
                grid = g._tree_variant(seed)
                greens = browns = 0
                for row in grid:
                    for r_, g_, b_, a in row:
                        if not a:
                            continue
                        if g_ > r_ and g_ > b_:
                            greens += 1
                        elif r_ > g_:
                            browns += 1
                self.assertGreater(greens, 0, f"tree {seed} has no canopy")
                self.assertGreater(browns, 0, f"tree {seed} has no trunk")

    def test_bushes_and_rocks_stay_one_tile(self):
        for seed in range(1, 11):
            self.assertEqual(len(g._bush_variant(seed)), 16)
        for seed in range(1, 6):
            self.assertEqual(len(g._rock_variant(seed)), 16)


if __name__ == "__main__":
    unittest.main()
