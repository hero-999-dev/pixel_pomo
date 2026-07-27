// ─────────────────────────────────────────────────────────────────────────
//  PixelPomo Garden Engine — a tiny, purpose-built 2.5D scene renderer.
//
//  Not a general game engine (no Unity/Flame): just what a living pixel garden
//  needs — a 2.5D projection with a fixed tilt but a hand-controllable compass
//  rotation (look from N/E/S/W like Google Maps), a contiguous grass field with
//  a raised soil slab for depth, flat roads, ground-connected fences, and a few
//  tiny critters that drift in (in garden space, so they rotate with the map),
//  visit a flower, and leave.
//
//  The camera zooms, pans (clamped so the garden can't leave the screen) and
//  yaws. Pure rendering + camera math live here; it reads a [Garden] from
//  logic.dart and a [SpriteBank].
// ─────────────────────────────────────────────────────────────────────────
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../logic.dart';

/// Fixed vertical squash of the ground plane — this constant *is* the 2.5D
/// depth (1.0 would be flat top-down). The viewing angle around the vertical
/// axis is the camera's [GardenCamera.yaw]; the tilt itself stays fixed.
const double kVy = 0.60;

/// Number of frames in a directional atlas — must match `FRAMES` in
/// tools/gen_objects.py. Only **critters** still ship as an 8-frame strip (so a
/// bee faces its travel heading); the painter slices out the matching frame.
/// Flowers are single billboards and fences are 3D meshes — neither uses this.
const int kDirFrames = 8;

/// Forest sprite pool sizes — must match the counts emitted by tools/gen_objects.py.
const int kForestTrees = 20, kForestBushes = 10, kForestRocks = 5;

/// Share of forest tiles left as bare grass. The pre-v34.8 woods left 18% and
/// read as a solid green wall once the trees grew to 2–4 tiles; the v34.9
/// backdrop went to the other extreme and looked empty. 34% was still "cok
/// yogun", so 42% (#v34.11) — raise it to thin the woods further.
///
/// Back down to 34 in #v34.15. 42 was tuned when the woods were 3- and 4-tile
/// trees that each covered several tiles of screen; once everything became
/// 2-tile trees and 0.85 bushes the same share of bare tiles started reading as
/// holes — "alt tarafta fazla bosluklar oluyor". Density is a function of what
/// is standing on the tiles, not of the number alone.
const int kForestGapPercent = 34;

/// The woods are small trees, bushes and rocks EVERYWHERE (#v34.12) — "tüm
/// orman alt taraf gibi olsun". Big trees are the exception, not the rule: one
/// candidate site per [kBigTreeBlock]x[kBigTreeBlock] block of tiles, placed
/// away from the block's own edges so two sites in neighbouring blocks always
/// sit at least 4 tiles apart — wider than the widest tree, so **no two big
/// trees can ever overlap on screen**.
///
/// That separation is the actual fix for "kamera acisi degisince büyük
/// agaclarin birbirinin icine gecmesi". Two overlapping billboards genuinely
/// do swap paint order when their ground depths cross mid-turn — that is
/// correct perspective, not a bug — but with 4-tile canopies the swap covers
/// half the screen and reads as a pop. Trees that never overlap can never
/// visibly swap, so the pop is gone by construction rather than by tuning.
const int kBigTreeBlock = 7;

/// Share of blocks that actually grow their big tree. The rest have none, so
/// the big ones read as occasional landmarks — "birkac tane" — instead of a
/// regular grid of them.
const int kBigTreePercent = 60;

/// A full 4-tile tree stays this many tiles back — "ilk 6 hatta cok büyük
/// agaclar olmasin" (#v34.17; was 6, so one still landed on the sixth row).
const int kBigTreeClearTiles = 7;

/// The 2-tile trees whose sprite is NARROW — the poplars, plus the slimmest
/// broadleaf. Indices into the tree pool, and the only trees allowed in the
/// innermost ring tile on the flanks.
///
/// A flank prop overlaps the clearing SIDEWAYS, by `width/2 - 0.5` tiles, so a
/// narrow silhouette is the one thing that genuinely reduces how far it reaches
/// in: "ilk hatta sag solda genis agac degilde, böyle ince uzun tarza agac".
/// The drawn rect is the same for every 2-tile tree — what changes is how much
/// of it the artwork actually fills, 41-56% here against 66-72% for the rest.
/// Gated by a sprite test, so re-rolling a silhouette cannot leave this stale.
const List<int> kNarrowTrees = [5, 13];

/// Bare-ground share for the tile hard against the clearing. Lower than the
/// woods' [kForestGapPercent] because at one tile out a hole is a hole in the
/// clearing's own rim — "birinci hatta bazen cok bosluk oluyor".
const int kRingInnerGapPercent = 20;

/// 3-tile trees may take a lattice site from this distance, so the size jump
/// from the 2-tile woods to the landmarks is not all-or-nothing and the middle
/// distances have something other than one repeated silhouette in them
/// (#v34.15 — "hala cesitlilikle görsel olarak problem var").
///
/// They ride the SAME lattice as the big ones, which is the whole point: sites
/// are guaranteed 4 tiles apart, so scattering taller trees around cannot
/// reintroduce the overlap-swap pop. Free-scattered 3-tile trees would sit one
/// tile apart and overlap by nearly two.
const int kMidTreeClearTiles = 4;

/// Drawn height and width, in tiles, of a one-tile forest prop. Bushes (which
/// are mostly squat little trees now, #v34.14) are 0.85 rather than a flower's
/// 1.05: their art fills its 16px canvas properly since the bottom padding was
/// removed, so drawing them at full height would make them stand taller on
/// screen than they used to and lean further over the plot. 0.85 keeps the
/// plant the same size it looks now while actually touching the ground.
const double kBushHeight = 0.85, kBushWidth = 0.9;

/// Rocks sit lower and wider than they are tall.
const double kRockHeight = 0.6, kRockWidth = 0.8;

/// Petal colours for the wild daisies scattered on the clearing's grass. Index
/// 0 is the white one that has always been there; the rest are the coloured
/// variants (#v34.14). The yellow eye is shared, so a tinted bloom reads as the
/// same little flower in another colour rather than a different species.
const List<int> kGrassBloomPetals = [
  0xFFFFFFFF, // white
  0xFFF2A6C4, // pink
  0xFF9AB8F0, // cornflower
  0xFFE0B0F0, // lilac
  0xFFF5D98A, // butter
];

/// Percent of grass daisies that get a coloured tint instead of white —
/// "%75 beyaz gerisi, farkli renkler olsun random sansda olsun" (#v34.15).
///
/// The first cut put this at 22, which reads as one coloured bloom per ~90
/// empty tiles: on a 25-tile plot that is well under one flower, so in practice
/// the colours never showed up at all. A quarter of the blooms is what "much
/// rarer than white" actually means at this plot size.
const int kGrassBloomTintPercent = 25;

/// Index into [kGrassBloomPetals] for a grass daisy, from its tile hash. White
/// nearly always; a coloured one is a find, not a pattern. The tint rolls on a
/// DIFFERENT slice of the hash than the 5% bloom chance, so the two are
/// independent and the colours don't cluster on whichever tiles happened to
/// bloom.
int grassBloomTint(int hash) {
  if ((hash ~/ 100) % 100 >= kGrassBloomTintPercent) return 0; // white
  return 1 + (hash ~/ 10000) % (kGrassBloomPetals.length - 1);
}

