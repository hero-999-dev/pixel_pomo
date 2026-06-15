package com.pixelpomo.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate

/**
 * Edge-case unit tests for [StatsAggregator] (windowing, per-label, formatting) and
 * [StatsCodec] (round-trip + defensive decoding). JVM-only; gates every CI build.
 */
class StatsTest {

    // 2026-06-17 is a Wednesday, so weekStart (Monday) = 2026-06-15 and is distinct from "today".
    private val today = LocalDate.of(2026, 6, 17)
    private val weekStart = today.minusDays((today.dayOfWeek.value - 1).toLong())

    private fun rec(date: LocalDate, min: Int, label: String) =
        SessionRecord(date.toEpochDay(), min, label)

    private fun sampleRecords() = listOf(
        rec(today, 60, "MATH"),                     // today, week, month, year, all
        rec(weekStart, 30, "CODING"),               // week, month, year, all
        rec(weekStart.minusDays(1), 20, "READING"), // before this week; same June + year
        rec(today.minusMonths(2), 40, "MATH"),      // April -> year + all only
        rec(today.minusYears(1), 50, "STUDY")       // last year -> all only
    )

    @Test
    fun aggregateSplitsAcrossWindows() {
        val t = StatsAggregator.aggregate(sampleRecords(), today)
        assertEquals(60, t.today)
        assertEquals(90, t.week)    // today + weekStart
        assertEquals(110, t.month)  // all three June records
        assertEquals(150, t.year)   // everything in 2026 (excludes last year's 50)
        assertEquals(200, t.all)
    }

    @Test
    fun aggregateEmptyIsAllZero() {
        val t = StatsAggregator.aggregate(emptyList(), today)
        assertEquals(0, t.today)
        assertEquals(0, t.week)
        assertEquals(0, t.month)
        assertEquals(0, t.year)
        assertEquals(0, t.all)
    }

    @Test
    fun weekIncludesMondayButNotSundayBefore() {
        val records = listOf(
            rec(weekStart, 25, "A"),                 // Monday of this week -> in
            rec(weekStart.minusDays(1), 25, "B")     // the Sunday before -> out
        )
        assertEquals(25, StatsAggregator.aggregate(records, today).week)
    }

    @Test
    fun negativeMinutesClampToZero() {
        val t = StatsAggregator.aggregate(listOf(rec(today, -99, "X")), today)
        assertEquals(0, t.today)
        assertEquals(0, t.all)
    }

    @Test
    fun byLabelSumsAndSortsDescending() {
        val breakdown = StatsAggregator.byLabel(sampleRecords())
        assertEquals(
            listOf("MATH" to 100, "STUDY" to 50, "CODING" to 30, "READING" to 20),
            breakdown
        )
    }

    @Test
    fun formatMinutesCoversAllShapes() {
        assertEquals("0m", StatsAggregator.formatMinutes(0))
        assertEquals("5m", StatsAggregator.formatMinutes(5))
        assertEquals("1h", StatsAggregator.formatMinutes(60))
        assertEquals("1h 30m", StatsAggregator.formatMinutes(90))
        assertEquals("2h 5m", StatsAggregator.formatMinutes(125))
        assertEquals("0m", StatsAggregator.formatMinutes(-10))
    }

    @Test
    fun codecRoundTrips() {
        val records = listOf(
            SessionRecord(20000, 25, "STUDY"),
            SessionRecord(20001, 50, "DEEP WORK")   // labels may contain spaces
        )
        assertEquals(records, StatsCodec.decode(StatsCodec.encode(records)))
    }

    @Test
    fun codecDecodeSkipsBlankAndMalformedLines() {
        val text = buildString {
            append("20000,25,STUDY\n")
            append("\n")                 // blank
            append("garbage line\n")     // no commas
            append("20001,notanumber,MATH\n") // bad minutes
            append("notaday,30,MATH\n")  // bad day
            append("20002,40,CODING")
        }
        val decoded = StatsCodec.decode(text)
        assertEquals(2, decoded.size)
        assertEquals(SessionRecord(20000, 25, "STUDY"), decoded[0])
        assertEquals(SessionRecord(20002, 40, "CODING"), decoded[1])
    }

    @Test
    fun codecDecodeHandlesNullAndBlank() {
        assertTrue(StatsCodec.decode(null).isEmpty())
        assertTrue(StatsCodec.decode("   ").isEmpty())
    }
}
