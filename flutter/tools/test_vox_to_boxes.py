#!/usr/bin/env python3
"""Self-check for the MagicaVoxel converter (#v36).

Same reasons as test_obj_to_boxes.py: the converter runs on an artist's machine
with no Flutter on it, and CI's gate is
`python3 -m unittest discover -s tools -p 'test_*.py'`.

    python tools/test_vox_to_boxes.py
"""
import os
import struct
import tempfile
import unittest

from obj_to_boxes import Refused
from vox_to_boxes import convert

WOOD, ROOF = 1, 2
PALETTE = {WOOD: (0x8B, 0x5A, 0x2B), ROOF: (0x8C, 0x3B, 0x2A)}


def chunk(cid, content=b"", children=b""):
    return cid + struct.pack("<ii", len(content), len(children)) + content + children


def vox(*models, palette=PALETTE):
    """The bytes MagicaVoxel would save for these {(x, y, z): index} models."""
    body = b""
    for voxels in models:
        size = [max(p[axis] for p in voxels) + 1 if voxels else 1 for axis in range(3)]
        body += chunk(b"SIZE", struct.pack("<iii", *size))
        body += chunk(b"XYZI", struct.pack("<i", len(voxels)) + b"".join(
            bytes((x, y, z, i)) for (x, y, z), i in voxels.items()))
    if palette is not None:
        # entry k colours palette index k + 1
        body += chunk(b"RGBA", b"".join(
            bytes(palette.get(k + 1, (0, 0, 0))) + b"\xff" for k in range(256)))
    return b"VOX " + struct.pack("<i", 200) + chunk(b"MAIN", children=body)


def block(sx, sy, sz, index=WOOD, at=(0, 0, 0)):
    return {(at[0] + x, at[1] + y, at[2] + z): index
            for x in range(sx) for y in range(sy) for z in range(sz)}


class VoxToBoxesTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def mesh(self, *models, name="hut", **kw):
        path = os.path.join(self.tmp.name, f"{name}.vox")
        with open(path, "wb") as f:
            f.write(vox(*models, **kw.pop("file", {})))
        return convert(path, name, **kw)

    def test_units_and_axes(self):
        # one 8-tall post: a single column, so a single box
        mesh = self.mesh(block(1, 1, 8))
        (post,) = mesh["boxes"]
        self.assertEqual(mesh["id"], "hut")
        # 16 voxels to a tile, MagicaVoxel's z (up) stays the garden's z
        self.assertEqual((post["w"], post["d"], post["h"]), (0.0625, 0.0625, 0.5))
        self.assertEqual((post["x"], post["y"], post["z"]), (0.0, 0.0, 0.0))
        self.assertEqual(mesh["tiles"], 0.0625)

    def test_colours_come_from_the_palette(self):
        (post,) = self.mesh(block(1, 1, 3))["boxes"]
        self.assertEqual(post["side"], "8B5A2B")   # palette entry, straight through
        self.assertEqual(post["top"], "AA6E34")    # brightened by TOP_LIFT

    def test_a_colour_change_splits_the_column_bottom_up(self):
        # Stacked boxes tie on depth and the engine's sort is stable, so file
        # order is the only thing putting the roof on the walls.
        mesh = self.mesh(block(1, 1, 4) | block(1, 1, 2, ROOF, at=(0, 0, 4)))
        self.assertEqual([(b["z"], b["h"], b["side"]) for b in mesh["boxes"]],
                         [(0.0, 0.25, "8B5A2B"), (0.25, 0.125, "8C3B2A")])

    def test_every_box_keeps_the_same_footprint(self):
        # The rule the whole path rests on: the engine sorts boxes by footprint
        # centre with no depth buffer, which is exact only between footprints
        # of one size. A wall merged sideways would paint over what stands in
        # front of its ends.
        mesh = self.mesh(block(6, 1, 3) | block(1, 4, 5, ROOF, at=(2, 1, 0)))
        self.assertEqual({(b["w"], b["d"]) for b in mesh["boxes"]}, {(0.0625, 0.0625)})

    def test_a_solid_block_costs_its_shell_not_its_volume(self):
        mesh = self.mesh(block(4, 4, 4))
        heights = sorted(b["h"] for b in mesh["boxes"])
        # 12 full-height columns round the outside; the 4 inside show only
        # their top voxel
        self.assertEqual(heights, [0.0625] * 4 + [0.25] * 12)

    def test_a_sealed_cavity_is_not_open_air(self):
        # A hollow 5x5x5 shell: the floor inside faces the cavity, not the
        # camera, so the middle column is its roof voxel and nothing else.
        shell = {p: i for p, i in block(5, 5, 5).items()
                 if 0 in p or 4 in p}
        middle = [b for b in self.mesh(shell)["boxes"] if (b["x"], b["y"]) == (0.0, 0.0)]
        self.assertEqual([(b["z"], b["h"]) for b in middle], [(0.25, 0.0625)])

    def test_the_magicavoxel_front_faces_the_camera_unmirrored(self):
        # MagicaVoxel's -y is its front and its +x its right; the garden's +y
        # is toward the camera. A marker at front-right must stay front-right,
        # which a careless axis swap would mirror to front-left.
        mesh = self.mesh(block(4, 4, 1) | {(3, 0, 1): ROOF})
        (marker,) = [b for b in mesh["boxes"] if b["side"] == "8C3B2A"]
        self.assertGreater(marker["x"], 0)
        self.assertGreater(marker["y"], 0)

    def test_turn_spins_without_mirroring(self):
        model = block(4, 4, 1) | {(3, 0, 1): ROOF}
        seen = []
        for turn in range(4):
            (marker,) = [b for b in self.mesh(model, turn=turn)["boxes"]
                         if b["side"] == "8C3B2A"]
            seen.append((marker["x"] > 0, marker["y"] > 0))
        # round the four corners in one consistent direction, back to the start
        self.assertEqual(len(set(seen)), 4)
        for a, b in zip(seen, seen[1:] + seen[:1]):
            self.assertEqual(sum(p != q for p, q in zip(a, b)), 1)

    def test_tiles_fits_the_wider_side(self):
        mesh = self.mesh(block(8, 4, 2), tiles=2)
        self.assertEqual(mesh["tiles"], 2.0)
        self.assertEqual(mesh["boxes"][0]["w"], 0.25)

    def test_a_scene_of_several_models_asks_which_one(self):
        # The whole value of this path is failing at conversion, with a message
        # saying what to do, instead of quietly converting the wrong object.
        with self.assertRaises(Refused) as caught:
            self.mesh(block(1, 1, 1), block(2, 2, 2))
        self.assertIn("--model", str(caught.exception))
        self.assertEqual(len(self.mesh(block(1, 1, 1), block(2, 2, 2), model=1)["boxes"]), 4)

    def test_a_file_without_a_palette_is_refused(self):
        with self.assertRaises(Refused):
            self.mesh(block(1, 1, 1), file={"palette": None})

    def test_something_that_is_not_a_vox_is_refused(self):
        path = os.path.join(self.tmp.name, "cube.vox")
        with open(path, "w", encoding="utf-8") as f:
            f.write("o cube\nv 0 0 0\n")
        with self.assertRaises(Refused):
            convert(path, "cube")


if __name__ == "__main__":
    unittest.main()