/// The clearing has a transition ring this many tiles deep before the woods
/// proper start — "ilk 2 sira her taraftan, kücük cali, tas, ve kücük agac
/// olsun" (#v34.14; it was 3 in #v34.12b).
///
/// The innermost tile takes bushes and rocks; small trees join from
/// [kRingTreeTiles] out. A billboard is anchored on its tile and drawn straight
/// up, while moving one tile away buys only `kVy` tiles of screen separation,
/// so a 2.1-tile tree standing one tile out reaches 1.5 tiles over the plot's
/// edge, while a 0.85 bush reaches 0.25 and a rock none at all.
const int kUndergrowthTiles = 2;

/// Small trees join the ring from this tile out; the innermost tile is bushes
/// and rocks. Only the innermost, deliberately — the first cut of this graded
/// the ring hard by height (rocks at 1, bushes at 2, trees at 3) and it looked
/// far worse than the problem: at yaw 0 the tiles beside the plot are all at
/// distance 1, so each side became an evenly spaced vertical column of pebbles,
/// and the ring as a whole read as a bare moat. The height grading only ever
/// mattered on the ONE side that happens to be between the camera and the plot,
/// and it was being paid for on all four.
const int kRingTreeTiles = 2;

/// How many tiles wide/tall each tree is drawn at (#v34.8).
///
/// The forest used to sit at 1.2 tiles, barely taller than a flower — "the
/// trees stay tiny next to the flowers". Mostly 2s and 3s with a few 4s
/// standing over them, so the tree line has a skyline instead of being one
/// uniform hedge. Bushes and rocks stay at one tile.
///
/// MUST match `TREE_TILES` in tools/gen_objects.py (the sprite is generated at
/// 16px per tile, so a mismatch also changes the pixel density) and the same
/// table in the Kotlin wallpaper's GardenRenderer.
const List<int> kTreeTiles = [2, 3, 2, 4, 3, 2, 3, 3, 2, 4, 2, 3, 4, 2, 3, 2, 3, 4, 2, 3];

/// Drawn size of a forest prop, in tiles. One source for the painter, the live
/// wallpaper's mirror and the lean maths in the tests — a prop whose drawn
/// height drifts from what the tests reason about is how a plant ends up
/// hanging in the air or leaning over the garden.
double forestPropHeight(String id) => id.startsWith('rock_')
    ? kRockHeight
    : id.startsWith('bush_')
        ? kBushHeight
        : forestPropTiles(id) * 1.05;

double forestPropWidth(String id) => id.startsWith('rock_')
    ? kRockWidth
    : id.startsWith('bush_')
        ? kBushWidth
        : forestPropTiles(id) * 0.95;

/// Tiles occupied by a forest prop id — trees vary, bushes and rocks are one.
double forestPropTiles(String id) {
  if (!id.startsWith('tree_')) return 1;
  // an id whose index doesn't parse falls back to one tile rather than
  // silently becoming tree 0 — a malformed id should look wrong, not plausible
  final n = int.tryParse(id.substring(5));
  if (n == null) return 1;
  return kTreeTiles[n % kTreeTiles.length].toDouble();
}

/// Is garden tile (c,r) inside the plantable plot (true) or the surrounding
/// screen-filling forest (false)? (#v18)
bool isGardenTile(int c, int r, int cols, int rows) => c >= 0 && c < cols && r >= 0 && r < rows;

/// Depth key for one HALF of a fence rail — the half owned by the post whose
/// ground screen-Y is [postGroundDy]. Pinned a hair BEHIND its own post so the
/// post always paints over the rail's end joint from every camera yaw. The
/// v31.18 whole-rail midpoint key crossed its own posts' depths as the camera
/// turned, flipping the rail in front of / behind them in a single frame —
/// which read as the fence suddenly "changing direction" mid-rotation (#v32).
double railHalfDepth(double postGroundDy) => postGroundDy - 0.01;

/// Stable back-to-front paint order for a list of depth keys: sorts ascending,
/// breaking exact ties on original index. `List.sort` is NOT guaranteed
/// stable, so two (near-)tied depths — e.g. a fence rail's midpoint vs. a
/// neighbouring post/flower — could otherwise flip paint order between frames
/// with unchanged input, reading as a sudden pop mid-rotation (#v31.21).
List<int> stableDepthOrder(List<double> depths) {
  final order = List<int>.generate(depths.length, (i) => i);
  order.sort((a, b) {
    final cmp = depths[a].compareTo(depths[b]);
    return cmp != 0 ? cmp : a.compareTo(b);
  });
  return order;
}

int _hash2(int c, int r) {
  var h = (c * 73856093) ^ (r * 19349663);
  h ^= h >> 13;
  return h & 0x7fffffff;
}

/// Tiles outside the plot rect, 0 when inside. Chebyshev, so a corner counts
/// the same as a side.
int tilesOutsidePlot(int c, int r, int cols, int rows) {
  final dx = c < 0 ? -c : (c > cols - 1 ? c - (cols - 1) : 0);
  final dy = r < 0 ? -r : (r > rows - 1 ? r - (rows - 1) : 0);
  return dx > dy ? dx : dy;
}

/// Is this tile off the plot's COLUMN edge (beside it) rather than off its row
/// edge (in front of or behind it)?
///
/// A billboard is drawn straight up from its tile, so a prop one tile in FRONT
/// of the clearing reaches 1.5 tiles up over its edge, while the same prop one
/// tile to the SIDE only overlaps by half a sprite width — it stands alongside
/// the garden instead of in front of it. That is why small trees are allowed in
/// the innermost ring tile on the flanks and not on the near and far edges:
/// "kücük agaclar koyabilirsin 1. hatta ama cok kücük, yan taraflarda olsun,
/// alt tarafda ve üst tarafta olmasin" (#v34.16).
///
/// Measured in GRID space, so it stays a pure function of the tile — at yaw 0
/// the column edges are the screen's left and right, and as the camera turns
/// the flanks turn with the garden rather than the prop changing species
/// mid-rotation, which is the fault #v34.12 removed.
bool isPlotSideTile(int c, int r, int cols, int rows) {
  final dx = c < 0 ? -c : (c > cols - 1 ? c - (cols - 1) : 0);
  final dy = r < 0 ? -r : (r > rows - 1 ? r - (rows - 1) : 0);
  return dx > 0 && dy == 0;
}

/// Floor division — Dart's `~/` truncates toward zero, which would fuse the
/// blocks either side of 0 into one double-width block.
int _floorDiv(int a, int b) => (a >= 0 ? a : a - b + 1) ~/ b;

/// Deterministic forest prop for a tile outside the plot (null = bare
/// woodland floor).
///
/// **A pure function of the tile and the plot size — nothing else.** Until
/// #v34.12 the caller passed in flags derived from the *viewport*
/// (`allowTallTrees: r > vb.minR + 3`), so the same tile grew a 2-tile tree at
/// one camera yaw and a 4-tile one at another: the tree visibly changed shape
/// as you turned, which is what "cizimde aci degisiyor ... saga bakarken sola
/// bakiyormus gibi" was seeing. It was never a mirrored sprite — nothing in
/// the painter flips a billboard — it was the tile swapping species mid-turn.
/// Anything that depends on the camera cannot decide what grows where.
String? forestPropAt(int c, int r, int cols, int rows) {
  final d = tilesOutsidePlot(c, r, cols, rows);
  if (d == 0) return null; // inside the plot — the garden owns this tile
  final bucket = _hash2(c, r) % 100;
  String id(String kind, int n) =>
      '${kind}_${_variant(c, r, n).toString().padLeft(2, '0')}';

  // A taller tree, where one of the sparse isolated lattice sites lands far
  // enough back. Checked BEFORE the gap roll: a landmark shouldn't be cancelled
  // by the same coin flip that thins the undergrowth. Nearer sites are capped
  // at 3 tiles so nothing leans more than about a tile over the clearing.
  if (d >= kMidTreeClearTiles) {
    final big = _bigTreeAt(c, r, d >= kBigTreeClearTiles ? 4 : 3);
    if (big != null) return big;
  }

  if (d == 1) return _innerRingProp(c, r, cols, rows);

  if (bucket < kForestGapPercent) return null; // bare woodland floor

  // The transition ring — small trees, bushes and rocks, at the same density as
  // the woods so it reads as undergrowth and not as a moat. Only the innermost
  // tile drops the trees: a 2.1-tile tree standing one tile out leans a full
  // 1.5 tiles over the plot on whichever side faces the camera, which is the
  // "crossing the garden's line" everyone has been looking at. From two tiles
  // out the worst case is 0.9 and from three it is 0.3 — a canopy tip passing
  // in front of the clearing, which is just what a tree in front of a clearing
  // does.
  if (d <= kUndergrowthTiles) {
    if (bucket < 78) return _smallTree(c, r);
    if (bucket < 90) return id('bush', kForestBushes);
    return id('rock', kForestRocks);
  }
  if (bucket < 84) return _smallTree(c, r);
  if (bucket < 94) return id('bush', kForestBushes);
  return id('rock', kForestRocks);
}

