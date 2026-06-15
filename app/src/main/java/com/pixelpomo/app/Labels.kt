package com.pixelpomo.app

/**
 * Pure, framework-free rules for the focus **labels** — the subject/activity tagged onto a
 * work session (e.g. STUDY, MATH, CODING). The user picks one on the main screen and can
 * add their own; "STUDY" is the seeded template. Kept Android-free so the rules are
 * unit-tested on the JVM (see LabelsTest); [MainActivity] owns persistence (SharedPreferences).
 */
object Labels {
    /** The template label every install starts with selected. */
    const val DEFAULT = "STUDY"

    /** Hard cap on a label's length so it fits the pixel chip. */
    const val MAX_LEN = 12

    /** Labels seeded on first launch, in display order. */
    val SEED = listOf("STUDY", "MATH", "CODING", "READING")

    /**
     * Canonical form of a user-typed label: upper-cased, restricted to A–Z / 0–9 / space,
     * inner whitespace collapsed, trimmed, and capped at [MAX_LEN]. The character filter also
     * guarantees a label can never contain the `,` or newline used by the stats/label codecs.
     * Returns null when nothing usable is left.
     */
    fun normalize(raw: String): String? {
        val cleaned = raw.uppercase()
            .map { if (it.isLetterOrDigit() || it == ' ') it else ' ' }
            .joinToString("")
            .replace(Regex("\\s+"), " ")
            .trim()
        if (cleaned.isEmpty()) return null
        return cleaned.take(MAX_LEN).trim()
    }

    /** Add a normalized label if it is valid and not already present (case-insensitive). */
    fun add(list: List<String>, raw: String): List<String> {
        val label = normalize(raw) ?: return list
        if (list.any { it.equals(label, ignoreCase = true) }) return list
        return list + label
    }

    /** Remove a label, but never empty the list — always keep at least one. */
    fun remove(list: List<String>, label: String): List<String> {
        if (list.size <= 1) return list
        return list.filterNot { it.equals(label, ignoreCase = true) }
    }
}
