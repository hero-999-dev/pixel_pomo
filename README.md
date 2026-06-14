# 🍅 Pixel Pomo

A retro **pixel-art Pomodoro timer** for Android. Built with native Kotlin and the
[Press Start 2P](https://fonts.google.com/specimen/Press+Start+2P) font for that
classic 8-bit look.

> **Status:** v0.1.0 — first working timer (WORK / BREAK, start / pause / reset, round counter).

---

## 📲 How to get the APK (test on your phone)

You don't build anything yourself. Every push to `main` triggers **GitHub Actions**,
which builds a debug APK in the cloud and attaches it to a release.

1. On your phone, open this repo on GitHub.
2. Go to the **Releases** section → **"Latest debug build"**.
3. Download **`pixel_pomo-debug.apk`** and tap to install.
   - If Android warns about "unknown sources", allow installs for your browser /
     file app, then re-open the APK.

> The APK is a *debug* build (debug-signed). That's fine for sideloading and testing
> on your own device. A signed *release* APK can be added later for wider distribution.

You can also grab the APK from the **Actions** tab → latest run → **Artifacts**
(`pixel_pomo-debug-apk`), but it comes zipped there, so the Releases link is easier on mobile.

---

## 🗂️ Project structure

```
pixel_pomo/
├── .github/workflows/build-apk.yml   # CI: builds the APK + publishes a release on every push
├── README.md                         # this file — structure & how to get the APK
├── log.md                            # changelog: what changed in each prompt/iteration
├── prompt.md                         # master prompt to recreate this project in a new AI session
├── .gitignore
│
├── settings.gradle.kts               # Gradle: declares the :app module + repositories
├── build.gradle.kts                  # Gradle: top-level plugin versions (AGP, Kotlin)
├── gradle.properties                 # Gradle/AndroidX flags
│
└── app/
    ├── build.gradle.kts              # module build config (SDK levels, deps)
    ├── proguard-rules.pro
    └── src/main/
        ├── AndroidManifest.xml       # app entry point, launcher activity, theme, icon
        ├── java/com/pixelpomo/app/
        │   └── MainActivity.kt       # all the timer logic + UI wiring
        └── res/
            ├── font/press_start_2p.ttf   # the pixel font (OFL licensed)
            ├── layout/activity_main.xml  # the single screen layout
            ├── drawable/                 # pixel button + progress-bar backgrounds, launcher art
            │   ├── btn_pixel.xml
            │   ├── btn_pixel_secondary.xml
            │   ├── progress_pixel.xml
            │   ├── ic_launcher_background.xml
            │   └── ic_launcher_foreground.xml   # blocky pixel tomato
            ├── mipmap-anydpi-v26/ic_launcher.xml # adaptive launcher icon
            └── values/
                ├── colors.xml            # retro palette
                ├── strings.xml
                └── themes.xml
```

## 🎮 What it does (v0.1.0)

- **WORK** phase = 25:00, **BREAK** phase = 5:00.
- **START / PAUSE** toggles the countdown; **RESET** restores the current phase.
- **>> SWITCH MODE** flips between WORK and BREAK manually.
- When a phase hits `00:00` it shows a toast, auto-switches to the other phase, and
  increments **ROUND** after each completed break.
- Pixel font, hard-edged buttons with drop shadows, and a chunky progress bar.

## 🛠️ Tech

| Piece            | Choice                              |
|------------------|-------------------------------------|
| Language         | Kotlin                              |
| UI               | Android Views (XML layouts)         |
| Min SDK          | 26 (Android 8.0)                    |
| Target / Compile | 34                                  |
| Gradle / AGP     | 8.7 / 8.5.2                         |
| Kotlin           | 1.9.24                              |
| Build/CI         | GitHub Actions (`ubuntu-latest`)    |

## 🧱 Building locally (optional)

Local builds need the **Android SDK** + **JDK 17 or newer**. With those installed and
`ANDROID_HOME` (or `local.properties` → `sdk.dir`) pointing at the SDK, from the repo root:

```bash
./gradlew assembleDebug
```

The APK lands at `app/build/outputs/apk/debug/app-debug.apk`. If you don't have the
SDK locally, just rely on the GitHub Actions build above.

## 📜 License

App code: free to use. The bundled **Press Start 2P** font is under the
[SIL Open Font License](https://openfontlicense.org/).
