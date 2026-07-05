# Extracts the v29 tracker icons from the user's ChatGPT icon sheet (LOCAL tool,
# needs Pillow — not run in CI, like extract_icons.py): crops the picked panels
# (HABIT 02 STAR calendar, MONEY 03 PIGGY BANK), flood-fills the tan panel
# background to transparency from the borders (the icons' own black outlines
# stop the fill), autocrops, squares, and saves 96px PNGs into assets/icon/.
import os
from collections import deque

from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
SHEET = os.path.normpath(os.path.join(
    HERE, "..", "..", "feedback & guides", "Guides", "Tracker Guides",
    "Habit Tracker", "ChatGPT Image Jul 4, 2026, 01_29_46 PM.png"))
OUT = os.path.normpath(os.path.join(HERE, "..", "assets", "icon"))

# panel boxes as fractions of the sheet (art panel only, inset past the frame)
PANELS = {
    "icon_habit.png": (0.295, 0.125, 0.465, 0.345),   # HABIT 02 - STAR calendar
    "icon_money.png": (0.535, 0.640, 0.705, 0.850),   # MONEY 03 - PIGGY BANK
}


def _keep_largest_component(img):
    """Clears every opaque pixel except those in the single largest
    4-connected blob. A soft drop-shadow that the colour-threshold flood-fill
    can't fully clear (too dark to safely bridge from the background without
    also risking the subject's own dark shading — tried a local-growth
    approach first, it ate straight through the pig's smoothly-shaded body,
    reverted) still shows up as a small ISOLATED blob once the icon's outline
    is a closed shape — this discards anything that isn't the main subject
    without ever touching the subject itself, since it's always the
    overwhelmingly largest connected region."""
    w, h = img.size
    px = img.load()
    visited = bytearray(w * h)
    best, best_size = [], 0
    for y0 in range(h):
        for x0 in range(w):
            i0 = y0 * w + x0
            if visited[i0] or px[x0, y0][3] == 0:
                continue
            comp = []
            q = deque([(x0, y0)])
            visited[i0] = 1
            while q:
                cx, cy = q.popleft()
                comp.append((cx, cy))
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = cx + dx, cy + dy
                    if 0 <= nx < w and 0 <= ny < h:
                        ni = ny * w + nx
                        if not visited[ni] and px[nx, ny][3] != 0:
                            visited[ni] = 1
                            q.append((nx, ny))
            if len(comp) > best_size:
                best_size = len(comp)
                best = comp
    keep = set(best)
    for y in range(h):
        for x in range(w):
            if px[x, y][3] != 0 and (x, y) not in keep:
                px[x, y] = (0, 0, 0, 0)


def extract(crop, out_path, size=96):
    w, h = crop.size
    crop = crop.crop((int(w * 0.10), int(h * 0.10), int(w * 0.90), int(h * 0.90)))
    cw, ch = crop.size
    # sparse seeds on 3 sides (corners + one midpoint each), but DENSE along
    # the BOTTOM edge specifically (every ~10px) — a background pocket
    # topologically trapped behind a leg (found happening on the piggy-bank:
    # a chunk of pure, unprocessed tan sat untouched, walled off from every
    # one of the old 8 fixed points by the pig's own silhouette) only gets
    # cleared if SOME seed lands directly on its little stretch of border,
    # and that gap was at the bottom, near the legs. Densifying ALL FOUR
    # sides this way was tried first and ate into the pig's own snout — a
    # stray point on the top/left edge (near the head) crossed into a facial
    # crease at high threshold. Restricting the extra density to the bottom
    # edge only reaches the actual gap without adding risk near the head.
    # Skip a candidate only if it landed on something near-black — the
    # icon's own outline (found separately: the old left-mid point hit the
    # pig's ear outline). Every other seed is used even if it starts inside
    # a shadow/gradient rather than flat background.
    pts = {(0, 0), (cw - 1, 0), (0, ch - 1), (cw - 1, ch - 1),
           (cw // 2, 0), (0, ch // 2), (cw - 1, ch // 2)}
    for x in range(0, cw, 10):
        pts.add((x, ch - 1))
    seeds = [p for p in pts if sum(crop.getpixel(p)[:3]) > 60]
    # four passes, widening each time: 48 clears the flat panel background,
    # 90/140 eat progressively more of the anti-aliased blend ring, and 200
    # reaches all the way through the pig's soft drop-shadow gradient — a
    # dark, fairly saturated brown well past the earlier ceilings but still
    # far short of the icon's own near-black outline, which stays a wall no
    # matter how high this goes (that's what keeps the flood-fill from ever
    # crossing into the subject itself). (#v30, tightened repeatedly.)
    for thresh in (48, 90, 140, 200):
        for xy in seeds:
            try:
                ImageDraw.floodfill(crop, xy, (0, 0, 0, 0), thresh=thresh)
            except ValueError:
                pass
    # erode the alpha mask by 2px to strip any fringe pixels still standing
    # (semi-opaque anti-aliasing a connected-region flood-fill can't reach) —
    # the source crop is well above 96px so this costs no visible detail once
    # downscaled.
    r, g, b, a = crop.split()
    crop = Image.merge("RGBA", (r, g, b, a.filter(ImageFilter.MinFilter(5))))
    _keep_largest_component(crop)
    bbox = crop.getbbox()
    assert bbox, out_path
    crop = crop.crop(bbox)
    s = max(crop.size)
    sq = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    sq.paste(crop, ((s - crop.width) // 2, (s - crop.height) // 2))
    sq.resize((size, size), Image.LANCZOS).save(out_path)
    print(f"{os.path.basename(out_path)}: bbox {bbox} -> {size}px")


def main():
    im = Image.open(SHEET).convert("RGBA")
    W, H = im.size
    print(f"sheet {W}x{H}")
    for name, (fx0, fy0, fx1, fy1) in PANELS.items():
        crop = im.crop((int(fx0 * W), int(fy0 * H), int(fx1 * W), int(fy1 * H)))
        extract(crop, os.path.join(OUT, name))


if __name__ == "__main__":
    main()
