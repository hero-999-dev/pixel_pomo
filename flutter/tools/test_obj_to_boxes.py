#!/usr/bin/env python3
"""Self-check for the Blockbench converter: `python tools/test_obj_to_boxes.py`.

The converter is the artist path into the garden, and it runs on a machine that
has no Flutter on it, so it carries its own check rather than a Dart test.
"""
import os
import tempfile

from obj_to_boxes import Refused, convert

# Two stacked cuboids in Blockbench's own units (16 = one tile): a 8x8x8 body
# on the ground and a wider 12x12x4 lid on top of it. OBJ is Y-up.
CUBE_FACES = "f 1 2 3 4\nf 5 6 7 8\n"


def cuboid(name, x0, y0, z0, x1, y1, z1, mtl, base):
    verts = [(x, y, z) for x in (x0, x1) for y in (y0, y1) for z in (z0, z1)]
    out = [f"o {name}", f"usemtl {mtl}"]
    out += [f"v {x} {y} {z}" for x, y, z in verts]
    out.append("f " + " ".join(str(base + i) for i in range(1, 9)))
    return "\n".join(out) + "\n"


def write(tmp, body):
    obj = os.path.join(tmp, "hut.obj")
    with open(obj, "w", encoding="utf-8") as f:
        f.write("mtllib hut.mtl\n" + body)
    with open(os.path.join(tmp, "hut.mtl"), "w", encoding="utf-8") as f:
        f.write("newmtl wood\nKd 0.545 0.353 0.169\nnewmtl roof\nKd 0.549 0.231 0.165\n")
    return obj


def main():
    with tempfile.TemporaryDirectory() as tmp:
        obj = write(tmp, cuboid("body", -4, 0, -4, 4, 8, 4, "wood", 0)
                    + cuboid("roof", -6, 8, -6, 6, 12, 6, "roof", 8))
        mesh = convert(obj, "hut")

        assert mesh["id"] == "hut", mesh["id"]
        body, roof = mesh["boxes"]                      # sorted bottom-up by z
        assert (body["z"], roof["z"]) == (0.0, 0.5), mesh["boxes"]
        assert (body["w"], body["d"], body["h"]) == (0.5, 0.5, 0.5), body
        assert (roof["w"], roof["h"]) == (0.75, 0.25), roof
        assert (body["x"], body["y"]) == (0.0, 0.0), body
        assert mesh["tiles"] == 0.75, mesh["tiles"]     # widest footprint
        assert body["side"] == "8B5A2B", body["side"]   # straight from the .mtl Kd
        assert body["top"] == "AA6E34", body["top"]     # brightened by TOP_LIFT
        assert roof["side"] == "8C3B2A", roof["side"]

        # A rotated or free-form shape must be refused here, where the message
        # can say what to fix, rather than drawn wrong on someone's phone.
        skewed = "o bad\nusemtl wood\n" + "".join(
            f"v {x} {y} {z}\n" for x, y, z in
            [(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1),
             (0.3, 2, 0), (1.3, 2, 0), (1.3, 2, 1), (0.3, 2, 1)]
        ) + "f 1 2 3 4 5 6 7 8\n"
        try:
            convert(write(tmp, skewed), "bad")
        except Refused as exc:
            assert "not axis-aligned" in str(exc), exc
        else:
            raise AssertionError("a rotated box was accepted")

    print("obj_to_boxes: ok")


if __name__ == "__main__":
    main()