/// The tile one step FURTHER from the plot than (c,r), along whichever edge
/// this tile sits off.
(int, int) _outward(int c, int r, int cols, int rows) {
  if (c < 0) return (c - 1, r);
  if (c > cols - 1) return (c + 1, r);
  if (r < 0) return (c, r - 1);
  return (c, r + 1);
}

/// The tile one step ALONG the rim from (c,r) — sideways on a flank, lengthways
/// on the near and far edges.
(int, int) _alongRim(int c, int r, int cols, int rows) =>
    isPlotSideTile(c, r, cols, rows) ? (c, r - 1) : (c - 1, r);

/// The raw roll for the tile hard against the clearing, before the two
/// anti-clustering rules below are applied to it.
String? _innerRingRaw(int c, int r, int cols, int rows) {
  final bucket = _hash2(c, r) % 100;
  String id(String kind, int n) =>
      '${kind}_${_variant(c, r, n).toString().padLeft(2, '0')}';
  if (bucket < kRingInnerGapPercent) return null;
  final flank = isPlotSideTile(c, r, cols, rows);
  if (flank) {
    if (bucket < 52) return _narrowTree(c, r);
    if (bucket < 88) return id('bush', kForestBushes);
    return id('rock', kForestRocks);
  }
  // The near and far edges take NO rocks (#v34.18). The plot's soil slab hangs
  // below its edge, and a rock one tile out is short enough that its sprite
  // straddles the slab's lower lip — so it reads as a pebble stuck to the side
  // of the raised bed rather than sitting on the ground: "tas havada duruyor".
  // A bush is tall enough to clear the slab and read as standing on the floor.
  return id('bush', kForestBushes);
}

/// The tile hard against the clearing (#v34.17), with the rim tidied (#v34.18).
///
/// Two deterministic anti-clustering passes on top of the roll, because at one
/// tile out the eye reads the whole rim as a line and picks out any repetition
/// in it — "2 tas yana gelmesin", "üstte 2 ve 3. satir ayni anda bosalmis".
/// Both look at a NEIGHBOUR'S raw roll, never at its finished value, so there
/// is no chain of dependencies and the result stays a pure function of the tile.
String? _innerRingProp(int c, int r, int cols, int rows) {
  final pick = _hash2(c, r) ~/ 100;
  var me = _innerRingRaw(c, r, cols, rows);

  // a hole is only allowed if the tile behind it is not also a hole, or the
  // two rings open up together and leave a bald patch in the rim
  if (me == null) {
    final (oc, or_) = _outward(c, r, cols, rows);
    if (forestPropAt(oc, or_, cols, rows) == null) {
      return 'bush_${(pick % kForestBushes).toString().padLeft(2, '0')}';
    }
    return null;
  }

  // no two rocks side by side along the rim
  if (me.startsWith('rock_')) {
    final (nc, nr) = _alongRim(c, r, cols, rows);
    final neighbour = _innerRingRaw(nc, nr, cols, rows);
    if (neighbour != null && neighbour.startsWith('rock_')) {
      return 'bush_${(pick % kForestBushes).toString().padLeft(2, '0')}';
    }
  }
  return me;
}

/// The big tree standing on tile (c,r), if any. One candidate site per
/// [kBigTreeBlock]-square block, offset within `[1, block-3]` on each axis so
/// sites in neighbouring blocks are always >= 4 tiles apart — the widest tree
/// is 3.8 tiles, so two big trees never overlap and so can never visibly swap
/// depth as the camera turns.
String? _bigTreeAt(int c, int r, int maxTiles) {
  final bc = _floorDiv(c, kBigTreeBlock), br = _floorDiv(r, kBigTreeBlock);
  // a separate hash stream from the per-tile one, so which blocks grow a tree
  // is independent of what the tiles themselves rolled
  final h = _hash2(bc * 2 + 1, br * 2 + 1);
  if (h % 100 >= kBigTreePercent) return null; // this block has no big tree
  final span = kBigTreeBlock - 3;
  final ox = (h ~/ 100) % span + 1, oy = (h ~/ 700) % span + 1;
  if (c - bc * kBigTreeBlock != ox || r - br * kBigTreeBlock != oy) return null;
  return _bigTree(c, r, maxTiles);
}

/// A variant index in `[0, n)` for this tile that differs from the ones its two
/// already-decided neighbours rolled (#v35.1).
///
/// "Ayni tür kücük cali ve agaclarin, kayalarin aynisinin yanyana olmasini
/// istemiyorum" — with ten bushes a plain hash repeats side by side one time in
/// ten, and the eye finds every one of them, because two identical sprites
/// touching read as a tiling artefact rather than as a forest.
///
/// Compares against the neighbours' RAW roll, never their final value, so there
/// is no chain of dependencies and the result stays a pure function of the tile.
/// One level: differ from the two upstream neighbours' RAW rolls.
int _variant1(int c, int r, int n) {
  int raw(int cc, int rr) => (_hash2(cc, rr) ~/ 100) % n;
  var v = raw(c, r);
  final a = raw(c - 1, r), b = raw(c, r - 1);
  for (var guard = 0; (v == a || v == b) && guard < n; guard++) {
    v = (v + 1) % n;
  }
  return v;
}

int _variant(int c, int r, int n) {
  if (n <= 1) return 0;
  // Two levels, not one. Correcting against a neighbour's RAW roll leaves the
  // case where the neighbour was itself bumped INTO this tile's value, which
  // measured 2.9% of adjacent pairs — still roughly fifteen visible twins on a
  // screen. Comparing against the neighbour's once-corrected value instead
  // takes it to a fraction of a percent. It cannot be driven to exactly zero
  // without a scan order, and a scan order would stop this being a pure
  // function of the tile — which is the property that keeps the forest from
  // changing as the camera moves (#v34.12).
  var v = _variant1(c, r, n);
  final a = _variant1(c - 1, r, n), b = _variant1(c, r - 1, n);
  for (var guard = 0; (v == a || v == b) && guard < n; guard++) {
    v = (v + 1) % n;
  }
  return v;
}

/// Tree pool indices whose size passes [want], in order.
List<int> _treesOfSize(bool Function(int) want) => [
      for (var i = 0; i < kForestTrees; i++)
        if (want(kTreeTiles[i])) i,
    ];

String _treeId(int i) => 'tree_${i.toString().padLeft(2, '0')}';

