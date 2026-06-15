package com.pixelpomo.app

/**
 * Pure rules for the **color a focus label is drawn in** — picked by the user in the label
 * overlay and reused as the series color in the stats charts (so a label looks the same on the
 * chip and in every graph). No Android deps → unit-tested on the JVM (LabelColorsTest).
 *
 * Colors are `0xAARRGGBB` ints. A label with no explicit choice gets a stable default from
 * [PALETTE] (assigned by name hash) so even un-customized labels chart in distinct colors.
 */
object LabelColors {

    /** The swatches offered in the picker (and the pool defaults are drawn from). */
    val PALETTE = listOf(
        0xFFE5484D.toInt(), // red
        0xFFF2994A.toInt(), // orange
        0xFFF2C94C.toInt(), // yellow
        0xFF46A03C.toInt(), // green
        0xFF2A9D8F.toInt(), // teal
        0xFF2A7DE1.toInt(), // blue
        0xFF8E4FE0.toInt(), // purple
        0xFFE0457B.toInt(), // pink
        0xFF9C6B4A.toInt(), // brown
        0xFF8E8E8E.toInt()  // gray
    )

    /** Stable default color for a label that hasn't been customized (by name hash). */
    fun defaultFor(label: String): Int {
        val key = label.trim().uppercase()
        val idx = ((key.hashCode() % PALETTE.size) + PALETTE.size) % PALETTE.size
        return PALETTE[idx]
    }

    /** The effective color: the user's choice if present, else a stable default. */
    fun colorFor(label: String, chosen: Map<String, Int>): Int =
        chosen[label.uppercase()] ?: defaultFor(label)

    /** Serialize the chosen-colors map (`LABEL:colorInt`, one per line) for SharedPreferences. */
    fun encode(colors: Map<String, Int>): String =
        colors.entries.joinToString("\n") { "${it.key.uppercase()}:${it.value}" }

    /** Defensive decode: blank/malformed lines are skipped so a corrupt store never crashes. */
    fun decode(text: String?): LinkedHashMap<String, Int> {
        val out = LinkedHashMap<String, Int>()
        if (text.isNullOrBlank()) return out
        for (line in text.split("\n")) {
            if (line.isBlank()) continue
            val parts = line.split(":", limit = 2)
            if (parts.size < 2) continue
            val name = parts[0].trim().uppercase()
            val color = parts[1].trim().toIntOrNull() ?: continue
            if (name.isNotEmpty()) out[name] = color
        }
        return out
    }
}
