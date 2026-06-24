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

    // Active PixelTheme palette, published by Dart `_publishBlocker` so the overlay
    // matches the app's font/theme (#v23 fb). Dart `setInt` is stored as a Long on
    // Android, so read getLong and narrow to an ARGB Int. Defaults = Themes.dark.
    private fun color(ctx: Context, key: String, def: Long): Int =
        prefs(ctx).getLong("flutter.$key", def).toInt()

    fun bg(ctx: Context): Int = color(ctx, "blocker_bg", 0xFF161616L)
    fun ink(ctx: Context): Int = color(ctx, "blocker_ink", 0xFFF4F4F4L)
    fun accent(ctx: Context): Int = color(ctx, "blocker_accent", 0xFFFF5A5FL)
    fun onAccent(ctx: Context): Int = color(ctx, "blocker_on_accent", 0xFF1A1A1AL)
    fun shadow(ctx: Context): Int = color(ctx, "blocker_shadow", 0xFF000000L)
}
