package com.pixelpomo.app

import android.graphics.Color

/**
 * A complete pixel-art color scheme. Mirrors the six themes shipped by the user's
 * ClaWus widget — **Dark, Light, Mocha, Macchiato, Frappe, Latte** — with the last four
 * drawn from the Catppuccin palette and adapted to Pixel Pomo's retro look.
 *
 * Themes are applied programmatically (the views/drawables are tinted at runtime) so the
 * user can switch instantly without recreating the Activity.
 */
data class PixelTheme(
    val id: String,
    val displayName: String,
    val bg: Int,            // screen background
    val panel: Int,         // secondary button fill + progress track
    val accent: Int,        // primary button fill (tomato)
    val work: Int,          // WORK label + progress fill while working
    val breakColor: Int,    // BREAK label + progress fill while resting
    val onSurface: Int,     // main text (timer, labels), icons, primary button border
    val onSurfaceDim: Int,  // dim text (session line, switch mode), secondary border
    val onAccent: Int,      // text drawn on the accent-colored primary button
    val shadow: Int         // hard drop-shadow under buttons
) {
    /** The accent color for a given phase: green-ish for WORK, blue-ish for BREAK. */
    fun phaseColor(mode: Mode): Int = if (mode == Mode.WORK) work else breakColor
}

/** Registry of the six selectable themes, in display order. */
object Themes {

    private fun c(hex: String) = Color.parseColor(hex)

    // DARK and LIGHT are deliberately **neutral grayscale** so they no longer blend into the
    // four blue/purple Catppuccin flavors (the user noted dark≈mocha/macchiato/frappe and
    // light≈latte). DARK's old crimson accent (#E43B44) is replaced with a brighter coral
    // tomato (#FF5A5F) that reads as a different hue from Catppuccin's pink (#F38BA8).

    val DARK = PixelTheme(
        id = "dark", displayName = "DARK",
        bg = c("#161616"), panel = c("#262626"),
        accent = c("#FF5A5F"), work = c("#46E08A"), breakColor = c("#58A6FF"),
        onSurface = c("#F4F4F4"), onSurfaceDim = c("#8E8E8E"), onAccent = c("#1A1A1A"),
        shadow = c("#000000")
    )

    val LIGHT = PixelTheme(
        id = "light", displayName = "LIGHT",
        bg = c("#F2F2F4"), panel = c("#FFFFFF"),
        accent = c("#E5484D"), work = c("#1F9D55"), breakColor = c("#2A7DE1"),
        onSurface = c("#18181B"), onSurfaceDim = c("#6E6E73"), onAccent = c("#FFFFFF"),
        shadow = c("#C7C7CC")
    )

    val MOCHA = PixelTheme(
        id = "mocha", displayName = "MOCHA",
        bg = c("#1E1E2E"), panel = c("#313244"),
        accent = c("#F38BA8"), work = c("#A6E3A1"), breakColor = c("#89B4FA"),
        onSurface = c("#CDD6F4"), onSurfaceDim = c("#A6ADC8"), onAccent = c("#1E1E2E"),
        shadow = c("#11111B")
    )

    // MACCHIATO removed in v0.4.0 — too close to Frappe/Mocha to justify a slot.

    val FRAPPE = PixelTheme(
        id = "frappe", displayName = "FRAPPE",
        bg = c("#303446"), panel = c("#414559"),
        accent = c("#E78284"), work = c("#A6D189"), breakColor = c("#8CAAEE"),
        onSurface = c("#C6D0F5"), onSurfaceDim = c("#A5ADCE"), onAccent = c("#303446"),
        shadow = c("#232634")
    )

    // LATTE now uses a warm **cream** background so it reads clearly apart from the cool
    // neutral LIGHT theme (the two were near-identical before).
    val LATTE = PixelTheme(
        id = "latte", displayName = "LATTE",
        bg = c("#F7EFDD"), panel = c("#FFFBF0"),
        accent = c("#D20F39"), work = c("#40A02B"), breakColor = c("#1E66F5"),
        onSurface = c("#4C4F69"), onSurfaceDim = c("#8A7F6A"), onAccent = c("#FFFFFF"),
        shadow = c("#D9CBB0")
    )

    val ALL = listOf(DARK, LIGHT, MOCHA, FRAPPE, LATTE)

    val DEFAULT = DARK

    fun byId(id: String?): PixelTheme = ALL.firstOrNull { it.id == id } ?: DEFAULT
}