/// Pick from a size class by VARIANT rather than by scanning forward from a
/// hash. The old `_treeOfSize` walked up from `pick % 20` to the next tree of
/// the right size, which bunched picks onto whichever index followed a long run
/// of wrong sizes — so the same silhouette turned up next to itself far more
/// often than one-in-eight. Indexing the eligible list directly spreads them
/// evenly and lets [_variant] keep neighbours apart.
String _treeOfSize(int c, int r, bool Function(int) want, String fallback) {
  final pool = _treesOfSize(want);
  if (pool.isEmpty) return fallback;
  return _treeId(pool[_variant(c, r, pool.length)]);
}

/// The 2-tile trees the whole forest is built from.
String _smallTree(int c, int r) => _treeOfSize(c, r, (t) => t == 2, 'tree_00');

/// One of the narrow 2-tile trees — see [kNarrowTrees].
String _narrowTree(int c, int r) =>
    _treeId(kNarrowTrees[_variant(c, r, kNarrowTrees.length)]);

/// A tree taller than the woods but no taller than [maxTiles].
String _bigTree(int c, int r, int maxTiles) =>
    _treeOfSize(c, r, (t) => t >= 3 && t <= maxTiles, 'tree_01');

/// Flat ambient palette per fence id as `(side, top, rail)`. The top face is a
/// touch brighter than the sides — light from the sky, baked to the geometry, so
/// it stays put as the camera yaws (a fixed sky glow, never a directional sun).
const Map<String, (int side, int top, int rail)> _fence3d = {
  'fence_wood': (0xFF8B5A2B, 0xFFA9743E, 0xFFA9743E),
  'fence_dark': (0xFF3D2814, 0xFF5A3A1E, 0xFF5A3A1E),
  'fence_stone': (0xFF6E6E6E, 0xFF9A9A9A, 0xFF9A9A9A),
};

/// The 8 screen-space corners of an upright box at garden [c] (tile units), with
/// a square footprint of half-width [half] tiles rising [height] tiles. Indices
/// 0..3 are the base ring (CW), 4..7 the matching top ring directly above. This
/// is the low-poly primitive every standing 3D object (fence posts now, trees /
/// houses next) is built from — real geometry that rotates correctly and keeps a
/// solid footprint from every angle, instead of a flat sprite that thins out.
List<Offset> boxCorners(Projector p, Offset c, double half, double height) {
  final base = <Offset>[
    p.projectGrid(Offset(c.dx - half, c.dy - half)),
    p.projectGrid(Offset(c.dx + half, c.dy - half)),
    p.projectGrid(Offset(c.dx + half, c.dy + half)),
    p.projectGrid(Offset(c.dx - half, c.dy + half)),
  ];
  return [...base, for (final b in base) b.translate(0, -height * p.t)];
}

// ---- sprite bank ------------------------------------------------------------

/// Decoded PNGs from assets/objects/, keyed by id. Critters are 8-frame
/// directional **atlases**; flowers (`flower_<id>`), the ground (`grass`), the
/// `forest` surround and every road are single tiles. Fences aren't loaded here
/// at all — they render as 3D meshes. Loaded once, reused for the scene.
class SpriteBank {
  final Map<String, ui.Image> images;
  const SpriteBank(this.images);

  ui.Image? grass() => images['grass'];
  ui.Image? forest() => images['forest'];
  ui.Image? tree() => images['tree'];
  ui.Image? forestProp(String id) => images[id]; // tree_NN / bush_NN / rock_NN
  ui.Image? object(String id) => images[id]; // roads
  /// Resolve a planted flower prop (which may carry a `~N` variant suffix, e.g.
  /// "gul~2") to its sprite, falling back to the base sprite if that variant isn't
  /// bundled (#v22).
  ui.Image? flower(String prop) {
    final i = prop.indexOf('~');
    if (i < 0) return images['flower_$prop'];
    final base = prop.substring(0, i);
    return images['flower_${base}_${prop.substring(i + 1)}'] ?? images['flower_$base'];
  }
  ui.Image? critter(String kind) => images[kind];

  static Future<SpriteBank> load() async {
    final out = <String, ui.Image>{};
    Future<void> grab(String key, String asset) async {
      final data = await rootBundle.load('assets/objects/$asset');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      out[key] = (await codec.getNextFrame()).image;
    }

    await Future.wait([
      grab('grass', 'grass.png'),
      grab('forest', 'forest.png'),
      grab('tree', 'tree.png'),
      for (var i = 0; i < kForestTrees; i++)
        grab('tree_${i.toString().padLeft(2, '0')}', 'tree_${i.toString().padLeft(2, '0')}.png'),
      for (var i = 0; i < kForestBushes; i++)
        grab('bush_${i.toString().padLeft(2, '0')}', 'bush_${i.toString().padLeft(2, '0')}.png'),
      for (var i = 0; i < kForestRocks; i++)
        grab('rock_${i.toString().padLeft(2, '0')}', 'rock_${i.toString().padLeft(2, '0')}.png'),
      for (final k in CritterSystem.kinds) grab(k, '$k.png'),
      for (final id in Placeables.roadIds) grab(id, '$id.png'),
      // fences render as low-poly 3D meshes, not sprites; their PNGs are only
      // used as shop thumbnails (loaded there via Image.asset).
      for (final f in Flowers.all) grab('flower_${f.id}', 'flower_${f.id}.png'),
      // multi-variant flowers also ship flower_<id>_0..n-1 (rose is the first, #v22)
      for (final f in Flowers.all)
        if (Flowers.variantsFor(f.id) > 1)
          for (var v = 0; v < Flowers.variantsFor(f.id); v++)
            grab('flower_${f.id}_$v', 'flower_${f.id}_$v.png'),
    ]);
    return SpriteBank(out);
  }
}

// ---- camera -----------------------------------------------------------------

/// Zoom + pan + yaw. [clamp] keeps the garden inside the viewport so it always
/// stays fixed on screen (you can't drag the map away).
class GardenCamera {
  double zoom;
  double panX;
  double panY;
  double yaw; // radians, rotation around the vertical axis

  GardenCamera({this.zoom = 1, this.panX = 0, this.panY = 0, this.yaw = 0});

  void reset() {
    zoom = 1;
    panX = 0;
    panY = 0;
    yaw = 0;
  }

  /// Bound pan to a roam radius around the plot: you can wander up to a plot-size
  /// into the surrounding (screen-filling) forest, but the garden can't be lost —
  /// bounded, not the infinite roam of older versions (#v18).
  void clamp(int cols, int rows, Size size) {
    final p = Projector.fit(cols, rows, this, size);
    final roam = (cols > rows ? cols : rows).toDouble();
    final maxX = (cols / 2 + roam) * p.t;
    final maxY = (rows / 2 + roam) * p.t * kVy;
    panX = panX.clamp(-maxX, maxX);
    panY = panY.clamp(-maxY, maxY);
  }
}

// ---- projection -------------------------------------------------------------

/// Maps garden coords (tile units, centred) → screen and back, with the camera's
/// yaw applied. Fits the whole plot in view at zoom 1; the inverse is exact so
/// taps land on the right tile from any rotation.
class Projector {
  final int cols;
  final int rows;
  final double t; // tile size in px (already includes zoom)
  final Offset center;
  final double yaw;
  late final double _cos = math.cos(yaw);
  late final double _sin = math.sin(yaw);

  Projector(this.cols, this.rows, this.t, this.center, this.yaw);

