#!/usr/bin/env python3
"""Generate the garden object sprites as PNGs into flutter/assets/objects/.

Dependency-free: emits PNG bytes by hand (zlib + CRC), so it runs anywhere a
plain Python 3 lives — no Pillow required. Each placeable object the engine can
draw gets its own crisp pixel-art PNG so the art lives as data, not as code.

Run from anywhere:  python flutter/tools/gen_objects.py
"""
import math
import os
import struct
import zlib

# Number of frames in every directional atlas (must match dir8 in the Dart
# engine). Frame k is the billboard spun by k*360/FRAMES degrees about the
# vertical axis, so the renderer can pick the facet that matches the camera.
FRAMES = 8

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


# ---- 8-direction billboard atlases (#4) -------------------------------------
# Fake a 3D facing for flat pixel objects: spin each base sprite about its
# vertical axis into FRAMES frames laid out in one horizontal strip (an atlas).
# The engine slices out the frame whose angle matches the camera, so rotating
# the garden makes flowers / fences / critters visibly turn instead of staying
# dead-on. No per-frame hand art — it's the coin-spin trick generalised.

def _bright(px, f):
    r, g, b, a = px
    if a == 0:
        return px
    return (min(255, int(r * f)), min(255, int(g * f)), min(255, int(b * f)), a)


def spin_frame(grid, theta_deg):
    """One billboard frame rotated `theta_deg` about the vertical axis:
    horizontally squash by |cos| (kept >= 0.45 so sides don't vanish), shade
    front bright / back dark, and highlight the leading vertical edge so a
    left turn differs from a right turn (breaks the cos symmetry)."""
    h, w = len(grid), len(grid[0])
    th = math.radians(theta_deg)
    sx = 0.45 + 0.55 * abs(math.cos(th))
    bright = max(0.45, 0.62 + 0.38 * math.cos(th))
    neww = max(2, round(w * sx))
    x0 = (w - neww) // 2
    out = blank(w, h)
    for r in range(h):
        for i in range(neww):
            src_c = min(w - 1, int(i / neww * w))
            px = grid[r][src_c]
            if px[3] == 0:
                continue
            out[r][x0 + i] = _bright(px, bright)
    s = math.sin(th)
    if abs(s) > 0.15 and neww >= 3:
        lead = x0 + neww - 1 if s > 0 else x0
        trail = x0 if s > 0 else x0 + neww - 1
        for r in range(h):
            if out[r][lead][3] != 0:
                out[r][lead] = _bright(out[r][lead], 1.25)
            if out[r][trail][3] != 0:
                out[r][trail] = _bright(out[r][trail], 0.7)
    return out


def make_atlas(grid, frames=FRAMES):
    """Concatenate `frames` spun frames into one horizontal strip."""
    cells = [spin_frame(grid, k * 360.0 / frames) for k in range(frames)]
    out = []
    for r in range(len(grid)):
        row = []
        for cell in cells:
            row += cell[r]
        out.append(row)
    return out


# ---- forest / rock surround (#3) --------------------------------------------
# A dark, dense forest-floor tile that fills the whole screen behind the plot,
# so the garden reads as a clearing and critters seem to drift in from the
# woods. Seamless-ish (wraps with %16) since it's only a backdrop.

def forest_grid():
    dark = hexrgb("12301A") + (255,)
    canopy = hexrgb("1E4D27") + (255,)
    canopy2 = hexrgb("2A6B33") + (255,)
    trunk = hexrgb("3A2A18") + (255,)
    rock = hexrgb("595E54") + (255,)
    rockd = hexrgb("3C403A") + (255,)
    g = [[dark for _ in range(16)] for _ in range(16)]
    seed = 99001

    def rnd(m):
        nonlocal seed
        seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
        return seed % m

    for r in range(16):
        for c in range(16):
            v = rnd(5)
            if v == 0:
                g[r][c] = canopy
            elif v == 1:
                g[r][c] = canopy2
    # round tree canopies with a trunk peeking out below
    for (br, bc) in ((4, 4), (11, 11), (2, 12)):
        for dr in range(-2, 3):
            for dc in range(-2, 3):
                if dr * dr + dc * dc <= 4:
                    g[(br + dr) % 16][(bc + dc) % 16] = canopy2 if (dr + dc) % 2 else canopy
        g[(br + 2) % 16][bc % 16] = trunk
    # a couple of mossy rocks
    for (br, bc) in ((9, 2), (14, 8)):
        for (dr, dc) in ((0, 0), (0, 1), (1, 0), (1, 1), (0, -1)):
            g[(br + dr) % 16][(bc + dc) % 16] = rock if (dr + dc) % 2 == 0 else rockd
    return g


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


