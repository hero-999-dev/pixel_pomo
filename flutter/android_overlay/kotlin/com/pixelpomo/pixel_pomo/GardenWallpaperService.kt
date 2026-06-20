package com.pixelpomo.pixel_pomo

import android.graphics.Canvas
import android.graphics.Color
import android.service.wallpaper.WallpaperService
import android.view.Choreographer
import android.view.SurfaceHolder

class GardenWallpaperService : WallpaperService() {
    override fun onCreateEngine(): Engine = GardenEngine()

    inner class GardenEngine : WallpaperService.Engine(), Choreographer.FrameCallback {
        private var visible = false
        private var xOffset = 0.5f
        private val startNanos = System.nanoTime()

        override fun onVisibilityChanged(v: Boolean) {
            visible = v
            if (v) Choreographer.getInstance().postFrameCallback(this)
            else Choreographer.getInstance().removeFrameCallback(this)
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

        // Replaced in Task 6 with the real garden scene.
        private fun drawFrame(canvas: Canvas, timeSec: Double) {
            canvas.drawColor(Color.rgb(0x12, 0x30, 0x1A)) // forest floor
        }
    }
}
