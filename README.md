# 🍅 Pixel Pomo

A retro **pixel-art Pomodoro timer** for Android. Built with native Kotlin and the
[Press Start 2P](https://fonts.google.com/specimen/Press+Start+2P) font for that
classic 8-bit look.

> **Status:** v0.2.0 — configurable timer (WORK / BREAK, start / pause / reset,
> **session counter**), a **settings** screen (study / break minutes + session count),
> and **6 selectable pixel themes**, with edge-case unit tests gating every build.

---

## 📲 How to get the APK (test on your phone)

You don't build anything yourself. Every push to `main` triggers **GitHub Actions**,
which runs the tests, builds a debug APK in the cloud, and attaches it to a release.

1. On your phone, open this repo on GitHub.
2. Go to the **Releases** section → **"Latest debug build"**.
3. Download **`0v02_pixelpomo.apk`** (named after the version) and tap to install.
   - If Android warns about "unknown sources", allow installs for your browser /
     file app, then re-open the APK.

> The APK is a *debug* build (debug-signed). That's fine for sideloading and testing
> on your own device. A signed *release* APK can be added later for wider distribution.

You can also grab the APK from the **Actions** tab → latest run → **Artifacts**
(named like `0v02_pixelpomo`), but it comes zipped there, so the Releases link is easier on mobile.

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
        │   │   ├── MainActivity.kt    # UI: timer + settings/theme overlays
        │   │   ├── PomodoroEngine.kt  # pure timer state machine (sessions, no Android deps)
        │   │   ├── PixelTheme.kt      # PixelTheme data class + the 6 ClaWus themes
        │   │   └── PixelStyle.kt      # builds themed button/progress drawables in code
        │   └── res/
        │       ├── font/press_start_2p.ttf   # the pixel font (OFL licensed)
        │       ├── layout/                   # activity_main.xml (+ overlays), row_stepper.xml
        │       ├── drawable/                 # icons + launcher art (buttons/progress drawn in code)
        │       │   ├── ic_settings.xml           # settings gear (top-right)
        │       │   ├── ic_palette.xml            # theme/palette icon (top-left)
        │       │   ├── ic_launcher_background.xml
        │       │   └── ic_launcher_foreground.xml   # blocky pixel tomato
        │       ├── mipmap-anydpi-v26/ic_launcher.xml # adaptive launcher icon
        │       └── values/
        │           ├── colors.xml            # retro palette
        │           ├── strings.xml
        │           └── themes.xml
        └── test/java/com/pixelpomo/app/
            └── PomodoroEngineTest.kt         # JUnit edge-case tests (gate every build)
```

## 🎮 What it does (v0.2.0)

- **WORK** and **BREAK** phases with **user-set durations** (defaults 25:00 / 5:00).
- **START / PAUSE** toggles the countdown; **RESET** restarts the whole run.
- **>> SWITCH MODE** flips between WORK and BREAK manually.
- When a phase hits `00:00` it shows a toast, auto-switches to the other phase, and
  advances the **SESSION** after each completed break. After the last session it shows
  **ALL DONE!** until you reset.
- **⚙️ Settings** (top-right gear): steppers for **study minutes**, **break minutes**,
  and **how many sessions** — saved and remembered between launches.
- **🎨 Themes** (top-left palette): six pixel themes mirroring the
  [ClaWus](https://github.com/hero-999-dev/ClaWus-Claude-Usage-Widget) widget —
  **Dark, Light, Mocha, Macchiato, Frappe, Latte** — switchable live.
- Pixel font, hard-edged buttons with drop shadows, and a chunky progress bar.

## 🧪 Testing

Timer logic lives in a pure `PomodoroEngine` class so it can be unit-tested on the JVM.
**16 JUnit edge-case tests** run locally and **gate every CI build** — a failing test
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

## 📜 License

App code: free to use. The bundled **Press Start 2P** font is under the
[SIL Open Font License](https://openfontlicense.org/).
