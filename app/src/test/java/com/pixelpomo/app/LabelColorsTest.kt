package com.pixelpomo.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Edge-case unit tests for [LabelColors]. JVM-only; gates every CI build. */
class LabelColorsTest {

    @Test
    fun defaultIsStableAndInPalette() {
        val a = LabelColors.defaultFor("MATH")
        val b = LabelColors.defaultFor("MATH")
        assertEquals(a, b)                                   // deterministic
        assertTrue(a in LabelColors.PALETTE)                 // always a real swatch
    }

    @Test
    fun defaultIsCaseAndWhitespaceInsensitive() {
        assertEquals(LabelColors.defaultFor("MATH"), LabelColors.defaultFor("  math "))
    }

    @Test
    fun colorForPrefersChosenOverDefault() {
        val chosen = mapOf("MATH" to 0xFF123456.toInt())
        assertEquals(0xFF123456.toInt(), LabelColors.colorFor("math", chosen))
        // unknown label falls back to a palette default
        assertEquals(LabelColors.defaultFor("CODING"), LabelColors.colorFor("CODING", chosen))
    }

    @Test
    fun codecRoundTrips() {
        val colors = linkedMapOf("MATH" to 0xFFE5484D.toInt(), "CODING" to 0xFF2A7DE1.toInt())
        assertEquals(colors, LabelColors.decode(LabelColors.encode(colors)))
    }

    @Test
    fun decodeSkipsMalformedAndBlankAndNull() {
        val text = listOf("MATH:-12000000", "", "garbage", "CODING:notanint").joinToString("\n")
        val decoded = LabelColors.decode(text)
        assertEquals(1, decoded.size)
        assertEquals(-12000000, decoded["MATH"])
        assertTrue(LabelColors.decode(null).isEmpty())
        assertTrue(LabelColors.decode("   ").isEmpty())
    }

    @Test
    fun paletteHasNoDuplicates() {
        assertEquals(LabelColors.PALETTE.size, LabelColors.PALETTE.toSet().size)
        assertNotEquals(0, LabelColors.PALETTE.size)
    }
}
