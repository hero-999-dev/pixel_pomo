package com.pixelpomo.app

import java.time.LocalDate

/**
 * One-time **test fixture** seeded on first launch of v0.5.0 (guarded by a prefs flag) so the
 * stats charts, month-navigator and garden mechanics have realistic data to explore. Pure +
 * date-relative → unit-tested (TestDataTest). [MainActivity] applies it once and never again.
 *
 * Bucket intent (when "today" is mid-week): TODAY 360 · THIS WEEK 700 · THIS MONTH 1000, with
 * extra history across previous 2026 months and the previous year (2025). On a Monday-"today"
 * the week has no earlier in-week days, so those extras land just before it — the data still
 * exists for the graphs and month navigation.
 */
object TestData {
    /** Free coins granted alongside the fixture so the shop/garden/upgrades can be exercised. */
    const val SEED_COINS = 1000

    /** Subjects used by the fixture — unioned into the label list so they show in the picker. */
    val LABELS = listOf("MATH", "HISTORY", "ENGLISH", "CODING", "SCIENCE", "TURKISH", "READING")

    fun records(today: LocalDate): List<SessionRecord> {
        val out = ArrayList<SessionRecord>()
        fun add(date: LocalDate, min: Int, label: String) =
            out.add(SessionRecord(date.toEpochDay(), min, label))

        // TODAY — 360 min (current time).
        add(today, 60, "MATH")
        add(today, 100, "HISTORY")
        add(today, 40, "ENGLISH")
        add(today, 160, "CODING")

        // Earlier THIS WEEK — +340 → week reads 700 (200 math + 100 science + 40 english).
        // Kept within the previous two days so they stay inside a Monday-start week (when
        // "today" is at least mid-week; see the class note for the Monday-"today" edge).
        add(today.minusDays(1), 200, "MATH")
        add(today.minusDays(2), 100, "SCIENCE")
        add(today.minusDays(2), 40, "ENGLISH")

        // Earlier THIS MONTH (before the week) — +300 turkish → month reads 1000.
        add(today.minusDays(9), 150, "TURKISH")
        add(today.minusDays(14), 150, "TURKISH")

        // Previous months of 2026 — history for the month-navigator.
        add(today.minusMonths(1).withDayOfMonth(10), 120, "CODING")
        add(today.minusMonths(1).withDayOfMonth(18), 90, "MATH")
        add(today.minusMonths(2).withDayOfMonth(6), 75, "READING")
        add(today.minusMonths(2).withDayOfMonth(22), 130, "HISTORY")
        add(today.minusMonths(3).withDayOfMonth(14), 60, "ENGLISH")

        // Previous year (2025) — so YEAR/older months have something to trace back to.
        add(LocalDate.of(2025, 11, 12), 200, "CODING")
        add(LocalDate.of(2025, 9, 5), 150, "MATH")
        add(LocalDate.of(2025, 6, 20), 90, "READING")
        add(LocalDate.of(2025, 3, 8), 110, "HISTORY")

        return out
    }
}
