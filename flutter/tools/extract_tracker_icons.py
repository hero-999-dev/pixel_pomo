# Extracts the v29 tracker icons from the user's ChatGPT icon sheet (LOCAL tool,
# needs Pillow — not run in CI, like extract_icons.py): crops the picked panels
# (HABIT 02 STAR calendar, MONEY 03 PIGGY BANK), flood-fills the tan panel
# background to transparency from the borders (the icons' own black outlines
# stop the fill), autocrops, squares, and saves 96px PNGs into assets/icon/.
import os

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


def _dist(a, b):
    return sum((x - y) ** 2 for x, y in zip(a[:3], b[:3])) ** 0.5


def extract(crop, out_path, size=96):
    w, h = crop.size
    crop = crop.crop((int(w * 0.10), int(h * 0.10), int(w * 0.90), int(h * 0.90)))
    cw, ch = crop.size
    corners = [(0, 0), (cw - 1, 0), (0, ch - 1), (cw - 1, ch - 1)]
    mids = [(cw // 2, 0), (0, ch // 2), (cw - 1, ch // 2), (cw // 2, ch - 1)]
    # background reference from the 4 CORNERS only — the icon's silhouette can
    # reach close enough to an edge midpoint to sample the SUBJECT there
    # instead (found happening on the piggy-bank: the left-mid point landed on
    # the pig's own dark outline). Any candidate seed — corner or midpoint —
    # only gets used if it actually matches that reference, so a bad seed
    # can't flood-fill from the wrong colour.
    bg = tuple(sum(crop.getpixel(p)[i] for p in corners) // 4 for i in range(3))
    seeds = [p for p in corners + mids if _dist(crop.getpixel(p), bg) < 40]
    # four passes, widening each time: 48 clears the flat panel background,
    # 90/140 eat progressively more of the anti-aliased blend ring, and 200
    # reaches all the way through the pig's soft drop-shadow gradient — a
    # dark, fairly saturated brown well past the earlier ceilings but still
    # far short of the icon's own near-black outline, which stays a wall no
    # matter how high this goes (that's what keeps the flood-fill from ever
    # crossing into the subject itself). (#v30, tightened a third time.)
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
