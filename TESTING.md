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

Unit tests in `app/src/test/java/com/pixelpomo/app/PomodoroEngineTest.kt`
(**13 tests, all passing** as of v0.1.1):

| Area | Edge cases checked |
|------|--------------------|
| Initial state | WORK, full time, not running, round 1, 100% progress, `00:10` format |
| start | sets running; **no-op when time left is 0** |
| pause | stops but **keeps remaining time** (so START resumes) |
| reset | restores full duration and stops |
| switch mode | toggles WORK↔BREAK, reloads that phase's time, stops |
| finish WORK | → BREAK, round **not** advanced |
| finish BREAK | → WORK, round **+1** |
| full cycles | round increments exactly **once per completed break** |
| setTimeLeft | **clamps** negative → 0 and over-duration → duration |
| progress % | 100 / 50 / 0 across the range; **never leaves 0..100** (incl. negative & `Long.MAX_VALUE`) |
| time format | rounds **up** (`1ms`→`00:01`), zero-pads, `25:00` at full, `00:00` at zero |

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

## Per-change checklist

Every time the app changes:

1. Add/adjust unit tests for any logic touched, then `./gradlew testDebugUnitTest`.
2. Manually sanity-check on a device (install the APK from the latest release):
   START counts down · PAUSE freezes · START resumes · RESET restores · SWITCH MODE
   flips WORK/BREAK · timer hits 00:00 → toast + auto-switch · ROUND increments after
   a break.
3. Update `log.md`, and `prompt.md` if behavior changed.
4. Push — CI runs the tests, and only then builds & publishes the APK.
