# 🍅 Pixel Pomo

A retro **pixel-art Pomodoro timer** for Android. Built with native Kotlin and the
[Press Start 2P](https://fonts.google.com/specimen/Press+Start+2P) font for that
classic 8-bit look.

> **Status:** v0.4.0 — configurable timer (WORK / BREAK, start / pause / reset,
> **session counter**), a **settings** screen (study / break / sessions up to 300 / 120 / 24),
> **5 pixel themes** (neutral Dark/Light + Catppuccin Mocha/Frappe and a cream Latte),
> **focus labels** (tap to switch, 🗑 to remove with confirm), **session stats**
> (today / week / month / year / all-time + per-label), and a **coin + shop** system —
> earn coins from focus time and buy 2D-pixel flowers — with edge-case unit tests gating
> every build.

---

## 📲 How to get the APK (test on your phone)

You don't build anything yourself. Every push to `main` triggers **GitHub Actions**,
which runs the tests, builds a debug APK in the cloud, and attaches it to a release.

1. On your phone, open this repo on GitHub.
2. Go to the **Releases** section → **"Latest debug build"**.
3. Download **`0v04_pixelpomo.apk`** (named after the version) and tap to install.
   - If Android warns about "unknown sources", allow installs for your browser /
     file app, then re-open the APK.

> The APK is a *debug* build (debug-signed). That's fine for sideloading and testing
> on your own device. A signed *release* APK can be added later for wider distribution.

You can also grab the APK from the **Actions** tab → latest run → **Artifacts**
(named like `0v04_pixelpomo`), but it comes zipped there, so the Releases link is easier on mobile.

---

## 🗂️ Project structure

```
pixel_pomo/
├── .github/workflows/build-apk.yml   # CI: run unit tests, then build the APK + publish a release
├── README.md                         # this file — structure & how to get the APK
├── TESTING.md                        # test strategy, covered edge cases, per-change checklist
├── log.md                            # changelog: what changed in each prompt/iteration
├── prompt.md                         # master prompt to recreate this project in a new AI session
├── .gitignore
│
├── settings.gradle.kts               # Gradle: declares the :app module + repositories
├── build.gradle.kts                  # Gradle: top-level plugin versions (AGP, Kotlin)
├── gradle.properties                 # Gradle/AndroidX flags
│
└── app/
    ├── build.gradle.kts              # module build config (SDK levels, deps, test deps)
    ├── proguard-rules.pro
    └── src/
        ├── main/
        │   ├── AndroidManifest.xml   # app entry point, launcher activity, theme, icon
        │   ├── java/com/pixelpomo/app/
        │   │   ├── MainActivity.kt    # UI: timer + settings/theme/label/stats/shop overlays
        │   │   ├── PomodoroEngine.kt  # pure timer state machine (sessions, no Android deps)
        │   │   ├── Labels.kt          # pure focus-label rules (normalize/add/remove)
        │   │   ├── Stats.kt           # pure session recording: aggregate + codec
        │   │   ├── Economy.kt         # pure coin math + garden-upgrade cost + inventory codec
        │   │   ├── Flowers.kt         # pure 2D-pixel flower catalog (grid data + colors)
        │   │   ├── PixelArt.kt        # renders a flower grid to a crisp Drawable
        │   │   ├── PixelTheme.kt      # PixelTheme data class + the 5 pixel themes
        │   │   └── PixelStyle.kt      # builds themed button/progress drawables in code
        │   └── res/
        │       ├── font/press_start_2p.ttf   # the pixel font (OFL licensed)
        │       ├── layout/                   # activity_main.xml (+ overlays), row_stepper.xml
        │       ├── drawable/                 # icons + launcher art (buttons/progress drawn in code)
        │       │   ├── ic_settings.xml           # settings gear (top-right)
        │       │   ├── ic_stats.xml              # bar-chart stats icon (top-right)
        │       │   ├── ic_coin.xml               # gold coin (top-right counter)
        │       │   ├── ic_palette.xml            # theme/palette icon (top-left)
        │       │   ├── ic_launcher_background.xml
        │       │   └── ic_launcher_foreground.xml   # blocky pixel tomato
        │       ├── mipmap-anydpi-v26/ic_launcher.xml # adaptive launcher icon
        │       └── values/
        │           ├── colors.xml            # retro palette
        │           ├── strings.xml
        │           └── themes.xml            # base theme + stats-row styles
        └── test/java/com/pixelpomo/app/
            ├── PomodoroEngineTest.kt         # JUnit edge-case tests (gate every build)
            ├── LabelsTest.kt                 # label normalize/add/remove edge cases
            ├── StatsTest.kt                  # aggregation/format/codec edge cases
            ├── EconomyTest.kt                # coin math + inventory codec edge cases
            └── FlowersTest.kt                # flower catalog + grid integrity
```

## 🎮 What it does (v0.4.0)

- **WORK** and **BREAK** phases with **user-set durations** (defaults 25:00 / 5:00).
- **START / PAUSE** toggles the countdown; **RESET** restarts the whole run.
- **>> SWITCH MODE** flips between WORK and BREAK manually.
- When a phase hits `00:00` it shows a toast, auto-switches to the other phase, and
  advances the **SESSION** after each completed break. After the last session it shows
  **ALL DONE!** until you reset.
- **🏷️ Focus labels:** a tappable chip under the mode label tags what you're focusing on
  (**STUDY / MATH / CODING / READING** out of the box). Tap one to use it (you stay on the
  page), **ADD** your own, or **🗑** to remove with a yes/no confirm. The choice is remembered
  and attached to every recorded session.
- **🪙 Coins & shop:** completing a WORK block earns coins (**1 per 5 minutes** — a 25-min
  block = 5). The **coin counter sits in the top-right corner**; tap it to open the **SHOP**
  and buy **2D-pixel flowers** (gül, papatya, lale, kaktüs, kasımpatı, menekşe, nilüfer,
  orkide, begonya, kamelya) at **10 coins** each, ready to plant in the garden (coming next).
- **📊 Stats** (top-right bar chart): every completed WORK block is logged, and the stats
  screen totals your focus time for **today / this week / this month / this year / all time**,
  plus an **all-time breakdown by label**.
- **⚙️ Settings** (top-right gear): steppers for **study minutes** (up to 300), **break
  minutes** (up to 120), and **sessions** (up to 24) — saved between launches.
- **🎨 Themes** (top-left palette): five pixel themes inspired by the
  [ClaWus](https://github.com/hero-999-dev/ClaWus-Claude-Usage-Widget) widget —
  **Dark, Light, Mocha, Frappe, Latte** — switchable live. Dark/Light are neutral grayscale
  and Latte is cream, so all five read distinctly.
- Pixel font, hard-edged buttons with drop shadows, and a chunky progress bar.

## 🧪 Testing

App logic lives in pure classes (`PomodoroEngine`, `Labels`, `StatsAggregator`, `StatsCodec`,
`Economy`, `Inventory`, `Flowers`) so it can be unit-tested on the JVM. **45 JUnit edge-case
tests** run locally and **gate every CI build** — a failing test blocks the APK. Run them with:

```bash
./gradlew testDebugUnitTest
```

See **[TESTING.md](TESTING.md)** for the full list of covered edge cases and known gaps.

## 🛠️ Tech

| Piece            | Choice                              |
|------------------|-------------------------------------|
| Language         | Kotlin                              |
| UI               | Android Views (XML layouts)         |
| Logic            | Pure `PomodoroEngine` + JUnit tests |
| Min SDK          | 26 (Android 8.0)                    |
| Target / Compile | 34                                  |
| Gradle / AGP     | 8.7 / 8.5.2                         |
| Kotlin           | 1.9.24                              |
| Build/CI         | GitHub Actions (`ubuntu-latest`)    |

## 🧱 Building locally (optional)

Local builds need the **Android SDK** + **JDK 17 or newer**. With those installed and
`ANDROID_HOME` (or `local.properties` → `sdk.dir`) pointing at the SDK, from the repo root:

```bash
./gradlew testDebugUnitTest   # run the edge-case tests
./gradlew assembleDebug       # build the APK
```

The APK lands at `app/build/outputs/apk/debug/app-debug.apk`. If you don't have the
SDK locally, just rely on the GitHub Actions build above.

## 🗺️ Roadmap

**Next up:** the **garden** (#7) — a 4×4 free grid you plant your bought flowers into, with
coin-priced upgrades (`Economy.upgradeCost`: 5×5 = 9 coins, 6×6 = 11, …) — then **languages**
(#6: English, Turkish, Polish, German, Korean, Italian).

**iOS / cross-platform (decided):** the target is **Flutter (Dart)** — one codebase building
both Android and iOS, with the best support for the hard part (background timers + local
notifications) and a game-friendly canvas for the garden. **No Mac is needed:** a GitHub
Actions **macOS runner** can build the iOS `.ipa` in CI, the same way `ubuntu` builds the
Android APK today (SideStore signing is a later, separate step we're not doing yet).

To make that port a single clean pass rather than a moving target, **all app logic is kept
in pure, framework-free classes** (`PomodoroEngine`, `Labels`, `Stats*`, `Economy`,
`Inventory`, `Flowers`) — only `MainActivity` and the drawables touch Android. We finish the
game design on Android (fast local builds + APKs you can test now), then port the stable
result to Flutter and turn on the iOS CI job.

## 📜 License

App code: free to use. The bundled **Press Start 2P** font is under the
[SIL Open Font License](https://openfontlicense.org/).
