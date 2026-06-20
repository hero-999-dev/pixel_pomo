package com.pixelpomo.pixel_pomo

import android.app.WallpaperManager
import android.content.ComponentName
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pixel_pomo/wallpaper")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setLiveWallpaper" -> result.success(openLiveWallpaperPicker())
                    "isActive" -> result.success(isOurWallpaperActive())
                    else -> result.notImplemented()
                }
            }
    }

    private fun openLiveWallpaperPicker(): Boolean {
        val component = ComponentName(this, GardenWallpaperService::class.java)
        // Preferred: jump straight to our wallpaper's preview.
        val direct = Intent(WallpaperManager.ACTION_CHANGE_LIVE_WALLPAPER)
            .putExtra(WallpaperManager.EXTRA_LIVE_WALLPAPER_COMPONENT, component)
        if (direct.resolveActivity(packageManager) != null) {
            startActivity(direct); return true
        }
        // Fallback: the generic live-wallpaper chooser.
        val chooser = Intent(WallpaperManager.ACTION_LIVE_WALLPAPER_CHOOSER)
        if (chooser.resolveActivity(packageManager) != null) {
            startActivity(chooser); return true
        }
        return false
    }

    private fun isOurWallpaperActive(): Boolean {
        val info = WallpaperManager.getInstance(this).wallpaperInfo ?: return false
        return info.packageName == packageName &&
            info.serviceName == GardenWallpaperService::class.java.name
    }
}
