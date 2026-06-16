#!/usr/bin/env python3
"""Generate the app launcher icon (the pixel tomato) as PNGs.

Mirrors the native Android adaptive icon (ic_launcher_foreground.xml). Produces:
  assets/icon/app_icon.png     - tomato on the dark app background (iOS / legacy)
  assets/icon/app_icon_fg.png  - tomato on transparent (Android adaptive foreground)

Dependency-free PNG writer (see gen_objects.py). Run: python flutter/tools/gen_icon.py
"""
import os
import struct
import zlib

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "icon")
SCALE = 10           # 108 viewport -> 1080px
VP = 108


def write_png(path, pixels):
    h, w = len(pixels), len(pixels[0])
    raw = bytearray()
    for row in pixels:
        raw.append(0)
        for (r, g, b, a) in row:
            raw += bytes((r, g, b, a))

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n"
                + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
                + chunk(b"IEND", b""))


def hexrgba(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


# Rectangles in 108-viewport coords: (x0, y0, x1, y1, color). Drawn in order.
TOMATO = [
    # body (main block + side bumps) — red
    (36, 52, 72, 82, "E43B44"),
    (30, 58, 36, 76, "E43B44"),
    (72, 58, 78, 76, "E43B44"),
    # bottom shading — dark red
    (36, 76, 72, 82, "9B1B22"),
    # top-left highlight
    (40, 58, 48, 64, "FF6B73"),
    # stem + leaves — green
    (50, 42, 58, 50, "3BE48B"),
    (42, 46, 50, 50, "3BE48B"),
    (58, 46, 66, 50, "3BE48B"),
]


def render(bg_hex, fill=0.78):
    """Render the tomato fitted to `fill` of the canvas, centered."""
    px = VP * SCALE
    bg = hexrgba(bg_hex) if bg_hex else (0, 0, 0, 0)
    img = [[bg for _ in range(px)] for _ in range(px)]

    minx = min(r[0] for r in TOMATO); maxx = max(r[2] for r in TOMATO)
    miny = min(r[1] for r in TOMATO); maxy = max(r[3] for r in TOMATO)
    cx, cy = (minx + maxx) / 2, (miny + maxy) / 2
    scale = fill * VP / max(maxx - minx, maxy - miny)

    def tx(x): return int(round(((x - cx) * scale + VP / 2) * SCALE))
    def ty(y): return int(round(((y - cy) * scale + VP / 2) * SCALE))

    for (x0, y0, x1, y1, c) in TOMATO:
        col = hexrgba(c)
        for y in range(ty(y0), ty(y1)):
            row = img[y]
            for x in range(tx(x0), tx(x1)):
                row[x] = col
    return img


def main():
    os.makedirs(OUT, exist_ok=True)
    write_png(os.path.join(OUT, "app_icon.png"), render("161616"))
    write_png(os.path.join(OUT, "app_icon_fg.png"), render(None))
    print("wrote launcher icons to", os.path.abspath(OUT))


if __name__ == "__main__":
    main()