  /// Fit the plot into the viewport leaving a small forest margin (`kFitMargin`
  /// tiles); the surrounding forest is then drawn screen-filling on every visible
  /// tile, so it covers the whole portrait screen around the plot (#v18).
  static const double kFitMargin = 2.0;
  factory Projector.fit(int cols, int rows, GardenCamera cam, Size size) {
    final fitW = size.width / (cols + kFitMargin);
    final fitH = size.height / ((rows + kFitMargin) * kVy);
    final t = math.min(fitW, fitH) * cam.zoom;
    return Projector(cols, rows, t,
        Offset(size.width / 2 + cam.panX, size.height / 2 + cam.panY), cam.yaw);
  }

  static double slabFor(double t) => t * 0.32 + 6;

  double get planeW => cols * t;
  double get planeH => rows * t * kVy;

  /// Project a continuous garden coordinate (in tile units, plot centred at 0).
  Offset projectGrid(Offset g) {
    final rx = g.dx * _cos - g.dy * _sin;
    final ry = g.dx * _sin + g.dy * _cos;
    return Offset(center.dx + rx * t, center.dy + ry * t * kVy);
  }

  /// Project a garden coordinate raised [e] tile-heights off the ground. The
  /// camera tilt is fixed, so true vertical maps **straight up the screen** by
  /// `e * t` and is identical from every compass [yaw] — a post is equally tall
  /// from all sides (uniform sky light, no moving sun).
  Offset projectElevated(Offset g, double e) => projectGrid(g).translate(0, -e * t);

  /// Garden coordinate of tile (col,row)'s centre.
  Offset gridOf(int c, int r) =>
      Offset(c - (cols - 1) / 2.0, r - (rows - 1) / 2.0);
  /// Continuous garden coord for fractional (col,row).
  Offset gridOfD(double c, double r) => Offset(c - (cols - 1) / 2.0, r - (rows - 1) / 2.0);
  Offset ground(int c, int r) => projectGrid(gridOf(c, r));
  Offset groundIndex(int i) => ground(i % cols, i ~/ cols);

  /// Inverse of [ground]: continuous (col,row) in claimed-index space for a
  /// screen point — finds which tiles are visible so the forest can fill the
  /// whole screen (#1).
  Offset gridAt(Offset p) {
    final dx = (p.dx - center.dx) / t;
    final dy = (p.dy - center.dy) / (t * kVy);
    final gx = dx * _cos + dy * _sin;
    final gy = -dx * _sin + dy * _cos;
    return Offset(gx + (cols - 1) / 2.0, gy + (rows - 1) / 2.0);
  }

  /// Integer tile range (1-tile bleed) covering the whole screen, so the forest
  /// can be drawn on every visible tile around the plot (#v18).
  ({int minC, int maxC, int minR, int maxR}) visibleTileBounds(Size size) {
    final corners = [
      gridAt(const Offset(0, 0)),
      gridAt(Offset(size.width, 0)),
      gridAt(Offset(size.width, size.height)),
      gridAt(Offset(0, size.height)),
    ];
    var minC = double.infinity, maxC = -double.infinity, minR = double.infinity, maxR = -double.infinity;
    for (final c in corners) {
      minC = math.min(minC, c.dx); maxC = math.max(maxC, c.dx);
      minR = math.min(minR, c.dy); maxR = math.max(maxR, c.dy);
    }
    return (minC: minC.floor() - 1, maxC: maxC.ceil() + 1, minR: minR.floor() - 1, maxR: maxR.ceil() + 1);
  }

  int tileAt(Offset p) {
    final dx = (p.dx - center.dx) / t;
    final dy = (p.dy - center.dy) / (t * kVy);
    final gx = dx * _cos + dy * _sin; // inverse rotation
    final gy = -dx * _sin + dy * _cos;
    final c = (gx + (cols - 1) / 2.0).round();
    final r = (gy + (rows - 1) / 2.0).round();
    if (c < 0 || r < 0 || c >= cols || r >= rows) return -1;
    return r * cols + c;
  }

  /// The 4 plot corners in screen space (for the slab + bounds + grid), CW.
  List<Offset> corners() {
    final hx = cols / 2.0, hy = rows / 2.0;
    return [
      projectGrid(Offset(-hx, -hy)),
      projectGrid(Offset(hx, -hy)),
      projectGrid(Offset(hx, hy)),
      projectGrid(Offset(-hx, hy)),
    ];
  }

  /// Affine mapping garden coords → screen, so the ground layer can be drawn
  /// axis-aligned and the canvas handles yaw + squash.
  Float64List gridToScreen() {
    final m = Float64List(16);
    m[0] = t * _cos;
    m[1] = t * kVy * _sin;
    m[4] = -t * _sin;
    m[5] = t * kVy * _cos;
    m[10] = 1;
    m[12] = center.dx;
    m[13] = center.dy;
    m[15] = 1;
    return m;
  }
}

// ---- critters (garden-space) ------------------------------------------------

enum _CState { approach, hover, leave }

/// A tiny visiting creature (bee / butterfly / ladybug). It lives in **garden
/// coordinates** — so it rotates/zooms with the map — entering from a plot edge,
/// flying to a flower, hovering as if sniffing, then leaving and despawning.
class Critter {
  /// Hard cap on how long a critter may live, in seconds, regardless of state —
  /// guarantees one can never get stuck (e.g. among the trees) forever (#3).
  static const double maxLife = 18.0;

  final String kind;
  Offset pos; // garden coords (tile units)
  Offset target; // garden coords
  _CState state = _CState.approach;
  double timer = 0;
  double life = 0; // total seconds alive
  final double speed; // tiles/sec
  final double phase; // flight-wobble offset
  final double hoverFor;
  // how high up the plant this visit perches while hovering, as a fraction
  // of a tile — randomized per critter so visits land anywhere from near
  // the base to near the bloom, not always the same spot (#v31.17).
  final double perch;

  Critter(this.kind, this.pos, this.target, this.speed, this.phase, this.hoverFor, this.perch);

  /// On its way out of the garden — no longer visiting anything.
  bool get leaving => state == _CState.leave;
}

/// Owns the (at most 2) active critters and spawns them occasionally. Works
/// purely in garden coords; the painter projects each critter to the screen.
class CritterSystem {
  static const kinds = [
    'bee', 'butterfly', 'ladybug', // originals
    'ladybug_yellow', 'butterfly_monarch', 'butterfly_blue', 'bee_bumble', // #v23 fb
  ];
  static const maxActive = 2;

  final math.Random _r;
  final List<Critter> critters = [];
  double time = 0;
  double _spawnIn;

  CritterSystem([int? seed])
      : _r = math.Random(seed),
        _spawnIn = 2 {
    _spawnIn = 2 + _r.nextDouble() * 3;
  }

  /// [flowers] are flower-tile centres in garden coords; [n] is the plot size.
  void step(double dt, int n, List<Offset> flowers) {
    final d = dt.clamp(0.0, 0.05);
    time += d;
    _spawnIn -= d;
    final half = n / 2.0 + 0.8;
    if (_spawnIn <= 0) {
      _spawnIn = 6 + _r.nextDouble() * 8; // a visitor every ~6–14s
      if (critters.length < maxActive && flowers.isNotEmpty) {
        _spawn(half, flowers);
      }
    }
    for (final c in critters) {
      c.life += d;
      // The flower it came for may have been dug up mid-visit (#v34.4). The
      // target is captured once at spawn, so without this the critter flew to
      // — and then sniffed at — an empty patch of grass for its whole hover,
      // up to the 18s lifetime cap. Re-checked every frame against the CURRENT
      // list, which step() is already handed.
      if (!c.leaving && !_flowerStillThere(c.target, flowers)) _sendAway(c, half);
      _stepOne(c, d, half);
    }
    // despawn on exit OR once past the hard lifetime cap, so none can stick (#3)
    critters.removeWhere((c) =>
        c.life > Critter.maxLife ||
        (c.state == _CState.leave &&
            (c.pos.dx.abs() > half + 0.5 || c.pos.dy.abs() > half + 0.5)));
  }

