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
        // Launch directly in a try/catch instead of guarding with resolveActivity():
        // on Android 11+ resolveActivity() returns null under package visibility even
        // though the system picker handles these intents, which made the picker never
        // open (#v16). Preferred: jump straight to our wallpaper's preview.
        try {
            startActivity(Intent(WallpaperManager.ACTION_CHANGE_LIVE_WALLPAPER)
                .putExtra(WallpaperManager.EXTRA_LIVE_WALLPAPER_COMPONENT, component))
            return true
        } catch (e: Exception) {
            // fall through to the generic live-wallpaper chooser
        }
        return try {
            startActivity(Intent(WallpaperManager.ACTION_LIVE_WALLPAPER_CHOOSER))
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun isOurWallpaperActive(): Boolean {
        val info = WallpaperManager.getInstance(this).wallpaperInfo ?: return false
        return info.packageName == packageName &&
            info.serviceName == GardenWallpaperService::class.java.name
    }
}
