package com.pixelpomo.app

/**
 * Pure, framework-free model of the **2D garden**: a square N×N grid of tiles, each either
 * empty or holding a planted flower (by its [Flower.id]). Everyone starts with a free
 * [Economy.BASE_GARDEN_SIZE]×N grid and can grow it one ring at a time
 * ([Economy.upgradeCost]). No Android deps → unit-tested on the JVM (GardenTest).
 *
 * Tiles are addressed by a flat index `row * size + col` (0-based). [plant]/[clear]/[grow]
 * all return a **new** [Garden] (immutable, copy-on-write) so callers can keep history cheap
 * and the rules stay easy to test.
 */
data class Garden(
    val size: Int = Economy.BASE_GARDEN_SIZE,
    /** tileIndex → flowerId for occupied tiles only. */
    val tiles: Map<Int, String> = emptyMap()
) {
    val tileCount: Int get() = size * size

    fun isValidIndex(index: Int): Boolean = index in 0 until tileCount

    fun flowerAt(index: Int): String? = tiles[index]

    /** Place [flowerId] on [index] (overwriting whatever was there). No-op for a bad index. */
    fun plant(index: Int, flowerId: String): Garden {
        if (!isValidIndex(index) || flowerId.isBlank()) return this
        return copy(tiles = tiles + (index to flowerId))
    }

    /** Empty a tile. No-op if it was already empty or the index is out of range. */
    fun clear(index: Int): Garden {
        if (!tiles.containsKey(index)) return this
        return copy(tiles = tiles - index)
    }

    /**
     * Grow to (size+1)×(size+1). Existing plantings keep their (row, col) — because the
     * flat index changes when the row width grows, each tile is remapped onto the larger grid.
     */
    fun grow(): Garden {
        val newSize = size + 1
        val remapped = HashMap<Int, String>(tiles.size)
        for ((index, id) in tiles) {
            val r = index / size
            val c = index % size
            remapped[r * newSize + c] = id
        }
        return Garden(newSize, remapped)
    }

    /** How many flowers of [flowerId] are currently planted (so we don't over-plant inventory). */
    fun countPlanted(flowerId: String): Int = tiles.values.count { it == flowerId }
}

/** Serializes a [Garden] to/from a SharedPreferences string: `size` then `index:flowerId` lines. */
object GardenCodec {
    fun encode(g: Garden): String = buildString {
        append("size:").append(g.size)
        for ((index, id) in g.tiles.toSortedMap()) append('\n').append(index).append(':').append(id)
    }

    fun decode(text: String?): Garden {
        if (text.isNullOrBlank()) return Garden()
        var size = Economy.BASE_GARDEN_SIZE
        val tiles = LinkedHashMap<Int, String>()
        for (line in text.split("\n")) {
            if (line.isBlank()) continue
            val parts = line.split(":", limit = 2)
            if (parts.size < 2) continue
            val key = parts[0].trim()
            val value = parts[1].trim()
            if (key == "size") {
                size = value.toIntOrNull()?.coerceAtLeast(Economy.BASE_GARDEN_SIZE) ?: size
            } else {
                val idx = key.toIntOrNull() ?: continue
                if (idx >= 0 && value.isNotEmpty()) tiles[idx] = value
            }
        }
        // Drop any tile that no longer fits (e.g. a corrupt oversized index).
        val g = Garden(size, tiles.filterKeys { it < size * size })
        return g
    }
}