  /// Is some flower still at (or very near) [target]?
  ///
  /// The tolerance covers `_spawn`'s ±0.35-tile landing jitter with a little
  /// slack; anything farther means the flower this critter chose is gone, not
  /// that it aimed loosely.
  static bool _flowerStillThere(Offset target, List<Offset> flowers) {
    for (final f in flowers) {
      if ((f - target).distance <= 0.75) return true;
    }
    return false;
  }

  /// Turn a critter around and send it out the nearest side.
  void _sendAway(Critter c, double half) {
    c.state = _CState.leave;
    c.timer = 0;
    final ex = c.pos.dx < 0 ? -(half + 1) : (half + 1);
    c.target = Offset(ex, c.pos.dy);
  }

  void _spawn(double half, List<Offset> flowers) {
    double rnd() => (_r.nextDouble() * 2 - 1) * half;
    final start = switch (_r.nextInt(4)) {
      0 => Offset(rnd(), -half),
      1 => Offset(half, rnd()),
      2 => Offset(rnd(), half),
      _ => Offset(-half, rnd()),
    };
    // land at a randomized spot NEAR the flower, not its exact tile centre
    // every time — a fixed target made every visit converge on the same
    // pixel, which read as snapping/teleporting rather than a real flight (#2).
    final flower = flowers[_r.nextInt(flowers.length)];
    final target = flower + Offset((_r.nextDouble() * 2 - 1) * 0.35, (_r.nextDouble() * 2 - 1) * 0.35);
    critters.add(Critter(
      kinds[_r.nextInt(kinds.length)],
      start,
      target,
      1.0 + _r.nextDouble() * 0.8, // tiles/sec
      _r.nextDouble() * math.pi * 2,
      2.0 + _r.nextDouble() * 2.5,
      0.20 + _r.nextDouble() * 0.65, // perch: near the base up to near the bloom (#v31.17)
    ));
  }

  void _stepOne(Critter c, double dt, double half) {
    c.timer += dt;
    final to = c.target - c.pos;
    final dist = to.distance;
    switch (c.state) {
      case _CState.approach:
        if (dist < 0.06) {
          c.state = _CState.hover;
          c.timer = 0;
        } else {
          // decelerate over the final stretch — full speed until ~0.6 tiles
          // out, then ease down instead of flying at full speed and stopping
          // dead 0.18 tiles short of the flower, which read as a "jump onto
          // the plant" together with the lift kicking in (#v32).
          final ease = 0.2 + 0.8 * math.min(1.0, dist / 0.6);
          c.pos += to / dist * c.speed * ease * dt;
        }
        break;
      case _CState.hover:
        if (c.timer >= c.hoverFor) _sendAway(c, half);
        break;
      case _CState.leave:
        // always progress, even if the exit target is ~where we already are,
        // so a critter can never freeze in place (#3)
        final dir = dist > 1e-3 ? to / dist : const Offset(1, 0);
        c.pos += dir * c.speed * 1.4 * dt;
        break;
    }
  }
}

// ---- painter ----------------------------------------------------------------

/// Sampling offset for the FOREST backdrop (#v35.0). The woods are a pure
/// function of the tile, so drawing them from far away in world space gives a
/// screen of deep forest — no clearing, no undergrowth rim, and no plot-shaped
/// hole in the middle — without a second code path to keep in step with this
/// one. Any large offset does; this one is arbitrary.
const int kForestBackdropOffset = 4096;

/// Roughly how many trees the FOREST backdrop fits across the screen.
///
/// The framing is set from this rather than from a camera zoom, because zoom
/// runs through `Projector.fit`, which is sized to the PLOT — so the same zoom
/// gave a different tree size as the garden grew, and on an 11-wide plot it
/// came out as a close-up of a dozen trees instead of the carpet of them the
/// reference image shows. Trees are 2 tiles wide, so the tile size is
/// `width / (2 * this)` and the result is the same on any screen (#v35.1).
const int kForestBackdropTreesAcross = 20;

class GardenPainter extends CustomPainter {
  final Garden garden;
  final GardenCamera cam;
  final SpriteBank sprites;
  final CritterSystem critterSystem;
  final bool customizing;
  final int groundColor;
  final int soilColor;

  /// Draw only the woods, from [kForestBackdropOffset] away — the "forest"
  /// home backdrop, a canopy seen from above with no garden in it.
  final bool forestOnly;

  GardenPainter({
    required this.garden,
    required this.cam,
    required this.sprites,
    required this.critterSystem,
    required this.customizing,
    required this.groundColor,
    required this.soilColor,
    required Listenable repaint,
    this.forestOnly = false,
  }) : super(repaint: repaint);

  double get time => critterSystem.time;
  int get _cols => garden.cols;
  int get _rows => garden.rows;

