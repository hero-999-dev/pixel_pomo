package com.pixelpomo.pixel_pomo

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import android.graphics.RectF
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

    // bee lifecycle (#v19): a gap with NO bee, then it flies in from the top edge,
    // visits a few flowers, leaves off the top, then gaps again — like the in-app
    // CritterSystem, so there isn't always a bug on screen.
    private var beeAlive = false
    private var beeTimer = 3.0      // seconds until the next spawn (while absent)
    private var beeVisitsLeft = 0  // <0 means it's leaving
    private var beeGx = 0.0; private var beeGy = 0.0
    private var beeTx = 0.0; private var beeTy = 0.0
    private var beeHover = 0.0
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
        val flowers = ArrayList<Pair<Double, Double>>() // planted-flower garden coords, for the bee
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
            if (isFence(it.id)) drawFencePost(canvas, it.c, it.r, it.id)
            else billboard(canvas, data.bitmap(spriteFor(it.id)), it.x, it.y,
                if (it.id.startsWith("rock_")) 0.6 else 1.2)
        }
        updateBee(canvas, timeSec, flowers)
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

    private fun fillClearing(canvas: Canvas) {
        val hx = cols / 2.0; val hy = rows / 2.0
        val corners = arrayOf(-hx to -hy, hx to -hy, hx to hy, -hx to hy)
        val path = Path()
        corners.forEachIndexed { i, (gx, gy) ->
            val rx = gx * cosY - gy * sinY; val ry = gx * sinY + gy * cosY
            val x = (cx + rx * t).toFloat(); val y = (cy + ry * t * KVY).toFloat()
            if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
        }
        path.close()
        paint.color = Color.rgb(0x57, 0xA6, 0x36) // grass base
        canvas.drawPath(path, paint)
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

    private fun billboard(canvas: Canvas, bmp: Bitmap?, x: Double, y: Double, heightTiles: Double) {
        canvas.drawOval((x - t * 0.35).toFloat(), (y - t * 0.12).toFloat(),
            (x + t * 0.35).toFloat(), (y + t * 0.12).toFloat(), shadow) // contact shadow
        if (bmp == null) return
        val ph = t * heightTiles
        val pw = ph * bmp.width / bmp.height
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

    // A bee with a come-and-go lifecycle: a gap with no bug, then it flies in from
    // the top, visits a few flowers, leaves off the top, then gaps again — like the
    // in-app CritterSystem (frameForAngle facing). Not always on screen (#v19).
    private fun updateBee(canvas: Canvas, timeSec: Double, flowers: List<Pair<Double, Double>>) {
        val bmp = data.bitmap("bee") ?: return
        val dt = (if (lastT == 0.0) 0.0 else timeSec - lastT).coerceIn(0.0, 0.1)
        lastT = timeSec

        val topEdge = -rows / 2.0 - 2.0
        if (!beeAlive) {
            beeTimer -= dt
            if (beeTimer > 0.0) return // absent during the gap — nothing drawn
            beeAlive = true
            beeVisitsLeft = 2 + Random.nextInt(3) // visit 2–4 spots
            beeGx = Random.nextDouble(-cols / 2.0, cols / 2.0); beeGy = topEdge - 1.0 // enter from the top
            val t0 = nextTarget(flowers); beeTx = t0.first; beeTy = t0.second
            beeHover = 0.0
        }

        val dx = beeTx - beeGx; val dy = beeTy - beeGy
        val dist = sqrt(dx * dx + dy * dy)
        if (dist < 0.15) {
            beeHover -= dt
            if (beeHover <= 0.0) {
                beeVisitsLeft--
                if (beeVisitsLeft <= 0) { // done visiting → head off the top edge
                    beeTx = Random.nextDouble(-cols / 2.0, cols / 2.0); beeTy = topEdge - 2.0
                    beeVisitsLeft = -1
                } else {
                    val nt = nextTarget(flowers); beeTx = nt.first; beeTy = nt.second
                    beeHover = 1.0 + Random.nextDouble() * 1.5
                }
            }
        } else {
            val speed = 2.4 // tiles/sec
            beeGx += dx / dist * speed * dt
            beeGy += dy / dist * speed * dt
        }
        if (beeVisitsLeft < 0 && beeGy <= topEdge) { // left the scene → despawn, gap before next
            beeAlive = false
            beeTimer = 5.0 + Random.nextDouble() * 9.0 // 5–14s with no bug
            return
        }

        val (sx, sy) = projGrid(beeGx, beeGy)
        // always the same facet so the bug keeps ONE shape regardless of camera angle (#v20)
        val cellW = bmp.width / 8
        val src = Rect(0, 0, cellW, bmp.height)
        val hover = t * 0.7 + sin(timeSec * 6) * t * 0.05 // above the flower + a gentle bob
        val px = sx.toFloat(); val py = (sy - hover).toFloat()
        val s = (t * 0.55).toFloat()
        canvas.drawBitmap(bmp, src, RectF(px - s / 2, py - s / 2, px + s / 2, py + s / 2), paint)
    }

    private fun nextTarget(flowers: List<Pair<Double, Double>>): Pair<Double, Double> =
        if (flowers.isNotEmpty()) flowers[Random.nextInt(flowers.size)]
        else Random.nextDouble(-cols / 2.0, cols / 2.0) to Random.nextDouble(-rows / 2.0, rows / 2.0)

    // a planted flower id (gul/papatya/…) — NOT a road/fence/forest prop, which load
    // by their own filename. Excluding tree_/bush_/rock_ here was the "only shadows"
    // bug: forest props were looked up as the nonexistent flower_tree_NN.png (#v17).
    private fun isFlower(id: String) = id.isNotEmpty() &&
        !id.startsWith("road_") && !id.startsWith("fence_") &&
        !id.startsWith("tree_") && !id.startsWith("bush_") && !id.startsWith("rock_")

    private fun spriteFor(id: String) = if (isFlower(id)) "flower_$id" else id

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