# ---- plain gold coin (static, 2D — #5) ---------------------------------------
# A clean struck-gold disc: dark rim, gold face, one small top-left shine.
# No "$", no smiley, no inner bevel marks that could read as a face. Static —
# the wallet shows it as a flat 2D coin with no animation.

def coin_grid():
    out = hexrgb("7A5200") + (255,)   # dark outline ring
    rim = hexrgb("C98A1B") + (255,)   # inner rim
    face = hexrgb("F2C94C") + (255,)  # gold face
    hi = hexrgb("FFE9A8") + (255,)    # single shine
    g = blank(16, 16)
    cx = cy = 7.5
    for r in range(16):
        for c in range(16):
            d = ((r - cy) ** 2 + (c - cx) ** 2) ** 0.5
            if d <= 7.7:
                if d > 6.6:
                    g[r][c] = out
                elif d > 5.3:
                    g[r][c] = rim
                else:
                    g[r][c] = face
    # one soft top-left shine arc — nothing in the centre (no face)
    for (r, c) in ((3, 6), (4, 5), (4, 6), (5, 4), (5, 5)):
        g[r][c] = hi
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


# ---- fence posts (3 materials, standing single posts — #1) -------------------
# A fence is now a STANDING post per tile (like a flower, not a flat ground
# network). The engine draws rails between any adjacent fence posts — of ANY
# material — so different fences join up. Each post is a single centred billboard
# spun into an 8-direction atlas, with two short rail nubs so a lone post still
# reads as "fence".

def _fence_post_grid(post_hex, rail_hex):
    post = hexrgb(post_hex) + (255,)
    cap = _bright(post, 1.2)
    rail = hexrgb(rail_hex) + (255,)
    g = blank(16, 16)
    for r in range(2, 16):             # the post
        g[r][7] = post
        g[r][8] = post
    g[1][7] = cap                      # little cap
    g[1][8] = cap
    for rr in (6, 10):                 # short rail nubs either side
        for c in (4, 5, 6, 9, 10, 11):
            g[rr][c] = rail
    return g


FENCES = {
    'fence_wood': lambda: _fence_post_grid("8B5A2B", "A9743E"),
    'fence_dark': lambda: _fence_post_grid("3D2814", "5A3A1E"),
    'fence_stone': lambda: _fence_post_grid("6E6E6E", "9A9A9A"),
}


def main():
    os.makedirs(OUT, exist_ok=True)
    SCALE = 16  # base grids are 8/10/16 px tall; ×16 keeps them crisp

    # Flowers, fences and critters ship as 8-frame directional atlases (#4).
    for fid, (petal, center, chars) in FLOWERS.items():
        atlas = make_atlas(flower_png_grid(petal, center, chars))
        write_png(os.path.join(OUT, f"flower_{fid}.png"), upscale(atlas, SCALE))
    for cid, fn in CRITTERS.items():
        write_png(os.path.join(OUT, f"{cid}.png"), upscale(make_atlas(fn()), SCALE))
    for fid, fn in FENCES.items():
        write_png(os.path.join(OUT, f"{fid}.png"), upscale(make_atlas(fn()), SCALE))

    # Flat / single-frame sprites: ground, surround, roads, wallet coin.
    write_png(os.path.join(OUT, "grass.png"), upscale(grass_grid(), SCALE))
    write_png(os.path.join(OUT, "forest.png"), upscale(forest_grid(), SCALE))
    write_png(os.path.join(OUT, "coin.png"), upscale(coin_grid(), SCALE))
    for rid, fn in ROADS.items():
        write_png(os.path.join(OUT, f"{rid}.png"), upscale(fn(), SCALE))

    # drop sprites that were renamed/removed over time, if present
    for old in ("road.png", "fence.png", "bug.png",
                "road_asphalt.png", "road_brick.png", "fence_white.png"):
        p = os.path.join(OUT, old)
        if os.path.exists(p):
            os.remove(p)
    n = len(FLOWERS) + len(CRITTERS) + len(FENCES) + len(ROADS) + 3  # +grass +forest +coin
    print("wrote", n, "sprites to", os.path.abspath(OUT), f"(FRAMES={FRAMES})")


if __name__ == "__main__":
    main()
