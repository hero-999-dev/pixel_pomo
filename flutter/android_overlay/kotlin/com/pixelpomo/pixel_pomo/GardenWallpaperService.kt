package com.pixelpomo.pixel_pomo

import android.graphics.Canvas
import android.service.wallpaper.WallpaperService
import android.view.Choreographer
import android.view.SurfaceHolder

/**
 * The live wallpaper: a Choreographer-driven render loop that draws the user's
 * saved garden (via [GardenData] + [GardenRenderer]) at the framing they picked.
 * Stops drawing when the wallpaper isn't visible (battery), and re-reads the
 * saved garden each time it becomes visible so new plantings show up (v15).
 */
class GardenWallpaperService : WallpaperService() {
    override fun onCreateEngine(): Engine = GardenEngine()

    inner class GardenEngine : WallpaperService.Engine(), Choreographer.FrameCallback {
        private var visible = false
        private var xOffset = 0.5f
        private val startNanos = System.nanoTime()
        private val data = GardenData(this@GardenWallpaperService)
        private val renderer = GardenRenderer(data)

        override fun onVisibilityChanged(v: Boolean) {
            visible = v
            if (v) {
                data.reload()
                Choreographer.getInstance().postFrameCallback(this)
            } else {
                Choreographer.getInstance().removeFrameCallback(this)
            }
        }

        override fun onOffsetsChanged(
            xOffset: Float, yOffset: Float, xStep: Float, yStep: Float,
            xPixels: Int, yPixels: Int
        ) { this.xOffset = xOffset }

        override fun onSurfaceDestroyed(holder: SurfaceHolder) {
            visible = false
            Choreographer.getInstance().removeFrameCallback(this)
        }

        override fun doFrame(frameTimeNanos: Long) {
            if (!visible) return
            val holder = surfaceHolder
            var canvas: Canvas? = null
            try {
                canvas = holder.lockCanvas()
                if (canvas != null) drawFrame(canvas, (frameTimeNanos - startNanos) / 1e9)
            } finally {
                if (canvas != null) holder.unlockCanvasAndPost(canvas)
            }
            // ~30 fps cap.
            Choreographer.getInstance().postFrameCallbackDelayed(this, 33)
        }

        private fun drawFrame(canvas: Canvas, timeSec: Double) {
            renderer.draw(canvas, canvas.width, canvas.height, timeSec, xOffset)
        }
    }
}
