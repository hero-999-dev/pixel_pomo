# 🔁 Recreation Prompt

Paste the block below into a fresh AI chat (or hand it to another developer) to
recreate **Pixel Pomo** from scratch, exactly as it stands today. Keep this file
updated whenever the app changes so it always reflects the current state.

---

## The prompt

> Build a private GitHub repository named **`pixel_pomo`**: a **pixel-art / retro
> 8-bit styled Pomodoro timer app for Android**, written in **native Kotlin using
> Android Views (XML layouts)** — not Jetpack Compose, not Flutter.
>
> ### Build & delivery
> - Build a **debug APK** I can sideload on my phone. Set up **GitHub Actions** to
>   run the unit tests and (only if they pass) build the APK on every push to `main`,
>   publishing it to a GitHub **Release** tagged `latest` (also upload it as a
>   workflow artifact), so I can download it on my phone.
> - **Name the APK after the version:** derive it from `versionName` in the workflow so
>   `0.1.x → 0v01_pixelpomo.apk`, `0.2.0 → 0v02_pixelpomo.apk`, etc., and title the
>   `latest` release with the version.
> - Toolchain: **Gradle 8.7**, **Android Gradle Plugin 8.5.2**, **Kotlin 1.9.24**,
>   **JDK 17**, **compileSdk/targetSdk 34**, **minSdk 26**.
>
> ### App spec (v0.4.0)
> - Package / applicationId: **`com.pixelpomo.app`**. App name: **"Pixel Pomo"**.
> - Single screen (`MainActivity` + `activity_main.xml`), **portrait-locked**.
> - Two phases: **WORK** (default 25:00) and **BREAK** (default 5:00), both
>   user-configurable (see Settings).
> - UI top-to-bottom: a **top bar** with a **theme/palette icon (top-left)** and, on the
>   right, a **stats bar-chart icon**, a **settings gear**, and a **gold coin counter in the
>   far-right corner**; then a **mode label** (WORK/BREAK/ALL DONE!), a tappable
>   **focus-label chip**, a big **MM:SS timer**, a chunky horizontal **progress bar**, a row
>   with **START/PAUSE** + **RESET** buttons, a **">> SWITCH MODE"** text button, and a
>   **"SESSION n / N"** counter.
> - **Settings overlay** (opened by the gear): three pixel **steppers** for
>   **STUDY (min)** (5–300, ×5), **BREAK (min)** (1–120, ×1) and **SESSIONS** (1–24, ×1),
>   each with `-`/`+` clamped to range. Edits are a draft committed on **SAVE**,
>   persisted in `SharedPreferences`, and rebuild the engine. CLOSE / back dismisses.
> - **Theme overlay** (opened by the palette icon): lists **five pixel themes** —
>   **Dark, Light, Mocha, Frappe, Latte**. Dark/Light are **neutral grayscale**, Latte uses a
>   warm **cream** background (`#F7EFDD`), Mocha/Frappe are canonical Catppuccin — so all five
>   read distinctly (no Macchiato). Tapping one persists it and **re-tints every view live**;
>   the selected theme has a `>` prefix; an unknown saved id falls back to Dark.
> - **Focus labels** (`Labels.kt`, pure): a tappable **chip** under the mode label shows the
>   current label; tapping opens a **label overlay**. Each row is **`[ name | 🗑 ]`**: tapping
>   the name **selects** it (and **stays on the page**); the **🗑** opens a **yes/no confirm
>   dialog** before removing (never empties the list). An **input + ADD** creates a label and
>   also stays on the page. Labels are **normalized** (upper-cased, A–Z/0–9/space only — so
>   they can't contain the codec's `,`/newline — inner separators → space, ≤12 chars, deduped).
>   Seeded **STUDY / MATH / CODING / READING**; the list + current selection persist.
> - **Coins & shop** (`Economy.kt` + `Flowers.kt` + `PixelArt.kt`, logic pure): completing a
>   WORK block awards `Economy.coinsFor(studyMinutes)` = **1 coin per 5 min** (25→5). The
>   coin balance shows in the top-right and **persists**. Tapping it opens a **SHOP** overlay
>   listing **ten flowers** (Turkish names gül/papatya/lale/kaktüs/kasımpatı/menekşe/nilüfer/
>   orkide/begonya/kamelya), each a **2D pixel sprite** rendered by `PixelArt` from an 8×8
>   char-grid in `Flowers` (`P`=petal,`C`=center,`S`/`L`=green stem/leaf). Each row shows the
>   name, **OWNED n**, and **BUY 10**; buying deducts 10 coins (blocked + dimmed if short) and
>   increments the owned count. Owned flowers persist via `Inventory` (`id:count` lines) for
>   the upcoming garden. `Economy.upgradeCost(n)=2n+1` and `BASE_GARDEN_SIZE=4` are ready for
>   the garden too.
> - **Session stats** (`Stats.kt`, pure): each **completed WORK block** appends a
>   `SessionRecord(epochDay, studyMinutes, currentLabel)` to `SharedPreferences` (one
>   `epochDay,minutes,label` line each; decode skips malformed lines). A **stats overlay**
>   (opened by the bar-chart icon) shows **TODAY / THIS WEEK (Monday-start) / THIS MONTH /
>   THIS YEAR / ALL TIME** totals (via `StatsAggregator`, using `java.time.LocalDate`) plus
>   an **all-time per-label** breakdown, formatted `Xh Ym`. SWITCH/PAUSE/RESET don't record.
> - **Architecture:** keep all timer state and transitions in a pure, Android-free
>   **`PomodoroEngine`** class — constructor args `workMillis`, `breakMillis`,
>   `totalSessions`; fields `mode`, `timeLeftMillis`, `isRunning`, `session`,
>   `isFinished`; methods `start`/`pause`/`reset`/`switchMode`/`setTimeLeft`/
>   `finishPhase`, plus derived `formattedTime()` and `progressPercent()`. A **session**
>   is one WORK+BREAK pair; after the final session's break the engine is `isFinished`
>   (timer stops; screen shows **ALL DONE!**). `MainActivity` only drives a
>   `CountDownTimer` (onTick → `setTimeLeft`; onFinish → `finishPhase` + toast) and
>   renders the engine state. Behavior: START/PAUSE toggles (START after ALL DONE
>   restarts the run); RESET restarts the **whole run** (session 1 / WORK / full time);
>   SWITCH MODE flips phase, resets time and clears finished; on finish, auto-switch to
>   the other phase and advance the session after each completed break. `start()` is a
>   no-op at 0 **and when finished**; `setTimeLeft` clamps to `[0, duration]`; progress
>   clamps to `0..100`; time formatting rounds **up** so a full phase reads `25:00`;
>   cancel the timer in `onDestroy` and before starting a new one.
>
> ### Testing (do this after every change)
> - Keep JUnit edge-case unit tests (JVM, no device) for the pure classes, **45 total**:
>   `PomodoroEngineTest` (16); `LabelsTest` (10) — normalize (case/trim/strip `,`+newline/
>   cap-12/reject empty), add (dedup/invalid), remove (keeps ≥1); `StatsTest` (9) — aggregate
>   across today/week(Mon-start)/month/year/all, per-label sort, `formatMinutes`, codec
>   round-trip + malformed-skip; `EconomyTest` (6) — `coinsFor` (1/5min, rounds down, ≥0),
>   `upgradeCost` (2n+1), inventory codec (drop zero/neg, skip malformed); `FlowersTest` (4)
>   — 10 unique ids, `byId`, grids rectangular/valid-cells/≥1 petal. Add
>   `testImplementation("junit:junit:4.13.2")`.
> - Run `./gradlew testDebugUnitTest`. The CI workflow runs the tests **before**
>   building, so a failing test blocks the APK. Document cases + known gaps in
>   **`TESTING.md`** and follow its per-change checklist.
>
> ### Pixel styling
> - Bundle the **Press Start 2P** font at `res/font/press_start_2p.ttf` (download from
>   `https://github.com/google/fonts/raw/main/ofl/pressstart2p/PressStart2P-Regular.ttf`)
>   and use it for all text.
> - **Themes are applied at runtime, not baked into XML.** Define a `PixelTheme` data
>   class (bg / panel / accent / work / break / onSurface / onSurfaceDim / onAccent /
>   shadow) and a `Themes` registry of **five** themes — **Dark** (default, **neutral** bg
>   `#161616`, panel `#262626`, coral accent `#FF5A5F`, work `#46E08A`, break `#58A6FF`),
>   **Light** (neutral bg `#F2F2F4`, accent `#E5484D`, near-black text), canonical Catppuccin
>   **Mocha** (`#1E1E2E`/`#F38BA8`/`#A6E3A1`/`#89B4FA`) and **Frappe** (`#303446`/`#E78284`/…),
>   and **Latte** with a warm **cream** bg `#F7EFDD` / panel `#FFFBF0` / accent `#D20F39`.
>   (No Macchiato — it was too close to the others.) Dark/Light grayscale + cream Latte keep
>   all five distinct. `MainActivity` tints every view/icon and rebuilds the drawables from
>   the active theme, so a switch takes effect instantly.
> - Buttons are **hard-edged rectangles** (no rounded corners) with an offset
>   drop-shadow + a contrasting border. Build them **in code** (`PixelStyle.kt`, a
>   `LayerDrawable` of two `GradientDrawable`s) rather than static XML so the colors come
>   from the theme. Use `androidx.appcompat.widget.AppCompatButton` (so
>   `android:background` is respected under a Material theme) with
>   `android:stateListAnimator="@null"`. Theme parent:
>   `Theme.MaterialComponents.DayNight.NoActionBar`.
> - The progress bar's `progressDrawable` is also built in `PixelStyle.kt` (panel track +
>   border + a `ClipDrawable` fill in the current phase color), reassigned on theme/phase
>   change.
> - Top-bar icons: a **settings gear** (`ic_settings.xml`) and a **palette** icon
>   (`ic_palette.xml`) as vector drawables, `setColorFilter`-tinted to the theme.
> - Launcher icon: an **adaptive icon** (`mipmap-anydpi-v26/ic_launcher.xml`) with a
>   solid-color background drawable and a **blocky "pixel tomato"** vector foreground
>   (red body, darker bottom shading, light highlight, green stem/leaves). minSdk 26
>   means no PNG fallbacks are needed.
>
> ### Repo housekeeping
> - Add a `.gitignore` for Gradle/Android Studio outputs (ignore `build/`, `.gradle/`,
>   `local.properties`, `*.apk`, `*.aab`, IDE files) and a `.gitattributes` (LF for
>   `gradlew`, CRLF for `*.bat`, binary for `*.jar`/`*.ttf`/`*.apk`).
> - Add **`README.md`** (folder structure + how to download the APK), **`TESTING.md`**
>   (test strategy + checklist), **`log.md`** (a per-iteration change log), and keep
>   **`prompt.md`** (this file) in sync with the current state.
> - Create the GitHub repo as **private** and push to `main`.

