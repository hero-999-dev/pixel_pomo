#!/usr/bin/env python3
"""The test build's voxel models: meshes and shop thumbnails (#v36).

Converts the .vox files in ``feedback & guides/Vox`` with ``vox_to_boxes.py``
and writes, for each id in ``Placeables.testHouseIds``:

    ../test_assets/meshes/<id>.json    the box mesh
    ../test_assets/objects/<id>.png    its shop thumbnail

Into ``test_assets/``, NOT ``assets/``, and that is the whole point. These are
other people's models, here only to try the mesh path on a real phone, and
pubspec.yaml does not list ``test_assets/`` — so a build bundles them only if
its own build step copies them across and passes
``--dart-define=TEST_MESHES=true``. The real app's build does neither. Both
folders, the sources and the output, are git-ignored for the same reason.

    python gen_test_meshes.py
"""
import json
import os

from gen_objects import upscale, write_png
from vox_to_boxes import convert, read_vox, turned

HERE = os.path.dirname(__file__)
SOURCES = os.path.join(HERE, "..", "..", "feedback & guides", "Vox")
OUT = os.path.join(HERE, "..", "test_assets")

#: Nothing wider than the cottage (house_wood is 1.7 tiles across): a building
#: already overhangs its tile, and the tank at its own scale would cover three.
WIDEST = 1.7

#: id -> (source file, model number in a file that holds several, fit to tiles)
MODELS = {
    "house_test_tree": ("upload_temp.vox", None, None),
    "house_test_tank": ("Walkure.vox", None, WIDEST),
    "house_test_coffee": ("CoffeeLocal.vox", None, WIDEST),
    "house_test_pipe": ("mario_props.vox", 5, None),
}

THUMB = 256  # the size every other shop thumbnail is


def front_view(path, model):
    """The model seen square-on from its front, one voxel to a pixel — which
    makes it pixel art of the same kind as the thumbnails beside it."""
    models, palette = read_vox(path)
    voxels = turned(models[model or 0][1], 0)
    nearest = {}
    for (x, y, z), index in voxels.items():
        if (x, z) not in nearest or y < nearest[x, z][0]:
            nearest[x, z] = (y, index)
    wide = max(x for x, _ in nearest) + 1
    tall = max(z for _, z in nearest) + 1
    side = max(wide, tall)
    left = (side - wide) // 2
    grid = [[(0, 0, 0, 0)] * side for _ in range(side)]
    for (x, z), (_, index) in nearest.items():
        hex6 = palette[index]
        grid[side - 1 - z][left + x] = tuple(int(hex6[i:i + 2], 16) for i in (0, 2, 4)) + (255,)
    return upscale(grid, max(1, THUMB // side))


def main():
    for folder in ("meshes", "objects"):
        os.makedirs(os.path.join(OUT, folder), exist_ok=True)
    for mesh_id, (source, model, tiles) in MODELS.items():
        path = os.path.join(SOURCES, source)
        mesh = convert(path, mesh_id, tiles=tiles, model=model)
        with open(os.path.join(OUT, "meshes", f"{mesh_id}.json"), "w", encoding="utf-8") as f:
            json.dump(mesh, f, separators=(",", ":"))
            f.write("\n")
        write_png(os.path.join(OUT, "objects", f"{mesh_id}.png"), front_view(path, model))
        print(f"wrote {mesh_id}: {len(mesh['boxes'])} boxes, {mesh['tiles']:.2f} tiles wide")


if __name__ == "__main__":
    main()
