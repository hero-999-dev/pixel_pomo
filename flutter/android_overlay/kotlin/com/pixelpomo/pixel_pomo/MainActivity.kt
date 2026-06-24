package com.pixelpomo.pixel_pomo

import android.Manifest
import android.app.WallpaperManager
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

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
        // App blocker (#v23): the installed-app list + permission checks/openers.
        // Blocker *state* crosses to AppBlockerService via SharedPreferences, not here.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pixel_pomo/blocker")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Enumerating apps + rendering every icon to PNG is heavy; run it
                    // off the platform thread so the picker never freezes the UI
                    // (#v23 fb — was blocking on the main thread). Reply on the UI
                    // thread as Flutter requires.
                    "installedApps" -> Thread {
                        val apps = installedApps()
                        runOnUiThread { result.success(apps) }
                    }.start()
                    "hasAccessibility" -> result.success(isAccessibilityOn())
                    "openAccessibilitySettings" -> {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(null)
                    }
                    "hasOverlay" -> result.success(Settings.canDrawOverlays(this))
                    "openOverlaySettings" -> {
                        startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        // Focus-timer notification (#v23 fb): a foreground-service-backed, lock-screen
        // countdown that can't be swiped away until the session ends (a plain ongoing
        // notification is user-dismissible on Android 14+). TimerService owns it; here
        // we relay start/stop and make sure we're allowed to post notifications.
        ensureNotifPermission()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pixel_pomo/timer")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "show" -> {
                        TimerService.show(
                            this,
                            call.argument<Number>("deadline")?.toLong() ?: 0L,
                            call.argument<String>("title") ?: "FOCUS",
                            call.argument<Number>("nextMs")?.toLong() ?: 0L,
                            call.argument<String>("nextTitle") ?: "",
                            call.argument<String>("doneTitle") ?: "")
                        result.success(null)
                    }
                    "cancel" -> { TimerService.cancel(this); result.success(null) }
                    else -> result.notImplemented()
                }
            }
    }

    private fun isAccessibilityOn(): Boolean {
        val flat = Settings.Secure.getString(
            contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        return flat.contains("$packageName/.AppBlockerService") ||
            flat.contains("$packageName/com.pixelpomo.pixel_pomo.AppBlockerService")
    }

    private fun installedApps(): List<Map<String, Any?>> {
        val pm = packageManager
        val main = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return pm.queryIntentActivities(main, 0)
            .map { it.activityInfo.packageName }
            .filter { it != packageName }
            .distinct()
            .map { pkg ->
                val label = try {
                    pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
                } catch (e: Exception) {
                    pkg
                }
                mapOf("package" to pkg, "label" to label, "icon" to iconPng(pkg))
            }
    }

    private fun iconPng(pkg: String): ByteArray? = try {
        val d = packageManager.getApplicationIcon(pkg)
        val bmp = Bitmap.createBitmap(48, 48, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        d.setBounds(0, 0, 48, 48)
        d.draw(c)
        val bos = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.PNG, 100, bos)
        bos.toByteArray()
    } catch (e: Exception) {
        null
    }

    private fun ensureNotifPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 9001)
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
