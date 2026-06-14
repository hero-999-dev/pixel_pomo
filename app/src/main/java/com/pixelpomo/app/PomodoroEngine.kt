package com.pixelpomo.app

import java.util.Locale

/** The two Pomodoro phases. */
enum class Mode { WORK, BREAK }

/**
 * Pure, framework-free Pomodoro state machine. It owns the current phase, the time
 * remaining, the run state and the completed-round count, and exposes the derived
 * values the UI renders (formatted time, progress percent).
 *
 * It has no Android dependencies on purpose, so the whole thing can be unit-tested
 * on the JVM (see PomodoroEngineTest). Durations are injectable so tests can use
 * short values instead of waiting 25 minutes.
 */
class PomodoroEngine(
    private val workMillis: Long = 25 * 60 * 1000L,
    private val breakMillis: Long = 5 * 60 * 1000L
) {
    var mode: Mode = Mode.WORK
        private set
    var timeLeftMillis: Long = workMillis
        private set
    var isRunning: Boolean = false
        private set
    var round: Int = 1
        private set

    fun durationOf(target: Mode): Long = if (target == Mode.WORK) workMillis else breakMillis

    /** Begin counting down. No-op when there is no time left to run. */
    fun start() {
        if (timeLeftMillis > 0) isRunning = true
    }

    /** Stop counting down but keep the remaining time (so START resumes). */
    fun pause() {
        isRunning = false
    }

    /** Stop and restore the current phase to its full duration. */
    fun reset() {
        isRunning = false
        timeLeftMillis = durationOf(mode)
    }

    /** Stop and flip to the other phase at its full duration. */
    fun switchMode() {
        isRunning = false
        mode = other(mode)
        timeLeftMillis = durationOf(mode)
    }

    /** Update remaining time from the platform timer; clamped to a valid range. */
    fun setTimeLeft(millis: Long) {
        timeLeftMillis = millis.coerceIn(0L, durationOf(mode))
    }

    /**
     * Handle the countdown reaching zero: flip to the other phase (a completed
     * BREAK advances the round counter) and reload its full duration.
     *
     * @return the phase that just finished.
     */
    fun finishPhase(): Mode {
        val finished = mode
        isRunning = false
        if (finished == Mode.BREAK) round++
        mode = other(mode)
        timeLeftMillis = durationOf(mode)
        return finished
    }

    /** Remaining time as a percentage (always 0..100) of the current phase. */
    fun progressPercent(): Int {
        val total = durationOf(mode)
        if (total <= 0L) return 0
        return ((timeLeftMillis * 100) / total).toInt().coerceIn(0, 100)
    }

    /** Remaining time as MM:SS, rounding up so a full phase reads e.g. 25:00. */
    fun formattedTime(): String {
        val totalSeconds = (timeLeftMillis + 999) / 1000
        return String.format(Locale.US, "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private fun other(target: Mode): Mode = if (target == Mode.WORK) Mode.BREAK else Mode.WORK
}
