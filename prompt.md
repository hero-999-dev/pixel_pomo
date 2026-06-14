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
>   build it on every push to `main` and publish it to a GitHub **Release** tagged
>   `latest` (also upload it as a workflow artifact), so I can download it on my phone.
> - Toolchain: **Gradle 8.7**, **Android Gradle Plugin 8.5.2**, **Kotlin 1.9.24**,
>   **JDK 17**, **compileSdk/targetSdk 34**, **minSdk 26**.
>
> ### App spec (v0.1.0)
> - Package / applicationId: **`com.pixelpomo.app`**. App name: **"Pixel Pomo"**.
> - Single screen (`MainActivity` + `activity_main.xml`), **portrait-locked**.
> - Two phases via an enum: **WORK = 25:00**, **BREAK = 5:00**.
> - UI top-to-bottom: a **mode label** (WORK/BREAK), a big **MM:SS timer**, a chunky
>   horizontal **progress bar**, a row with **START/PAUSE** + **RESET** buttons, a
>   **">> SWITCH MODE"** text button, and a **"ROUND n"** counter.
> - Logic with `CountDownTimer`: START/PAUSE toggles; RESET restores the current
>   phase's full time; SWITCH MODE flips phase and resets time. On finish: show a
>   toast, auto-switch to the other phase, and increment the round after each break.
>   Timer text rounds seconds up so a full phase reads `25:00`. Cancel the timer in
>   `onDestroy`.
>
> ### Pixel styling
> - Bundle the **Press Start 2P** font at `res/font/press_start_2p.ttf` (download from
>   `https://github.com/google/fonts/raw/main/ofl/pressstart2p/PressStart2P-Regular.ttf`)
>   and use it for all text.
> - Retro palette in `colors.xml`: bg `#0F0F1B`, panel `#1B1B2F`, accent/tomato
>   `#E43B44`, work-green `#3BE48B`, break-blue `#4DA6FF`, light text `#F4F4F4`,
>   dim text `#8A8AA3`.
> - Buttons are **hard-edged rectangles** (no rounded corners) with a black offset
>   drop-shadow + a contrasting border, built as `layer-list` drawables. Use
>   `androidx.appcompat.widget.AppCompatButton` (so `android:background` is respected
>   under a Material theme) with `android:stateListAnimator="@null"`. Theme parent:
>   `Theme.MaterialComponents.DayNight.NoActionBar`.
> - The progress bar uses a custom `layer-list` `progressDrawable` (panel background +
>   border, green progress fill).
> - Launcher icon: an **adaptive icon** (`mipmap-anydpi-v26/ic_launcher.xml`) with a
>   solid-color background drawable and a **blocky "pixel tomato"** vector foreground
>   (red body, darker bottom shading, light highlight, green stem/leaves). minSdk 26
>   means no PNG fallbacks are needed.
>
> ### Repo housekeeping
> - Add a `.gitignore` for Gradle/Android Studio outputs (ignore `build/`, `.gradle/`,
>   `local.properties`, `*.apk`, `*.aab`, IDE files).
> - Add **`README.md`** documenting the folder structure and how to download the APK,
>   **`log.md`** (a per-iteration change log), and keep **`prompt.md`** (this file) in
>   sync with the current state.
> - Create the GitHub repo as **private** and push to `main`.

---

## Current file tree (for reference)

```
pixel_pomo/
├── .github/workflows/build-apk.yml
├── .gitignore
├── README.md
├── log.md
├── prompt.md
├── settings.gradle.kts
├── build.gradle.kts
├── gradle.properties
└── app/
    ├── build.gradle.kts
    ├── proguard-rules.pro
    └── src/main/
        ├── AndroidManifest.xml
        ├── java/com/pixelpomo/app/MainActivity.kt
        └── res/
            ├── font/press_start_2p.ttf
            ├── layout/activity_main.xml
            ├── drawable/{btn_pixel,btn_pixel_secondary,progress_pixel,ic_launcher_background,ic_launcher_foreground}.xml
            ├── mipmap-anydpi-v26/ic_launcher.xml
            └── values/{colors,strings,themes}.xml
```

> **Tip:** When the app evolves, append the new behavior to the spec above and update
> the file tree, so this single prompt always reproduces the latest version.
