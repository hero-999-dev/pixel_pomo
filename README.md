# 🍅 Pixel Pomo

A retro **pixel-art Pomodoro timer** for Android. Built with native Kotlin and the
[Press Start 2P](https://fonts.google.com/specimen/Press+Start+2P) font for that
classic 8-bit look.

> **Status:** v0.5.0 — configurable timer (WORK / BREAK, start / pause / reset,
> **session counter**), a **settings** screen (study / break / sessions up to 300 / 120 / 24
> + a **6-language** selector), **5 pixel themes** (neutral Dark/Light + Catppuccin Mocha/Frappe
> and a cream Latte), **focus labels** (tap to switch, **pick a color**, 🗑 to remove with
> confirm), **session stats** with a **month navigator** and **bar / line / pie charts**, a
> **coin + shop** system (earn coins, buy localized 2D-pixel flowers), and a **garden** — plant
> your flowers on a free 4×4 grid and grow it with coins. Edge-case unit tests gate every build.

---

## 📲 How to get the APK (test on your phone)

You don't build anything yourself. Every push to `main` triggers **GitHub Actions**,
which runs the tests, builds a debug APK in the cloud, and attaches it to a release.

1. On your phone, open this repo on GitHub.
2. Go to the **Releases** section → **"Latest debug build"**.
3. Download **`0v05_pixelpomo.apk`** (named after the version) and tap to install.
   - If Android warns about "unknown sources", allow installs for your browser /
     file app, then re-open the APK.

> The APK is a *debug* build (debug-signed). That's fine for sideloading and testing
> on your own device. A signed *release* APK can be added later for wider distribution.

You can also grab the APK from the **Actions** tab → latest run → **Artifacts**
(named like `0v05_pixelpomo`), but it comes zipped there, so the Releases link is easier on mobile.

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
        │   │   ├── MainActivity.kt    # UI: timer + settings/theme/label/stats/shop/garden overlays
        │   │   ├── PomodoroEngine.kt  # pure timer state machine (sessions, no Android deps)
        │   │   ├── Labels.kt          # pure focus-label rules (normalize/add/remove)
        │   │   ├── LabelColors.kt     # pure per-label color palette + codec (feeds the charts)
        │   │   ├── Stats.kt           # pure session recording: aggregate + month views + codec
        │   │   ├── Economy.kt         # pure coin math + garden-upgrade cost + inventory codec
        │   │   ├── Garden.kt          # pure garden grid model (plant/clear/grow) + codec
        │   │   ├── Flowers.kt         # pure 2D-pixel flower catalog (grids + 6-language names)
        │   │   ├── TestData.kt        # pure first-launch fixture (seed stats + 1000 coins)
        │   │   ├── PixelArt.kt        # renders a flower grid to a crisp Drawable
        │   │   ├── ChartView.kt       # custom bar/line/pie chart view for the stats screen
        │   │   ├── LocaleManager.kt   # applies the chosen UI language at runtime
        │   │   ├── PixelTheme.kt      # PixelTheme data class + the 5 pixel themes
        │   │   └── PixelStyle.kt      # builds themed button/progress drawables in code
        │   └── res/
        │       ├── font/press_start_2p.ttf   # the pixel font (OFL licensed)
        │       ├── layout/                   # activity_main.xml (+ overlays), row_stepper.xml
        │       ├── drawable/                 # icons + launcher art (buttons/progress drawn in code)
        │       │   ├── ic_settings.xml           # settings gear (top bar)
        │       │   ├── ic_stats.xml              # bar-chart stats icon (top bar)
        │       │   ├── ic_coin.xml               # gold coin (top-right counter)
        │       │   ├── ic_palette.xml            # theme/palette icon (top-left)
        │       │   ├── ic_garden.xml             # garden flower icon (top-left)
        │       │   ├── ic_launcher_background.xml
        │       │   └── ic_launcher_foreground.xml   # blocky pixel tomato
        │       ├── mipmap-anydpi-v26/ic_launcher.xml # adaptive launcher icon
        │       └── values[-tr/-pl/-de/-ko/-it]/
        │           ├── colors.xml            # retro palette
        │           ├── strings.xml           # English base + 5 translated locales
        │           └── themes.xml            # base theme + stats-row styles
        └── test/java/com/pixelpomo/app/
            ├── PomodoroEngineTest.kt         # JUnit edge-case tests (gate every build)
            ├── LabelsTest.kt · LabelColorsTest.kt   # label rules + color palette/codec
            ├── StatsTest.kt · StatsMonthTest.kt     # aggregation/format/codec + month views
            ├── EconomyTest.kt · GardenTest.kt       # coin math + garden grid/codec
            ├── FlowersTest.kt · FlowersLocalizationTest.kt  # catalog + 6-language names
            └── TestDataTest.kt               # the seeded fixture buckets to the brief
```

## 🎮 What it does (v0.5.0)

- **WORK** and **BREAK** phases with **user-set durations** (defaults 25:00 / 5:00).
- **START / PAUSE** toggles the countdown; **RESET** restarts the whole run.
- **>> SWITCH MODE** flips between WORK and BREAK manually.
- When a phase hits `00:00` it shows a toast, auto-switches to the other phase, and
  advances the **SESSION** after each completed break. After the last session it shows
  **ALL DONE!** until you reset.
- **🏷️ Focus labels:** a tappable chip under the mode label tags what you're focusing on
  (**STUDY / MATH / CODING / READING** out of the box). Tap one to use it (you stay on the
  page), tap its **● swatch to pick a color**, **ADD** your own, or **🗑** to remove with a
  yes/no confirm. The choice is remembered and attached to every recorded session, and the
  color flows straight into the stats charts.
- **🪙 Coins & shop:** completing a WORK block earns coins (**1 per 5 minutes** — a 25-min
  block = 5). The **coin counter sits in the top-right corner** (same height as the icons,
  count beside it); tap it to open the **SHOP** and buy **2D-pixel flowers** — names shown in
  your chosen language (rose/gül/róża/rose/장미/rosa, …) — at **10 coins** each.
- **🌱 Garden** (top-left flower icon): a square **4×4 grid** everyone gets free. Tap
  **CUSTOMIZE**, then a tile to **plant** a flower you bought (or clear it). **UPGRADE** (top-left
  of the garden) grows the grid one ring at a time for the new-tile count in coins
  (5×5 = 9, 6×6 = 11, …).
- **📊 Stats** (bar-chart icon): every completed WORK block is logged. The stats screen totals
  **today / this week / this month / this year / all time**, and adds a **month navigator**
  (◀ ▶ to trace back through past months and years) with a **BAR / LINE / PIE** chart you choose
  and a per-month **by-label** breakdown (colored by each label's color).
- **⚙️ Settings** (gear): steppers for **study minutes** (up to 300), **break minutes** (up to
  120), and **sessions** (up to 24), plus a **LANGUAGE** picker —
  **English / Türkçe / Polski / Deutsch / 한국어 / Italiano** — applied instantly.
- **🎨 Themes** (palette): five pixel themes inspired by the
  [ClaWus](https://github.com/hero-999-dev/ClaWus-Claude-Usage-Widget) widget —
  **Dark, Light, Mocha, Frappe, Latte** — switchable live.
- Pixel font, hard-edged buttons with drop shadows, and a chunky progress bar.

## 🧪 Testing

App logic lives in pure classes (`PomodoroEngine`, `Labels`, `LabelColors`, `StatsAggregator`,
`StatsCodec`, `Economy`, `Inventory`, `Garden`, `Flowers`, `TestData`) so it can be unit-tested
on the JVM. **72 JUnit edge-case tests** run locally and **gate every CI build** — a failing test
blocks the APK. Run them with:

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

**Done in v0.5.0:** the **garden** (#7), **6 languages** (#6), **localized flowers**, **label
colors**, **stats charts + month navigation** (#10), and a seeded **test fixture** (1000 coins
+ example study history) so the new screens have data to explore.

**Next up — iOS / cross-platform (decided):** the target is **Flutter (Dart)** — one codebase
building both Android and iOS, with the best support for the hard part (background timers +
local notifications) and a game-friendly canvas for the garden. **No Mac is needed:** a GitHub
Actions **macOS runner** can build the iOS `.ipa` in CI, the same way `ubuntu` builds the
Android APK today (SideStore signing is a later, separate step we're not doing yet). The Flutter
port is a single clean pass done now that the feature set has settled.

To make that port a single clean pass rather than a moving target, **all app logic is kept
in pure, framework-free classes** (`PomodoroEngine`, `Labels`, `Stats*`, `Economy`,
`Inventory`, `Flowers`) — only `MainActivity` and the drawables touch Android. We finish the
game design on Android (fast local builds + APKs you can test now), then port the stable
result to Flutter and turn on the iOS CI job.

## 📜 License

App code: free to use. The bundled **Press Start 2P** font is under the
[SIL Open Font License](https://openfontlicense.org/).
