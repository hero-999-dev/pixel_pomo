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
    """One billboard frame rotated `theta_deg` about the vertical axis: just a
    horizontal squash by |cos| (kept >= 0.45 so the sides never vanish). The
    light is uniform from every angle — NO front-bright/back-dark shading and no
    leading-edge highlight — so rotating an object never looks like a moving sun
    sweeping across it (lighting is flat sky-ambient, the same from all sides)."""
    h, w = len(grid), len(grid[0])
    th = math.radians(theta_deg)
    sx = 0.45 + 0.55 * abs(math.cos(th))
    neww = max(2, round(w * sx))
    x0 = (w - neww) // 2
    out = blank(w, h)
    for r in range(h):
        for i in range(neww):
            src_c = min(w - 1, int(i / neww * w))
            px = grid[r][src_c]
            if px[3] == 0:
                continue
            out[r][x0 + i] = px
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


# ---- forest tree billboard (#1) ---------------------------------------------
# A single standing tree on a transparent background. The garden engine tiles
# the WHOLE screen as one 2.5D world and stamps this billboard on every
# *unclaimed* tile, so the plot reads as a clearing inside the woods that
# recedes (tree -> grass) as the garden EXPANDs. Flat, no directional shading
# (matches the v10 no-sun lighting).

def tree_grid():
    g = blank(16, 16)
    canopy = hexrgb("1E4D27") + (255,)
    canopy2 = hexrgb("2A6B33") + (255,)
    trunk = hexrgb("3A2A18") + (255,)
    cx, cy, rad = 7.5, 6.0, 5.0
    for r in range(16):
        for c in range(16):
            if (c - cx) ** 2 + ((r - cy) * 1.15) ** 2 <= rad * rad:
                g[r][c] = canopy2 if (r + c) % 2 else canopy
    # trunk peeking out below the canopy
    for r in range(11, 16):
        g[r][7] = trunk
        g[r][8] = trunk
    return g


# ---- forest variety (#5): many trees + bushes + rocks, scattered -------------

# How many garden tiles wide/tall each tree is drawn at (#v34.8). The forest
# used to sit at 1.2 tiles — barely taller than a flower, which is what "the
# trees stay tiny next to the flowers" meant. Trees now come in three sizes and
# the mix is deliberate: mostly 2s and 3s with a few 4s standing over them, so
# the tree line has a skyline instead of being one uniform hedge.
#
# The Dart and Kotlin renderers read the SAME table (forestTreeTiles), so a
# change here has to be mirrored in both — see garden_engine.dart.
TREE_TILES = [2, 3, 2, 4, 3, 2, 3, 3, 2, 4, 2, 3, 4, 2, 3, 2, 3, 4, 2, 3]

# Pixels per tile in a tree sprite. A 4-tile tree drawn from a 16px grid would
# upscale 4x more than a flower does and read as a blurry blob; sizing the grid
# with the tree keeps the pixel density even across the whole scene.
TREE_PX_PER_TILE = 16


