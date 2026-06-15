package com.pixelpomo.app

import java.time.LocalDate
import java.time.YearMonth

/** One completed focus block: the day it happened (epoch day), its length in minutes, and its label. */
data class SessionRecord(val epochDay: Long, val minutes: Int, val label: String)

/** Aggregated focus minutes over the standard reporting windows. */
data class StatTotals(
    val today: Int,
    val week: Int,
    val month: Int,
    val year: Int,
    val all: Int
)

/**
 * Pure, framework-free aggregation of completed [SessionRecord]s into day / week / month /
 * year / all-time totals, plus a per-label breakdown and compact minute formatting. No
 * Android dependencies, so the windowing math is unit-tested on the JVM (see StatsTest).
 * [MainActivity] owns persistence and supplies the real "today".
 */
object StatsAggregator {

    /**
     * Sum minutes across each window relative to [today]. The **week** runs Monday→[today]
     * (purely by date range, so it is correct across month/year boundaries); **month** and
     * **year** are calendar-based.
     */
    fun aggregate(records: List<SessionRecord>, today: LocalDate): StatTotals {
        val todayEpoch = today.toEpochDay()
        val weekStart = today.minusDays((today.dayOfWeek.value - 1).toLong()).toEpochDay()
        var day = 0; var week = 0; var month = 0; var year = 0; var all = 0
        for (r in records) {
            val minutes = if (r.minutes < 0) 0 else r.minutes
            all += minutes
            val date = LocalDate.ofEpochDay(r.epochDay)
            if (date.year == today.year) {
                year += minutes
                if (date.month == today.month) month += minutes
            }
            if (r.epochDay in weekStart..todayEpoch) week += minutes
            if (r.epochDay == todayEpoch) day += minutes
        }
        return StatTotals(day, week, month, year, all)
    }

    /** All-time minutes per label, highest first. */
    fun byLabel(records: List<SessionRecord>): List<Pair<String, Int>> =
        records.groupBy { it.label }
            .map { (label, recs) -> label to recs.sumOf { if (it.minutes < 0) 0 else it.minutes } }
            .sortedByDescending { it.second }

    // ---- month-scoped views (drive the stats month-navigator + charts, v0.5.0) ----------

    private fun inMonth(epochDay: Long, ym: YearMonth): Boolean {
        val d = LocalDate.ofEpochDay(epochDay)
        return d.year == ym.year && d.monthValue == ym.monthValue
    }

    /** Total focus minutes recorded in the calendar month [ym]. */
    fun monthTotal(records: List<SessionRecord>, ym: YearMonth): Int =
        records.filter { inMonth(it.epochDay, ym) }
            .sumOf { if (it.minutes < 0) 0 else it.minutes }

    /** Minutes per label within month [ym], highest first (drives the per-label list + charts). */
    fun byLabelInMonth(records: List<SessionRecord>, ym: YearMonth): List<Pair<String, Int>> =
        records.filter { inMonth(it.epochDay, ym) }
            .groupBy { it.label }
            .map { (label, recs) -> label to recs.sumOf { if (it.minutes < 0) 0 else it.minutes } }
            .filter { it.second > 0 }
            .sortedByDescending { it.second }

    /** Per-day minutes for month [ym]: an array indexed by (dayOfMonth − 1). For line/bar charts. */
    fun dailySeries(records: List<SessionRecord>, ym: YearMonth): IntArray {
        val days = IntArray(ym.lengthOfMonth())
        for (r in records) {
            if (!inMonth(r.epochDay, ym)) continue
            val day = LocalDate.ofEpochDay(r.epochDay).dayOfMonth - 1
            days[day] += if (r.minutes < 0) 0 else r.minutes
        }
        return days
    }

    /** Minutes → compact "Xh Ym" / "Ym" / "0m" (negatives clamp to 0). */
    fun formatMinutes(min: Int): String {
        val safe = if (min < 0) 0 else min
        val h = safe / 60
        val m = safe % 60
        return when {
            h == 0 -> "${m}m"
            m == 0 -> "${h}h"
            else -> "${h}h ${m}m"
        }
    }
}

/**
 * Serializes [SessionRecord]s to/from a single SharedPreferences string. One record per line
 * as `epochDay,minutes,label`. Decoding is defensive: blank and malformed lines are skipped
 * so a partially-corrupt store never crashes the app. (Labels can't contain `,` or newline —
 * see [Labels.normalize] — so the format is unambiguous.)
 */
object StatsCodec {
    fun encode(records: List<SessionRecord>): String =
        records.joinToString("\n") { "${it.epochDay},${it.minutes},${it.label}" }

    fun decode(text: String?): List<SessionRecord> {
        if (text.isNullOrBlank()) return emptyList()
        val out = ArrayList<SessionRecord>()
        for (line in text.split("\n")) {
            if (line.isBlank()) continue
            val parts = line.split(",", limit = 3)
            if (parts.size < 3) continue
            val day = parts[0].trim().toLongOrNull() ?: continue
            val min = parts[1].trim().toIntOrNull() ?: continue
            val label = parts[2].trim()
            if (label.isEmpty()) continue
            out.add(SessionRecord(day, min, label))
        }
        return out
    }
}
