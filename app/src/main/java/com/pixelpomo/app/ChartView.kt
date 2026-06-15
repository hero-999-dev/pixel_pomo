package com.pixelpomo.app

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import android.util.AttributeSet
import android.view.View
import kotlin.math.max

/**
 * A tiny, dependency-free pixel chart for the stats screen. Renders the selected month's data
 * in one of three styles the user picks: **BAR** and **PIE** plot per-label minutes (each slice/
 * bar in that label's chosen color — so [LabelColors] flow straight into the graph), while
 * **LINE** plots the month's per-day minutes as a trend. Hard-edged (no anti-aliased fills) to
 * match the retro look; purely presentational, so it isn't unit-tested (the data feeding it is).
 */
class ChartView @JvmOverloads constructor(
    context: Context, attrs: AttributeSet? = null
) : View(context, attrs) {

    enum class Mode { BAR, LINE, PIE }

    /** One per-label slice/bar: its display name, minutes, and color. */
    data class Entry(val label: String, val value: Int, val color: Int)

    var mode: Mode = Mode.BAR
    private var labelEntries: List<Entry> = emptyList()
    private var daySeries: IntArray = IntArray(0)

    var lineColor: Int = 0xFF46E08A.toInt()
    var axisColor: Int = 0xFF8E8E8E.toInt()
    var textColor: Int = 0xFFF4F4F4.toInt()
    var pixelTypeface: Typeface? = null

    private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
    private val text = Paint(Paint.ANTI_ALIAS_FLAG)

    fun setData(labelEntries: List<Entry>, daySeries: IntArray, mode: Mode) {
        this.labelEntries = labelEntries
        this.daySeries = daySeries
        this.mode = mode
        invalidate()
    }

    private fun dp(v: Float) = v * resources.displayMetrics.density

    private fun hasData(): Boolean =
        if (mode == Mode.LINE) daySeries.any { it > 0 } else labelEntries.any { it.value > 0 }

    override fun onDraw(canvas: Canvas) {
        val w = width.toFloat()
        val h = height.toFloat()
        text.typeface = pixelTypeface
        text.color = textColor

        if (!hasData()) {
            text.textAlign = Paint.Align.CENTER
            text.textSize = dp(9f)
            canvas.drawText(context.getString(R.string.chart_no_data), w / 2f, h / 2f, text)
            return
        }
        when (mode) {
            Mode.BAR -> drawBars(canvas, w, h)
            Mode.LINE -> drawLine(canvas, w, h)
            Mode.PIE -> drawPie(canvas, w, h)
        }
    }

    private fun drawBars(canvas: Canvas, w: Float, h: Float) {
        val padL = dp(8f); val padR = dp(8f)
        val padTop = dp(10f); val padBottom = dp(26f)
        val plotW = w - padL - padR
        val plotH = h - padTop - padBottom
        val maxVal = max(1, labelEntries.maxOf { it.value })
        val n = labelEntries.size
        val slot = plotW / n
        val barW = slot * 0.62f

        stroke.color = axisColor; stroke.strokeWidth = dp(2f)
        canvas.drawLine(padL, padTop + plotH, padL + plotW, padTop + plotH, stroke)

        text.textAlign = Paint.Align.CENTER
        text.textSize = dp(7f)
        labelEntries.forEachIndexed { i, e ->
            val cx = padL + slot * i + slot / 2f
            val barH = plotH * (e.value.toFloat() / maxVal)
            val left = cx - barW / 2f
            val top = padTop + plotH - barH
            fill.color = e.color
            canvas.drawRect(left, top, left + barW, padTop + plotH, fill)
            text.color = textColor
            canvas.drawText(shortLabel(e.label), cx, h - dp(14f), text)
            canvas.drawText(StatsAggregator.formatMinutes(e.value), cx, top - dp(3f), text)
        }
    }

    private fun drawLine(canvas: Canvas, w: Float, h: Float) {
        val padL = dp(10f); val padR = dp(10f)
        val padTop = dp(12f); val padBottom = dp(18f)
        val plotW = w - padL - padR
        val plotH = h - padTop - padBottom
        val maxVal = max(1, daySeries.max())
        val n = daySeries.size

        stroke.color = axisColor; stroke.strokeWidth = dp(2f)
        canvas.drawLine(padL, padTop + plotH, padL + plotW, padTop + plotH, stroke)

        val path = Path()
        fun x(i: Int) = padL + plotW * (if (n <= 1) 0f else i.toFloat() / (n - 1))
        fun y(v: Int) = padTop + plotH * (1f - v.toFloat() / maxVal)
        daySeries.forEachIndexed { i, v ->
            val px = x(i); val py = y(v)
            if (i == 0) path.moveTo(px, py) else path.lineTo(px, py)
        }
        stroke.color = lineColor; stroke.strokeWidth = dp(2.5f)
        canvas.drawPath(path, stroke)
        // mark each day point
        fill.color = lineColor
        daySeries.forEachIndexed { i, v -> canvas.drawCircle(x(i), y(v), dp(2f), fill) }

        text.textAlign = Paint.Align.LEFT; text.textSize = dp(7f); text.color = textColor
        canvas.drawText("1", padL, h - dp(4f), text)
        text.textAlign = Paint.Align.RIGHT
        canvas.drawText(n.toString(), padL + plotW, h - dp(4f), text)
    }

    private fun drawPie(canvas: Canvas, w: Float, h: Float) {
        val total = labelEntries.sumOf { it.value }.toFloat()
        val legendW = w * 0.42f
        val size = minOf(h - dp(16f), (w - legendW) - dp(16f))
        val cx = dp(8f) + (w - legendW - dp(8f)) / 2f
        val cy = h / 2f
        val rect = RectF(cx - size / 2f, cy - size / 2f, cx + size / 2f, cy + size / 2f)

        var start = -90f
        labelEntries.forEach { e ->
            val sweep = 360f * (e.value / total)
            fill.color = e.color
            canvas.drawArc(rect, start, sweep, true, fill)
            start += sweep
        }

        // legend on the right
        text.textAlign = Paint.Align.LEFT
        text.textSize = dp(7f)
        val lx = w - legendW + dp(6f)
        var ly = cy - (labelEntries.size * dp(13f)) / 2f + dp(8f)
        labelEntries.forEach { e ->
            fill.color = e.color
            canvas.drawRect(lx, ly - dp(7f), lx + dp(8f), ly + dp(1f), fill)
            text.color = textColor
            val pct = Math.round(100f * e.value / total)
            canvas.drawText("${shortLabel(e.label)} $pct%", lx + dp(12f), ly, text)
            ly += dp(13f)
        }
    }

    private fun shortLabel(label: String): String =
        if (label.length <= 6) label else label.take(6)
}