---

## Current file tree (for reference)

```
pixel_pomo/
├── .github/workflows/build-apk.yml
├── .gitignore
├── .gitattributes
├── README.md
├── TESTING.md
├── log.md
├── prompt.md
├── settings.gradle.kts
├── build.gradle.kts
├── gradle.properties
└── app/
    ├── build.gradle.kts
    ├── proguard-rules.pro
    └── src/
        ├── main/
        │   ├── AndroidManifest.xml
        │   ├── java/com/pixelpomo/app/MainActivity.kt    # UI: timer + settings/theme/label/stats/shop overlays
        │   ├── java/com/pixelpomo/app/PixelTheme.kt      # PixelTheme + the 5 pixel themes
        │   ├── java/com/pixelpomo/app/PixelStyle.kt      # builds themed button/progress drawables
        │   ├── java/com/pixelpomo/app/PixelArt.kt        # renders a flower grid to a Drawable
        │   ├── java/com/pixelpomo/app/PomodoroEngine.kt  # pure timer state machine (sessions + isFinished)
        │   ├── java/com/pixelpomo/app/Labels.kt          # pure focus-label rules (normalize/add/remove)
        │   ├── java/com/pixelpomo/app/Stats.kt           # pure session recording (aggregate + codec)
        │   ├── java/com/pixelpomo/app/Economy.kt         # pure coin math + upgrade cost + inventory codec
        │   ├── java/com/pixelpomo/app/Flowers.kt         # pure 2D-pixel flower catalog (grids + colors)
        │   └── res/
        │       ├── font/press_start_2p.ttf
        │       ├── layout/{activity_main,row_stepper}.xml
        │       ├── drawable/{ic_settings,ic_stats,ic_coin,ic_palette,ic_launcher_background,ic_launcher_foreground}.xml
        │       ├── mipmap-anydpi-v26/ic_launcher.xml
        │       └── values/{colors,strings,themes}.xml   # themes.xml also has stats-row styles
        └── test/java/com/pixelpomo/app/{PomodoroEngine,Labels,Stats,Economy,Flowers}Test.kt  # JUnit edge tests
```

> **Tip:** When the app evolves, append the new behavior to the spec above and update
> the file tree, so this single prompt always reproduces the latest version.
