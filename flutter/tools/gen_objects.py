#!/usr/bin/env python3
"""Generate the garden object sprites as PNGs into flutter/assets/objects/.

Dependency-free: emits PNG bytes by hand (zlib + CRC), so it runs anywhere a
plain Python 3 lives — no Pillow required. Each placeable object the engine can
draw gets its own crisp pixel-art PNG so the art lives as data, not as code.

Run from anywhere:  python flutter/tools/gen_objects.py
"""
import os
import struct
import zlib

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "objects")


def write_png(path, pixels):
    """pixels: 2D list of (r,g,b,a) rows, all rows equal length."""
    h = len(pixels)
    w = len(pixels[0])
    raw = bytearray()
    for row in pixels:
        raw.append(0)  # filter type 0 (None) per scanline
        for (r, g, b, a) in row:
            raw += bytes((r, g, b, a))

    def chunk(tag, data):
        out = struct.pack(">I", len(data)) + tag + data
        crc = zlib.crc32(tag + data) & 0xFFFFFFFF
        return out + struct.pack(">I", crc)

    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)  # 8-bit RGBA
    idat = zlib.compress(bytes(raw), 9)
    with open(path, "wb") as f:
        f.write(sig + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b""))


def hexrgb(h):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


def blank(w, h):
    return [[(0, 0, 0, 0) for _ in range(w)] for _ in range(h)]


def upscale(grid, factor):
    """Nearest-neighbour upscale of an RGBA grid by an integer factor."""
    out = []
    for row in grid:
        big = []
        for px in row:
            big += [px] * factor
        for _ in range(factor):
            out.append(list(big))
    return out


# ---- flowers: render the same char-grids the Dart FlowerSprite uses ----------

GREEN = hexrgb("46A03C")

BLOOM = ['..PPP...', '.PPPPP..', '.PPCPP..', '.PPPPP..',
         '..PPP...', '...S....', '..LSL...', '...S....']
TULIP = ['.P.P.P..', '.PPPPP..', '.PPPPP..', '..PPP...',
         '...S....', '..LS....', '...SL...', '...S....']
CACTUS = ['...C....', '..PPP...', 'P.PPP...', 'PPPPP...',
          '..PPP...', '..PPP...', '..PPP...', '..PPP...']

FLOWERS = {
    'gul':       ('E5484D', 'B01030', BLOOM),
    'papatya':   ('FFFFFF', 'F2C94C', BLOOM),
    'lale':      ('E0457B', 'C02060', TULIP),
    'kaktus':    ('46A03C', 'F2C94C', CACTUS),
    'kasimpati': ('F2994A', 'C9710B', BLOOM),
    'menekse':   ('8E4FE0', 'F2C94C', BLOOM),
    'nilufer':   ('F4A6C0', 'F2C94C', BLOOM),
    'orkide':    ('C24FE0', '7A2EA0', BLOOM),
    'begonya':   ('F2585B', 'FFD9A0', BLOOM),
    'kamelya':   ('E02C6D', 'FFFFFF', BLOOM),
}


def flower_grid(petal_hex, center_hex, chars):
    petal = hexrgb(petal_hex) + (255,)
    center = hexrgb(center_hex) + (255,)
    grn = GREEN + (255,)
    grid = blank(8, 8)
    for r, line in enumerate(chars):
        for c, ch in enumerate(line):
            if ch == 'P':
                grid[r][c] = petal
            elif ch == 'C':
                grid[r][c] = center
            elif ch in ('S', 'L'):
                grid[r][c] = grn
    return grid


# ---- grass tile (seamless, subtle speckle) -----------------------------------

def grass_grid():
    base = hexrgb("4E9E3E")
    dark = hexrgb("3F8A33")
    lite = hexrgb("5DB14A")
    g = [[base + (255,) for _ in range(16)] for _ in range(16)]
    # deterministic speckle so tiles stay seamless when repeated
    seed = 1234567
    for r in range(16):
        for c in range(16):
            seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
            v = seed % 11
            if v == 0:
                g[r][c] = dark + (255,)
            elif v == 1:
                g[r][c] = lite + (255,)
    return g


# ---- bug (a tiny flying critter, mostly transparent) -------------------------

def bug_grid():
    body = hexrgb("2B2B2B") + (255,)
    wing = (220, 220, 255, 200)
    g = blank(6, 6)
    # wings
    g[2][0] = wing
    g[2][5] = wing
    g[1][1] = wing
    g[1][4] = wing
    # body 2x3
    for r in (2, 3, 4):
        g[r][2] = body
        g[r][3] = body
    return g


# ---- road tile (a worn stone path) -------------------------------------------

def road_grid():
    base = hexrgb("B7A687")
    edge = hexrgb("8C7C5E")
    crack = hexrgb("9C8B6B")
    g = [[base + (255,) for _ in range(16)] for _ in range(16)]
    for i in range(16):
        g[0][i] = edge + (255,)
        g[15][i] = edge + (255,)
        g[i][0] = edge + (255,)
        g[i][15] = edge + (255,)
    seed = 999
    for r in range(2, 14):
        for c in range(2, 14):
            seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
            if seed % 9 == 0:
                g[r][c] = crack + (255,)
    return g


# ---- fence tile (wooden rail + posts) ----------------------------------------

def fence_grid():
    post = hexrgb("8B5A2B")
    rail = hexrgb("A9743E")
    g = blank(16, 16)
    # two posts
    for col in (3, 12):
        for r in range(4, 15):
            g[r][col] = post + (255,)
            g[r][col + 1] = post + (255,)
    # top + middle rails
    for rr in (5, 6, 9, 10):
        for c in range(2, 15):
            g[rr][c] = rail + (255,)
    return g


def main():
    os.makedirs(OUT, exist_ok=True)
    SCALE = 16  # 16x16 source grids -> 256px; 8x8 flowers -> 128px; bug 6 -> 96
    for fid, (petal, center, chars) in FLOWERS.items():
        write_png(os.path.join(OUT, f"flower_{fid}.png"), upscale(flower_grid(petal, center, chars), SCALE))
    write_png(os.path.join(OUT, "grass.png"), upscale(grass_grid(), SCALE))
    write_png(os.path.join(OUT, "road.png"), upscale(road_grid(), SCALE))
    write_png(os.path.join(OUT, "fence.png"), upscale(fence_grid(), SCALE))
    write_png(os.path.join(OUT, "bug.png"), upscale(bug_grid(), SCALE))
    print("wrote", len(FLOWERS) + 4, "sprites to", os.path.abspath(OUT))


if __name__ == "__main__":
    main()
