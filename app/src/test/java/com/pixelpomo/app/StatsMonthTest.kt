package com.pixelpomo.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.YearMonth

/** Edge-case tests for the month-scoped stats views added in v0.5.0. JVM-only; gates CI. */
class StatsMonthTest {

    private fun rec(date: LocalDate, min: Int, label: String) =
        SessionRecord(date.toEpochDay(), min, label)

    private val records = listOf(
        rec(LocalDate.of(2026, 6, 1), 100, "MATH"),
        rec(LocalDate.of(2026, 6, 1), 50, "CODING"),
        rec(LocalDate.of(2026, 6, 15), 60, "MATH"),
        rec(LocalDate.of(2026, 5, 20), 200, "READING"),  // different month
        rec(LocalDate.of(2025, 6, 15), 999, "MATH")      // different year
    )

    @Test
    fun monthTotalOnlyCountsThatCalendarMonth() {
        assertEquals(210, StatsAggregator.monthTotal(records, YearMonth.of(2026, 6)))
        assertEquals(200, StatsAggregator.monthTotal(records, YearMonth.of(2026, 5)))
        assertEquals(0, StatsAggregator.monthTotal(records, YearMonth.of(2026, 4)))
    }

    @Test
    fun byLabelInMonthSumsAndSortsDescending() {
        val byLabel = StatsAggregator.byLabelInMonth(records, YearMonth.of(2026, 6))
        assertEquals(listOf("MATH" to 160, "CODING" to 50), byLabel)
    }

    @Test
    fun byLabelInMonthDropsEmptyLabels() {
        val byLabel = StatsAggregator.byLabelInMonth(records, YearMonth.of(2026, 4))
        assertTrue(byLabel.isEmpty())
    }

    @Test
    fun dailySeriesBucketsByDayOfMonth() {
        val series = StatsAggregator.dailySeries(records, YearMonth.of(2026, 6))
        assertEquals(30, series.size)          // June has 30 days
        assertEquals(150, series[0])           // June 1 → 100 + 50
        assertEquals(60, series[14])           // June 15 → 60
        assertEquals(0, series[1])             // June 2 → none
    }

    @Test
    fun negativeMinutesClampToZeroInMonthViews() {
        val r = listOf(rec(LocalDate.of(2026, 6, 3), -40, "MATH"))
        assertEquals(0, StatsAggregator.monthTotal(r, YearMonth.of(2026, 6)))
        assertEquals(0, StatsAggregator.dailySeries(r, YearMonth.of(2026, 6))[2])
    }
}
