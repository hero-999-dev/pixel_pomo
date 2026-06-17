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


def outline(grid, hexcol):
    """Add a 1px border in `hexcol` around every opaque pixel (transparent only)."""
    h, w = len(grid), len(grid[0])
    ol = hexrgb(hexcol) + (255,)
    add = []
    for r in range(h):
        for c in range(w):
            if grid[r][c][3] != 0:
                continue
            for dr, dc in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nr, nc = r + dr, c + dc
                if 0 <= nr < h and 0 <= nc < w and grid[nr][nc][3] != 0:
                    add.append((r, c))
                    break
    for (r, c) in add:
        grid[r][c] = ol
    return grid


def flower_png_grid(petal_hex, center_hex, chars):
    """Garden PNG version: the 8x8 flower on a 10x10 canvas with a dark outline,
    so green stems/cacti separate cleanly from the green grass (#5)."""
    g8 = flower_grid(petal_hex, center_hex, chars)
    g = blank(10, 10)
    for r in range(8):
        for c in range(8):
            g[r + 1][c + 1] = g8[r][c]
    return outline(g, "16280F")


# ---- grass tile (seamless, subtle speckle) -----------------------------------

def grass_grid():
    # Brighter, more textured field (closer to the feedback inspiration) so plant
    # greens read against it — paired with the dark plant outline in flower_png_grid.
    base = hexrgb("5BA838")
    d1 = hexrgb("4F9A30")
    d2 = hexrgb("3E7F2A")    # darker blade tufts
    l1 = hexrgb("6FC04A")
    olive = hexrgb("BBD37A")
    g = [[base + (255,) for _ in range(16)] for _ in range(16)]
    seed = 1234567
    for r in range(16):
        for c in range(16):
            seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
            v = seed % 14
            if v == 0:
                g[r][c] = d1 + (255,)
            elif v == 1:
                g[r][c] = l1 + (255,)
            elif v == 2:
                g[r][c] = olive + (255,)
    # a couple of little grass tufts
    for (br, bc) in ((3, 4), (10, 11)):
        for (dr, dc) in ((0, 0), (1, -1), (1, 1), (2, 0)):
            rr, cc = br + dr, bc + dc
            if 0 <= rr < 16 and 0 <= cc < 16:
                g[rr][cc] = d2 + (255,)
    return g


# ---- spinning coin (pixel-art, animated in the wallet) -----------------------

def coin_grid():
    out = hexrgb("6E4A00") + (255,)
    rim = hexrgb("C98A1B") + (255,)
    face = hexrgb("F2C94C") + (255,)
    hi = hexrgb("FFE9A8") + (255,)
    g = blank(16, 16)
    cx = cy = 7.5
    for r in range(16):
        for c in range(16):
            d = ((r - cy) ** 2 + (c - cx) ** 2) ** 0.5
            if d <= 7.7:
                g[r][c] = out if d > 6.5 else (rim if d > 5.2 else face)
    # inner bevel + a top-left shine, so it reads as a struck gold coin
    for (r, c) in ((5, 5), (5, 6), (6, 5), (4, 7), (7, 4)):
        g[r][c] = hi
    for (r, c) in ((6, 8), (8, 6), (9, 9), (8, 9), (9, 8)):
        g[r][c] = rim
    return g


# ---- tiny garden creatures (bee / butterfly / ladybug) -----------------------
# Small (8x8), recognisable, no oversized wings. They visit flowers, not the
# whole screen. Drawn from a char-grid + a per-creature palette.

def _crit(chars, palette):
    g = blank(8, 8)
    for r, line in enumerate(chars):
        for c, ch in enumerate(line):
            if ch in palette:
                g[r][c] = palette[ch]
    return g


def bee_grid():
    y = hexrgb("F2C94C") + (255,)   # yellow body
    k = hexrgb("2B2B2B") + (255,)   # black stripes
    w = (255, 255, 255, 210)        # tiny wings
    return _crit([
        '........',
        '..wkw...',
        '.wykyw..',
        '..kyk...',
        '..yky...',
        '..kyk...',
        '...k....',
        '........',
    ], {'y': y, 'k': k, 'w': w})


def butterfly_grid():
    a = hexrgb("E0457B") + (255,)   # wing colour
    b = hexrgb("F2994A") + (255,)   # wing accent
    k = hexrgb("2B2B2B") + (255,)   # body
    return _crit([
        '........',
        '.a.k.a..',
        'aba.aba.',
        'aba.aba.',
        '.a.k.a..',
        '...k....',
        '........',
        '........',
    ], {'a': a, 'b': b, 'k': k})


def ladybug_grid():
    r = hexrgb("E5484D") + (255,)   # red shell
    k = hexrgb("2B2B2B") + (255,)   # head + spots
    return _crit([
        '........',
        '..kkk...',
        '.rkrkr..',
        '.rrkrr..',
        '.rkrkr..',
        '..rrr...',
        '........',
        '........',
    ], {'r': r, 'k': k})


