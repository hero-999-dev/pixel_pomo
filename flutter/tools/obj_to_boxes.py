#!/usr/bin/env python3
"""Convert a Blockbench OBJ export into a garden box mesh (#v36).

This is the artist path. Blockbench is free, runs on macOS and in a browser,
and builds models out of axis-aligned cuboids — which is exactly the primitive
the garden engine already draws. So the engine never grew a mesh importer; this
script meets it halfway instead, turning an OBJ export into the same JSON that
``gen_meshes.py`` writes.

    File -> Export -> OBJ  in Blockbench, then:

        python obj_to_boxes.py house_wood.obj --id house_wood

    Writes ../assets/meshes/house_wood.json.

What it expects, and enforces:

* **Cuboids only.** Every object group must be a box with 8 distinct corners.
  A rotated box, a wedge or a free mesh is refused by name, so a model that
  would come out wrong fails here rather than looking broken on a phone.
* **16 units to a tile** (Blockbench's own block scale). Override with --units.
* **Colours from the .mtl**, one material per box, taken from its Kd. The top
  face is brightened by --top-lift so the object catches the same fixed sky
  glow every other 3D object in the garden does.

Deliberately NOT supported: textures, rotation, bones, animation. All three
would need the engine to grow a real material and skinning system; the whole
point of the box pipeline is that it does not have to.
"""
import argparse
import json
import os
import sys

DEFAULT_UNITS = 16.0  # Blockbench: 16 units = one block = one garden tile
TOP_LIFT = 1.22       # how much brighter the sky-lit top face is


class Refused(Exception):
    """Raised instead of writing a mesh that would draw wrong."""


def parse_mtl(path):
    """material name -> 'RRGGBB' from each newmtl's Kd."""
    out, name = {}, None
    if not os.path.exists(path):
        return out
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            parts = line.split()
            if not parts:
                continue
            if parts[0] == "newmtl":
                name = parts[1]
            elif parts[0] == "Kd" and name:
                r, g, b = (float(v) for v in parts[1:4])
                out[name] = "%02X%02X%02X" % tuple(
                    max(0, min(255, round(v * 255))) for v in (r, g, b))
    return out


def brighten(hex6, factor=TOP_LIFT):
    r, g, b = (int(hex6[i:i + 2], 16) for i in (0, 2, 4))
    return "%02X%02X%02X" % tuple(min(255, round(v * factor)) for v in (r, g, b))


def parse_obj(path):
    """[(group name, [vertices], material)] — vertices are (x, y, z) floats.

    OBJ vertex indices are file-global and 1-based, so vertices are collected
    across the whole file and each group keeps only the ones its faces use.
    """
    verts, groups, mtllib = [], [], None
    name, used, material = None, [], None

    def flush():
        if name is not None and used:
            groups.append((name, [verts[i] for i in sorted(used)], material))

    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            parts = line.split()
            if not parts:
                continue
            head = parts[0]
            if head == "v":
                verts.append(tuple(float(v) for v in parts[1:4]))
            elif head in ("o", "g"):
                flush()
                name, used, material = " ".join(parts[1:]) or "unnamed", [], material
            elif head == "usemtl":
                material = parts[1]
            elif head == "f":
                for token in parts[1:]:
                    i = int(token.split("/")[0])
                    used.append(i - 1 if i > 0 else len(verts) + i)
            elif head == "mtllib":
                mtllib = " ".join(parts[1:])
    flush()
    if not groups:
        raise Refused(f"{os.path.basename(path)} has no object groups in it — "
                      "export from Blockbench with 'Export OBJ', not a merged mesh")
    return groups, mtllib


def group_to_box(name, verts, colour):
    """One cuboid group -> the mesh box dict, still in OBJ units."""
    uniq = sorted(set(verts))
    if len(uniq) != 8:
        raise Refused(
            f"'{name}' has {len(uniq)} distinct corners, not 8 — the engine draws "
            "axis-aligned boxes only, so split it into cuboids in Blockbench "
            "(no rotation, no free meshes)")
    xs = sorted({v[0] for v in uniq})
    ys = sorted({v[1] for v in uniq})
    zs = sorted({v[2] for v in uniq})
    if (len(xs), len(ys), len(zs)) != (2, 2, 2):
        raise Refused(
            f"'{name}' is not axis-aligned — its corners span "
            f"{len(xs)}x{len(ys)}x{len(zs)} distinct values instead of 2x2x2. "
            "Set its rotation back to 0 in Blockbench.")
    return {
        # OBJ is Y-up; the garden's ground plane is x/z with y as elevation.
        "x": (xs[0] + xs[1]) / 2,
        "y": (zs[0] + zs[1]) / 2,
        "z": ys[0],
        "w": xs[1] - xs[0],
        "d": zs[1] - zs[0],
        "h": ys[1] - ys[0],
        "side": colour,
        "top": brighten(colour),
    }


def convert(obj_path, mesh_id, units=DEFAULT_UNITS, default_colour="8B5A2B"):
    groups, mtllib = parse_obj(obj_path)
    materials = parse_mtl(os.path.join(os.path.dirname(obj_path), mtllib)) if mtllib else {}

    boxes = []
    for name, verts, material in groups:
        colour = materials.get(material or "", default_colour)
        b = group_to_box(name, verts, colour)
        for k in ("x", "y", "z", "w", "d", "h"):
            b[k] = round(b[k] / units, 4)
        boxes.append(b)

    # bottom-up, so stacked boxes (which tie on depth) land in the right order
    boxes.sort(key=lambda b: b["z"])
    footprint = max(max(abs(b["x"]) + b["w"] / 2, abs(b["y"]) + b["d"] / 2) for b in boxes)
    return {"id": mesh_id, "tiles": round(footprint * 2, 4), "boxes": boxes}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("obj", help="the .obj exported from Blockbench")
    ap.add_argument("--id", help="mesh id (default: the file's own name)")
    ap.add_argument("--units", type=float, default=DEFAULT_UNITS,
                    help=f"OBJ units per garden tile (default {DEFAULT_UNITS:g})")
    ap.add_argument("--out", help="output dir (default ../assets/meshes)")
    args = ap.parse_args(argv)

    mesh_id = args.id or os.path.splitext(os.path.basename(args.obj))[0]
    out_dir = args.out or os.path.join(os.path.dirname(__file__), "..", "assets", "meshes")

    try:
        mesh = convert(args.obj, mesh_id, args.units)
    except Refused as exc:
        print(f"refused: {exc}", file=sys.stderr)
        return 1

    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, f"{mesh_id}.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(mesh, f, indent=1)
        f.write("\n")
    top = max(b["z"] + b["h"] for b in mesh["boxes"])
    print(f"wrote {path}: {len(mesh['boxes'])} boxes, "
          f"{mesh['tiles']:.2f} tiles wide, {top:.2f} tall")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
