package com.pixelpomo.app

import java.util.Locale

/** The two Pomodoro phases. */
enum class Mode { WORK, BREAK }

/**
 * Pure, framework-free Pomodoro state machine. It owns the current phase, the time
 * remaining, the run state, the current session number and a "finished" flag, and
 * exposes the derived values the UI renders (formatted time, progress percent).
 *
 * Durations and the number of sessions are injectable so the user can configure them
 * (and so tests can use short values instead of waiting 25 minutes). The engine has no
 * Android dependencies on purpose, so the whole thing can be unit-tested on the JVM
 * (see PomodoroEngineTest).
 *
 * A "session" is one WORK + BREAK pair. The user picks how many sessions to run; after
 * the final break the engine is [isFinished] and won't run again until [reset].
 */
class PomodoroEngine(
    private val workMillis: Long = 25 * 60 * 1000L,
    private val breakMillis: Long = 5 * 60 * 1000L,
    val totalSessions: Int = 4
) {
    var mode: Mode = Mode.WORK
        private set
    var timeLeftMillis: Long = workMillis
        private set
    var isRunning: Boolean = false
        private set

    /** 1-based index of the session in progress, in `1..totalSessions`. */
    var session: Int = 1
        private set

    /** True once the final session's break has elapsed. The timer stops until [reset]. */
    var isFinished: Boolean = false
        private set

    fun durationOf(target: Mode): Long = if (target == Mode.WORK) workMillis else breakMillis

    /** Begin counting down. No-op when finished or when there is no time left to run. */
    fun start() {
        if (!isFinished && timeLeftMillis > 0) isRunning = true
    }

    /** Stop counting down but keep the remaining time (so START resumes). */
    fun pause() {
        isRunning = false
    }

    /**
     * Full restart: stop, clear the finished flag, return to session 1 / WORK at its
     * full duration. With finite sessions, RESET means "start the whole run over".
     */
    fun reset() {
        isRunning = false
        isFinished = false
        session = 1
        mode = Mode.WORK
        timeLeftMillis = workMillis
    }

    /** Stop and flip to the other phase at its full duration (does not change session). */
    fun switchMode() {
        isRunning = false
        isFinished = false
        mode = other(mode)
        timeLeftMillis = durationOf(mode)
    }

    /** Update remaining time from the platform timer; clamped to a valid range. */
    fun setTimeLeft(millis: Long) {
        timeLeftMillis = millis.coerceIn(0L, durationOf(mode))
    }

    /**
     * Handle the countdown reaching zero. WORK -> BREAK (same session). BREAK -> next
     * session's WORK, unless it was the last session's break, in which case the run is
     * [isFinished].
     *
     * @return the phase that just finished.
     */
    fun finishPhase(): Mode {
        val finished = mode
        isRunning = false
        if (finished == Mode.WORK) {
            mode = Mode.BREAK
            timeLeftMillis = breakMillis
        } else { // a BREAK just finished
            if (session >= totalSessions) {
                isFinished = true
                mode = Mode.WORK
                timeLeftMillis = workMillis
            } else {
                session++
                mode = Mode.WORK
                timeLeftMillis = workMillis
            }
        }
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
