#!/usr/bin/env python3
"""Convert a MagicaVoxel .vox file into a garden box mesh (#v36).

The second artist path, beside ``obj_to_boxes.py``. MagicaVoxel's own OBJ
export is one merged, palette-textured mesh, which that converter rightly
refuses — so this one reads the .vox itself, where every voxel is already the
axis-aligned box the garden engine draws.

        python vox_to_boxes.py cafe.vox --id house_cafe

    Writes ../assets/meshes/house_cafe.json.

How a model becomes boxes:

* **One box per vertical run.** Voxels of one colour stacked in the same
  column merge into a single box; nothing is merged sideways. That is not
  timidity: the engine has no depth buffer and sorts whole boxes by their
  footprint centre, which is exact only while every footprint is the same
  size. A wall merged into one long box would sort by its middle and paint
  over the things standing in front of its ends.
* **Only what the camera can see.** A voxel is kept if open air touches its
  top or one of its four sides; the underside never counts (the camera is
  always above) and a sealed cavity is not open air. A solid model therefore
  costs its shell, not its volume.
* **16 voxels to a tile**, the same scale as Blockbench and as the sprites
  (one tile = 16 art pixels). --units changes it; --tiles fits the model's
  wider side to a number of tiles instead.
* **MagicaVoxel's front (-y) faces the camera.** --turn spins the model in
  quarter turns if it was built facing another way.
* **Colours from the palette**, with the top face brightened exactly as
  ``obj_to_boxes.py`` does it.

Deliberately NOT supported: materials (glass, emission, metal), and the scene
graph — a file holding several models converts ONE of them (--model N, --list
to see them), untransformed. Placing and rotating models against each other is
the same material-and-skinning road the Blockbench path already declined.
"""
import argparse
import json
import os
import struct
import sys

from obj_to_boxes import DEFAULT_UNITS, Refused, brighten


def read_vox(path):
    """-> ([(size, {(x, y, z): palette index})] per model, ['RRGGBB'] * 256).

    A .vox is 'VOX ', a version, then one MAIN chunk whose children are what
    matter here: a SIZE + XYZI pair per model, and one RGBA palette. Every
    chunk is id, content length, children length, content.
    """
    name = os.path.basename(path)
    with open(path, "rb") as f:
        buf = f.read()
    if buf[:4] != b"VOX " or buf[8:12] != b"MAIN":
        raise Refused(f"{name} is not a MagicaVoxel .vox file")

    models, palette, size = [], None, None
    at, end = 20 + struct.unpack_from("<i", buf, 12)[0], len(buf)
    while at + 12 <= end:
        cid, n, m = struct.unpack_from("<4sii", buf, at)
        body = at + 12
        if cid == b"SIZE":
            size = struct.unpack_from("<iii", buf, body)
        elif cid == b"XYZI":
            count, = struct.unpack_from("<i", buf, body)
            raw = buf[body + 4:body + 4 + 4 * count]
            models.append((size, {(raw[i], raw[i + 1], raw[i + 2]): raw[i + 3]
                                  for i in range(0, len(raw), 4)}))
        elif cid == b"RGBA":
            # entry k is the colour of palette index k + 1; index 0 is "empty"
            palette = ["000000"] + ["%02X%02X%02X" % tuple(buf[body + 4 * k:body + 4 * k + 3])
                                    for k in range(255)]
        at = body + n + m

    if not models:
        raise Refused(f"{name} has no models in it")
    if palette is None:
        raise Refused(f"{name} carries no palette — open it in MagicaVoxel and "
                      "save it again, which writes one")
    return models, palette


def turned(voxels, quarter_turns):
    """Spin the model about its vertical axis and slide it back to the origin,
    so the footprint centre and the ground are where the mesh expects them."""
    for _ in range(quarter_turns % 4):
        voxels = {(y, -x, z): i for (x, y, z), i in voxels.items()}
    x0 = min(x for x, _, _ in voxels)
    y0 = min(y for _, y, _ in voxels)
    z0 = min(z for _, _, z in voxels)
    return {(x - x0, y - y0, z - z0): i for (x, y, z), i in voxels.items()}


