# 🧪 Testing

This project does **edge testing after every change**. The timer logic lives in a
pure, framework-free class (`PomodoroEngine`) precisely so it can be unit-tested on
the JVM — fast, deterministic, no emulator. Tests run locally and **gate every CI
build**: if a test fails, the workflow stops and **no APK is published**.

## How to run

```bash
# locally (needs JDK + Android SDK)
./gradlew testDebugUnitTest

# the exact command CI runs before building the APK
./gradlew testDebugUnitTest --no-daemon --stacktrace
```

HTML report after a run: `app/build/reports/tests/testDebugUnitTest/index.html`.
In CI it's uploaded as the **`unit-test-report`** artifact (even on failure).

## What's covered

**35 JUnit tests, all passing** as of v0.3.0, across three pure classes:

### `PomodoroEngineTest.kt` (16) — timer state machine

| Area | Edge cases checked |
|------|--------------------|
| Initial state | WORK, full time, not running, session 1, `totalSessions`, 100% progress, `00:10` format |
| start | sets running; **no-op when time left is 0**; **no-op when the run is finished** |
| pause | stops but **keeps remaining time** (so START resumes) |
| reset | restarts the **whole run** → session 1 / WORK / full time, clears finished |
| switch mode | toggles WORK↔BREAK, reloads that phase's time, stops, **clears finished**, keeps session |
| finish WORK | → BREAK, session **not** advanced |
| finish BREAK | → WORK, session **+1** |
| final break | last session's break sets **`isFinished`**, session **never overflows** `totalSessions` |
| custom durations | injected study/break minutes are honored (`50:00` / `10:00`) |
| setTimeLeft | **clamps** negative → 0 and over-duration → duration |
| progress % | 100 / 50 / 0 across the range; **never leaves 0..100** (incl. negative & `Long.MAX_VALUE`) |
| time format | rounds **up** (`1ms`→`00:01`), zero-pads, `25:00` at full, `00:00` at zero |

### `LabelsTest.kt` (10) — focus-label rules

| Area | Edge cases checked |
|------|--------------------|
| normalize | upper-cases + trims; collapses inner whitespace; **strips disallowed chars** incl. `,` and newline (codec safety); inner separators (`-`) → space; edge symbols trimmed |
| normalize cap | caps at **12 chars** and re-trims a tail that lands on a space |
| normalize reject | empty / whitespace-only / symbol-only → `null` |
| add | appends a valid label; **ignores case-insensitive duplicates**; ignores invalid input |
| remove | drops a match but **never empties** the list; missing label is a no-op |
| seed | seed set contains the `STUDY` default |

### `StatsTest.kt` (9) — recording & aggregation

| Area | Edge cases checked |
|------|--------------------|
| aggregate | splits minutes across **today / week / month / year / all**; empty → all zero |
| week boundary | **Monday-start** week includes this Monday, excludes the Sunday before |
| negatives | negative minutes clamp to 0 |
| by-label | sums per label, **sorted descending** |
| format | `0m` / `5m` / `1h` / `1h 30m` / `2h 5m`; negative → `0m` |
| codec | **round-trips** (labels with spaces survive); decode **skips blank/malformed lines**; null/blank → empty |

## Notes for v0.3.0 (limits, themes, labels, stats)

- **Higher limits are presentation-only.** The steppers now allow study 5–300, break 1–120,
  sessions 1–24; `PomodoroEngine` already accepted arbitrary durations/sessions, so
  `customDurationsAreHonored` still covers the engine side. No new engine cases needed.
- **Theme change is data-only.** Recoloring DARK/LIGHT and DARK's accent doesn't touch logic.
- **Labels & stats logic is pure and unit-tested** (`Labels`, `StatsAggregator`, `StatsCodec`).
  The Android glue (`SharedPreferences` persistence, the two overlays, recording a block on
  WORK completion) is verified manually per the checklist — a completed WORK phase appends
  one record `(today, studyMinutes, currentLabel)`; SWITCH/PAUSE/RESET do **not** record.
- **`java.time`** (`LocalDate`) is used for date bucketing — available natively on minSdk 26.

## Notes for v0.2.0 (settings, sessions, themes)

- **"Round" became "Session."** A session is one WORK+BREAK pair; the user picks how
  many via Settings. After the final session's break the engine is **`isFinished`**
  (timer stops, screen shows **ALL DONE!**) until RESET or SWITCH MODE.
- **Configurable durations.** Study minutes, break minutes and session count are
  injected into `PomodoroEngine` and persisted in `SharedPreferences`. `customDurationsAreHonored`
  guards that the engine respects whatever durations it's built with.
- **Themes are presentation-only** — the six pixel themes (mirroring the ClaWus
  widget: Dark, Light, Mocha, Macchiato, Frappe, Latte) tint views/drawables at
  runtime and don't touch `PomodoroEngine`, so the logic tests are unaffected.

## Bugs fixed / behavior hardened (v0.1.1)

Surfaced while writing the edge tests:

- **`start()` guarded** — does nothing when there's no time left (avoids spawning a
  zero-length countdown).
- **`setTimeLeft()` clamped** to `[0, duration]` — a stray/overshooting tick can no
  longer show negative or above-max time.
- **`progressPercent()` clamped** to `0..100` — the progress bar can't overflow or
  go negative.
- **Old timer cancelled before a new one starts** — prevents two `CountDownTimer`s
  running at once if start is ever triggered while running.

## Known gaps (not yet covered)

These are limitations to address in future changes, tracked here so they aren't
forgotten:

1. **State loss on Activity recreation.** The screen is portrait-locked so rotation
   won't recreate it, but a system theme/locale change or multi-window resize would
   reset the timer to WORK 25:00. Fix later via `onSaveInstanceState`/`ViewModel`.
2. **Background timing.** `CountDownTimer` is tied to the Activity; if the process is
   killed the countdown stops. True background timing needs a foreground service.
3. **No instrumented UI tests yet.** Button clicks → view updates are currently
   verified manually (see checklist). Espresso tests could automate this once an
   emulator/device is wired into CI.
4. **Stats grow unbounded.** One line per completed WORK block is appended forever. Fine
   for normal use; a future change could roll old records up into daily totals.

## Per-change checklist

Every time the app changes:

1. Add/adjust unit tests for any logic touched, then `./gradlew testDebugUnitTest`.
2. Manually sanity-check on a device (install the APK from the latest release):
   START counts down · PAUSE freezes · START resumes · RESET restarts the run · SWITCH
   MODE flips WORK/BREAK · timer hits 00:00 → toast + auto-switch · SESSION increments
   after a break · run ends at ALL DONE! after the last session · Settings steppers
   change study/break/sessions (up to 300/120/24) and persist · each theme re-tints the
   whole screen live and DARK/LIGHT look distinct from the Catppuccin flavors · the label
   chip opens the picker, selecting changes the chip, ADD creates a label, long-press
   deletes · finishing a WORK block bumps the STATS totals (today/week/month/year/all) and
   the per-label breakdown.
3. Update `log.md`, and `prompt.md` if behavior changed.
4. Push — CI runs the tests, and only then builds & publishes the APK.
