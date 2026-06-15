package com.pixelpomo.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Sanity/edge tests for the [Flowers] catalog + grid integrity. JVM-only; gates CI. */
class FlowersTest {

    @Test
    fun tenFlowersWithUniqueIds() {
        assertEquals(10, Flowers.ALL.size)
        val ids = Flowers.ALL.map { it.id }
        assertEquals(ids.size, ids.toSet().size)   // no duplicates
    }

    @Test
    fun byIdResolvesKnownAndRejectsUnknown() {
        assertNotNull(Flowers.byId("kaktus"))
        assertEquals("Kaktüs", Flowers.byId("kaktus")?.nameTr)
        assertNull(Flowers.byId("dragonfruit"))
        assertNull(Flowers.byId(null))
    }

    @Test
    fun everyGridIsRectangularWithOnlyKnownCells() {
        val allowed = setOf('P', 'C', 'S', 'L', '.')
        Flowers.ALL.forEach { flower ->
            val width = flower.grid.first().length
            assertTrue("grid not empty", width > 0)
            flower.grid.forEach { rowLine ->
                assertEquals("rows uniform width in ${flower.id}", width, rowLine.length)
                rowLine.forEach { ch ->
                    assertTrue("bad cell '$ch' in ${flower.id}", ch in allowed)
                }
            }
        }
    }

    @Test
    fun everyFlowerHasAtLeastOnePetal() {
        Flowers.ALL.forEach { flower ->
            assertTrue("${flower.id} has no petal", flower.grid.any { it.contains('P') })
        }
    }
}
