# 🍅 Pixel Pomo

A retro **pixel-art Pomodoro timer** for **Android and iPhone**. Focus in 8-bit:
plant a flower for every session you finish, grow a little garden, and turn it into
a living wallpaper. Built with the
[Press Start 2P](https://fonts.google.com/specimen/Press+Start+2P) font for that
classic arcade look.

> **Status:** **v0.24.0** — one Flutter (Dart) codebase ships **both** an Android APK and an
> iOS app. On top of the core timer it has a full-screen **living 2.5D garden**, an animated
> **Android live wallpaper**, an **app blocker** to keep you off distracting apps during a focus
> session, **session stats** with charts and history, a **coin + shop** economy, **6 themes**,
> **6 languages**, and **focus labels**. The original native-Kotlin app (v0.5.0) still lives in
> [`app/`](app/) as the frozen base the port grew from.

---

## 📲 Get it on your phone

You don't build anything yourself — every release attaches a ready-to-install file.

**Android**
1. Open this repo on GitHub → **Releases** → **`flutter-v23`** (or the rolling **`latest-flutter`**).
2. Download **`pixel_pomo_flutter.apk`** and tap to install.
   - If Android warns about "unknown sources", allow installs for your browser / file app, then re-open the APK.
   - Installs alongside the old native build (different app id), so you can keep both.

**iPhone**
1. From the same release, download **`pixel_pomo_ios.ipa`**.
2. Sideload it with **[SideStore](https://sidestore.io/)** or **AltStore** — they sign the app on-device, so **no Mac is needed**.

> iOS builds run on a macOS CI runner and are published when CI minutes are available; a release titled
> *"Android"* only means the `.ipa` for that round is still pending — grab it from the next build, or use an earlier one.

---

## 🎮 What it does

- **Focus timer** — **FOCUS** and **BREAK** phases with your own durations (defaults 25:00 / 5:00),
  **START / PAUSE / RESET**, and a **session counter** that ends on **ALL DONE!**. A finished focus session
  **auto-starts the break** (or asks first, per a Settings toggle), and a running session shows a phone
  **notification** so the countdown is visible outside the app. **Cancelling a started session still pays out
  the minutes you spent.**
- **🏷️ Focus labels** — a tappable chip tags what you're working on (**STUDY / MATH / CODING / READING** to start).
  Tap to switch, tap its **● swatch to pick a color**, **long-press to rename**, **ADD** your own, or **🗑** to remove.
  Every recorded session remembers its label, and the color flows into the stats charts.
- **🪙 Coins & shop** — finishing a focus block earns coins (**1 per 5 minutes**). Spend them in the **SHOP** on
  **2D-pixel flowers** (names in your language) and **garden decor** (roads + fences).
- **🌱 Living garden** — a full-screen, portrait **2.5D world** drawn by a tiny custom engine (no Unity/Flame).
  Plant your flowers on a grass **clearing** ringed by a **forest** (trees, bushes, rocks). **EXPAND** grows the
  plot from the center; **two-finger twist to rotate**, **pinch-zoom and pan**. **Bee, butterfly and ladybug**
  critters drift in to visit your flowers. **Every** flower ships **two** hand-drawn models (shape variants in
  one colour — rose, tulip, camellia, cactus, chrysanthemum, violet, daisy, water lily, begonia, orchid) so a
  flower bed looks varied.
- **📸 Camera & live wallpaper** — a **peek** button hides all the UI; **camera mode** lets you frame any angle, then
  **CAPTURE** to **share** the shot or, on **Android**, **set it as an animated live wallpaper** — your real garden,
  swaying plants and a visiting bug, redrawn on your home screen. **Settings → HOME SCREEN `CLEAN | GARDEN`** can also
  put the live garden behind the timer.
- **🚫 App blocker** *(Android)* — pick the apps that distract you; while a focus session runs, opening one is met with
  a full-screen **"STAY FOCUSED"** cover. Hard block — stop the timer to lift it. Needs Accessibility + draw-over-apps
  permission (Settings walks you through it).
- **📊 Stats** — every focus block is logged. Totals for **today / week / month / year / all-time**, a
  **DAILY → ALL-TIME** selector with a **◀ ▶ history navigator**, **bar / pie / TREND** charts (DAILY fills up hour by
  hour), a per-label breakdown, and **CURRENT / AVERAGE / BEST** in trend view.
- **⚙️ Settings** — steppers for **focus / break / sessions**, **auto-start break**, the **app blocker**, a **home-screen
  garden** toggle, and a **language** picker — **English / Türkçe / Polski / Deutsch / Français / Italiano** — applied instantly.
- **🎨 Themes** — six live pixel themes: **Dark, Light, Mocha, Frappe, Latte, Matcha**. The system bars match the theme and
  there's no white tap ripple.

## 🧪 Testing

All app logic lives in **pure, framework-free Dart** (timer engine, labels, stats, economy, garden, flowers, the app-blocker
rules) so it can be unit-tested without a device. **77 Dart tests** plus a widget smoke test (boots the app and opens every
screen) **gate every build**. The garden engine has its own geometry tests. Run them from `flutter/`:

```bash
flutter test
```

See **[TESTING.md](TESTING.md)** for the covered edge cases and known gaps.

## 🛠️ Tech

| Piece            | Choice                                                |
|------------------|-------------------------------------------------------|
| App              | **Flutter / Dart** — one codebase, Android + iOS      |
| Rendering        | Custom 2.5D garden engine (`flutter/lib/engine/`)     |
| Live wallpaper   | Native Kotlin `WallpaperService` (Android)            |
| App blocker      | Native Kotlin `AccessibilityService` (Android)        |
| Logic            | Pure Dart classes + unit tests                        |
| Build / CI       | GitHub Actions — Android on `ubuntu`, iOS on `macOS`  |
| Original base    | Native Kotlin (Android Views) — v0.5.0, in [`app/`](app/) |

## 🗂️ Where things live

```
pixel_pomo/
├── flutter/        # the current app (Dart) — see flutter/README.md for the full layout
│   ├── lib/        #   logic, screens, the garden engine
│   ├── android_overlay/  # native Kotlin: live wallpaper + app-blocker services
│   └── test/       #   the Dart test suite
├── app/            # original native-Kotlin app, frozen at v0.5.0
├── README.md       # this file
├── TESTING.md      # test strategy + covered edge cases
├── log.md          # per-iteration changelog
└── prompt.md       # master prompt to recreate the project
```

## 🧱 Building locally (optional)

Needs the **Flutter SDK** (validated against Flutter 3.44.2 / Dart 3.12.2). From `flutter/`:

```bash
flutter create --org com.pixelpomo --project-name pixel_pomo --platforms=ios,android .
git checkout -- pubspec.yaml lib && rm -f test/widget_test.dart analysis_options.yaml
flutter pub get
flutter test
flutter run        # or: flutter build apk / flutter build ios --no-codesign
```

The generated `ios/` and `android/` projects aren't committed — CI regenerates them with `flutter create`, then
restores the committed files (and the native overlay). See **[`flutter/README.md`](flutter/README.md)** for the
full porting notes, the low-RAM Gradle tip, and the live-wallpaper / app-blocker internals.

## 📜 License

App code: free to use. Bundled fonts — **Press Start 2P** (Latin) and **Galmuri11** (accented-Latin fallback) —
are under the [SIL Open Font License](https://openfontlicense.org/).
