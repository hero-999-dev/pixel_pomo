#!/usr/bin/env python3
"""Box meshes for the garden's buildings (#v36).

The garden engine draws a building as a stack of axis-aligned boxes rather than
as a billboard, because a house is the one object a flat sprite cannot fake:
turn the camera and a billboard reads as a sheet of paper standing in a field.

Meshes ship as JSON in ``assets/meshes/`` because there are TWO renderers — the
Flutter one and the native Kotlin live wallpaper — and they have to draw exactly
the same object. A generated Dart file could only feed one of them.

Two ways to fill that folder:

* this file, for shapes we author ourselves (the placeholder cottage below);
* ``obj_to_boxes.py``, which converts a Blockbench OBJ export into the same
  schema, so an artist can model in a real 3D tool.

Coordinates are in TILE units, matching the engine (one tile = 16 art pixels):

    x, y   centre offset from the tile centre (+y is toward the camera at yaw 0)
    z      elevation of the box's underside; 0 sits on the ground
    w,d,h  full extents across, into, and up
    side   flat colour of all four walls, hex, no '#'
    top    the upward face — a touch brighter, a fixed sky glow baked into the
           geometry so it never swings round when the camera yaws

Boxes are written BOTTOM-UP. Boxes that share a footprint tie on depth and the
engine's sort is stable, so file order is what puts the roof on the walls.
"""
import json
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "meshes")

# Wood matches the wooden fence exactly (8B5A2B / A9743E) so a cottage and the
# fence around it read as the same material.
WOOD, WOOD_TOP = "8B5A2B", "A9743E"
ROOF, ROOF_TOP = "8C3B2A", "A8503A"
STONE, STONE_TOP = "6E6E6E", "9A9A9A"
DOOR, DOOR_TOP = "4A2E16", "5C3A1E"
# Lit windows, the coin/flower-centre gold. They are what carries "someone is
# home" — the shop thumbnail has them, so the object standing in the garden has
# to have them too, or the two read as different buildings.
GLASS, GLASS_TOP = "F2C94C", "F7DD8B"


#: A building is drawn bigger than the tile it stands on, exactly as a forest
#: tree is. Authored at a readable 1.0 = one tile and scaled once here, so the
#: shape stays easy to edit and the size is a single number to tune. At 1.0 the
#: first cottage came out SHORTER than the daisy beside it, which read as a
#: dollhouse; 1.85 puts it at a small tree's height.
SCALE = 1.85


def box(x, y, z, w, d, h, side, top):
    return {k: round(v * SCALE, 4) for k, v in
            (("x", x), ("y", y), ("z", z), ("w", w), ("d", d), ("h", h))} | \
        {"side": side, "top": top}


def house_wood():
    """A wooden cottage: body, a stepped roof, chimney, door.

    The roof is stepped rather than sloped on purpose. A true slope needs
    non-axis-aligned faces, which the box primitive does not have, and a stair
    of three slabs is what pixel art does anyway — it reads as a pitched roof at
    a glance and stays crisp at every zoom.

    The chimney is the one asymmetric part. Everything else mirrors, per the
    house style; a chimney is architecture rather than hand-drawn irregularity,
    and it is what stops the roofline reading as a plain pyramid.
    """
    return {
        "id": "house_wood",
        "tiles": 0.92 * SCALE,
        "boxes": [
            box(0, 0, 0.00, 0.72, 0.72, 0.55, WOOD, WOOD_TOP),      # body
            # Door and windows sit ON the front wall (y 0.38 = the wall's own
            # 0.36 plus half their 0.04 thickness) rather than sunk into it —
            # the no-intersection rule the chimney note below spells out.
            box(0, 0.38, 0.00, 0.24, 0.04, 0.34, DOOR, DOOR_TOP),   # door
            box(-0.22, 0.38, 0.28, 0.16, 0.04, 0.14, GLASS, GLASS_TOP),
            box(0.22, 0.38, 0.28, 0.16, 0.04, 0.14, GLASS, GLASS_TOP),
            box(0, 0, 0.55, 0.92, 0.92, 0.13, ROOF, ROOF_TOP),      # eaves
            box(0, 0, 0.68, 0.64, 0.64, 0.13, ROOF, ROOF_TOP),      # roof step
            box(0, 0, 0.81, 0.34, 0.34, 0.13, ROOF, ROOF_TOP),      # ridge cap
            # The chimney SITS ON the roof step (top 0.81) rather than sinking
            # into it. Boxes must not intersect: the engine sorts whole boxes by
            # their footprint, with no depth buffer, so an intersecting box is
            # drawn either wholly in front or wholly behind — a chimney buried
            # in the roof showed its buried half hanging down the front wall as
            # soon as the camera came round. Non-intersecting boxes sort
            # exactly right from every angle; that is the rule the whole
            # pipeline rests on.
            box(0.22, -0.20, 0.81, 0.16, 0.16, 0.36, STONE, STONE_TOP),  # chimney
        ],
    }


MESHES = [house_wood]


def main():
    os.makedirs(OUT, exist_ok=True)
    for fn in MESHES:
        mesh = fn()
        path = os.path.join(OUT, f"{mesh['id']}.json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump(mesh, f, indent=1)
            f.write("\n")
        top = max(b["z"] + b["h"] for b in mesh["boxes"])
        print(f"wrote {mesh['id']}: {len(mesh['boxes'])} boxes, {top:.2f} tiles tall")


if __name__ == "__main__":
    main()
