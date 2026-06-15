package com.pixelpomo.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Edge-case unit tests for [Garden] + [GardenCodec]. JVM-only; gates every CI build. */
class GardenTest {

    @Test
    fun startsAsFreeFourByFourEmpty() {
        val g = Garden()
        assertEquals(4, g.size)
        assertEquals(16, g.tileCount)
        assertTrue(g.tiles.isEmpty())
    }

    @Test
    fun plantAndClearTiles() {
        val g = Garden().plant(0, "gul").plant(5, "kaktus")
        assertEquals("gul", g.flowerAt(0))
        assertEquals("kaktus", g.flowerAt(5))
        assertNull(g.flowerAt(1))
        val cleared = g.clear(0)
        assertNull(cleared.flowerAt(0))
        assertEquals("kaktus", cleared.flowerAt(5))
    }

    @Test
    fun plantIgnoresBadIndexAndBlankId() {
        val g = Garden()
        assertEquals(g, g.plant(16, "gul"))   // out of range
        assertEquals(g, g.plant(-1, "gul"))
        assertEquals(g, g.plant(0, "  "))     // blank id
    }

    @Test
    fun growKeepsRowColPositions() {
        // 4x4: index 5 = (row 1, col 1). After growth to 5x5 that's index 1*5+1 = 6.
        val grown = Garden().plant(5, "lale").grow()
        assertEquals(5, grown.size)
        assertEquals("lale", grown.flowerAt(6))
        assertNull(grown.flowerAt(5))
    }

    @Test
    fun countPlantedTracksInventoryUse() {
        val g = Garden().plant(0, "gul").plant(1, "gul").plant(2, "lale")
        assertEquals(2, g.countPlanted("gul"))
        assertEquals(1, g.countPlanted("lale"))
        assertEquals(0, g.countPlanted("orkide"))
    }

    @Test
    fun codecRoundTrips() {
        val g = Garden(5, mapOf(0 to "gul", 6 to "lale", 24 to "kaktus"))
        val decoded = GardenCodec.decode(GardenCodec.encode(g))
        assertEquals(g.size, decoded.size)
        assertEquals(g.tiles, decoded.tiles)
    }

    @Test
    fun codecDefaultsAndDropsOutOfRange() {
        assertEquals(Garden(), GardenCodec.decode(null))
        assertEquals(Garden(), GardenCodec.decode("  "))
        // a tile index that doesn't fit the (smaller) size is dropped
        val decoded = GardenCodec.decode("size:4\n99:gul\n0:lale")
        assertEquals(4, decoded.size)
        assertFalse(decoded.tiles.containsKey(99))
        assertEquals("lale", decoded.flowerAt(0))
    }

    @Test
    fun codecNeverShrinksBelowBaseSize() {
        val decoded = GardenCodec.decode("size:1\n0:gul")
        assertEquals(4, decoded.size)   // clamped up to BASE_GARDEN_SIZE
    }
}
