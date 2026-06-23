package com.pixelpomo.pixel_pomo

import android.content.Context

/// Reads the app-blocker state the Flutter app publishes to SharedPreferences
/// (the `flutter.` prefix is how shared_preferences stores keys on Android — same
/// as GardenData for the wallpaper). Mirrors Dart `AppBlocker.active`/`shouldBlock`.
object BlockerData {
    private fun prefs(ctx: Context) =
        ctx.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

    /// On while a focus session is running; `block_until` (wall-clock end ms) is a
    /// safety so a killed Flutter app can't leave blocking on forever.
    fun active(ctx: Context): Boolean {
        val p = prefs(ctx)
        if (!p.getBoolean("flutter.blocker_active", false)) return false
        return System.currentTimeMillis() < p.getLong("flutter.block_until", 0L)
    }

    fun blocked(ctx: Context): Set<String> =
        (prefs(ctx).getString("flutter.blocked_apps", "") ?: "")
            .split(",").map { it.trim() }.filter { it.isNotEmpty() }.toSet()

    fun title(ctx: Context): String =
        prefs(ctx).getString("flutter.blocker_title", null) ?: "STAY FOCUSED"

    fun button(ctx: Context): String =
        prefs(ctx).getString("flutter.blocker_button", null) ?: "BACK TO PIXEL POMO"

    fun shouldBlock(ctx: Context, pkg: String, own: String, launcher: String?): Boolean =
        active(ctx) && blocked(ctx).contains(pkg) && pkg != own && pkg != launcher
}
