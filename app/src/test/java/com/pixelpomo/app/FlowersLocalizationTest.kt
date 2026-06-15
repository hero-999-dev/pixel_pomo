package com.pixelpomo.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Verifies every flower is named in all six supported languages. JVM-only; gates CI. */
class FlowersLocalizationTest {

    @Test
    fun everyFlowerHasAllSixLocalizedNames() {
        Flowers.ALL.forEach { flower ->
            Flowers.LANGS.forEach { lang ->
                val name = flower.names[lang]
                assertTrue("${flower.id} missing $lang name", !name.isNullOrBlank())
            }
        }
    }

    @Test
    fun nameInFallsBackToEnglishThenTurkish() {
        val rose = Flowers.byId("gul")!!
        assertEquals("Rose", rose.nameIn("en"))
        assertEquals("Gül", rose.nameIn("tr"))
        assertEquals("Róża", rose.nameIn("pl"))
        // unknown language → English fallback
        assertEquals("Rose", rose.nameIn("xx"))
    }

    @Test
    fun sixLanguagesAreRegistered() {
        assertEquals(listOf("en", "tr", "pl", "de", "ko", "it"), Flowers.LANGS)
        assertFalse(Flowers.LANGS.isEmpty())
    }
}
