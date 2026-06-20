package com.pixelpomo.pixel_pomo

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import android.graphics.RectF
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin

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
        for (r in -BORDER until rows + BORDER) {
            for (c in -BORDER until cols + BORDER) {
                val inGarden = c in 0 until cols && r in 0 until rows
                if (inGarden) {
                    val idx = r * cols + c
                    data.groundAt(idx)?.let { drawRoad(canvas, c, r) }
                    val prop = data.propAt(idx) ?: continue
                    val (x, y) = ground(c, r)
                    items.add(Item(y, x, y, prop, isFlower(prop)))
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
        drawCritter(canvas, w, h, timeSec)
    }

    private fun ground(c: Int, r: Int): Pair<Double, Double> {
        val gx = c - (cols - 1) / 2.0; val gy = r - (rows - 1) / 2.0
        val rx = gx * cosY - gy * sinY; val ry = gx * sinY + gy * cosY
        return (cx + rx * t) to (cy + ry * t * KVY)
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

    private fun drawCritter(canvas: Canvas, w: Int, h: Int, timeSec: Double) {
        val bmp = data.bitmap("bee") ?: return
        val frameW = bmp.height // 8-frame square strip; use frame 0
        val src = Rect(0, 0, frameW, bmp.height)
        val px = (w * (0.5 + 0.4 * sin(timeSec * 0.5))).toFloat()
        val py = (h * (0.35 + 0.05 * sin(timeSec * 1.3))).toFloat()
        val s = (t * 0.5).toFloat()
        canvas.drawBitmap(bmp, src, RectF(px - s / 2, py - s / 2, px + s / 2, py + s / 2), paint)
    }

    private fun isFlower(id: String) =
        id.isNotEmpty() && !id.startsWith("road_") && !id.startsWith("fence_")

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
