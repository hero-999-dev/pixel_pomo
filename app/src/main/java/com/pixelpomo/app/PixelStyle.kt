package com.pixelpomo.app

import android.graphics.drawable.ClipDrawable
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.LayerDrawable
import android.util.TypedValue
import android.view.Gravity
import android.content.res.Resources

/**
 * Builds Pixel Pomo's hard-edged, drop-shadow drawables in code so their colors can come
 * from the active [PixelTheme]. These replace the static `btn_pixel*.xml` / `progress_pixel.xml`
 * drawables, which had colors baked in and so couldn't be re-themed at runtime.
 */
object PixelStyle {

    private const val OFFSET_DP = 6f   // hard drop-shadow offset
    private const val STROKE_DP = 3f   // border thickness

    private fun dp(res: Resources, value: Float): Int =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, value, res.displayMetrics).toInt()

    /**
     * A pixel button: a black/dark shadow square offset to the bottom-right, with the
     * colored face (fill + border) on the top-left — no rounded corners.
     */
    fun button(res: Resources, fill: Int, border: Int, shadow: Int): Drawable {
        val off = dp(res, OFFSET_DP)
        val stroke = dp(res, STROKE_DP)

        val shadowShape = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            setColor(shadow)
        }
        val faceShape = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            setColor(fill)
            setStroke(stroke, border)
        }

        return LayerDrawable(arrayOf(shadowShape, faceShape)).apply {
            setLayerInset(0, off, off, 0, 0)   // shadow pushed down-right
            setLayerInset(1, 0, 0, off, off)   // face pulled up-left
        }
    }

    /**
     * A pixel progress bar drawable: a panel track with a border and a clipped fill.
     * Assign to `ProgressBar.progressDrawable`; the bar's `progress` drives the clip.
     */
    fun progress(res: Resources, track: Int, trackBorder: Int, fill: Int): LayerDrawable {
        val stroke = dp(res, STROKE_DP)

        val background = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            setColor(track)
            setStroke(stroke, trackBorder)
        }
        val fillShape = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            setColor(fill)
        }
        val clip = ClipDrawable(fillShape, Gravity.START, ClipDrawable.HORIZONTAL)

        return LayerDrawable(arrayOf(background, clip)).apply {
            setId(0, android.R.id.background)
            setId(1, android.R.id.progress)
        }
    }
}
