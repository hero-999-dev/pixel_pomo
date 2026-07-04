# Extracts the v29 tracker icons from the user's ChatGPT icon sheet (LOCAL tool,
# needs Pillow — not run in CI, like extract_icons.py): crops the picked panels
# (HABIT 02 STAR calendar, MONEY 03 PIGGY BANK), flood-fills the tan panel
# background to transparency from the borders (the icons' own black outlines
# stop the fill), autocrops, squares, and saves 96px PNGs into assets/icon/.
import os

from PIL import Image, ImageDraw

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


def extract(crop, out_path, size=96):
    w, h = crop.size
    crop = crop.crop((int(w * 0.10), int(h * 0.10), int(w * 0.90), int(h * 0.90)))
    pts = [(0, 0), (crop.width - 1, 0), (0, crop.height - 1),
           (crop.width - 1, crop.height - 1), (crop.width // 2, 0),
           (0, crop.height // 2), (crop.width - 1, crop.height // 2),
           (crop.width // 2, crop.height - 1)]
    for xy in pts:
        try:
            ImageDraw.floodfill(crop, xy, (0, 0, 0, 0), thresh=48)
        except ValueError:
            pass
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
