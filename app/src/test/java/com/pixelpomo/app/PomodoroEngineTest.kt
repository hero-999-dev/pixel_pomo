package com.pixelpomo.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Edge-case unit tests for [PomodoroEngine]. These run on the JVM (no device needed)
 * via `gradlew testDebugUnitTest`, and gate every CI build. Short durations are used
 * so the state transitions are easy to read.
 */
class PomodoroEngineTest {

    private fun engine() = PomodoroEngine(workMillis = 10_000L, breakMillis = 4_000L)

    @Test
    fun initialState() {
        val e = engine()
        assertEquals(Mode.WORK, e.mode)
        assertEquals(10_000L, e.timeLeftMillis)
        assertFalse(e.isRunning)
        assertEquals(1, e.round)
        assertEquals(100, e.progressPercent())
        assertEquals("00:10", e.formattedTime())
    }

    @Test
    fun startSetsRunning() {
        val e = engine()
        e.start()
        assertTrue(e.isRunning)
    }

    @Test
    fun startIsNoOpWhenNoTimeLeft() {
        val e = engine()
        e.setTimeLeft(0)
        e.start()
        assertFalse(e.isRunning)
    }

    @Test
    fun pauseKeepsRemainingTime() {
        val e = engine()
        e.start()
        e.setTimeLeft(6_000)
        e.pause()
        assertFalse(e.isRunning)
        assertEquals(6_000L, e.timeLeftMillis)
    }

    @Test
    fun resetRestoresFullDurationAndStops() {
        val e = engine()
        e.start()
        e.setTimeLeft(2_000)
        e.reset()
        assertFalse(e.isRunning)
        assertEquals(10_000L, e.timeLeftMillis)
    }

    @Test
    fun switchModeTogglesPhaseAndResetsTime() {
        val e = engine()
        e.start()
        e.switchMode()
        assertEquals(Mode.BREAK, e.mode)
        assertEquals(4_000L, e.timeLeftMillis)
        assertFalse(e.isRunning)
        e.switchMode()
        assertEquals(Mode.WORK, e.mode)
        assertEquals(10_000L, e.timeLeftMillis)
    }

    @Test
    fun finishWorkGoesToBreakWithoutAdvancingRound() {
        val e = engine()
        val finished = e.finishPhase()
        assertEquals(Mode.WORK, finished)
        assertEquals(Mode.BREAK, e.mode)
        assertEquals(4_000L, e.timeLeftMillis)
        assertEquals(1, e.round)
        assertFalse(e.isRunning)
    }

    @Test
    fun finishBreakAdvancesRoundAndReturnsToWork() {
        val e = engine()
        e.finishPhase()                  // WORK -> BREAK
        val finished = e.finishPhase()   // BREAK -> WORK
        assertEquals(Mode.BREAK, finished)
        assertEquals(Mode.WORK, e.mode)
        assertEquals(10_000L, e.timeLeftMillis)
        assertEquals(2, e.round)
    }

    @Test
    fun fullCyclesIncrementRoundOncePerCompletedBreak() {
        val e = engine()
        repeat(3) {
            e.finishPhase()  // WORK -> BREAK
            e.finishPhase()  // BREAK -> WORK (round++)
        }
        assertEquals(4, e.round) // started at 1, +1 per completed break
        assertEquals(Mode.WORK, e.mode)
    }

    @Test
    fun setTimeLeftClampsToValidRange() {
        val e = engine()
        e.setTimeLeft(-500)
        assertEquals(0L, e.timeLeftMillis)
        e.setTimeLeft(999_999)
        assertEquals(10_000L, e.timeLeftMillis) // clamped to the work duration
    }

    @Test
    fun progressPercentAcrossRange() {
        val e = engine()
        assertEquals(100, e.progressPercent())
        e.setTimeLeft(5_000)
        assertEquals(50, e.progressPercent())
        e.setTimeLeft(0)
        assertEquals(0, e.progressPercent())
    }

    @Test
    fun progressPercentNeverEscapesBounds() {
        val e = engine()
        e.setTimeLeft(-1_000)
        assertTrue(e.progressPercent() in 0..100)
        e.setTimeLeft(Long.MAX_VALUE)
        assertTrue(e.progressPercent() in 0..100)
    }

    @Test
    fun formattedTimeRoundsUpAndZeroPads() {
        val e = PomodoroEngine(workMillis = 25 * 60 * 1000L)
        assertEquals("25:00", e.formattedTime())
        e.setTimeLeft(60_000)
        assertEquals("01:00", e.formattedTime())
        e.setTimeLeft(59_000)
        assertEquals("00:59", e.formattedTime())
        e.setTimeLeft(1)
        assertEquals("00:01", e.formattedTime()) // rounds up, never shows 00:00 early
        e.setTimeLeft(0)
        assertEquals("00:00", e.formattedTime())
    }
}
