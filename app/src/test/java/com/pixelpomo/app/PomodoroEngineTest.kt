package com.pixelpomo.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Edge-case unit tests for [PomodoroEngine]. These run on the JVM (no device needed)
 * via `gradlew testDebugUnitTest`, and gate every CI build. Short durations and a small
 * session count are used so the state transitions are easy to read.
 */
class PomodoroEngineTest {

    private fun engine(sessions: Int = 3) =
        PomodoroEngine(workMillis = 10_000L, breakMillis = 4_000L, totalSessions = sessions)

    @Test
    fun initialState() {
        val e = engine()
        assertEquals(Mode.WORK, e.mode)
        assertEquals(10_000L, e.timeLeftMillis)
        assertFalse(e.isRunning)
        assertEquals(1, e.session)
        assertFalse(e.isFinished)
        assertEquals(3, e.totalSessions)
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
    fun startIsNoOpWhenFinished() {
        val e = engine(sessions = 1)
        e.finishPhase()              // WORK -> BREAK
        e.finishPhase()              // BREAK (last) -> finished
        assertTrue(e.isFinished)
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
    fun resetRestartsWholeRun() {
        val e = engine()
        e.finishPhase()              // -> BREAK
        e.finishPhase()              // -> session 2, WORK
        e.start()
        e.setTimeLeft(2_000)
        e.reset()
        assertFalse(e.isRunning)
        assertFalse(e.isFinished)
        assertEquals(1, e.session)
        assertEquals(Mode.WORK, e.mode)
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
        assertEquals(1, e.session)   // switching does not advance the session
        e.switchMode()
        assertEquals(Mode.WORK, e.mode)
        assertEquals(10_000L, e.timeLeftMillis)
    }

    @Test
    fun finishWorkGoesToBreakWithoutAdvancingSession() {
        val e = engine()
        val finished = e.finishPhase()
        assertEquals(Mode.WORK, finished)
        assertEquals(Mode.BREAK, e.mode)
        assertEquals(4_000L, e.timeLeftMillis)
        assertEquals(1, e.session)
        assertFalse(e.isRunning)
        assertFalse(e.isFinished)
    }

    @Test
    fun finishBreakAdvancesSessionAndReturnsToWork() {
        val e = engine()
        e.finishPhase()                  // WORK -> BREAK
        val finished = e.finishPhase()   // BREAK -> WORK (session++)
        assertEquals(Mode.BREAK, finished)
        assertEquals(Mode.WORK, e.mode)
        assertEquals(10_000L, e.timeLeftMillis)
        assertEquals(2, e.session)
        assertFalse(e.isFinished)
    }

    @Test
    fun finalBreakMarksFinishedAndDoesNotOverflowSession() {
        val e = engine(sessions = 2)
        e.finishPhase()  // s1 WORK -> BREAK
        e.finishPhase()  // s1 BREAK -> s2 WORK
        assertEquals(2, e.session)
        e.finishPhase()  // s2 WORK -> BREAK
        e.finishPhase()  // s2 BREAK (last) -> finished
        assertTrue(e.isFinished)
        assertEquals(2, e.session)       // never exceeds totalSessions
        assertEquals(Mode.WORK, e.mode)
        assertFalse(e.isRunning)
    }

    @Test
    fun switchModeClearsFinished() {
        val e = engine(sessions = 1)
        e.finishPhase()
        e.finishPhase()
        assertTrue(e.isFinished)
        e.switchMode()
        assertFalse(e.isFinished)
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

    @Test
    fun customDurationsAreHonored() {
        val e = PomodoroEngine(workMillis = 50 * 60 * 1000L, breakMillis = 10 * 60 * 1000L)
        assertEquals("50:00", e.formattedTime())
        e.switchMode()
        assertEquals("10:00", e.formattedTime())
    }
}
