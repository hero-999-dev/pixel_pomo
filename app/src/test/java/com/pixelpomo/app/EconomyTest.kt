package com.pixelpomo.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Edge-case unit tests for [Economy] + [Inventory]. JVM-only; gates every CI build. */
class EconomyTest {

    @Test
    fun coinsForFollowsFiveMinutesPerCoin() {
        assertEquals(0, Economy.coinsFor(0))
        assertEquals(0, Economy.coinsFor(4))    // rounds down
        assertEquals(1, Economy.coinsFor(5))
        assertEquals(5, Economy.coinsFor(25))
        assertEquals(10, Economy.coinsFor(50))
        assertEquals(6, Economy.coinsFor(30))
        assertEquals(0, Economy.coinsFor(-10))  // never negative
    }

    @Test
    fun upgradeCostIsTheNewTileCount() {
        assertEquals(9, Economy.upgradeCost(4))   // 4x4 -> 5x5
        assertEquals(11, Economy.upgradeCost(5))  // 5x5 -> 6x6
        assertEquals(13, Economy.upgradeCost(6))  // 6x6 -> 7x7
    }

    @Test
    fun inventoryRoundTrips() {
        val owned = linkedMapOf("gul" to 2, "kaktus" to 1)
        assertEquals(owned, Inventory.decode(Inventory.encode(owned)))
    }

    @Test
    fun inventoryEncodeDropsZeroAndNegative() {
        val encoded = Inventory.encode(linkedMapOf("gul" to 0, "lale" to -3, "orkide" to 2))
        assertEquals("orkide:2", encoded)
    }

    @Test
    fun inventoryDecodeSkipsMalformedAndBlank() {
        val text = listOf("gul:2", "", "garbage", "lale:notanumber", "kaktus:1").joinToString("\n")
        val decoded = Inventory.decode(text)
        assertEquals(2, decoded.size)
        assertEquals(2, decoded["gul"])
        assertEquals(1, decoded["kaktus"])
    }

    @Test
    fun inventoryDecodeHandlesNullAndBlank() {
        assertTrue(Inventory.decode(null).isEmpty())
        assertTrue(Inventory.decode("  ").isEmpty())
    }
}
