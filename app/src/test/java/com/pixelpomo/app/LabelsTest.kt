package com.pixelpomo.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Edge-case unit tests for the pure [Labels] rules. JVM-only (no device), part of the
 * suite that gates every CI build.
 */
class LabelsTest {

    @Test
    fun normalizeUppercasesAndTrims() {
        assertEquals("MATH", Labels.normalize("  math  "))
        assertEquals("DEEP WORK", Labels.normalize("deep   work"))
    }

    @Test
    fun normalizeStripsDisallowedCharsIncludingCommaAndNewline() {
        // commas/newlines must never survive — the stats/label codecs depend on it
        assertEquals("A B", Labels.normalize("a,b"))
        assertEquals("A B", Labels.normalize("a" + 10.toChar() + "b"))  // 10 = newline
        assertEquals("CODING", Labels.normalize("@@coding!!"))          // edge symbols trimmed away
        assertEquals("DEEP WORK", Labels.normalize("deep-work"))        // inner separator -> space
    }

    @Test
    fun normalizeCapsLengthAndRetrimsTail() {
        // 12-char cap; a cut that lands on a space is trimmed back
        assertEquals("ABCDEFGHIJKL", Labels.normalize("ABCDEFGHIJKLMNOP"))
        assertEquals("AAAAA BBBBB", Labels.normalize("AAAAA BBBBB CCCCC"))
        assertEquals(Labels.MAX_LEN, Labels.normalize("ABCDEFGHIJKLMNOP")!!.length)
    }

    @Test
    fun normalizeRejectsEmptyAndSymbolOnly() {
        assertNull(Labels.normalize(""))
        assertNull(Labels.normalize("   "))
        assertNull(Labels.normalize("!!!"))
    }

    @Test
    fun addAppendsValidLabel() {
        val result = Labels.add(listOf("STUDY"), "math")
        assertEquals(listOf("STUDY", "MATH"), result)
    }

    @Test
    fun addIgnoresDuplicatesCaseInsensitively() {
        val list = listOf("STUDY", "MATH")
        assertEquals(list, Labels.add(list, "math"))
        assertEquals(list, Labels.add(list, "  STUDY "))
    }

    @Test
    fun addIgnoresInvalidInput() {
        val list = listOf("STUDY")
        assertEquals(list, Labels.add(list, "   "))
        assertEquals(list, Labels.add(list, "@@@"))
    }

    @Test
    fun removeDropsMatchButKeepsAtLeastOne() {
        assertEquals(listOf("STUDY"), Labels.remove(listOf("STUDY", "MATH"), "math"))
        // never empties the list
        assertEquals(listOf("STUDY"), Labels.remove(listOf("STUDY"), "study"))
    }

    @Test
    fun removeOfMissingLabelIsNoOp() {
        val list = listOf("STUDY", "MATH")
        assertEquals(list, Labels.remove(list, "READING"))
    }

    @Test
    fun seedContainsDefault() {
        assertTrue(Labels.SEED.contains(Labels.DEFAULT))
    }
}
