package com.pixelpomo.pixel_pomo

import android.graphics.Bitmap
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Shader
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.random.Random

private const val KVY = 0.60

/**
 * Draws a calm, animated version of the garden at the framing the user saved
 * (yaw/zoom/pan), mirroring the Dart Projector. Forest props fill the visible
 * border; planted flowers stand still; fences are low-poly 3D meshes (posts +
 * linking rails) like the app, not flat cards; one bee drifts; parallax follows
 * home-screen swipes (v15, fences ported #v20).
 */
class GardenRenderer(private val data: GardenData) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { isFilterBitmap = false }
    private val shadow = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0x33000000 }
    private val quad = Paint().apply { isAntiAlias = false } // pixel-crisp low-poly faces

    // Flat (side, top, rail) colours per fence id — mirrors the in-app `_fence3d`.
    private val fence3d = mapOf(
        "fence_wood" to Triple(Color.rgb(0x8B, 0x5A, 0x2B), Color.rgb(0xA9, 0x74, 0x3E), Color.rgb(0xA9, 0x74, 0x3E)),
        "fence_dark" to Triple(Color.rgb(0x3D, 0x28, 0x14), Color.rgb(0x5A, 0x3A, 0x1E), Color.rgb(0x5A, 0x3A, 0x1E)),
        "fence_stone" to Triple(Color.rgb(0x6E, 0x6E, 0x6E), Color.rgb(0x9A, 0x9A, 0x9A), Color.rgb(0x9A, 0x9A, 0x9A)))

    private var t = 1.0; private var cx = 0.0; private var cy = 0.0
    private var cosY = 1.0; private var sinY = 0.0; private var cols = 10; private var rows = 16

    // Up to MAX_ACTIVE visiting creatures (bee/butterfly/ladybug), mirroring the
    // in-app CritterSystem so the wallpaper shows the same variety as the garden,
    // not one lone bee. They come and go, so the screen isn't always buggy (#v20).
    private val critters = CritterSim()
    private var lastT = 0.0

    private data class Item(val depth: Double, val x: Double, val y: Double, val id: String, val flower: Boolean, val c: Int, val r: Int)

    fun draw(canvas: Canvas, w: Int, h: Int, timeSec: Double, xOffset: Float) {
        cols = data.cols; rows = data.rows
        val cam = data.cam
        val fitW = w / (cols + 2.0) // plot-based fit + small forest margin, matches the in-app Projector (#v18)
        val fitH = h / ((rows + 2.0) * KVY)
        t = min(fitW, fitH) * cam.zoom
        val parallax = (xOffset - 0.5) * t * 1.5 // gentle home-screen scroll
        cx = w / 2.0 + cam.panXFrac * t + parallax
        cy = h / 2.0 + cam.panYFrac * t
        cosY = cos(cam.yaw); sinY = sin(cam.yaw)

        canvas.drawColor(Color.rgb(0x12, 0x30, 0x1A)) // forest floor
        fillClearing(canvas)
        drawGrassFlowers(canvas) // a few wild blooms on empty grass (#v18)
        drawFenceRails(canvas)   // raised rails between adjacent posts, under the standing items (#v20)

        val items = ArrayList<Item>()
        val flowers = ArrayList<Pair<Double, Double>>() // planted-flower garden coords, for the critters
        val vb = visibleBounds(w, h) // forest on every visible tile → fills the screen (#v18)
        for (r in vb[2]..vb[3]) {
            for (c in vb[0]..vb[1]) {
                val inGarden = c in 0 until cols && r in 0 until rows
                if (inGarden) {
                    val idx = r * cols + c
                    data.groundAt(idx)?.let { drawRoad(canvas, c, r, it) }
                    val prop = data.propAt(idx) ?: continue
                    val (x, y) = ground(c, r)
                    val flower = isFlower(prop)
                    if (flower) flowers.add(gridXY(c, r))
                    items.add(Item(y, x, y, prop, flower, c, r))
                } else {
                    val fp = forestPropAt(c, r) ?: continue
                    val (x, y) = ground(c, r)
                    items.add(Item(y, x, y, fp, false, c, r))
                }
            }
        }
        items.sortBy { it.depth }
        for (it in items) {
            // fences are 3D posts; everything else is a still billboard — no wind (#v20)
            if (isFence(it.id)) {
                drawFencePost(canvas, it.c, it.r, it.id)
            } else {
                // match the in-app _paintBillboard dimensions so flowers aren't thick (#v22):
                // flowers 1.05h×0.9w, trees/bushes 1.2×1.05, rocks 0.6×0.8.
                val (ht, wd) = when {
                    it.id.startsWith("rock_") -> 0.6 to 0.8
                    it.flower -> 1.05 to 0.9
                    else -> 1.2 to 1.05
                }
                val bmp = if (it.flower) flowerBitmap(it.id) else data.bitmap(spriteFor(it.id))
                billboard(canvas, bmp, it.x, it.y, ht, wd)
            }
        }
        drawCritters(canvas, timeSec, flowers)
    }

    private fun gridXY(c: Int, r: Int) = (c - (cols - 1) / 2.0) to (r - (rows - 1) / 2.0)

    /// Project a continuous centered-garden coord to screen (mirrors Projector.projectGrid).
    private fun projGrid(gx: Double, gy: Double): Pair<Double, Double> {
        val rx = gx * cosY - gy * sinY; val ry = gx * sinY + gy * cosY
        return (cx + rx * t) to (cy + ry * t * KVY)
    }

    /// Inverse of projGrid → continuous (col,row); used to find the visible tiles.
    private fun gridAt(px: Double, py: Double): Pair<Double, Double> {
        val dx = (px - cx) / t; val dy = (py - cy) / (t * KVY)
        val gx = dx * cosY + dy * sinY; val gy = -dx * sinY + dy * cosY
        return (gx + (cols - 1) / 2.0) to (gy + (rows - 1) / 2.0)
    }

    /// Tile range covering the screen [minC, maxC, minR, maxR] (1-tile bleed).
    private fun visibleBounds(w: Int, h: Int): IntArray {
        val cs = listOf(gridAt(0.0, 0.0), gridAt(w.toDouble(), 0.0),
            gridAt(w.toDouble(), h.toDouble()), gridAt(0.0, h.toDouble()))
        val xs = cs.map { it.first }; val ys = cs.map { it.second }
        return intArrayOf(
            floor(xs.min()).toInt() - 1, ceil(xs.max()).toInt() + 1,
            floor(ys.min()).toInt() - 1, ceil(ys.max()).toInt() + 1)
    }

    private fun ground(c: Int, r: Int): Pair<Double, Double> {
        val (gx, gy) = gridXY(c, r)
        return projGrid(gx, gy)
    }

    // Tile the real grass.png across the claimed plot under the same projection the
    // app uses (Projector.gridToScreen), so the wallpaper's clearing has the app's
    // textured grass instead of a flat green slab (#v22). Falls back to a flat fill.
    private fun fillClearing(canvas: Canvas) {
        val hx = cols / 2.0; val hy = rows / 2.0
        val path = Path()
        arrayOf(-hx to -hy, hx to -hy, hx to hy, -hx to hy).forEachIndexed { i, (gx, gy) ->
            val (x, y) = projGrid(gx, gy)
            if (i == 0) path.moveTo(x.toFloat(), y.toFloat()) else path.lineTo(x.toFloat(), y.toFloat())
        }
        path.close()
        val grass = data.bitmap("grass")
        if (grass == null) {
            paint.color = Color.rgb(0x57, 0xA6, 0x36) // grass base (fallback)
            canvas.drawPath(path, paint)
            return
        }
        canvas.save()
        canvas.clipPath(path)
        // affine garden(tile)->screen, mirroring Projector.gridToScreen (column form).
        val m = Matrix()
        m.setValues(floatArrayOf(
            (t * cosY).toFloat(), (-t * sinY).toFloat(), cx.toFloat(),
            (t * KVY * sinY).toFloat(), (t * KVY * cosY).toFloat(), cy.toFloat(),
            0f, 0f, 1f))
        canvas.concat(m)
        // one grass tile == one garden unit (scale bitmap px -> unit), tiled.
        val shader = BitmapShader(grass, Shader.TileMode.REPEAT, Shader.TileMode.REPEAT)
        shader.setLocalMatrix(Matrix().apply { setScale(1f / grass.width, 1f / grass.height) })
        val gp = Paint().apply { isFilterBitmap = false; this.shader = shader }
        canvas.drawRect((-hx).toFloat(), (-hy).toFloat(), hx.toFloat(), hy.toFloat(), gp)
        canvas.restore()
    }

    // draw the actual road sprite flat on the tile (was a gray square — looked bad #v20)
    private fun drawRoad(canvas: Canvas, c: Int, r: Int, road: String) {
        val (x, y) = ground(c, r)
        val hs = t / 2
        val dst = RectF((x - hs).toFloat(), (y - (hs * KVY)).toFloat(),
            (x + hs).toFloat(), (y + (hs * KVY)).toFloat())
        val bmp = data.bitmap(road)
        if (bmp != null) {
            canvas.drawBitmap(bmp, null, dst, paint)
        } else {
            paint.color = Color.rgb(0x88, 0x88, 0x88)
            canvas.drawRect(dst, paint)
        }
    }

    // sparse white daisies on empty grass tiles — mirrors the in-app
    // _paintGrassFlowers (64-bit hash so the same tiles bloom both places) (#v19).
    private fun grassFlowerHash(c: Int, r: Int): Int {
        var h = (c.toLong() * 0x1f1f1f1f) xor (r.toLong() * 0x2c2c2c2c) xor 0x5bd1e995L
        h = h xor (h shr 15)
        return (h and 0x7fffffffL).toInt()
    }

    private fun drawGrassFlowers(canvas: Canvas) {
        for (r in 0 until rows) {
            for (c in 0 until cols) {
                val idx = r * cols + c
                if (data.groundAt(idx) != null || data.propAt(idx) != null) continue // only empty grass
                if (grassFlowerHash(c, r) % 100 >= 5) continue // ~5% — sparse
                val (x, y) = ground(c, r)
                drawBloom(canvas, x, y)
            }
        }
    }

    // a small FLAT pixel daisy lying on the grass (white petals + yellow eye) —
    // mirrors the in-app _paintBloom (#v20), not a billboard object.
    private fun drawBloom(canvas: Canvas, x: Double, y: Double) {
        val s = t * 0.085
        fun petal(dx: Double, dy: Double, color: Int) {
            paint.color = color
            val px = x + dx
            val py = y + dy * KVY
            canvas.drawRect((px - s / 2).toFloat(), (py - s * KVY / 2).toFloat(),
                (px + s / 2).toFloat(), (py + s * KVY / 2).toFloat(), paint)
        }
        petal(0.0, -s, Color.WHITE)
        petal(0.0, s, Color.WHITE)
        petal(-s, 0.0, Color.WHITE)
        petal(s, 0.0, Color.WHITE)
        petal(0.0, 0.0, Color.rgb(0xF2, 0xC9, 0x4C)) // yellow eye
    }

    private fun billboard(canvas: Canvas, bmp: Bitmap?, x: Double, y: Double, heightTiles: Double, widthTiles: Double) {
        canvas.drawOval((x - t * 0.35).toFloat(), (y - t * 0.12).toFloat(),
            (x + t * 0.35).toFloat(), (y + t * 0.12).toFloat(), shadow) // contact shadow
        if (bmp == null) return
        val ph = t * heightTiles
        val pw = t * widthTiles // fixed fraction like the app (was aspect-derived → flowers looked thick #v22)
        val left = (x - pw / 2).toFloat(); val top = (y - ph).toFloat()
        canvas.drawBitmap(bmp, null, RectF(left, top, (left + pw).toFloat(), (top + ph).toFloat()), paint)
    }

    private fun isFence(id: String) = id.startsWith("fence_")

    private fun fenceAt(idx: Int): Boolean {
        if (idx < 0 || idx >= cols * rows) return false
        return isFence(data.propAt(idx) ?: return false)
    }

    /// Project a centered-garden coord raised by `e` tiles (mirrors projectElevated).
    private fun projElev(gx: Double, gy: Double, e: Double): Pair<Double, Double> {
        val (sx, sy) = projGrid(gx, gy)
        return sx to (sy - e * t)
    }

    /// Fill one flat-shaded low-poly face (no anti-aliasing) — mirrors `_fillQuad`.
    private fun fillQuad(canvas: Canvas, a: Pair<Double, Double>, b: Pair<Double, Double>,
                         c: Pair<Double, Double>, d: Pair<Double, Double>, color: Int) {
        val path = Path()
        path.moveTo(a.first.toFloat(), a.second.toFloat())
        path.lineTo(b.first.toFloat(), b.second.toFloat())
        path.lineTo(c.first.toFloat(), c.second.toFloat())
        path.lineTo(d.first.toFloat(), d.second.toFloat())
        path.close()
        quad.color = color
        canvas.drawPath(path, quad)
    }

    /// 8 corners (4 base, 4 top) of an upright box — mirrors `boxCorners`.
    private fun boxCorners(gx: Double, gy: Double, half: Double, height: Double): Array<Pair<Double, Double>> {
        val base = arrayOf(
            projGrid(gx - half, gy - half), projGrid(gx + half, gy - half),
            projGrid(gx + half, gy + half), projGrid(gx - half, gy + half))
        return arrayOf(base[0], base[1], base[2], base[3],
            base[0].first to base[0].second - height * t, base[1].first to base[1].second - height * t,
            base[2].first to base[2].second - height * t, base[3].first to base[3].second - height * t)
    }

    /// Raised rails between adjacent fence posts — mirrors `_paintFenceRails`. Each
    /// tile only links toward its E and S neighbour so every shared edge draws once.
    private fun drawFenceRails(canvas: Canvas) {
        for (r in 0 until rows) {
            for (c in 0 until cols) {
                val id = data.propAt(r * cols + c) ?: continue
                if (!isFence(id)) continue
                val rail = fence3d[id]?.third ?: continue
                val (ax, ay) = gridXY(c, r)
                fun link(nc: Int, nr: Int) {
                    val (bx, by) = gridXY(nc, nr)
                    for (e in doubleArrayOf(0.50, 0.28)) {
                        fillQuad(canvas, projElev(ax, ay, e + 0.05), projElev(bx, by, e + 0.05),
                            projElev(bx, by, e - 0.05), projElev(ax, ay, e - 0.05), rail)
                    }
                }
                if (c < cols - 1 && fenceAt(r * cols + c + 1)) link(c + 1, r)
                if (r < rows - 1 && fenceAt((r + 1) * cols + c)) link(c, r + 1)
            }
        }
    }

    /// One fence as a low-poly 3D post (upright box + brighter top) — mirrors
    /// `_paintFencePost`. The four side faces share one colour; the top draws last.
    private fun drawFencePost(canvas: Canvas, c: Int, r: Int, id: String) {
        val pal = fence3d[id] ?: return
        val (gx, gy) = gridXY(c, r)
        val (groundX, groundY) = projGrid(gx, gy)
        val scy = groundY + t * KVY * 0.10
        canvas.drawOval((groundX - t * 0.17).toFloat(), (scy - t * KVY * 0.15).toFloat(),
            (groundX + t * 0.17).toFloat(), (scy + t * KVY * 0.15).toFloat(), shadow)
        val box = boxCorners(gx, gy, 0.10, 0.66)
        for (i in 0 until 4) {
            val j = (i + 1) % 4
            fillQuad(canvas, box[i], box[j], box[j + 4], box[i + 4], pal.first)
        }
        fillQuad(canvas, box[4], box[5], box[6], box[7], pal.second)
    }

    // Advance the visiting creatures one frame, then draw each one. Mirrors the
    // in-app _paintCritters: a flat frame-0 facet (one shape, no camera-angle
    // morphing #v20), lifted a quarter-tile off the ground with a gentle per-kind
    // bob (ladybugs barely bob, fliers flutter).
    private fun drawCritters(canvas: Canvas, timeSec: Double, flowers: List<Pair<Double, Double>>) {
        val dt = (if (lastT == 0.0) 0.0 else timeSec - lastT).coerceIn(0.0, 0.1)
        lastT = timeSec
        critters.step(dt, maxOf(cols, rows), flowers)

        val s = (t * 0.42).coerceIn(12.0, 30.0).toFloat()
        for (c in critters.list) {
            val bmp = data.bitmap(c.kind) ?: continue
            val amp = if (c.kind == "ladybug") 0.6 else 2.2
            val bob = sin((critters.time + c.phase) * 9) * amp
            val (sx, sy) = projGrid(c.x, c.y)
            val cellW = bmp.width / 8 // atlases are 8-wide; always frame 0 (#v20)
            val src = Rect(0, 0, cellW, bmp.height)
            val px = sx.toFloat(); val py = (sy + bob - t * 0.25).toFloat() // hover above ground
            canvas.drawBitmap(bmp, src, RectF(px - s / 2, py - s / 2, px + s / 2, py + s / 2), paint)
        }
    }

    private enum class CState { APPROACH, HOVER, LEAVE }

    /** One visiting creature in garden coords (tile units) — mirrors Dart's Critter. */
    private class Critter(
        val kind: String, var x: Double, var y: Double, var tx: Double, var ty: Double,
        val speed: Double, val phase: Double, val hoverFor: Double,
    ) {
        var state = CState.APPROACH
        var timer = 0.0
        var life = 0.0
    }

    /**
     * Faithful port of the in-app CritterSystem (garden_engine.dart): up to
     * [MAX_ACTIVE] creatures that drift in from a random plot edge, fly to a planted
     * flower, hover, then leave and despawn, with a gap (no bug on screen) between
     * spawns. This is why the wallpaper now shows the same bee/butterfly/ladybug
     * variety as the garden, instead of one lone bee.
     *
     * ADD A CREATURE to the wallpaper later (a new bug, or a pet/NPC that visits
     * flowers): drop its PNG in assets/objects/ and add its id to [kinds] here AND
     * to CritterSystem.kinds in garden_engine.dart — nothing else. Every kind shares
     * this movement; only the per-kind bob in drawCritters differs. A genuinely
     * different movement (a pet that walks the ground, an NPC that follows a path)
     * is a NEW CState branch added once in each engine — bounded, not a rewrite.
     * (The wallpaper is a separate native renderer because hosting the real Flutter
     * engine on a wallpaper Surface was tried and abandoned in v20; this hand-kept
     * mirror is the supported path, so new entities must be added in both places.)
     */
    private class CritterSim {
        val list = ArrayList<Critter>()
        var time = 0.0
            private set
        private var spawnIn = 2.0 + Random.nextDouble() * 3.0

        fun step(dt: Double, n: Int, flowers: List<Pair<Double, Double>>) {
            val d = dt.coerceIn(0.0, 0.05)
            time += d
            spawnIn -= d
            val half = n / 2.0 + 0.8
            if (spawnIn <= 0.0) {
                spawnIn = 6.0 + Random.nextDouble() * 8.0 // a visitor every ~6–14s
                if (list.size < MAX_ACTIVE && flowers.isNotEmpty()) spawn(half, flowers)
            }
            for (c in list) { c.life += d; stepOne(c, d, half) }
            // despawn on exit OR past the hard lifetime cap, so none can stick (#3)
            list.removeAll { c ->
                c.life > MAX_LIFE ||
                    (c.state == CState.LEAVE && (abs(c.x) > half + 0.5 || abs(c.y) > half + 0.5))
            }
        }

        private fun spawn(half: Double, flowers: List<Pair<Double, Double>>) {
            fun rnd() = (Random.nextDouble() * 2 - 1) * half
            val start = when (Random.nextInt(4)) {
                0 -> rnd() to -half
                1 -> half to rnd()
                2 -> rnd() to half
                else -> -half to rnd()
            }
            val target = flowers[Random.nextInt(flowers.size)]
            list.add(Critter(
                kinds[Random.nextInt(kinds.size)], start.first, start.second, target.first, target.second,
                1.0 + Random.nextDouble() * 0.8, Random.nextDouble() * Math.PI * 2, 2.0 + Random.nextDouble() * 2.5))
        }

        private fun stepOne(c: Critter, dt: Double, half: Double) {
            c.timer += dt
            val tox = c.tx - c.x; val toy = c.ty - c.y
            val dist = sqrt(tox * tox + toy * toy)
            when (c.state) {
                CState.APPROACH ->
                    if (dist < 0.18) { c.state = CState.HOVER; c.timer = 0.0 }
                    else { c.x += tox / dist * c.speed * dt; c.y += toy / dist * c.speed * dt }
                CState.HOVER ->
                    if (c.timer >= c.hoverFor) {
                        c.state = CState.LEAVE; c.timer = 0.0
                        c.tx = if (c.x < 0) -(half + 1) else (half + 1); c.ty = c.y
                    }
                CState.LEAVE -> {
                    // always progress, even if the exit ~= here, so it can't freeze (#3)
                    val dx = if (dist > 1e-3) tox / dist else 1.0
                    val dy = if (dist > 1e-3) toy / dist else 0.0
                    c.x += dx * c.speed * 1.4 * dt; c.y += dy * c.speed * 1.4 * dt
                }
            }
        }

        companion object {
            // The wallpaper's creatures. Mirror of CritterSystem.kinds (garden_engine.dart).
            val kinds = listOf("bee", "butterfly", "ladybug")
            const val MAX_ACTIVE = 2
            const val MAX_LIFE = 18.0
        }
    }

    // a planted flower id (gul/papatya/…) — NOT a road/fence/forest prop, which load
    // by their own filename. Excluding tree_/bush_/rock_ here was the "only shadows"
    // bug: forest props were looked up as the nonexistent flower_tree_NN.png (#v17).
    private fun isFlower(id: String) = id.isNotEmpty() &&
        !id.startsWith("road_") && !id.startsWith("fence_") &&
        !id.startsWith("tree_") && !id.startsWith("bush_") && !id.startsWith("rock_")

    private fun spriteFor(id: String) = if (isFlower(id)) "flower_$id" else id

    // Resolve a flower prop (may carry a ~N variant suffix, e.g. "gul~2") to its
    // bitmap, falling back to the base sprite if that variant isn't bundled (#v22).
    private fun flowerBitmap(id: String): Bitmap? {
        val i = id.indexOf('~')
        if (i < 0) return data.bitmap("flower_$id")
        val base = id.substring(0, i)
        return data.bitmap("flower_${base}_" + id.substring(i + 1)) ?: data.bitmap("flower_$base")
    }

    // 64-bit to match Dart's int math, so the forest border matches the in-app view.
    private fun hash2(c: Int, r: Int): Int {
        var hsh = (c.toLong() * 73856093L) xor (r.toLong() * 19349663L)
        hsh = hsh xor (hsh shr 13)
        return (hsh and 0x7fffffffL).toInt()
    }

    private fun forestPropAt(c: Int, r: Int): String? {
        val hsh = hash2(c, r); val bucket = hsh % 100; val pick = hsh / 100
        fun id(kind: String, n: Int) = "${kind}_" + (pick % n).toString().padStart(2, '0')
        return when {
            bucket < 18 -> null
            bucket < 80 -> id("tree", 20)
            bucket < 95 -> id("bush", 10)
            else -> id("rock", 5)
        }
    }
}
