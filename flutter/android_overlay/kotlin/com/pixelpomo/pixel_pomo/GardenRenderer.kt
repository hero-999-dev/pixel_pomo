package com.pixelpomo.pixel_pomo

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import android.graphics.RectF
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.random.Random

private const val KVY = 0.60
private const val BORDER = 4

/**
 * Draws a calm, animated version of the garden at the framing the user saved
 * (yaw/zoom/pan), mirroring the Dart Projector — but simplified: no 3D fence
 * meshes, no gestures. Forest props fill the fixed border ring; planted flowers
 * sway; one bee drifts; parallax follows home-screen swipes (v15).
 */
class GardenRenderer(private val data: GardenData) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { isFilterBitmap = false }
    private val shadow = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0x33000000 }

    private var t = 1.0; private var cx = 0.0; private var cy = 0.0
    private var cosY = 1.0; private var sinY = 0.0; private var cols = 10; private var rows = 16

    // bee state in centered garden coords — flies between planted flowers, hovers,
    // then picks the next, like the in-app CritterSystem (#v17).
    private var beeReady = false
    private var beeGx = 0.0; private var beeGy = 0.0
    private var beeTx = 0.0; private var beeTy = 0.0
    private var beeHover = 0.0
    private var lastT = 0.0

    private data class Item(val depth: Double, val x: Double, val y: Double, val id: String, val flower: Boolean)

    fun draw(canvas: Canvas, w: Int, h: Int, timeSec: Double, xOffset: Float) {
        cols = data.cols; rows = data.rows
        val cam = data.cam
        val fitW = w / (cols + 2.0 * BORDER + 0.5)
        val fitH = h / ((rows + 2.0 * BORDER + 0.5) * KVY)
        t = min(fitW, fitH) * cam.zoom
        val parallax = (xOffset - 0.5) * t * 1.5 // gentle home-screen scroll
        cx = w / 2.0 + cam.panXFrac * t + parallax
        cy = h / 2.0 + cam.panYFrac * t
        cosY = cos(cam.yaw); sinY = sin(cam.yaw)

        canvas.drawColor(Color.rgb(0x12, 0x30, 0x1A)) // forest floor
        fillClearing(canvas)

        val items = ArrayList<Item>()
        val flowers = ArrayList<Pair<Double, Double>>() // planted-flower garden coords, for the bee
        for (r in -BORDER until rows + BORDER) {
            for (c in -BORDER until cols + BORDER) {
                val inGarden = c in 0 until cols && r in 0 until rows
                if (inGarden) {
                    val idx = r * cols + c
                    data.groundAt(idx)?.let { drawRoad(canvas, c, r) }
                    val prop = data.propAt(idx) ?: continue
                    val (x, y) = ground(c, r)
                    val flower = isFlower(prop)
                    if (flower) flowers.add(gridXY(c, r))
                    items.add(Item(y, x, y, prop, flower))
                } else {
                    val fp = forestPropAt(c, r) ?: continue
                    val (x, y) = ground(c, r)
                    items.add(Item(y, x, y, fp, false))
                }
            }
        }
        items.sortBy { it.depth }
        for (it in items) {
            val sway = if (it.flower) sin(timeSec * 1.6 + it.x * 0.03) * t * 0.04 else 0.0
            billboard(canvas, data.bitmap(spriteFor(it.id)), it.x + sway, it.y,
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

    private fun drawRoad(canvas: Canvas, c: Int, r: Int) {
        val (x, y) = ground(c, r)
        paint.color = Color.rgb(0x88, 0x88, 0x88)
        val hs = (t / 2)
        canvas.drawRect((x - hs).toFloat(), (y - hs * KVY).toFloat(),
            (x + hs).toFloat(), (y + hs * KVY).toFloat(), paint)
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

    // A bee that flies between planted flowers in garden space, hovering at each
    // (mirrors the in-app CritterSystem feel + frameForAngle facing) instead of a
    // screen-space sine sway (#v17).
    private fun updateBee(canvas: Canvas, timeSec: Double, flowers: List<Pair<Double, Double>>) {
        val bmp = data.bitmap("bee") ?: return
        val dt = (if (lastT == 0.0) 0.0 else timeSec - lastT).coerceIn(0.0, 0.1)
        lastT = timeSec
        if (!beeReady) {
            beeReady = true
            val s0 = nextTarget(flowers)
            beeGx = s0.first; beeGy = s0.second; beeTx = beeGx; beeTy = beeGy; beeHover = 1.0
        }
        val dx = beeTx - beeGx; val dy = beeTy - beeGy
        val dist = sqrt(dx * dx + dy * dy)
        if (dist < 0.12) {
            beeHover -= dt
            if (beeHover <= 0.0) {
                val nt = nextTarget(flowers); beeTx = nt.first; beeTy = nt.second
                beeHover = 1.0 + Random.nextDouble() * 1.5
            }
        } else {
            val speed = 2.2 // tiles/sec
            beeGx += dx / dist * speed * dt
            beeGy += dy / dist * speed * dt
        }
        val (sx, sy) = projGrid(beeGx, beeGy)
        val (ax, ay) = projGrid(beeGx + dx, beeGy + dy) // look-ahead → screen-space heading
        val frame = if (dist < 0.15) 0 else frameForAngle(atan2(ay - sy, ax - sx))
        val cellW = bmp.width / 8
        val src = Rect(frame * cellW, 0, (frame + 1) * cellW, bmp.height)
        val hover = t * 0.7 + sin(timeSec * 6) * t * 0.05 // above the flower + a gentle bob
        val px = sx.toFloat(); val py = (sy - hover).toFloat()
        val s = (t * 0.55).toFloat()
        canvas.drawBitmap(bmp, src, RectF(px - s / 2, py - s / 2, px + s / 2, py + s / 2), paint)
    }

    private fun nextTarget(flowers: List<Pair<Double, Double>>): Pair<Double, Double> =
        if (flowers.isNotEmpty()) flowers[Random.nextInt(flowers.size)]
        else Random.nextDouble(-cols / 2.0, cols / 2.0) to Random.nextDouble(-rows / 2.0, rows / 2.0)

    // mirrors Dart frameForAngle: an 8-way facet from a screen-space heading.
    private fun frameForAngle(a: Double): Int {
        val k = Math.round(a / (2 * Math.PI) * 8).toInt() % 8
        return (k + 8) % 8
    }

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
