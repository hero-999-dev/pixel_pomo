#!/usr/bin/env python3
"""One-time LOCAL tool (needs Pillow): extract the 5 menu icons from the user's
ChatGPT icon sheet, keying out the navy background to transparency. The committed
PNGs are what the app uses; CI never runs this (stays dependency-free).

Flood-fills the navy bg from the borders (so blue *inside* an icon — e.g. the
market stall's canopy — is kept), drops the label band, then splits into 5 cells
and autocrops each.
"""
import os
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "..", "feedback & guides", "Feedback",
                   "Version 12v Feedback", "ChatGPT Image Jun 19, 2026, 11_28_57 PM.png")
OUT = os.path.join(HERE, "..", "assets", "icon")
NAMES = ["theme", "garden", "stats", "settings", "store"]  # left → right

SENTINEL = (255, 0, 255)
THRESH = 38          # flood-fill colour tolerance (navy gradient vs icon edges)
OUT_SIZE = 96
GAP = 12             # a transparent gap this many rows tall = icon ends, label follows


def main():
    im = Image.open(SRC).convert("RGB")
    w, h = im.size

    # 1) flood-fill the navy background from many border points → magenta sentinel.
    seeds = []
    for x in range(0, w, 16):
        seeds += [(x, 0), (x, h - 1)]
    for y in range(0, h, 16):
        seeds += [(0, y), (w - 1, y)]
    for s in seeds:
        if im.getpixel(s) != SENTINEL:
            ImageDraw.floodfill(im, s, SENTINEL, thresh=THRESH)

    # 2) sentinel → transparent.
    rgba = im.convert("RGBA")
    px = rgba.load()
    for y in range(h):
        for x in range(w):
            r, g, b, _ = px[x, y]
            if (r, g, b) == SENTINEL:
                px[x, y] = (0, 0, 0, 0)

    # 3) split at the real transparent gaps BETWEEN icons (equal 5ths cut through
    #    neighbours), restricting to the icon y-band (labels sit lower).
    px = rgba.load()
    ICON_TOP, ICON_BOT = 290, 590  # exclude the label band below ~595

    def col_full(x):
        return sum(1 for y in range(ICON_TOP, ICON_BOT) if px[x, y][3] > 30)

    segs = []
    x = 0
    while x < w:
        if col_full(x) > 2:
            x0 = x
            while x < w and col_full(x) > 2:
                x += 1
            segs.append((x0, x))
        else:
            x += 1
    segs.sort(key=lambda s: s[1] - s[0], reverse=True)
    icons_x = sorted(segs[:5])  # the 5 widest column-runs, left → right
    assert len(icons_x) == 5, "expected 5 icon segments, got %d" % len(icons_x)

    os.makedirs(OUT, exist_ok=True)
    for (x0, x1), name in zip(icons_x, NAMES):
        col = rgba.crop((x0, 0, x1, h))
        cpx = col.load()
        cwd, chd = col.size

        def row_has(y):
            return sum(1 for xx in range(cwd) if cpx[xx, y][3] > 30) >= 2

        y0 = 0
        while y0 < chd and not row_has(y0):
            y0 += 1
        y1, gap = y0, 0
        y = y0
        while y < chd:
            if row_has(y):
                y1, gap = y, 0
            else:
                gap += 1
                if gap >= GAP and y1 > y0:
                    break
            y += 1

        icon = col.crop((0, y0, cwd, y1 + 1))
        bbox = icon.getbbox()
        if bbox:
            icon = icon.crop(bbox)
        side = max(icon.size)
        sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        sq.paste(icon, ((side - icon.width) // 2, (side - icon.height) // 2))
        sq = sq.resize((OUT_SIZE, OUT_SIZE), Image.LANCZOS)
        sq.save(os.path.join(OUT, f"icon_{name}.png"))
        print("wrote icon_%s.png  (x %d-%d, size %s)" % (name, x0, x1, icon.size))


if __name__ == "__main__":
    main()
