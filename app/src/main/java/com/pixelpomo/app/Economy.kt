package com.pixelpomo.app

/**
 * Pure coin / garden economy rules. No Android deps → unit-tested on the JVM (EconomyTest).
 * Coins are earned by completing focus blocks and spent in the shop on flowers (later
 * planted in the garden).
 */
object Economy {
    /** A flower costs this many coins. */
    const val FLOWER_COST = 10

    /** The garden everyone starts with: a 4×4 grid (free). */
    const val BASE_GARDEN_SIZE = 4

    /** Coins for a completed focus block: 1 coin per 5 minutes (5→1, 25→5, 50→10). */
    fun coinsFor(minutes: Int): Int = if (minutes <= 0) 0 else minutes / 5

    /**
     * Cost to grow the garden from an N×N grid to (N+1)×(N+1): the number of new tiles,
     * (N+1)² − N² = 2N+1. So 4×4 → 5×5 costs 9, 5×5 → 6×6 costs 11.
     */
    fun upgradeCost(currentSize: Int): Int = 2 * currentSize + 1
}

/** Serializes the owned-flowers map (flowerId → count) to/from a SharedPreferences string. */
object Inventory {
    fun encode(owned: Map<String, Int>): String =
        owned.filterValues { it > 0 }
            .entries.joinToString("\n") { "${it.key}:${it.value}" }

    fun decode(text: String?): LinkedHashMap<String, Int> {
        val out = LinkedHashMap<String, Int>()
        if (text.isNullOrBlank()) return out
        for (line in text.split("\n")) {
            if (line.isBlank()) continue
            val parts = line.split(":", limit = 2)
            if (parts.size < 2) continue
            val id = parts[0].trim()
            val n = parts[1].trim().toIntOrNull() ?: continue
            if (id.isNotEmpty() && n > 0) out[id] = n
        }
        return out
    }
}
