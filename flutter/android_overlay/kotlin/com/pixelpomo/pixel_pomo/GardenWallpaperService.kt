package com.pixelpomo.pixel_pomo

import android.service.wallpaper.WallpaperService
import android.view.SurfaceHolder
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.renderer.FlutterRenderer

/**
 * Live wallpaper that renders the REAL garden: it hosts a [FlutterEngine] running
 * the `wallpaperMain` Dart entry point (lib/wallpaper_main.dart) and points the
 * engine's renderer at the wallpaper [SurfaceHolder]'s surface — so it's the exact
 * same `GardenView` as the app (3D fences, real critters, all sprites), not a
 * simplified native re-draw (#v20). Heavier on battery, which is the trade-off the
 * user chose. (Rendering Flutter into a wallpaper surface isn't an officially
 * supported path, so the surface/lifecycle wiring below is the fragile part.)
 */
class GardenWallpaperService : WallpaperService() {
    override fun onCreateEngine(): Engine = GardenEngine()

    inner class GardenEngine : WallpaperService.Engine() {
        private var flutterEngine: FlutterEngine? = null

        override fun onCreate(surfaceHolder: SurfaceHolder) {
            super.onCreate(surfaceHolder)
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(applicationContext)
            loader.ensureInitializationComplete(applicationContext, null)
            val engine = FlutterEngine(applicationContext) // auto-registers plugins (shared_preferences)
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "wallpaperMain")
            )
            flutterEngine = engine
        }

        override fun onSurfaceCreated(holder: SurfaceHolder) {
            super.onSurfaceCreated(holder)
            flutterEngine?.renderer?.startRenderingToSurface(holder.surface, false)
        }

        override fun onSurfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
            super.onSurfaceChanged(holder, format, width, height)
            val renderer = flutterEngine?.renderer ?: return
            renderer.surfaceChanged(width, height)
            val vm = FlutterRenderer.ViewportMetrics()
            vm.devicePixelRatio = resources.displayMetrics.density
            vm.width = width
            vm.height = height
            renderer.setViewportMetrics(vm)
        }

        override fun onVisibilityChanged(visible: Boolean) {
            super.onVisibilityChanged(visible)
            // pause the engine when hidden so it stops drawing (battery)
            if (visible) flutterEngine?.lifecycleChannel?.appIsResumed()
            else flutterEngine?.lifecycleChannel?.appIsPaused()
        }

        override fun onSurfaceDestroyed(holder: SurfaceHolder) {
            super.onSurfaceDestroyed(holder)
            flutterEngine?.renderer?.stopRenderingToSurface()
        }

        override fun onDestroy() {
            super.onDestroy()
            flutterEngine?.destroy()
            flutterEngine = null
        }
    }
}