  @override
  void paint(Canvas canvas, Size size) {
    // One screen-filling 2.5D world (#1): the claimed plot is the grass clearing;
    // the projector is sized to the plot, and the forest is drawn over every
    // visible tile outside it, so the woods fill the whole screen at any pan/zoom.
    // The FOREST backdrop frames by tree size, not by the plot (see
    // kForestBackdropTreesAcross) — Projector.fit is sized to the clearing, so
    // through it the same zoom means a different tree size on every garden.
    final p = forestOnly
        ? Projector(
            _cols,
            _rows,
            size.width / (2.0 * kForestBackdropTreesAcross),
            Offset(size.width / 2, size.height / 2),
            cam.yaw)
        : Projector.fit(_cols, _rows, cam, size);
    final t = p.t;
    final slab = Projector.slabFor(t);

    // claimed plot corners (the plot is centred at the world centre, so its
    // half-extents are simply ±cols/2, ±rows/2 in centred-grid units)
    final hx = _cols / 2.0, hy = _rows / 2.0;
    final cs = [
      p.projectGrid(Offset(-hx, -hy)),
      p.projectGrid(Offset(hx, -hy)),
      p.projectGrid(Offset(hx, hy)),
      p.projectGrid(Offset(-hx, hy)),
    ];

    // 0) forest floor — dark woodland ground over the whole screen so the
    //    garden is a clearing critters drift into.
    //
    //    #v34.10: the forest is world props again. #v34.9 made it a static
    //    screen-space frame, which did stop the rotation pop but read as
    //    wallpaper — "bahce dönüyor baska birsey dönmüyor". It turns with the
    //    camera like it used to; what the user did NOT want was the woods
    //    behaving like the garden's own flowers, which is handled by keeping
    //    them out of the depth-sorted prop list (see below).
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF12301A));

    // FOREST backdrop: the woods and nothing else (#v35.0).
    if (forestOnly) {
      _paintWoods(canvas, p, size);
      return;
    }

    final standing = <(double, void Function())>[]; // (depthY, paint) — garden props

    // 1) soil slab — extrude each claimed-plot edge downward for 2.5D thickness.
    final soil = Paint()..color = Color(soilColor);
    for (var i = 0; i < 4; i++) {
      final a = cs[i], b = cs[(i + 1) % 4];
      canvas.drawPath(
          Path()
            ..moveTo(a.dx, a.dy)
            ..lineTo(b.dx, b.dy)
            ..lineTo(b.dx, b.dy + slab)
            ..lineTo(a.dx, a.dy + slab)
            ..close(),
          soil);
    }

    // 2) grass + flat roads, clipped to the claimed plot, under the yaw+squash
    //    affine — rotates cleanly. (The claimed region is centred, so its rect in
    //    centred-grid units is exactly [-cols/2..cols/2]×[-rows/2..rows/2].)
    final plot = Path()
      ..moveTo(cs[0].dx, cs[0].dy)
      ..lineTo(cs[1].dx, cs[1].dy)
      ..lineTo(cs[2].dx, cs[2].dy)
      ..lineTo(cs[3].dx, cs[3].dy)
      ..close();
    canvas.save();
    canvas.clipPath(plot);
    canvas.transform(p.gridToScreen());
    final gridRect = Rect.fromLTWH(-hx, -hy, _cols.toDouble(), _rows.toDouble());
    final grass = sprites.grass();
    if (grass != null) {
      paintImage(
        canvas: canvas,
        rect: gridRect,
        image: grass,
        fit: BoxFit.none,
        repeat: ImageRepeat.repeat,
        scale: grass.width.toDouble(), // one grass tile == one garden unit
        filterQuality: FilterQuality.none,
        alignment: Alignment.topLeft,
      );
    } else {
      canvas.drawRect(gridRect, Paint()..color = Color(groundColor));
    }
    _paintRoads(canvas);
    canvas.restore();

    // crisp plot outline
    canvas.drawPath(
        plot,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Color(soilColor).withValues(alpha: 0.7));

    // a few wild decorative blooms scattered on empty grass tiles (#v18)
    _paintGrassFlowers(canvas, p);

    // 3) customize gridlines over the claimed plot.
    if (customizing) _paintGrid(canvas, p);

    // 4) the woods, then the garden's own standing things.
    //
    //    The woods paint ON TOP of the clearing, as their own depth-sorted
    //    layer under the garden's props. #v34.12 briefly painted them
    //    underneath, which did make the outline mathematically untouchable —
    //    and was wrong: "agaclar bahcenin altinda kaliyor ne anladim bu isten".
    //    A tree standing in front of the clearing that vanishes behind it is a
    //    worse artefact than the one it was fixing. The line is kept clean by
    //    the undergrowth ring instead (see kUndergrowthTiles): nothing within
    //    reach of the plot is tall enough to lean over it in the first place.
    _paintWoods(canvas, p, size);

    //    Then claimed props + the fence rails between them. Fences are low-poly
    //    3D posts/rails; flowers are flat billboards. Rails share this same sort
    //    (keyed by the midpoint of the two posts they link) instead of always
    //    painting in an earlier fixed pass, so a flower correctly passes behind
    //    a nearer rail/post instead of always drawing over it (#v31.18).
    for (var r = 0; r < _rows; r++) {
      for (var c = 0; c < _cols; c++) {
        final prop = garden.propAt(r * _cols + c);
        if (prop == null) continue;
        final anchor = p.ground(c, r);
        if (Placeables.isFence(prop)) {
          standing.add((anchor.dy, () => _paintFencePost(canvas, p, c, r, prop)));
        } else {
          // flowers stand still — no wind sway (#v20 item 2)
          standing.add(
              (anchor.dy, () => _paintBillboard(canvas, sprites.flower(prop), anchor, p.t)));
        }
      }
    }
    _collectFenceRails(canvas, p, standing);
    for (final i in stableDepthOrder(standing.map((s) => s.$1).toList(growable: false))) {
      standing[i].$2();
    }

    // 5) critters on top of everything (projected from claimed garden coords)
    _paintCritters(canvas, p, t);
  }

  /// The forest — every tile outside the plot that can reach the screen, sorted
  /// back-to-front among themselves.
  ///
  /// Kept in its own layer instead of merged into the garden's `standing` sort
  /// (#v34.10): the woods are scenery, so they can never interleave with — or
  /// pop in front of — a flower or a fence. That is the "orman cicekler gibi
  /// kamerayi takip etmesin" part. The trees still turn with the world, they
  /// just take no part in the garden's own depth sort.
  void _paintWoods(Canvas canvas, Projector p, Size size) {
    final vb = p.visibleTileBounds(size);
    // Scan past the viewport far enough that a tree whose GROUND tile is off
    // screen still paints its canopy into view (#v34.12). Without this the top
    // of the screen was a row of flat-cut trunks — "agaclarin kafasi kesik" —
    // because the tile that would have grown the tree standing up there was
    // never visited at all. One tile of up-screen travel costs at most 1/kVy
    // tiles of grid travel, so this is the worst case for the tallest tree.
    // Purely extra hash lookups: anything that lands off screen is culled below
    // before it reaches the paint list.
    final tallest = kTreeTiles.reduce((a, b) => a > b ? a : b);
    final bleed = (tallest * 1.05 / kVy).ceil();
    final woods = <(double, void Function())>[];
    final off = forestOnly ? kForestBackdropOffset : 0;
    for (var r = vb.minR - bleed; r <= vb.maxR + bleed; r++) {
      for (var c = vb.minC - bleed; c <= vb.maxC + bleed; c++) {
        final fp = forestPropAt(c + off, r + off, _cols, _rows); // null inside the plot
        if (fp == null) continue;
        final anchor = p.ground(c, r);
        final h = forestPropHeight(fp), w = forestPropWidth(fp);
        if (anchor.dy < 0 || anchor.dy - h * p.t > size.height) continue;
        final halfW = w * p.t / 2;
        if (anchor.dx + halfW < 0 || anchor.dx - halfW > size.width) continue;
        woods.add((anchor.dy,
            () => _paintBillboard(canvas, sprites.forestProp(fp), anchor, p.t,
                height: h, width: w)));
      }
    }
    for (final i in stableDepthOrder(woods.map((w) => w.$1).toList(growable: false))) {
      woods[i].$2();
    }
  }

  // ---- decorative grass daisies (#v19) --------------------------------------
  int _grassFlowerHash(int c, int r) {
    var h = (c * 0x1f1f1f1f) ^ (r * 0x2c2c2c2c) ^ 0x5bd1e995;
    h ^= h >> 15;
    return h & 0x7fffffff;
  }

  /// Scatter **sparse daisies** on empty grass tiles (no planted prop / road),
  /// so the clearing has life without looking like a quilt. Deterministic, so
  /// they don't shimmer between frames (#v19).
  void _paintGrassFlowers(Canvas canvas, Projector p) {
    for (var r = 0; r < _rows; r++) {
      for (var c = 0; c < _cols; c++) {
        if (garden.tiles.containsKey(r * _cols + c)) continue; // skip planted/road
        final h = _grassFlowerHash(c, r);
        if (h % 100 >= 5) continue; // ~5% of empty tiles — sparse
        _paintBloom(canvas, p.ground(c, r), p.t, kGrassBloomPetals[grassBloomTint(h)]);
      }
    }
  }


  /// A small **flat** pixel daisy lying on the grass — not a billboard object;
  /// matches the 2D flowered-grass look the user sent (#v20). [petals] is the
  /// petal colour; the eye stays yellow so a coloured bloom still reads as the
  /// same flower in a different colour (#v34.14).
  void _paintBloom(Canvas canvas, Offset a, double t, int petals) {
    final s = t * 0.085;
    final petal = Paint()..color = Color(petals);
    final eye = Paint()..color = const Color(0xFFF2C94C);
    void px(double dx, double dy, Paint p) => canvas.drawRect(
        Rect.fromCenter(center: a.translate(dx, dy * kVy), width: s, height: s * kVy), p);
    px(0, -s, petal); // petals, flattened onto the ground by kVy
    px(0, s, petal);
    px(-s, 0, petal);
    px(s, 0, petal);
    px(0, 0, eye); // yellow centre
  }

  void _paintRoads(Canvas canvas) {
    for (var r = 0; r < _rows; r++) {
      for (var c = 0; c < _cols; c++) {
        final id = garden.groundAt(r * _cols + c);
        if (id == null) continue;
        final img = sprites.object(id);
        final dst = Rect.fromCenter(
            center: Offset(c - (_cols - 1) / 2.0, r - (_rows - 1) / 2.0), width: 1, height: 1);
        if (img != null) {
          canvas.drawImageRect(
              img,
              Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
              dst,
              Paint()..filterQuality = FilterQuality.none);
        } else {
          canvas.drawRect(dst, Paint()..color = const Color(0xFFB7A687));
        }
      }
    }
  }

  /// Raised 3D rails between adjacent fence posts. A post links to **any** fence
  /// neighbour regardless of material (#1), so a wood fence joins a stone one.
  /// Each tile only draws toward its E and S neighbour (so every shared edge is
  /// drawn once). Each rail is a flat ribbon at a fixed height in garden space,
  /// so it rotates with the map and keeps a steady thickness from every angle —
  /// no more vanishing into a thin antenna under rotation.
  ///
  /// Every rail is split into TWO HALVES, each appended to the shared
  /// `standing` depth-sort keyed just behind its own post ([railHalfDepth]).
  /// The v31.18 single midpoint key crossed its own posts' depths during
  /// rotation, flipping the whole rail in front of / behind a post in one
  /// frame ("the fence suddenly changes direction"). A half pinned behind its
  /// own post can never flip against it, and both halves share one colour and
  /// elevation so the midpoint seam is invisible whichever paints first (#v32).
  void _collectFenceRails(
      Canvas canvas, Projector p, List<(double, void Function())> standing) {
    bool fence(int idx) =>
        idx >= 0 && idx < _cols * _rows && Placeables.isFence(garden.propAt(idx) ?? '');
    for (var r = 0; r < _rows; r++) {
      for (var c = 0; c < _cols; c++) {
        final index = r * _cols + c;
        final id = garden.propAt(index);
        if (id == null || !Placeables.isFence(id)) continue;
        final rail = Color(_fence3d[id]!.$3);
        final a = p.gridOf(c, r);
        void link(int nc, int nr) {
          final b = p.gridOf(nc, nr);
          final m = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
          void half(Offset from, Offset to, double postDy) {
            standing.add((railHalfDepth(postDy), () {
              for (final e in const [0.50, 0.28]) {
                _fillQuad(canvas, p.projectElevated(from, e + 0.05), p.projectElevated(to, e + 0.05),
                    p.projectElevated(to, e - 0.05), p.projectElevated(from, e - 0.05), rail);
              }
            }));
          }
          half(a, m, p.ground(c, r).dy);
          half(m, b, p.ground(nc, nr).dy);
        }
        if (c < _cols - 1 && fence(r * _cols + c + 1)) link(c + 1, r);
        if (r < _rows - 1 && fence((r + 1) * _cols + c)) link(c, r + 1);
      }
    }
  }

  /// One fence as a low-poly 3D post (the first object on the reusable mesh
  /// pipeline): an upright [boxCorners] box with a brighter top face. The four
  /// side faces share one flat colour, so their draw order is irrelevant; the
  /// top is drawn last so it always reads correctly however the box is turned.
  void _paintFencePost(Canvas canvas, Projector p, int c, int r, String id) {
    final pal = _fence3d[id]!;
    final gc = p.gridOf(c, r);
    final box = boxCorners(p, gc, 0.10, 0.66);
    for (var i = 0; i < 4; i++) {
      final j = (i + 1) % 4;
      _fillQuad(canvas, box[i], box[j], box[j + 4], box[i + 4], Color(pal.$1));
    }
    _fillQuad(canvas, box[4], box[5], box[6], box[7], Color(pal.$2));
  }

  /// Fill a flat-shaded quad (one low-poly face). Pixel-crisp, no anti-aliasing.
  void _fillQuad(Canvas canvas, Offset a, Offset b, Offset c, Offset d, Color color) {
    canvas.drawPath(
        Path()
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy)
          ..lineTo(c.dx, c.dy)
          ..lineTo(d.dx, d.dy)
          ..close(),
        Paint()
          ..color = color
          ..isAntiAlias = false);
  }

  void _paintGrid(Canvas canvas, Projector p) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0x66FFFFFF);
    final hx = _cols / 2.0, hy = _rows / 2.0;
    for (var i = 0; i <= _cols; i++) {
      final g = -hx + i;
      canvas.drawLine(p.projectGrid(Offset(g, -hy)), p.projectGrid(Offset(g, hy)), line);
    }
    for (var i = 0; i <= _rows; i++) {
      final g = -hy + i;
      canvas.drawLine(p.projectGrid(Offset(-hx, g)), p.projectGrid(Offset(hx, g)), line);
    }
  }

  /// Draw a flower as a flat, camera-facing billboard. Flowers are radially
  /// symmetric, so one sprite looks the same from every angle — no directional
  /// atlas to slice, no wasted memory, no fake snapping.
  void _paintBillboard(Canvas canvas, ui.Image? img, Offset anchor, double t,
      {double height = 1.05, double width = 0.9, double sway = 0}) {
    if (img == null) return;
    final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    final h = t * height;
    final bottom = anchor.dy + t * kVy * 0.30;
    final dst = Rect.fromCenter(
        center: Offset(anchor.dx + sway, bottom - h / 2), width: t * width, height: h);
    canvas.drawImageRect(img, src, dst, Paint()..filterQuality = FilterQuality.none);
  }

  void _paintCritters(Canvas canvas, Projector p, double t) {
    // critters scale with the tile (zoom) so they grow as you zoom in, instead of
    // staying one pinned size (#v23); a small floor keeps them visible when far out.
    final s = math.max(10.0, t * 0.42);
    for (final c in critterSystem.critters) {
      final img = sprites.critter(c.kind);
      final amp = c.kind.startsWith('ladybug') ? 0.6 : 2.2; // ladybugs barely bob
      final bob = math.sin((time + c.phase) * 9) * amp;
      // fly low most of the time; while visiting a flower, ease up to ITS OWN
      // randomized height on the plant (base→bloom) instead of every visit
      // snapping to the same fixed spot near the top (#v25 item4, #v31.17).
      // Glide smoothly over the transition instead of snapping instantly the
      // moment it arrives/leaves — the instant jump was still visible even
      // once the landing height itself was randomized (#v31.21).
      const travelLift = 0.25;
      const ease = 0.4; // seconds to glide between travel height and perch
      final k = (c.timer / ease).clamp(0.0, 1.0);
      final liftFrac = switch (c.state) {
        _CState.approach => travelLift,
        _CState.hover => travelLift + (c.perch - travelLift) * k,
        _CState.leave => c.perch + (travelLift - c.perch) * k,
      };
      final lift = t * liftFrac;
      final at = p.projectGrid(c.pos).translate(0, bob - lift);
      final rect = Rect.fromCenter(center: at, width: s, height: s);
      if (img != null) {
        // always the same facet (frame 0) so the critter keeps ONE shape and
        // doesn't morph as the camera rotates (#v20). The atlas is still 8-wide.
        const frame = 0;
        final cellW = img.width / kDirFrames;
        canvas.drawImageRect(
            img,
            Rect.fromLTWH(frame * cellW, 0, cellW, img.height.toDouble()),
            rect,
            Paint()..filterQuality = FilterQuality.none);
      } else {
        canvas.drawRect(rect.deflate(s * 0.3), Paint()..color = const Color(0xFF2B2B2B));
      }
    }
  }

  @override
  bool shouldRepaint(covariant GardenPainter old) => true; // driven by ticker
}
