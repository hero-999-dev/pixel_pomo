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

    # Every number that decides what grows where is written twice — once in Dart
    # for the phone garden, once in Kotlin for the live wallpaper. A mismatch is
    # silent and grows two different forests from the same save (#v34.10).
    FOREST_CONSTANTS = [
        ("forest density", r"const int kForestGapPercent = (\d+);",
         r"val forestGapPercent = (\d+)"),
        ("big-tree block size", r"const int kBigTreeBlock = (\d+);",
         r"val bigTreeBlock = (\d+)"),
        ("big-tree share of blocks", r"const int kBigTreePercent = (\d+);",
         r"val bigTreePercent = (\d+)"),
        ("big-tree clearance", r"const int kBigTreeClearTiles = (\d+);",
         r"val bigTreeClearTiles = (\d+)"),
        ("mid-tree clearance", r"const int kMidTreeClearTiles = (\d+);",
         r"val midTreeClearTiles = (\d+)"),
        ("undergrowth ring depth", r"const int kUndergrowthTiles = (\d+);",
         r"val undergrowthTiles = (\d+)"),
        ("small trees inside the ring", r"const int kRingTreeTiles = (\d+);",
         r"val ringTreeTiles = (\d+)"),
        ("grass-bloom tint rarity", r"const int kGrassBloomTintPercent = (\d+);",
         r"val grassBloomTintPercent = (\d+)"),
        ("inner-ring density", r"const int kRingInnerGapPercent = (\d+);",
         r"val ringInnerGapPercent = (\d+)"),
        ("narrow trees", r"const List<int> kNarrowTrees = \[([^\]]*)\]",
         r"val narrowTrees = intArrayOf\(([^)]*)\)"),
    ]

    def test_the_narrow_tree_list_is_actually_the_narrow_trees(self):
        # kNarrowTrees is the only thing standing between a flank tile and a
        # wide canopy reaching across the clearing's edge, and it is a hand-kept
        # list of indices — exactly the kind that goes stale the moment a
        # silhouette is re-rolled. Derive the answer and compare (#v34.17).
        dart = self._table(
            os.path.join(FLUTTER, "lib", "engine", "garden_engine.dart"),
            r"const List<int> kNarrowTrees = \[([^\]]*)\]")
        for idx in dart:
            grid = g._tree_variant(idx + 1)
            n = len(grid)
            self.assertEqual(g.TREE_TILES[idx], 2,
                             f"tree_{idx:02d} is in kNarrowTrees but is not a 2-tile tree")
            cols = [c for c in range(n) if any(grid[r][c][3] for r in range(n))]
            width = (max(cols) - min(cols) + 1) / n
            self.assertLessEqual(width, 0.50,
                                 f"tree_{idx:02d} fills {width:.0%} of its canvas — not narrow")
        # and nothing narrow was left out, or the flanks lose variety for no reason
        for idx, tiles in enumerate(g.TREE_TILES):
            if tiles != 2 or idx in dart:
                continue
            grid = g._tree_variant(idx + 1)
            n = len(grid)
            cols = [c for c in range(n) if any(grid[r][c][3] for r in range(n))]
            self.assertGreater((max(cols) - min(cols) + 1) / n, 0.50,
                               f"tree_{idx:02d} is narrow but missing from kNarrowTrees")

    def test_the_one_tile_prop_sizes_match_in_dart_and_kotlin(self):
        # A prop drawn at a different height in the two renderers sits at a
        # different place relative to the garden's edge in each (#v34.14).
        dart_path = os.path.join(FLUTTER, "lib", "engine", "garden_engine.dart")
        kotlin_path = os.path.join(FLUTTER, "android_overlay", "kotlin", "com",
                                   "pixelpomo", "pixel_pomo", "GardenRenderer.kt")
        with open(dart_path, encoding="utf-8") as fh:
            dart = fh.read()
        with open(kotlin_path, encoding="utf-8") as fh:
            kotlin = fh.read()
        for name, dart_re, kotlin_re in [
            ("bush", r"const double kBushHeight = ([\d.]+), kBushWidth = ([\d.]+);",
             r'startsWith\("bush_"\) -> ([\d.]+) to ([\d.]+)'),
            ("rock", r"const double kRockHeight = ([\d.]+), kRockWidth = ([\d.]+);",
             r'startsWith\("rock_"\) -> ([\d.]+) to ([\d.]+)'),
        ]:
            with self.subTest(prop=name):
                d = re.search(dart_re, dart)
                k = re.search(kotlin_re, kotlin)
                self.assertIsNotNone(d, f"{name} size not found in garden_engine.dart")
                self.assertIsNotNone(k, f"{name} size not found in GardenRenderer.kt")
                self.assertEqual([float(x) for x in d.groups()],
                                 [float(x) for x in k.groups()],
                                 f"the two renderers draw a {name} at different sizes")

    def test_the_grass_bloom_palette_matches_in_dart_and_kotlin(self):
        dart_path = os.path.join(FLUTTER, "lib", "engine", "garden_engine.dart")
        kotlin_path = os.path.join(FLUTTER, "android_overlay", "kotlin", "com",
                                   "pixelpomo", "pixel_pomo", "GardenRenderer.kt")
        with open(dart_path, encoding="utf-8") as fh:
            dart = re.search(r"kGrassBloomPetals = \[(.*?)\];", fh.read(), re.S)
        with open(kotlin_path, encoding="utf-8") as fh:
            kotlin = re.search(r"grassBloomPetals = intArrayOf\((.*?)\)\n", fh.read(), re.S)
        self.assertIsNotNone(dart)
        self.assertIsNotNone(kotlin)
        hexes = lambda s: [x.lower() for x in re.findall(r"0x([0-9A-Fa-f]{8})", s)]
        self.assertEqual(hexes(dart.group(1)), hexes(kotlin.group(1)),
                         "the two renderers scatter different coloured daisies")

    def test_every_forest_constant_matches_in_dart_and_kotlin(self):
        dart_path = os.path.join(FLUTTER, "lib", "engine", "garden_engine.dart")
        kotlin_path = os.path.join(FLUTTER, "android_overlay", "kotlin", "com",
                                   "pixelpomo", "pixel_pomo", "GardenRenderer.kt")
        for label, dart_re, kotlin_re in self.FOREST_CONSTANTS:
            with self.subTest(constant=label):
                self.assertEqual(self._table(dart_path, dart_re),
                                 self._table(kotlin_path, kotlin_re),
                                 f"the two renderers disagree on {label}")

    def test_the_block_spacing_is_wider_than_the_widest_tree(self):
        # Big trees sit one per block, offset within [1, block-3], so two sites
        # in neighbouring blocks are at least `block + 1 - (block - 3)` = 4
        # tiles apart. That is what stops two big trees ever overlapping — and
        # therefore ever visibly swapping depth as the camera turns (#v34.12).
        widest = max(g.TREE_TILES) * 0.95
        self.assertGreaterEqual(4, widest,
                                "the 4-tile block spacing no longer clears the widest tree")

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

    def test_every_tree_is_mirror_symmetric(self):
        # "ben sag sol esit cizim istedim" (#v35.1). The round broadleaf grew a
        # shoulder lobe on ONE randomly chosen side, so a bump stuck out of one
        # shoulder with nothing opposite it — every "yuvarlak cikinti" report
        # was pointing at that, and two rounds of shading fixes never touched
        # it because the asymmetry was in the SILHOUETTE, not the shading.
        #
        # Exact pixel equality, which also pins the two things that quietly
        # break mirroring: blobs centred on n/2 instead of (n-1)/2, and the
        # trunk's darker bark being applied to one side only.
        for seed in range(1, len(g.TREE_TILES) + 1):
            with self.subTest(tree=f"tree_{seed - 1:02d}"):
                grid = g._tree_variant(seed)
                n = len(grid)
                for r in range(n):
                    for c in range(n // 2):
                        self.assertEqual(grid[r][c], grid[r][n - 1 - c],
                                         f"row {r} differs at columns {c} / {n - 1 - c}")

    def test_every_tree_shows_some_trunk(self):
        # "yere baglamissin agaci": the pine's widest tier sat at 0.70n with a
        # half-height of 0.30n, so the canopy's underside landed exactly on the
        # ground row — the crown swallowed the trunk and the tree read as a bush
        # glued to the floor. Assert there are rows of trunk with no canopy
        # beside them, which is what "the trunk shows" actually means.
        for seed in range(1, len(g.TREE_TILES) + 1):
            with self.subTest(tree=f"tree_{seed - 1:02d}"):
                grid = g._tree_variant(seed)
                bare = 0
                for row in grid:
                    ink = [px for px in row if px[3]]
                    if ink and all(px[0] > px[1] for px in ink):  # brown only
                        bare += 1
                self.assertGreaterEqual(bare, 2,
                                        "the canopy reaches the ground — no trunk shows")

    def test_no_canopy_has_a_seam_running_through_it(self):
        # "yuvarlagin icinde sanki baska bir agac parcasi varmis gibi bogumlar"
        # (#v34.17). Each lobe used to shade itself as it was painted, so where
        # two lobes overlapped the later one laid its dark rim down INSIDE the
        # shared crown — a curved seam through the middle of the canopy.
        #
        # The observable property: a crown shaded from its own outline keeps its
        # DARK tones on that outline. A lobe rim painted inside the shared crown
        # puts them deep in the middle instead. Measured as the true distance to
        # transparency (multi-source BFS), independent of how the generator
        # decides what is an edge — so this is a check on the result, not a
        # restatement of the algorithm.
        #
        # The bound was set by running this against the pre-fix generator, not
        # by guessing: the SHADE tone (second darkest) reached 0.250n inside the
        # crown on the ten lobed trees and 0.094n at worst on the fixed ones, so
        # 0.12n fails every sprite the user complained about and passes all
        # twenty now. A first attempt used "the two darkest tones" at 0.20n and
        # would have passed the broken sprites unchanged — the underside band is
        # legitimately deep, and averaging it in hid the signal.
        for seed in range(1, len(g.TREE_TILES) + 1):
            with self.subTest(tree=f"tree_{seed - 1:02d}"):
                grid = g._tree_variant(seed)
                n = len(grid)
                canopy = [[bool(px[3]) and px[1] >= px[0] for px in row] for row in grid]
                dist = [[-1] * n for _ in range(n)]
                q = deque()
                for r in range(n):
                    for c in range(n):
                        if not canopy[r][c]:
                            dist[r][c] = 0
                            q.append((r, c))
                while q:
                    r, c = q.popleft()
                    for dr, dc in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        nr, nc = r + dr, c + dc
                        if 0 <= nr < n and 0 <= nc < n and dist[nr][nc] < 0:
                            dist[nr][nc] = dist[r][c] + 1
                            q.append((nr, nc))
                tones = {}
                for r in range(n):
                    for c in range(n):
                        if canopy[r][c]:
                            tones.setdefault(grid[r][c][:3], []).append((r, c))
                if len(tones) < 3:
                    continue  # a single-tone crown has no seams to find
                shade = sorted(tones, key=sum)[1]  # darkest is the underside band
                deepest = max(dist[r][c] for r, c in tones[shade]) / n
                self.assertLessEqual(deepest, 0.12,
                                     f"shade sits {deepest:.3f}n inside the crown "
                                     f"— that is a lobe seam, not an outline")

    def test_the_forest_keeps_some_dark_trees(self):
        # #v34.9 — the user asked for the old deep-green trees back in the mix,
        # so the tree line has weight instead of being all bright canopy.
        dark = 0
        for seed in range(1, len(g.TREE_TILES) + 1):
            canopy = [px for row in g._tree_variant(seed) for px in row
                      if px[3] and px[1] > px[0] and px[1] > px[2]]
            # 90 sits in the empty band between the two clusters the seven hue
            # families actually produce: 74.7-80.7 for the three dark ones and
            # 104-132 for the four bright ones, with nothing in between. The
            # old 75 was calibrated against the pre-#v34.18 shading, where a
            # wide dark underside band dragged every mean down — it landed
            # INSIDE the dark cluster, so thinning the rim to a 1px outline
            # made genuinely-dark trees start reading as bright.
            if canopy and sum(px[1] for px in canopy) / len(canopy) < 90:
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

    def test_every_prop_stands_on_the_bottom_row_of_its_canvas(self):
        # "calilar sanki havadaymis gibi duruyor" (#v34.14). The renderer puts
        # the canvas BOTTOM on the tile's ground point, so an empty row under
        # the art is a gap of air under the plant. Bushes and rocks each carried
        # 2-3 of them while trees and flowers had none — same drawn height,
        # different ground contact, and nothing in the suite looked.
        def bottom_pad(grid):
            n = len(grid)
            rows = [r for r in range(n) if any(px[3] for px in grid[r])]
            return n - 1 - max(rows) if rows else n

        for seed in range(1, len(g.TREE_TILES) + 1):
            with self.subTest(prop=f"tree_{seed - 1:02d}"):
                self.assertEqual(bottom_pad(g._tree_variant(seed)), 0)
        for seed in range(1, 11):
            with self.subTest(prop=f"bush_{seed - 1:02d}"):
                self.assertEqual(bottom_pad(g._bush_variant(seed)), 0)
        for seed in range(1, 6):
            with self.subTest(prop=f"rock_{seed - 1:02d}"):
                self.assertEqual(bottom_pad(g._rock_variant(seed)), 0)

    def test_no_tree_has_a_flat_cut_across_its_head(self):
        # "digerleri gibi yumusak bir sekilde üstü cizmek varken düz cizgi
        # direk, sanki agac tepeden kesilmis gibi" (#v34.14).
        #
        # blob() derived its row range asymmetrically — `bcy - rad` on top but
        # `bcy + rad/squash` underneath — so any blob with squash < 1, i.e.
        # every poplar at 0.60, never had the top ~10 rows of its crown visited
        # and came out with a hard horizontal edge. The existing canvas-edge
        # test could not see it: the cut lands mid-canvas, not on row 0.
        #
        # Measured as the longest run of adjacent columns whose topmost opaque
        # pixel is on the SAME row, against the CANVAS width.
        #
        # Against the canopy's ink width — the first version — it punished
        # narrow crowns for nothing: a 12-pixel-wide poplar top discretises to
        # 6 columns on one row simply because that is what a small rounded arc
        # does, scoring 0.50 while looking perfectly round. Against the canvas
        # the numbers separate on the thing that matters, how much of the tree's
        # own frame the flat edge spans: every current sprite is <= 0.19, and
        # the poplars that really were cut measured 0.34-0.39.
        for seed in range(1, len(g.TREE_TILES) + 1):
            with self.subTest(tree=f"tree_{seed - 1:02d}"):
                grid = g._tree_variant(seed)
                n = len(grid)
                tops = [next((r for r in range(n) if grid[r][c][3]), None)
                        for c in range(n)]
                width = sum(1 for t in tops if t is not None)
                best = cur = 0
                prev = None
                for t in tops:
                    cur = cur + 1 if (t is not None and t == prev) else (1 if t is not None else 0)
                    prev = t
                    best = max(best, cur)
                self.assertLess(best / n, 0.28,
                                f"{best} adjacent canopy columns start on one row, "
                                f"spanning {best / n:.0%} of the {n}px canvas "
                                f"(canopy is {width}px wide) — the head is cut "
                                f"flat, not drawn round")


if __name__ == "__main__":
    unittest.main()