def visible_runs(voxels):
    """[(x, y, z0, z1, palette index)] — one per same-colour vertical run that
    the camera can see any of, trimmed to the part it can see.

    Open air is flooded in from above and from the sides of the bounding box,
    never from below: the model stands on the ground, so a hollow shell's
    inside is sealed and its floor is not drawn.
    """
    sx = max(x for x, _, _ in voxels) + 3   # one cell of air either side
    sy = max(y for _, y, _ in voxels) + 3
    sz = max(z for _, _, z in voxels) + 2   # and one above; none below
    layer = sx * sy
    solid, air = 1, 2
    grid = bytearray(layer * sz)

    def at(x, y, z):
        return z * layer + (y + 1) * sx + x + 1

    for x, y, z in voxels:
        grid[at(x, y, z)] = solid
    # A step off the end of a row lands in the next row's margin, which is air
    # too, so the flat index needs no edge test — only the two ends of the array.
    steps = (1, -1, sx, -sx, layer, -layer)
    todo = [len(grid) - 1]
    grid[todo[0]] = air
    while todo:
        here = todo.pop()
        for step in steps:
            there = here + step
            if 0 <= there < len(grid) and not grid[there]:
                grid[there] = air
                todo.append(there)

    def seen(x, y, z):
        here = at(x, y, z)
        return any(grid[here + step] == air for step in (layer, 1, -1, sx, -sx))

    columns = {}
    for (x, y, z), i in voxels.items():
        columns.setdefault((x, y), []).append((z, i))

    runs = []
    for (x, y), column in columns.items():
        column.sort()
        start = 0
        for k in range(1, len(column) + 1):
            if (k == len(column) or column[k][1] != column[start][1]
                    or column[k][0] != column[k - 1][0] + 1):
                zs = [z for z, _ in column[start:k] if seen(x, y, z)]
                if zs:
                    runs.append((x, y, zs[0], zs[-1] + 1, column[start][1]))
                start = k
    return runs


def describe(models):
    return "\n".join(f"  {n}: {sx}x{sy}x{sz}, {len(voxels)} voxels"
                     for n, ((sx, sy, sz), voxels) in enumerate(models))


def convert(vox_path, mesh_id, units=DEFAULT_UNITS, tiles=None, model=None, turn=0):
    models, palette = read_vox(vox_path)
    name = os.path.basename(vox_path)
    if model is None:
        if len(models) > 1:
            raise Refused(f"{name} holds {len(models)} models — a mesh is one of "
                          f"them, so pick it with --model N:\n{describe(models)}")
        model = 0
    if not 0 <= model < len(models):
        raise Refused(f"{name} has no model {model} — it holds 0..{len(models) - 1}")
    voxels = models[model][1]
    if not voxels:
        raise Refused(f"model {model} of {name} is empty")

    voxels = turned(voxels, turn)
    span_x = max(x for x, _, _ in voxels) + 1
    span_y = max(y for _, y, _ in voxels) + 1
    if tiles is not None:
        units = max(span_x, span_y) / tiles

    boxes = []
    for x, y, z0, z1, index in visible_runs(voxels):
        colour = palette[index]
        boxes.append({
            # MagicaVoxel is z-up like the garden, but its +y runs AWAY from
            # the viewer where the garden's runs toward the camera.
            "x": round((x + 0.5 - span_x / 2) / units, 4),
            "y": round(-(y + 0.5 - span_y / 2) / units, 4),
            "z": round(z0 / units, 4),
            "w": round(1 / units, 4),
            "d": round(1 / units, 4),
            "h": round((z1 - z0) / units, 4),
            "side": colour,
            "top": brighten(colour),
        })

    # bottom-up, so stacked boxes (which tie on depth) land in the right order
    boxes.sort(key=lambda b: (b["z"], b["y"], b["x"]))
    return {"id": mesh_id, "tiles": round(max(span_x, span_y) / units, 4), "boxes": boxes}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("vox", help="the .vox saved from MagicaVoxel")
    ap.add_argument("--id", help="mesh id (default: the file's own name)")
    ap.add_argument("--model", type=int, help="which model, in a file that holds several")
    ap.add_argument("--list", action="store_true", help="list the file's models and stop")
    size = ap.add_mutually_exclusive_group()
    size.add_argument("--units", type=float, default=DEFAULT_UNITS,
                      help=f"voxels per garden tile (default {DEFAULT_UNITS:g})")
    size.add_argument("--tiles", type=float,
                      help="fit the model's wider side to this many tiles instead")
    ap.add_argument("--turn", type=int, default=0, choices=(0, 90, 180, 270),
                    help="spin the model this many degrees about its vertical axis")
    ap.add_argument("--out", help="output dir (default ../assets/meshes)")
    args = ap.parse_args(argv)

    mesh_id = args.id or os.path.splitext(os.path.basename(args.vox))[0]
    out_dir = args.out or os.path.join(os.path.dirname(__file__), "..", "assets", "meshes")

    try:
        if args.list:
            print(describe(read_vox(args.vox)[0]))
            return 0
        mesh = convert(args.vox, mesh_id, args.units, args.tiles, args.model, args.turn // 90)
    except Refused as exc:
        print(f"refused: {exc}", file=sys.stderr)
        return 1

    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, f"{mesh_id}.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(mesh, f, indent=1)
        f.write("\n")
    top = max(b["z"] + b["h"] for b in mesh["boxes"])
    # The box count is the price: both renderers fill five quads per box, per
    # frame, for every copy of the object standing in the garden.
    print(f"wrote {path}: {len(mesh['boxes'])} boxes, "
          f"{mesh['tiles']:.2f} tiles wide, {top:.2f} tall")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
