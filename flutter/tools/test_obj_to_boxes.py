#!/usr/bin/env python3
"""Self-check for the Blockbench converter (#v36).

The converter is the artist path into the garden and runs on a machine with no
Flutter on it, so it carries its own check rather than a Dart test. `unittest`,
not bare asserts, because CI's gate is
`python3 -m unittest discover -s tools -p 'test_*.py'` — anything else here is
imported and then silently not run.

    python tools/test_obj_to_boxes.py
"""
import os
import tempfile
import unittest

from obj_to_boxes import Refused, convert


def cuboid(name, x0, y0, z0, x1, y1, z1, mtl, base):
    """One OBJ object group spanning the given corners. OBJ indices are
    file-global and 1-based, hence [base]."""
    verts = [(x, y, z) for x in (x0, x1) for y in (y0, y1) for z in (z0, z1)]
    out = [f"o {name}", f"usemtl {mtl}"]
    out += [f"v {x} {y} {z}" for x, y, z in verts]
    out.append("f " + " ".join(str(base + i) for i in range(1, 9)))
    return "\n".join(out) + "\n"


def write(tmp, body, name="hut"):
    obj = os.path.join(tmp, f"{name}.obj")
    with open(obj, "w", encoding="utf-8") as f:
        f.write(f"mtllib {name}.mtl\n" + body)
    with open(os.path.join(tmp, f"{name}.mtl"), "w", encoding="utf-8") as f:
        f.write("newmtl wood\nKd 0.545 0.353 0.169\n"
                "newmtl roof\nKd 0.549 0.231 0.165\n")
    return obj


class ObjToBoxesTest(unittest.TestCase):
    """A body 8x8x8 on the ground with a wider 12x12x4 lid on top, in
    Blockbench's own units (16 = one garden tile). OBJ is Y-up."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.mesh = convert(write(
            self.tmp.name,
            cuboid("body", -4, 0, -4, 4, 8, 4, "wood", 0)
            + cuboid("roof", -6, 8, -6, 6, 12, 6, "roof", 8)), "hut")

    def test_units_and_axes(self):
        body, roof = self.mesh["boxes"]
        self.assertEqual(self.mesh["id"], "hut")
        # 16 OBJ units to a tile, and OBJ's Y (up) becomes the garden's z
        self.assertEqual((body["w"], body["d"], body["h"]), (0.5, 0.5, 0.5))
        self.assertEqual((body["x"], body["y"], body["z"]), (0.0, 0.0, 0.0))
        self.assertEqual((roof["w"], roof["h"]), (0.75, 0.25))
        # the widest footprint, so the mesh declares how big it means to read
        self.assertEqual(self.mesh["tiles"], 0.75)

    def test_boxes_come_out_bottom_up(self):
        # Stacked boxes tie on depth and the engine's sort is stable, so file
        # order is the only thing putting the roof on the walls.
        self.assertEqual([b["z"] for b in self.mesh["boxes"]], [0.0, 0.5])

    def test_colours_come_from_the_mtl(self):
        body, roof = self.mesh["boxes"]
        self.assertEqual(body["side"], "8B5A2B")   # Kd, straight through
        self.assertEqual(body["top"], "AA6E34")    # brightened by TOP_LIFT
        self.assertEqual(roof["side"], "8C3B2A")

    def test_a_rotated_box_is_refused_by_name(self):
        # The whole value of this path is failing at conversion, with a message
        # saying what to fix, instead of looking broken on someone's phone.
        skewed = "o bad\nusemtl wood\n" + "".join(
            f"v {x} {y} {z}\n" for x, y, z in
            [(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1),
             (0.3, 2, 0), (1.3, 2, 0), (1.3, 2, 1), (0.3, 2, 1)]
        ) + "f 1 2 3 4 5 6 7 8\n"
        with self.assertRaises(Refused) as caught:
            convert(write(self.tmp.name, skewed, "bad"), "bad")
        self.assertIn("not axis-aligned", str(caught.exception))

    def test_a_merged_mesh_is_refused(self):
        # 'Export OBJ' with everything merged loses the per-cuboid groups, and
        # a mesh with no groups would otherwise write an empty file.
        obj = write(self.tmp.name, "v 0 0 0\nv 1 0 0\nv 1 1 0\n", "flat")
        with self.assertRaises(Refused):
            convert(obj, "flat")


if __name__ == "__main__":
    unittest.main()
