package com.pixelpomo.pixel_pomo

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory

/** Background + foreground colors mirrored from the Dart PixelTheme (v15). */
data class ThemeColors(val bg: Int, val onSurface: Int)

/** The camera framing the wallpaper reproduces; mirrors Dart WallpaperCam. */
data class CamFraming(val yaw: Double, val zoom: Double, val panXFrac: Double, val panYFrac: Double)

private val ROADS = setOf("road_concrete", "road_wood", "road_dirt", "road_stone")

/**
 * Reads the same saved state the Flutter app writes (FlutterSharedPreferences) and
 * the same bundled sprite PNGs, so the live wallpaper renders the real garden
 * without duplicating any state or art. Mirrors Dart Garden.decode / Placeables.split.
 */
class GardenData(private val context: Context) {
    var cols = 10; private set
    var rows = 16; private set
    private val tiles = HashMap<Int, String>()
    var theme = ThemeColors(0xFF161616.toInt(), 0xFFF4F4F4.toInt()); private set
    var cam = CamFraming(0.0, 1.0, 0.0, 0.0); private set
    private val cache = HashMap<String, Bitmap?>()

    init { reload() }

    /** Re-read the saved garden/theme/framing (called when the wallpaper becomes visible). */
    fun reload() {
        val sp = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        parseGarden(sp.getString("flutter.garden", null))
        theme = themeFor(sp.getString("flutter.theme_id", null))
        cam = parseCam(sp.getString("flutter.wallpaper_cam", null))
    }

    fun groundAt(i: Int): String? = split(tiles[i]).first
    fun propAt(i: Int): String? = split(tiles[i]).second

    private fun parseGarden(text: String?) {
        cols = 10; rows = 16; tiles.clear()
        if (text.isNullOrBlank()) return
        for (line in text.split("\n")) {
            val t = line.trim(); if (t.isEmpty()) continue
            val c = t.indexOf(':'); if (c < 0) continue
            val key = t.substring(0, c).trim(); val value = t.substring(c + 1).trim()
            when (key) {
                "cols" -> value.toIntOrNull()?.takeIf { it >= 1 }?.let { cols = it }
                "rows" -> value.toIntOrNull()?.takeIf { it >= 1 }?.let { rows = it }
                "size" -> value.toIntOrNull()?.takeIf { it >= 1 }?.let { cols = it; rows = it }
                else -> {
                    val idx = key.toIntOrNull()
                    if (idx != null && idx >= 0 && value.isNotEmpty()) tiles[idx] = value
                }
            }
        }
        val limit = cols * rows
        tiles.keys.filter { it >= limit }.toList().forEach { tiles.remove(it) }
    }

    /** Mirror of Placeables.split: returns (road, prop). */
    private fun split(value: String?): Pair<String?, String?> {
        if (value == null) return null to null
        var road: String? = null; var prop: String? = null
        for (p in value.split("+")) {
            if (p.isEmpty()) continue
            if (ROADS.contains(p)) road = p else prop = p
        }
        return road to prop
    }

    private fun parseCam(s: String?): CamFraming {
        if (s.isNullOrEmpty()) return CamFraming(0.0, 1.0, 0.0, 0.0)
        val p = s.split(",")
        if (p.size != 4) return CamFraming(0.0, 1.0, 0.0, 0.0)
        val y = p[0].toDoubleOrNull(); val z = p[1].toDoubleOrNull()
        val px = p[2].toDoubleOrNull(); val py = p[3].toDoubleOrNull()
        return if (y == null || z == null || px == null || py == null)
            CamFraming(0.0, 1.0, 0.0, 0.0) else CamFraming(y, z, px, py)
    }

    private fun themeFor(id: String?): ThemeColors = when (id) {
        "light" -> ThemeColors(0xFFF2F2F4.toInt(), 0xFF18181B.toInt())
        "mocha" -> ThemeColors(0xFF1E1E2E.toInt(), 0xFFCDD6F4.toInt())
        "frappe" -> ThemeColors(0xFF303446.toInt(), 0xFFC6D0F5.toInt())
        "latte" -> ThemeColors(0xFFF7EFDD.toInt(), 0xFF4C4F69.toInt())
        else -> ThemeColors(0xFF161616.toInt(), 0xFFF4F4F4.toInt())
    }

    /** Decode a bundled sprite PNG once (e.g. "flower_gul", "tree_03", "grass"). */
    fun bitmap(id: String): Bitmap? = cache.getOrPut(id) {
        try {
            context.assets.open("flutter_assets/assets/objects/$id.png").use {
                BitmapFactory.decodeStream(it)
            }
        } catch (e: Exception) { null }
    }
}
