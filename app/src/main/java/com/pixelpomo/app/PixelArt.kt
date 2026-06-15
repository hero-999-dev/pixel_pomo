package com.pixelpomo.app

import android.content.res.Resources
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable

/**
 * Renders a [Flower]'s pixel grid into a crisp (non-antialiased) [Drawable] by painting one
 * solid rectangle per cell. Kept separate from the pure [Flowers] data so that data stays
 * JVM-testable.
 */
object PixelArt {

    fun flower(res: Resources, flower: Flower, cellPx: Int): Drawable {
        val cols = flower.grid.maxOf { it.length }
        val rows = flower.grid.size
        val bmp = Bitmap.createBitmap(cols * cellPx, rows * cellPx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val paint = Paint().apply { isAntiAlias = false }

        for (r in 0 until rows) {
            val line = flower.grid[r]
            for (col in line.indices) {
                val color = when (line[col]) {
                    'P' -> flower.petal
                    'C' -> flower.center
                    'S', 'L' -> Flowers.GREEN
                    else -> continue
                }
                paint.color = color
                val x = col * cellPx
                val y = r * cellPx
                canvas.drawRect(
                    x.toFloat(), y.toFloat(),
                    (x + cellPx).toFloat(), (y + cellPx).toFloat(),
                    paint
                )
            }
        }
        return BitmapDrawable(res, bmp)
    }
}
