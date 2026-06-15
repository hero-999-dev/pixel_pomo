package com.pixelpomo.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate

/** Sanity tests for the seeded [TestData] fixture. JVM-only; gates CI. */
class TestDataTest {

    // A mid-week Wednesday so the week/month buckets split exactly as documented.
    private val today = LocalDate.of(2026, 6, 17)
    private val recs = TestData.records(today)

    @Test
    fun todayBucketIsThreeSixtyAcrossFourSubjects() {
        val todayMin = recs.filter { it.epochDay == today.toEpochDay() }.sumOf { it.minutes }
        assertEquals(360, todayMin)
    }

    @Test
    fun weekAndMonthBucketsMatchTheBrief() {
        val totals = StatsAggregator.aggregate(recs, today)
        assertEquals(360, totals.today)
        assertEquals(700, totals.week)
        assertEquals(1000, totals.month)
    }

    @Test
    fun previousYearHasData() {
        val y2025 = recs.filter { LocalDate.ofEpochDay(it.epochDay).year == 2025 }
        assertTrue("2025 should be seeded", y2025.isNotEmpty())
    }

    @Test
    fun fixtureLabelsAreAllPresent() {
        val used = recs.map { it.label }.toSet()
        TestData.LABELS.forEach { assertTrue("missing $it", used.contains(it)) }
    }

    @Test
    fun grantsAThousandCoins() {
        assertEquals(1000, TestData.SEED_COINS)
    }
}