CRITTERS = {'bee': bee_grid, 'butterfly': butterfly_grid, 'ladybug': ladybug_grid}


# ---- road tiles (5 flat surfaces, drawn one full texture per tile) -----------

def _speckle(g, w, h, seed, choices, density):
    """Sprinkle `choices` colours over grid g at ~1/density of cells."""
    for r in range(h):
        for c in range(w):
            seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
            if seed % density == 0:
                g[r][c] = choices[(seed >> 8) % len(choices)]
    return seed


def road_concrete_grid():
    base = hexrgb("ADADAD") + (255,)
    joint = hexrgb("6E6E6E") + (255,)
    g = [[base for _ in range(16)] for _ in range(16)]
    _speckle(g, 16, 16, 555, [hexrgb("B8B8B8") + (255,), hexrgb("9C9C9C") + (255,)], 6)
    # straight expansion joints → reads as poured concrete slabs when tiled
    for i in range(16):
        g[0][i] = joint
        g[i][0] = joint
    return g


def road_wood_grid():
    plank = hexrgb("9C6B3F") + (255,)
    seam = hexrgb("6E4A28") + (255,)
    g = [[plank for _ in range(16)] for _ in range(16)]
    _speckle(g, 16, 16, 222, [hexrgb("8A5E37") + (255,), hexrgb("A9743E") + (255,)], 6)
    for r in (0, 5, 10, 15):           # horizontal plank seams
        for c in range(16):
            g[r][c] = seam
    for c in (3, 11):                   # a couple of nail/board breaks
        g[2][c] = seam
        g[12][c] = seam
    return g


def road_dirt_grid():
    base = hexrgb("7A5230") + (255,)
    g = [[base for _ in range(16)] for _ in range(16)]
    _speckle(g, 16, 16, 888,
             [hexrgb("6A4526") + (255,), hexrgb("8A613B") + (255,), hexrgb("5C3C20") + (255,)], 4)
    return g


def road_stone_grid():
    base = hexrgb("8A8A8A") + (255,)
    mortar = hexrgb("5E5E5E") + (255,)
    g = [[base for _ in range(16)] for _ in range(16)]
    # irregular cobbles separated by darker mortar
    for r in range(16):
        for c in range(16):
            if (r % 5 == 0) or ((c + (r // 5) * 3) % 6 == 0):
                g[r][c] = mortar
    _speckle(g, 16, 16, 333, [hexrgb("9A9A9A") + (255,), hexrgb("787878") + (255,)], 5)
    return g


ROADS = {
    'road_concrete': road_concrete_grid,
    'road_wood': road_wood_grid,
    'road_dirt': road_dirt_grid,
    'road_stone': road_stone_grid,
}


# ---- fence tiles (4 materials, front-on billboards: posts + two rails) --------

def _fence_grid(post_hex, rail_hex):
    post = hexrgb(post_hex) + (255,)
    rail = hexrgb(rail_hex) + (255,)
    g = blank(16, 16)
    for col in (3, 12):                # two posts
        for r in range(3, 15):
            g[r][col] = post
            g[r][col + 1] = post
    for rr in (5, 6, 9, 10):           # top + middle rails
        for c in range(1, 15):
            g[rr][c] = rail
    return g


FENCES = {
    'fence_wood': lambda: _fence_grid("8B5A2B", "A9743E"),
    'fence_dark': lambda: _fence_grid("3D2814", "5A3A1E"),
    'fence_stone': lambda: _fence_grid("6E6E6E", "9A9A9A"),
}


def main():
    os.makedirs(OUT, exist_ok=True)
    SCALE = 16  # 16x16 grids -> 256px; 8x8 flowers/critters -> 128px
    for fid, (petal, center, chars) in FLOWERS.items():
        write_png(os.path.join(OUT, f"flower_{fid}.png"), upscale(flower_png_grid(petal, center, chars), SCALE))
    write_png(os.path.join(OUT, "grass.png"), upscale(grass_grid(), SCALE))
    write_png(os.path.join(OUT, "coin.png"), upscale(coin_grid(), SCALE))
    for cid, fn in CRITTERS.items():
        write_png(os.path.join(OUT, f"{cid}.png"), upscale(fn(), SCALE))
    for rid, fn in ROADS.items():
        write_png(os.path.join(OUT, f"{rid}.png"), upscale(fn(), SCALE))
    for fid, fn in FENCES.items():
        write_png(os.path.join(OUT, f"{fid}.png"), upscale(fn(), SCALE))
    # drop sprites that were renamed/removed over time, if present
    for old in ("road.png", "fence.png", "bug.png",
                "road_asphalt.png", "road_brick.png", "fence_white.png"):
        p = os.path.join(OUT, old)
        if os.path.exists(p):
            os.remove(p)
    n = len(FLOWERS) + 2 + len(CRITTERS) + len(ROADS) + len(FENCES)  # +grass +coin
    print("wrote", n, "sprites to", os.path.abspath(OUT))


if __name__ == "__main__":
    main()