def _tree_variant(seed):
    """One forest tree, sized by its class in [TREE_TILES] (#v34.8).

    Four silhouettes rather than one blob: a round broadleaf, a conical pine, a
    narrow poplar and a wide oak. Each gets a lit side, a shaded side, a darker
    underside and a tapered trunk with a branch, so a tree reads as a tree at
    three or four tiles tall instead of as a green circle.
    """
    rnd = (seed * 1103515245 + 12345) & 0x7fffffff
    def rb(n):
        nonlocal rnd
        rnd = (rnd * 1103515245 + 12345) & 0x7fffffff
        return rnd % n

    tiles = TREE_TILES[(seed - 1) % len(TREE_TILES)]
    n = tiles * TREE_PX_PER_TILE          # square canvas, 32 / 48 / 64
    g = blank(n, n)

    # one hue family per tree, in four tones: lit, mid, shade, underside
    families = [
        ("4E9B4A", "327A3B", "23602C", "17401F"),   # fresh green
        ("6BA83F", "4A8A32", "356A25", "204415"),   # yellow-green
        ("3F8F5C", "2C7048", "1E5537", "133724"),   # blue-green
        ("8A9B3A", "6B7F2B", "4E5F1E", "343F14"),   # olive
    ]
    lit, mid, shade, under = (hexrgb(h) + (255,) for h in families[rb(len(families))])
    bark = hexrgb(["4A3421", "3A2A18", "56402A"][rb(3)]) + (255,)
    bark_d = hexrgb("241a10") + (255,)

    shape = rb(4)                          # 0 round, 1 pine, 2 poplar, 3 oak
    trunk_w = max(2, n // 10)
    cx = n / 2.0
    ground = n - 1

    def put(c, r, col):
        if 0 <= c < n and 0 <= r < n:
            g[int(r)][int(c)] = col

    def blob(bcx, bcy, rad, squash=1.0, highlight=True):
        """A shaded ellipse of canopy: a small highlight up-left, shade on the
        lower-right edge, a dark underside. The highlight is deliberately a
        SMALL cap — lighting half the crown made every tree read as two flat
        colours split down the middle."""
        for r in range(int(bcy - rad - 1), int(bcy + rad / squash + 2)):
            for c in range(int(bcx - rad - 1), int(bcx + rad + 2)):
                dx, dy = c - bcx, (r - bcy) * squash
                d2 = dx * dx + dy * dy
                if d2 > rad * rad:
                    continue
                edge = d2 > (rad - max(1.0, rad * 0.30)) ** 2
                hx, hy = dx + rad * 0.42, dy + rad * 0.42   # highlight centre, up-left
                if dy > rad * 0.55:
                    col = under
                elif edge and (dx > rad * 0.1 or dy > 0):
                    col = shade
                elif highlight and hx * hx + hy * hy < (rad * 0.30) ** 2:
                    col = lit
                else:
                    col = mid
                put(c, r, col)

    if shape == 1:
        # PINE — stacked tiers, widest at the bottom, a spike on top. The tiers
        # OVERLAP: spaced by less than their own height, or the top one floats
        # off on its own with a gap of sky under it.
        tiers = 3 + (tiles - 2)
        top, bottom = n * 0.13, n * 0.68
        for i in range(tiers):
            f = i / (tiers - 1)
            rad = n * (0.15 + 0.19 * f)
            # squash 1.12, not 1.35: flatter tiers left a gap of sky between
            # the top one and the rest, so the spike floated off the tree
            blob(cx, top + (bottom - top) * f, rad, squash=1.12, highlight=i > 0)
        trunk_top = bottom + n * 0.10
    elif shape == 2:
        # POPLAR — tall and narrow. The crown stops well short of the ground so
        # the trunk actually shows; a full-height crown just looked like a bush.
        blob(cx, n * 0.38, n * 0.25, squash=0.60)
        trunk_top = n * 0.70
    elif shape == 3:
        # OAK — a wide crown from three overlapping lobes. Only the middle lobe
        # carries the highlight, so the shoulders don't read as separate trees.
        blob(cx, n * 0.36, n * 0.25)
        blob(cx - n * 0.18, n * 0.46, n * 0.18, highlight=False)
        blob(cx + n * 0.18, n * 0.46, n * 0.18, highlight=False)
        trunk_top = n * 0.68
    else:
        # ROUND broadleaf — one crown plus a small shoulder lobe (no highlight
        # of its own, or it reads as a hole punched in the canopy)
        blob(cx, n * 0.38, n * 0.27)
        blob(cx + n * 0.15 * (1 if rb(2) else -1), n * 0.50, n * 0.15, highlight=False)
        trunk_top = n * 0.72

    # Trunk: start it INSIDE the canopy, not at a guessed fraction of the
    # height. Half the trees came out with the trunk floating below a crown
    # that stopped short — the canopy's real extent depends on shape, radius
    # and squash, so measure it instead of predicting it. Connectivity is
    # checked by a test; a tree in two pieces is the bug this prevents.
    lo, hi = int(cx - trunk_w), int(cx + trunk_w) + 1
    canopy_bottom = 0
    for r in range(n):
        for c in range(max(0, lo), min(n, hi)):
            if g[r][c][3]:
                canopy_bottom = max(canopy_bottom, r)
    trunk_top = min(trunk_top, canopy_bottom - 1)   # overlap the crown by 1px

    for r in range(int(trunk_top), n):
        f = (r - trunk_top) / max(1.0, ground - trunk_top)
        half = trunk_w / 2.0 + f * trunk_w * 0.35
        for c in range(int(cx - half), int(cx + half) + 1):
            put(c, r, bark_d if c - cx > half * 0.25 else bark)

    return g


def _bush_variant(seed):
    rnd = (seed * 2654435761 + 40503) & 0x7fffffff
    def rb(n):
        nonlocal rnd
        rnd = (rnd * 1103515245 + 12345) & 0x7fffffff
        return rnd % n
    g = blank(16, 16)
    greens = ["2A6B33", "327A3B", "246B2E", "3C8A45"]
    a = hexrgb(greens[rb(len(greens))]) + (255,)
    b = hexrgb(greens[rb(len(greens))]) + (255,)
    rad = 3.0 + rb(2)
    cx, cy = 7.5, 10.0
    for r in range(16):
        for c in range(16):
            if (c - cx) ** 2 + ((r - cy) * 1.3) ** 2 <= rad * rad:
                g[r][c] = b if (r + c) % 2 else a
    return g


def _rock_variant(seed):
    rnd = (seed * 40503 + 12345) & 0x7fffffff
    def rb(n):
        nonlocal rnd
        rnd = (rnd * 1103515245 + 12345) & 0x7fffffff
        return rnd % n
    g = blank(16, 16)
    grays = ["6E6E6E", "7C7C7C", "5E5E5E", "888888"]
    a = hexrgb(grays[rb(len(grays))]) + (255,)
    b = hexrgb("4A4A4A") + (255,)
    rad = 2.5 + rb(2)
    cx, cy = 7.5, 11.0
    for r in range(16):
        for c in range(16):
            if (c - cx) ** 2 + ((r - cy) * 1.4) ** 2 <= rad * rad:
                g[r][c] = b if r > cy else a   # darker bottom
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
    'kaktusf':   ('F06A92', 'F2C94C', CACTUS),   # flower cactus (#v26)
    'kaktusd':   ('46A03C', '5FBF4A', CACTUS),   # desert cactus, no bloom (#v26)
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


# NB: the menu icons (assets/icon/icon_*.png) are no longer generated here — they
# come from tools/extract_icons.py (the user's ChatGPT art, navy keyed out) (#v18).


def flower_png_grid(petal_hex, center_hex, chars):
    """Garden PNG version: the 8x8 flower on a 10x10 canvas with a dark outline,
    so green stems/cacti separate cleanly from the green grass (#5)."""
    g8 = flower_grid(petal_hex, center_hex, chars)
    g = blank(10, 10)
    for r in range(8):
        for c in range(8):
            g[r + 1][c + 1] = g8[r][c]
    return outline(g, "16280F")


# ---- rose variants (#v23) ----------------------------------------------------
# Two rose models in ONE cozy APICO/Littlewood style, derived from the user's
# 4-rose reference and rebuilt as clean pixel art: a strong dark rim, a 3-tone red
# ramp (dark crease / mid body / light highlight) placed to follow the reference's
# petal shading, plus a green stem + two leaves so they read as one species. The
# bloom differs (full bloom / bud) AND the leaves differ (left-first vs right-first
# — #v22) so a row of
# roses looks varied, not cloned. Modular: the bloom (reds) and the plant (greens)
# are outlined SEPARATELY (dark-red rim vs dark-green rim, like the reference) then
# composited; the same pipeline carries over when the other flowers get this look.
# A random variant is planted each time (Flowers.variantsFor("gul") == 3).

_ROSE_PAL = {
    "d": hexrgb("8E1B2E") + (255,),  # rose dark (creases / petal shadow)
    "m": hexrgb("CC2A3D") + (255,),  # rose mid (main petal body)
    "l": hexrgb("F26571") + (255,),  # rose light (highlight)
    "S": hexrgb("3E8E36") + (255,),  # stem mid
    "G": hexrgb("5FBF4A") + (255,),  # leaf
    "k": hexrgb("2C6E2A") + (255,),  # leaf vein / stem shade
}
_ROSE_RED_OL = "3A0A14"  # dark-red rim around the bloom
_ROSE_GRN_OL = "1E5A24"  # dark-green rim around the stem + leaves
_ROSE_REDS = set("dml")

# Stem + two leaves below the bloom — a DIFFERENT arrangement per variant so the three
# roses read apart (user feedback #v22): variant 0 = left leaf higher / right lower
# ("left first"); variant 1 = right higher / left lower ("right first"); variant 2 =
# symmetric (both leaves level).
# Leaves redrawn as real pointed leaves (#v32.1, user: "make the rose's two
# bottom leaves more real, like the model"): each is a 3-row tapered shape —
# a short upper edge hugging the stem, a long body reaching a 1px tip, and a
# mid-length drooping lower edge — instead of the old symmetric 2/3/2 diamond
# blob. The k column stays the leaf-to-stem attachment seam. NOTE: these stems
# are SHARED by every _u()-based flower, so the whole family's leaves improve
# together (deliberate — family consistency).
_ROSE_STEM_OFFSET = [  # left-first
    ".......SS.......",
    ".....GkSS.......",
    "..GGGGkSS.......",
    "....GGkSS.......",
    ".......SSkG.....",
    ".......SSkGGGG..",
    ".......SSkGG....",
    ".......SS.......",
]
_ROSE_STEM_OFFSET_R = [  # right-first (mirror of left-first)
    ".......SS.......",
    ".......SSkG.....",
    ".......SSkGGGG..",
    ".......SSkGG....",
    ".....GkSS.......",
    "..GGGGkSS.......",
    "....GGkSS.......",
    ".......SS.......",
]
_ROSE_STEM_SYM = [
    ".......SS.......",
    ".......SS.......",
    "....GGkSSkGG....",
    "...GGGkSSkGGG...",
    "....GGkSSkGG....",
    ".......SS.......",
    ".......SS.......",
    ".......SS.......",
]

# Each bloom is 16 wide, reds only (d/m/l); the dark rim is added by outline().
_ROSE_BLOOMS = [
    [  # 0 full bloom (round, layered) = shop thumbnail + fallback
        "......ddddd.....",
        "...mmdmmmlld....",
        "..mmlmmmddmmmm..",
        "..mlmdlmmmdmlm..",
        ".mdmmldddmmdmld.",
        ".dldmldmldmmmld.",
        ".dlmdlmddmlddd..",
        "..mmddmllmddmd..",
        "...dlmddddmlmm..",
        "...mmlllmdmmm...",
        ".....ddmmddd....",
        ".......ddd......",
    ],
    [  # 1 bud (closed goblet)
        ".....mddddm.....",
        "...mddlllmddm...",
        "...mlmdmmmdlm...",
        "...mmllddmlmd...",
        "....dmmlmlmd....",
        "....dmmldmmd....",
        "....dmlmldmd....",
        "....dmlmldmd....",
        "....dmmmmdmm....",
        ".....dddddd.....",
    ],
]


def _rose_compose(layers):
    """Paint each layer's opaque pixels (back to front) onto one grid."""
    h = len(layers[0])
    w = len(layers[0][0])
    out = blank(w, h)
    for lay in layers:
        for r in range(h):
            for c in range(w):
                if lay[r][c][3] != 0:
                    out[r][c] = lay[r][c]
    return out


def rose_variant(v):
    """One rose model (0..2): a reference-derived bloom over the shared stem. The
    bloom (reds) gets a dark-red rim and the stem/leaves (greens) a dark-green rim;
    each is outlined separately then composited so the two materials read apart."""
    bloom_rows = _ROSE_BLOOMS[v]
    stem = (_ROSE_STEM_OFFSET, _ROSE_STEM_OFFSET_R, _ROSE_STEM_SYM)[v]  # left/right/symmetric leaves (#v22)
    bh = len(bloom_rows)
    h = bh + len(stem) - 1  # stem tucks one row under the bloom base
    bloom = blank(16, h)
    plant = blank(16, h)
    for r, line in enumerate(bloom_rows):
        for c in range(min(len(line), 16)):
            if line[c] in _ROSE_REDS:
                bloom[r][c] = _ROSE_PAL[line[c]]
    for r, line in enumerate(stem):
        rr = bh - 1 + r
        for c in range(min(len(line), 16)):
            if line[c] in _ROSE_PAL and line[c] not in _ROSE_REDS:
                plant[rr][c] = _ROSE_PAL[line[c]]
    bloom = outline(bloom, _ROSE_RED_OL)
    plant = outline(plant, _ROSE_GRN_OL)
    return _rose_compose([plant, bloom])


# ---- grass tile (seamless, subtle speckle) -----------------------------------

def grass_grid():
    # A calm field: one base green with only sparse, low-contrast speckle so it
    # doesn't read as a patchwork quilt (#6). No bright olive, no hard tufts —
    # plants keep their dark outline (flower_png_grid) to separate from it.
    base = hexrgb("57A636")
    d1 = hexrgb("4F9A30")   # subtle darker
    l1 = hexrgb("63B23E")   # subtle lighter
    g = [[base + (255,) for _ in range(16)] for _ in range(16)]
    seed = 1234567
    for r in range(16):
        for c in range(16):
            seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
            v = seed % 30
            if v == 0:
                g[r][c] = d1 + (255,)
            elif v == 1:
                g[r][c] = l1 + (255,)
    return g


# NB: coin.png is NO LONGER generated here (#v30.8) — after three rounds of
# approximating the guide procedurally, the coin is now the user's actual art,
# extracted from the Coin Icon guide sheet by tools/extract_tracker_icons.py
# (same rule as the #v18 menu icons: never reintroduce generation for it).


# ---- mood faces (#v29 habit tracker) -----------------------------------------
# Daylio-style daily mood, but round-BOX pixel faces (user: not circle emojis).
# 14x14 rounded square + 1px near-black rim (via outline), dark features, one
# flat mood color each. 1=awful .. 5=great.

_FACE_COLORS = {1: 'E5484D', 2: 'F2994A', 3: 'F2C94C', 4: 'A8D93A', 5: '46A03C'}


def face_grid(mood):
    box = hexrgb(_FACE_COLORS[mood]) + (255,)
    ink = hexrgb("1A1D22") + (255,)
    g = blank(14, 14)
    for r in range(14):
        for c in range(14):
            corner = (r in (0, 13) and c in (0, 1, 12, 13)) or \
                     (r in (1, 12) and c in (0, 13))
            if not corner:
                g[r][c] = box
    for (r, c) in [(4, 3), (4, 4), (5, 3), (5, 4), (4, 9), (4, 10), (5, 9), (5, 10)]:
        g[r][c] = ink                                   # eyes
    mouths = {
        1: [(3, 4), (3, 9),                              # angry brow tips
            (9, 5), (9, 6), (9, 7), (9, 8), (10, 4), (10, 9)],   # deep frown
        2: [(9, 5), (9, 6), (9, 7), (9, 8), (10, 4), (10, 9)],   # frown
        3: [(10, 4), (10, 5), (10, 6), (10, 7), (10, 8), (10, 9)],  # flat
        4: [(9, 4), (9, 9), (10, 5), (10, 6), (10, 7), (10, 8)],    # smile
        5: [(9, 3), (9, 10), (10, 4), (10, 9),                       # big open
            (10, 5), (10, 6), (10, 7), (10, 8), (11, 5), (11, 6), (11, 7), (11, 8)],
    }
    for (r, c) in mouths[mood]:
        g[r][c] = ink
    return outline(g, "1A1D22")


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


# Extra species (#v23 fb) in real-world colours — same shapes as their cousins
# above, only the palette changes, so they fly/land with the existing behaviour.
def ladybug_yellow_grid():
    y = hexrgb("EFC81F") + (255,)   # 22-spot ladybird: lemon-yellow shell
    k = hexrgb("2B2B2B") + (255,)
    return _crit([
        '........', '..kkk...', '.rkrkr..', '.rrkrr..', '.rkrkr..', '..rrr...', '........', '........',
    ], {'r': y, 'k': k})


def butterfly_monarch_grid():
    a = hexrgb("E8751A") + (255,)   # monarch orange
    b = hexrgb("2B2B2B") + (255,)   # black veins
    k = hexrgb("2B2B2B") + (255,)
    return _crit([
        '........', '.a.k.a..', 'aba.aba.', 'aba.aba.', '.a.k.a..', '...k....', '........', '........',
    ], {'a': a, 'b': b, 'k': k})


def butterfly_blue_grid():
    a = hexrgb("2E86DE") + (255,)   # blue-morpho wing
    b = hexrgb("1B4F8A") + (255,)   # deep-blue edge
    k = hexrgb("2B2B2B") + (255,)
    return _crit([
        '........', '.a.k.a..', 'aba.aba.', 'aba.aba.', '.a.k.a..', '...k....', '........', '........',
    ], {'a': a, 'b': b, 'k': k})


def bee_bumble_grid():
    blk = hexrgb("2B2B2B") + (255,)  # bumblebee: black body...
    yl = hexrgb("F2C94C") + (255,)   # ...with yellow bands (palette of the honeybee, swapped)
    w = (255, 255, 255, 210)
    return _crit([
        '........', '..wkw...', '.wykyw..', '..kyk...', '..yky...', '..kyk...', '...k....', '........',
    ], {'y': blk, 'k': yl, 'w': w})


CRITTERS = {
    'bee': bee_grid, 'butterfly': butterfly_grid, 'ladybug': ladybug_grid,
    'ladybug_yellow': ladybug_yellow_grid,
    'butterfly_monarch': butterfly_monarch_grid,
    'butterfly_blue': butterfly_blue_grid,
    'bee_bumble': bee_bumble_grid,
}


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


# ---- other flowers: 2 hand-authored models each, same modular pipeline as the
# rose (per-flower d/m/l palette + a centre C, the shared stem/leaves, bloom and
# plant outlined separately). Rolled out flower-by-flower (#v22); ids NOT listed
# here keep their old single char-grid sprite until they're redrawn.
_FLOWER_PALS = {  # id: (dark, mid, light, centre, bloom-outline) — hex
    'lale':      ('9C1B2E', 'D93645', 'F2737C', 'F2C94C', '2E0810'),  # red tulip
    'kamelya':   ('A21250', 'E02C6D', 'F573A2', 'F2D24C', '37041F'),  # pink-red camellia, gold eye
    'kaktus':    ('E0457B', 'F06A92', 'F9A8C2', 'F2C94C', '5A1030'),  # LEGACY (#v27: off-catalogue; PNGs kept for old saves' wallpaper)
    'kaktusf':   ('E0457B', 'F06A92', 'F9A8C2', 'C98A1B', '5A1030'),  # flower cactus — single darker-gold bloom dot (#v27)
    'kaktusd':   ('E0457B', 'F06A92', 'F9A8C2', 'F2C94C', '5A1030'),  # desert cactus — bloom unused (#v26)
    'kasimpati': ('C9710B', 'F2A03A', 'F8C66A', 'E0860B', '5A3206'),  # gold chrysanthemum
    'menekse':   ('5B2A9E', '8E4FE0', 'B98CF0', 'F2C94C', '24104A'),  # purple violet, gold eye
    'papatya':   ('CFD4DA', 'FFFFFF', 'FFDE73', 'F2C94C', '3D2E0A'),  # white daisy, gold eye — dark warm gold-brown rim, not black (#v30 item 3; was near-black 181A1F in #v28.8)
    'nilufer':   ('D85C8E', 'F4A6C0', 'FAD0E0', 'F2C94C', '5A1E38'),  # pink water lily, gold eye
    'begonya':   ('C0285A', 'F2585B', 'F78AA0', 'F2C94C', '3A0A1C'),  # pink begonia (both same colour)
    'orkide':    ('7A2EA0', 'C24FE0', 'E0A6F2', 'F2C94C', '2C0E40'),  # purple orchid (both same colour)
}

# Shared upright stem + 2 leaves (reuse the rose's, so every species reads as the
# same garden style): left-first leaves for model 0, right-first for model 1.
_STEM_L = _ROSE_STEM_OFFSET
_STEM_R = _ROSE_STEM_OFFSET_R


def _u(b0, b1):
    """Build a 2-model flower from two 8-row blooms by standing each on the shared
    stem (left leaves / right leaves) — a full 16-row grid per model."""
    return [b0 + _STEM_L, b1 + _STEM_R]


_FLOWER_BLOOMS = {
    # --- upright flowers: an 8-row bloom standing on the shared stem -----------
    'lale': [  # guide-sheet study picks (#v27, flower_study/tulip)
        [  # 0 classic closed tulip — smooth cup, blade leaves (guide TULIP 01)
            "................",
            ".......ll.......",
            "......lmml......",
            ".....dmmmmd.....",
            ".....dmmmmd.....",
            ".....dmlmld.....",
            "......dmmd......",
            ".......S........",
            ".......S........",
            ".....G.S.G......",
            "....GGkSkGG.....",
            ".....GGSGG......",
            "......kSk.......",
            ".......S........",
            "................",
        ],
        [  # 1 open tulip — flared crown with three tips (guide TULIP 03)
            "................",
            ".....l..l..l....",
            ".....mllmllm....",
            "....dmmmmmmd....",
            "....dmmmmmmd....",
            ".....dmmmmd.....",
            "......dmmd......",
            ".......S........",
            ".......S........",
            "....GkkSkkG.....",
            ".....GGSGG......",
            "......kSk.......",
            ".......S........",
            "................",
        ],
    ],
    'kamelya': _u(
        [  # 0 semi-open camellia — guide CAMELLIA 02
            "......mmmm......",
            "....dmmmmmmd....",
            "...dmmllllmmd...",
            "...dmlCCCClmd...",
            "...dmmlCClmmd...",
            "....dmllllmd....",
            ".....dmmmmd.....",
            ".......dd.......",
        ],
        [  # 1 full bloom camellia — guide CAMELLIA 03
            ".....mmmmmm.....",
            "...dmmllllmmd...",
            "..dmllCCCCllmd..",
            "..dmlCCCCCClmd..",
            "..dmllCCCCllmd..",
            "...dmmllllmmd...",
            "....dmmmmmmd....",
            ".....dmmmd......",
        ],
    ),
    'kasimpati': [  # guide-sheet study picks (#v27, flower_study/chrysanthemum)
        [  # 0 pom-pom mum — dense round bloom, curl speckles (guide MUM 01)
            "................",
            "......mmm.......",
            "....mlmlmlm.....",
            "....lmdmlml.....",
            "...mlmldmlmm....",
            "...mmdmlmdlm....",
            "....lmldmlm.....",
            ".....mdmdm......",
            "......mmm.......",
            ".......S........",
            ".......S........",
            "....GGkSkGG.....",
            ".....GGSGG......",
            ".......S........",
            "................",
        ],
        [  # 1 spider mum — thin radiating petals (guide MUM 02)
            "................",
            "....d..m..d.....",
            "....md.m.dm.....",
            ".....mmmmm......",
            "...mmldmdlmm....",
            ".....mmmmm......",
            "....md.m.dm.....",
            "....d..m..d.....",
            ".......S........",
            ".......S........",
            "....GGkSkGG.....",
            ".....GGSGG......",
            ".......S........",
            "................",
        ],
    ],
    'papatya': [  # USER PICKS from the hand-authored daisy round 3 (#v28,
        # flower_study/daisy: m2_0 + m2_3 — chosen 2026-07-04)
        [  # 0 classic daisy — FINAL (#v28.8 polish on the kept #v28.5 design):
           # heart is UNIFORM dark gold, symmetric 2/4/4/2 (the 'l' highlight
           # pixel and the +1-gold offset removed on user request), so all four
           # gray seams line up at the same columns; tapered lobe corners,
           # rounded mound, scalloped silhouette, black rim only.
           # #v34.6: leading blank row so outline() can draw the TOP rim — the
           # petals sat on row 0 with no transparent pixel above them, so the
           # bloom had side rims but no dark line across its top. Same fix
           # #v32.2 applied to the bushy variant; this one was missed.
            "................",
            "......dmmd......",
            "....m.mmmm.m....",
            "...mmmdmmdmmm...",
            "...dmmdCCdmmd...",
            "..mmmmCCCCmmmm..",
            "..dmmmCCCCmmmd..",
            "...mmmdCCdmmm...",
            "...mmmdmmdmmm...",
            "....d.mmmm.d....",
            "......mmmm......",
            "..GG..GGGG..GG..",
            "..GGGGkkkkGGGG..",
            "....GGkkkkGG....",
            "......GGGG......",
        ],
        [  # 1 bushy daisy — three round blooms over the mound, no side bud.
           # #v28.9: side blooms mirror about the STEM COLUMN c7 (the v28.1 fix
           # mirrored about the grid's 7|8 midline, leaving the right bloom 1px
           # farther from the stem — visibly unequal on the phone). Stem, top
           # bloom, mound and both side blooms now all center on c7.
           # #v32.2: leading blank row so outline() can draw the TOP bloom's top
           # rim — sitting at row 0 it was clipped by the canvas edge (no top line).
            "................",
            "......mmm.......",
            ".....mmCmm......",
            ".....mmCmm......",
            "......mmm.......",
            "..mmm..S..mmm...",
            ".mmCmm.S.mmCmm..",
            ".mmCmm.S.mmCmm..",
            "..mmm..S..mmm...",
            ".......S........",
            "..GGGkGSGkGGG...",
            ".GGSGGkSkGGSGG..",
            "..GGkSGSGSkGG...",
            "...kGGkSkGGk....",
            ".....kkkkk......",
        ],
    ],
    'begonya': _u(
        [  # 0 cane begonia (full rounded cluster, gold flower-centres) — guide BEGONIA 02
            "....ddddd.......",
            "..ddmmmmmdd.....",
            ".dmmCmmmCmmd....",
            ".dmllmmmllmd....",
            ".dmmCmmmCmmd....",
            "..dmmmmmmmd.....",
            "...dmmmmmd......",
            "....ddddd.......",
        ],
        [  # 1 rhizomatous begonia (same colour, wider low cluster) — guide BEGONIA 03
            "..ddddddddd.....",
            ".dmmmmmmmmmd....",
            ".dmCmmCmmCmd....",
            ".dmmmmmmmmmd....",
            ".dmmmmmmmmmd....",
            "..dmmmmmmmd.....",
            "...ddddddd......",
            "................",
        ],
    ),
    'orkide': _u(
        [  # 0 dendrobium (two bold blooms with gold throats) — guide ORCHID 02
            "...dmmmmd.......",
            "..dmlCClmd......",
            "..dmlCClmd......",
            "...dmmmmd.......",
            "...dmmmmd.......",
            "..dmlCClmd......",
            "...dmmmmd.......",
            "................",
        ],
        [  # 1 oncidium (fuller spray, same colour) — guide ORCHID 04
            "...dmmd.dmmd....",
            "..dmCmd.dmCmd...",
            "...dmmd.dmmd....",
            "......dmmd......",
            ".....dmCmd......",
            "......dmmd......",
            "................",
            "................",
        ],
    ),
    # --- special shapes: full 16-row grids (own body / foliage) ---------------
    'kaktus': [
        [  # 0 round barrel cactus + flower, no pot — guide CACTUS 01
            ".......d........",
            "......dmd.......",
            ".....dmCmd......",
            "......ddd.......",
            "....GGGGGGG.....",
            "...GkGGGkGGk....",
            "..GkGGGGGkGGk...",
            "..GGGGGGGGGGG...",
            "..GkGGGGGkGGk...",
            "..GkGGGGGkGGk...",
            "...GGGGGGGGG....",
            "....GGGGGGG.....",
            ".....GGGGG......",
            "......kkk.......",
            "................",
            "................",
        ],
        [  # 1 columnar cactus + side arm + flower, no pot — guide CACTUS 02
            "......d.........",
            ".....dmd........",
            "....dmCmd.......",
            ".....ddd........",
            "......GGG.......",
            "......GkG.......",
            "...GG.GkG.......",
            "..GkG.GkG.......",
            "..GkG.GkG.......",
            "..GkGGGkG.......",
            "...GGGGkG.......",
            "......GkG.......",
            "......GkG.......",
            "......GkG.......",
            ".....GGGGG......",
            "................",
        ],
    ],
    'menekse': [  # guide-sheet study picks (#v27, flower_study/violet)
        [  # 0 classic violet — five-petal bloom, gold eye, leaf mound (guide VIOLET 01)
            "................",
            ".....mm.mm......",
            "....lmmlmml.....",
            "....lmmCmml.....",
            ".....mmlmm......",
            "......mmm.......",
            ".......S........",
            ".......S........",
            "....GkkSkkG.....",
            "...GGSGGSGGG....",
            "....kGGSGGk.....",
            ".....kkkkk......",
            "................",
        ],
        [  # 1 upright violets — two blooms + side bud over the mound (guide VIOLET 02)
            "................",
            "......mm........",
            ".....lmml.......",
            ".....mlCm.ll....",
            "......mm..mm....",
            ".......S..d.....",
            ".......S.S......",
            "..ll...S.S......",
            "..lmd..SS.......",
            "...d...S........",
            "...S...S........",
            "..GGSkGSGkGG....",
            "...GGkSGGkG.....",
            "....kkkkk.......",
            "................",
        ],
    ],
    'nilufer': [
        [  # 0 partially-open water lily on a pad — guide WATER LILY 02
            "................",
            "................",
            "......ddd.......",
            ".....dmCmd......",
            "....dmlClmd.....",
            ".....dmmmd......",
            "......ddd.......",
            "...GGGGGGGGG....",
            "..GGGGGGGGGGG...",
            ".GGGGGGGGGGGGG..",
            "..GGGGGGGGGGG...",
            "...GGGGGGGGG....",
            "................",
            "................",
            "................",
            "................",
        ],
        [  # 1 full-bloom water lily on a pad — guide WATER LILY 03
            "................",
            "......l.l.......",
            ".....dmlmld.....",
            "....dmlCClmd....",
            "....dmlCClmd....",
            ".....dmlmld.....",
            "......ddd.......",
            "...GGGGGGGGG....",
            "..GGGGGGGGGGG...",
            ".GGGGGGGGGGGGG..",
            "..GGGGGGGGGGG...",
            "...GGGGGGGGG....",
            "................",
            "................",
            "................",
            "................",
        ],
    ],
    # --- cactus 2.0 (#v26): two NEW species picked from the user's guide-sheet
    # study (now flower_study\cactus, 2 methods). kaktusf = FLOWER CACTUS, traced from the
    # rendered guide art (rose method); kaktusd = DESERT CACTUS (no bloom):
    # model 0 hand-authored crisp saguaro, model 1 = the traced prickly pear of
    # kaktusf-style shape 03, de-flowered. 'o' = interior seam (dark rim green).
    'kaktusf': [
        [  # 0 tall columnar, pink crown flower — traced guide shape 01
            # (#v27: gold scatter removed — ONE centred darker-gold C per bloom,
            #  like the approved flower_study\cactus m1_flower_3 caps)
            '.......m........',
            '.....mldl.......',
            '.....ldCdmm.....',
            '.....mmdmdl.....',
            '......dmdl......',
            '.....SSkSkS.....',
            '.....SGGGkG.....',
            '.....SGGGkG.....',
            '...GGSGGGkG.....',
            '...GGSSGSkS.....',
            '...GGSSGGkG.G...',
            '...SSkSGGkSkG...',
            '....GkSGGkSkS...',
            # (#v27.1: silhouette-edge k lightened to S — edge-k + the near-black
            #  rim read as a 2px-wide border; k stays only on interior ribs)
            '.....SSGSkS.....',
            '.....SSSSkS.....',
            '.....SSSSkS.....',
        ],
        [  # 1 round barrel, pink top flower — traced guide shape 02
            # (#v27: single centred darker-gold C, edge golds re-pinked)
            '........m.......',
            '......mmmdm.....',
            '......mdCmm.....',
            '......mdmdm.....',
            '...GGSlldd.kSG..',
            '..GSSGklkdkSGSS.',
            # (#v27.1: edge-k and the solid-k bottom bands brightened to S so the
            #  border reads 1px thin like the rose; o seams + single-k creases
            #  keep the barrel folds)
            '..SGGSSkkkkSSGG.',
            '..SGSGGSGSSGkSG.',
            '..SGkGGkGGkGSSG.',
            '..SSkSSoSGkSSkS.',
            '..SSkSSoGSkSGoS.',
            '..SSkSSkSSokSkS.',
            '...SkSSoSSkSSk..',
        ],
    ],
    'kaktusd': [
        [  # 0 saguaro — hand-authored, no ridge dots. #v27.1: the k edge column
           # merged with the near-black rim into a fat 2px border — edges are S
           # now; k survives only as the 1px arm-trunk seams (study rule: parts
           # touch with a single dark seam).
            '.......SG.......',
            '......SSGG......',
            '......SSGG......',
            '......SSGG......',
            '......SSGG......',
            '..SG..SSGG......',
            '.SSG..SSGG..SG..',
            '.SSG..SSGG..SGG.',
            '.SSGGkSSGG..SGG.',
            '..SSGkSSGGkGSG..',
            '......SSGGkGG...',
            '......SSGG......',
            '......SSGG......',
            '......SSGG......',
            '......SSSG......',
        ],
        [  # 1 prickly pear — de-flowered trace of guide shape 03. #v27.1: the
           # solid-k lower pads + edge-k read as a wide dark blob — brightened
           # to S; single-k creases keep the pad separations.
            '...........SG...',
            '...........GGSS.',
            '..GSSG....SGSSS.',
            '..SSGG....SGSSS.',
            '..GSSS..GGkSSk..',
            '..SSSSkGGGSS....',
            '...SSkSGGGGS....',
            '....GkGSGGSS....',
            '.....SSSSSSS....',
            '.....SGSkSSS....',
            '.....SSkSSSS....',
            '......SSSSSS....',
            '......SSSSSS....',
        ],
    ],
}


def _flower_pal(fid):
    d, m, l, cen, ol = _FLOWER_PALS[fid]
    return {
        'd': hexrgb(d) + (255,), 'm': hexrgb(m) + (255,), 'l': hexrgb(l) + (255,),
        'C': hexrgb(cen) + (255,),
        'S': _ROSE_PAL['S'], 'G': _ROSE_PAL['G'], 'k': _ROSE_PAL['k'],
        'o': hexrgb(_ROSE_GRN_OL) + (255,),   # interior seam between plant parts (#v26)
        'x': hexrgb(ol) + (255,),  # bloom-interior seam, 1px thin petal separators (#v28.1)
    }


# Dark-green plant rim for the cactuses, matching the rose's dark-TONE
# approach (#v30 item 3 — reverses the #v27 near-black decision at the
# user's request: rims should be a dark shade of the plant's own colour,
# never flat black). Same tone as the interior 'o' seams (_ROSE_GRN_OL) so
# the whole plant reads as one dark-green family, not a black silhouette.
_PLANT_OL = {'kaktusf': '1E5A24', 'kaktusd': '1E5A24'}


def flower_variant(fid, v):
    """One model of a (non-rose) flower as a full self-contained grid: petal chars
    d/m/l + centre C are the bloom (outlined with the flower's dark rim); green
    chars S/G/k are the stem/leaves/body (outlined dark green); composited so the
    two materials read apart, like the rose. Each grid already carries its own
    foliage — an upright stem (via _u) or a custom body (cactus/violet/water lily)."""
    pal = _flower_pal(fid)
    rows = _FLOWER_BLOOMS[fid][v]
    h = len(rows)
    bloom = blank(16, h)
    plant = blank(16, h)
    for r, line in enumerate(rows):
        for c in range(min(len(line), 16)):
            ch = line[c]
            if ch in 'dmlCx':
                bloom[r][c] = pal[ch]
            elif ch in 'SGko':
                plant[r][c] = pal[ch]
    bloom = outline(bloom, _FLOWER_PALS[fid][4])
    plant = outline(plant, _PLANT_OL.get(fid, _ROSE_GRN_OL))
    return _rose_compose([plant, bloom])


def main():
    os.makedirs(OUT, exist_ok=True)
    SCALE = 16  # base grids are 8/10/16 px tall; ×16 keeps them crisp

    # Critters still ship as 8-frame directional atlases so a bee faces its
    # travel heading (#4). Flowers are single billboards (radially symmetric — an
    # atlas would be 8x the memory for no visible gain), and fences are single
    # frames too: the garden renders them as low-poly 3D meshes, so their PNG is
    # now only a shop thumbnail.
    # Flowers with hand-authored 2-model variants render through the modular
    # pipeline (rose + anything in _FLOWER_BLOOMS); the rest keep their single
    # char-grid sprite until they're redrawn. variant 0 is the shop thumbnail.
    for fid, (petal, center, chars) in FLOWERS.items():
        if fid == 'gul':
            for v in range(2):  # rose: 2 hand-authored models (#v22)
                write_png(os.path.join(OUT, f"flower_gul_{v}.png"), upscale(rose_variant(v), SCALE))
            write_png(os.path.join(OUT, "flower_gul.png"), upscale(rose_variant(0), SCALE))
        elif fid in _FLOWER_BLOOMS:
            for v in range(2):
                write_png(os.path.join(OUT, f"flower_{fid}_{v}.png"), upscale(flower_variant(fid, v), SCALE))
            write_png(os.path.join(OUT, f"flower_{fid}.png"), upscale(flower_variant(fid, 0), SCALE))
        else:
            write_png(os.path.join(OUT, f"flower_{fid}.png"),
                      upscale(flower_png_grid(petal, center, chars), SCALE))
    for cid, fn in CRITTERS.items():
        write_png(os.path.join(OUT, f"{cid}.png"), upscale(make_atlas(fn()), SCALE))
    for fid, fn in FENCES.items():
        write_png(os.path.join(OUT, f"{fid}.png"), upscale(fn(), SCALE))

    # Flat / single-frame sprites: ground, surround, roads, wallet coin.
    write_png(os.path.join(OUT, "grass.png"), upscale(grass_grid(), SCALE))
    write_png(os.path.join(OUT, "forest.png"), upscale(forest_grid(), SCALE))
    write_png(os.path.join(OUT, "tree.png"), upscale(tree_grid(), SCALE))
    # forest variety (#5): 20 trees + 10 bushes + 5 rocks
    for i in range(20):
        write_png(os.path.join(OUT, f"tree_{i:02d}.png"), upscale(_tree_variant(i + 1), SCALE))
    for i in range(10):
        write_png(os.path.join(OUT, f"bush_{i:02d}.png"), upscale(_bush_variant(i + 1), SCALE))
    for i in range(5):
        write_png(os.path.join(OUT, f"rock_{i:02d}.png"), upscale(_rock_variant(i + 1), SCALE))
    for mood in range(1, 6):  # habit-tracker mood faces (#v29)
        write_png(os.path.join(OUT, f"face_{mood}.png"), upscale(face_grid(mood), 8))
    for rid, fn in ROADS.items():
        write_png(os.path.join(OUT, f"{rid}.png"), upscale(fn(), SCALE))

    # drop sprites that were renamed/removed over time, if present
    for old in ("road.png", "fence.png", "bug.png", "flower_gul_3.png", "flower_gul_2.png",
                "road_asphalt.png", "road_brick.png", "fence_white.png"):
        p = os.path.join(OUT, old)
        if os.path.exists(p):
            os.remove(p)
    n = len(FLOWERS) + len(CRITTERS) + len(FENCES) + len(ROADS) + 3  # +grass +forest +tree
    print("wrote", n, "sprites to", os.path.abspath(OUT), f"(FRAMES={FRAMES})")
    # NB: the menu icons in assets/icon/ come from tools/extract_icons.py (#v18)
    # and coin.png from tools/extract_tracker_icons.py (#v30.8) — the user's
    # own ChatGPT art, NOT generated here.


if __name__ == "__main__":
    main()
