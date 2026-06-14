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

    val DARK = PixelTheme(
        id = "dark", displayName = "DARK",
        bg = c("#0F0F1B"), panel = c("#1B1B2F"),
        accent = c("#E43B44"), work = c("#3BE48B"), breakColor = c("#4DA6FF"),
        onSurface = c("#F4F4F4"), onSurfaceDim = c("#8A8AA3"), onAccent = c("#FFFFFF"),
        shadow = c("#000000")
    )

    val LIGHT = PixelTheme(
        id = "light", displayName = "LIGHT",
        bg = c("#E6E6F0"), panel = c("#FFFFFF"),
        accent = c("#E43B44"), work = c("#1F9D55"), breakColor = c("#2A7DE1"),
        onSurface = c("#1B1B2F"), onSurfaceDim = c("#6C6C85"), onAccent = c("#FFFFFF"),
        shadow = c("#3A3A4A")
    )

    val MOCHA = PixelTheme(
        id = "mocha", displayName = "MOCHA",
        bg = c("#1E1E2E"), panel = c("#313244"),
        accent = c("#F38BA8"), work = c("#A6E3A1"), breakColor = c("#89B4FA"),
        onSurface = c("#CDD6F4"), onSurfaceDim = c("#A6ADC8"), onAccent = c("#1E1E2E"),
        shadow = c("#11111B")
    )

    val MACCHIATO = PixelTheme(
        id = "macchiato", displayName = "MACCHIATO",
        bg = c("#24273A"), panel = c("#363A4F"),
        accent = c("#ED8796"), work = c("#A6DA95"), breakColor = c("#8AADF4"),
        onSurface = c("#CAD3F5"), onSurfaceDim = c("#A5ADCB"), onAccent = c("#24273A"),
        shadow = c("#181926")
    )

    val FRAPPE = PixelTheme(
        id = "frappe", displayName = "FRAPPE",
        bg = c("#303446"), panel = c("#414559"),
        accent = c("#E78284"), work = c("#A6D189"), breakColor = c("#8CAAEE"),
        onSurface = c("#C6D0F5"), onSurfaceDim = c("#A5ADCE"), onAccent = c("#303446"),
        shadow = c("#232634")
    )

    val LATTE = PixelTheme(
        id = "latte", displayName = "LATTE",
        bg = c("#EFF1F5"), panel = c("#FFFFFF"),
        accent = c("#D20F39"), work = c("#40A02B"), breakColor = c("#1E66F5"),
        onSurface = c("#4C4F69"), onSurfaceDim = c("#6C6F85"), onAccent = c("#FFFFFF"),
        shadow = c("#BCC0CC")
    )

    val ALL = listOf(DARK, LIGHT, MOCHA, MACCHIATO, FRAPPE, LATTE)

    val DEFAULT = DARK

    fun byId(id: String?): PixelTheme = ALL.firstOrNull { it.id == id } ?: DEFAULT
}
