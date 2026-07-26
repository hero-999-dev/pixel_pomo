# 🍅 Pixel Pomo

A retro **pixel-art Pomodoro timer** for **Android and iPhone**. Focus in 8-bit:
plant a flower for every session you finish, grow a little garden, and turn it into
a living wallpaper. Built with the
[Press Start 2P](https://fonts.google.com/specimen/Press+Start+2P) font for that
classic arcade look.

> **Status:** **v0.34.3** — one Flutter (Dart) codebase ships **both** an Android APK and an
> iOS app. On top of the core timer it has a full-screen **living 2.5D garden**, an animated
> **Android live wallpaper**, an **app blocker** to keep you off distracting apps during a focus
> session, **session stats** with charts and history, a **coin + shop** economy, **6 themes**,
> **6 languages**, and **focus labels**. The original native-Kotlin app (v0.5.0) still lives in
> [`app/`](app/) as the frozen base the port grew from.

---

## 📲 Get it on your phone

You don't build anything yourself — every release attaches a ready-to-install file.

**Android**
1. Open this repo on GitHub → **Releases** → **`flutter-v32`** (the latest numbered build).
2. Download **`pixel_pomo_flutter.apk`** and tap to install.
   - If Android warns about "unknown sources", allow installs for your browser / file app, then re-open the APK.
   - Installs alongside the old native build (different app id), so you can keep both.
   - Starts with **50 coins and a completely empty history** — nothing pre-filled.

There's also a separate **Test Pixel Pomo** build (**`flutter-test`** release, rebuilt automatically on every
push) — a different app id, so it installs *alongside* the real one — pre-filled with years of sample sessions
and coins, for trying out stats/heatmap features without needing to build up real history first.

**iPhone**
1. From the same release, download **`pixel_pomo_ios.ipa`**.
2. Sideload it with **[SideStore](https://sidestore.io/)** or **AltStore** — they sign the app on-device, so **no Mac is needed**.

> iOS builds run on a macOS CI runner and are published when CI minutes are available; a release titled
> *"Android"* only means the `.ipa` for that round is still pending — grab it from the next build, or use an earlier one.

---

## 🎮 What it does

- **Focus timer** — **FOCUS** and **BREAK** phases with your own durations (defaults 25:00 / 5:00),
  **START / PAUSE / RESET**, and a **session counter** that ends on **ALL DONE!**. With **AUTO-START** on, a finished
  focus session rolls into the break and the break into the next session; with it **off** the app asks first **both
  times** ("Start the break?" / "Start the next session?"). A running session shows a phone
  **notification** so the countdown is visible outside the app. **Cancelling a started session still pays out
  the minutes you spent.**
- **⏱️ Stopwatch mode** — flip **Settings → STOPWATCH** for a plain count-up clock instead: no fixed duration, no
  session counter, just **START/PAUSE** and a running total (switches to hours once you pass 60 minutes). Time
  still logs to your stats like any focus session — it just **never earns coins**.
- **🏷️ Focus labels** — a tappable chip tags what you're working on (**STUDY / MATH / CODING / READING** to start).
  Tap to switch, tap its **● swatch to pick a color**, **long-press to rename**, **ADD** your own, or **🗑** to remove.
  Every recorded session remembers its label, and the color flows into the stats charts.
- **🪙 Coins & shop** — finishing a focus block earns coins (**1 per 5 minutes**). Spend them in the **SHOP** on
  **2D-pixel flowers** (names in your language) and **garden decor** (roads + fences). A fresh install starts
  with **50 coins and a genuinely empty history** — no pre-filled sessions or labels.
- **🌱 Living garden** — a full-screen, portrait **2.5D world** drawn by a tiny custom engine (no Unity/Flame).
  Plant your flowers on a grass **clearing** ringed by a **forest** (trees, bushes, rocks). **EXPAND** grows the
  plot from the center; **two-finger twist to rotate**, **pinch-zoom and pan**. **Bee, butterfly and ladybug**
  critters drift in and settle at a different spot on each flower they visit — never the same landing
  point twice. **Every** flower ships **two** hand-drawn models (shape variants in
  one colour — rose, tulip, camellia, flower cactus, desert cactus, chrysanthemum, violet, daisy, water lily,
  begonia, orchid) so a flower bed looks varied.
- **📸 Camera & live wallpaper** — a **peek** button hides all the UI; **camera mode** lets you frame any angle, then
  **CAPTURE** to **share** the shot or, on **Android**, **set it as an animated live wallpaper** — your real garden,
  swaying plants and a visiting bug, redrawn on your home screen. **Settings → HOME SCREEN `CLEAN | GARDEN`** can also
  put the live garden behind the timer.
- **🚫 App blocker** *(Android)* — pick the apps that distract you; while a focus session runs, opening one is met with
  a full-screen **"STAY FOCUSED"** cover. Hard block — stop the timer to lift it. Needs Accessibility + draw-over-apps
  permission (Settings walks you through it).
- **📊 Stats** — every focus block is logged. Totals for **today / week / month / year / all-time**, a
  **DAILY → ALL-TIME** selector with a **◀ ▶ history navigator**, **bar / pie / TREND** charts (DAILY fills up hour by
  hour), a per-label breakdown, and **CURRENT / AVERAGE / BEST** in trend view. A **SESSION TIMELINE IN A WEEK**
  shows each completed session as a colored box, grouped per day with weekday initials, spread evenly across the
  width — **tap a box** to see which label it was and how long. A **SESSIONS IN PIXELS** button opens a
  dedicated screen with two parts: a **SESSION HEATMAP** — one box per session, coloured by label, in one
  flat sequence from start to end (no day boxes or borders — just the sessions, in order) with a period
  picker choosing how much history to pull in: **DAILY** shows just today, **WEEKLY** the current week,
  **MONTHLY / YEARLY** every session that month/year — do 30 sessions this week and you get exactly 30
  boxes, do 1000 this year and you get exactly 1000 — plus a **◀ ▶ navigator** to browse an earlier
  day/week/month/year instead of only ever seeing the current one. Above the boxes sits a one-line summary of
  whatever window you're on: **how many sessions, the total, and your average per day** — averaged over the
  days you actually studied, so rest days don't quietly drag the number down. Below it, **FOCUS SESSIONS** heatmaps
  per label with **WEEKLY / MONTHLY / 18 WEEKS / YEARLY** views and its own **◀ ▶ navigator** to browse an
  earlier period, independent of any other screen. **Weekly and monthly pack 2 labels side by side** (a fixed count — the rows stay
  two rows whatever the screen does), yearly's vertical style 2, and **18 weeks and yearly horizontal give each label the full width**; a
  **LABEL button** with pixel switches picks which labels to show for 18 weeks *and* yearly alike (yearly used
  to be one-label-only — now it's the same multi-select). Each label's box also shows **days · times**, the
  **total time studied** and the **average** — on one line where the column is wide enough, split onto three
  where it isn't, so a number is never cut in half by the edge of a narrow
  column — and the labels you currently have switched on get a **combined
  total and average** of their own right under the period buttons — pick MATH and CODING and it tells you what
  those two together came to over the window you're looking at. It names your picks, or just says **ALL 7
  LABELS** when nothing is filtered out, and it **disappears entirely once you're down to one label**, where
  it would only have repeated that label's own line. **Yearly has its own STYLE picker**: **HORIZONTAL** (default) draws all 12
  months as their own bordered squares, 4 per row, each holding exactly that month's real days — no bleed from
  a neighbouring month; **VERTICAL** draws the same year Daylio-style — 12 month columns × up to 31 day rows,
  one box per calendar day. Grids always show every box — future days sit faint until they color in. **Tap any
  box** for a floating callout with that day's session count and time. **LOG HISTORY**, right below it, is a
  **paginated list of every past session** (50 a page) — tap a row to **change its label** or **remove it**
  (confirm first) to the **RECYCLE BIN**, which drops it out of your stats immediately. Reach the Recycle Bin
  from a button on Log History: tap an entry to **RESTORE** it (instant) or **DELETE FOREVER** (confirm
  first), or **CLEAN RECYCLE BIN** to permanently empty it all at once.
- **⭐ Habit tracker** — three tabs. **Mood Tracker**: a daily 5-face mood picker plus a history heatmap —
  **tap any past day to set its mood too**. **Your
  Year in Pixels**: every heatmap in one place — mood, habits, and focus-session labels, "all data" at a glance.
  **Your Goals**: **HabitKit-style cards**, each with a **contribution heatmap** and a **"N days · M times"**
  streak — add your own, or let your **focus labels count automatically** (study Turkish and it appears as
  *TURKISH · 7 days · 15 times*, no extra tapping).
- **🐷 Money Tracker** — a simple **income / expense ledger**. **Entries keep the currency you spent in** —
  earn euros, spend złoty on holiday, and the row still reads 150 PLN with its euro equivalent right under it.
  Categories are extendable via **+ ADD CATEGORY** (long-press a custom one to remove it). **Monthly totals
  with a signed NET line**, **category bars**, a **bar / pie chart** (daily / weekly / monthly, with a **◀ ▶
  history navigator**), and **paged entries**. Pick a **main currency**; rates refresh from the internet
  (hourly when online). Set a **daily budget** in settings — stay under it for a day and earn **+1 garden
  coin**.
- **⚙️ Settings** — a **STOPWATCH / POMODORO** toggle at the top (POMODORO shows the steppers below,
  STOPWATCH hides them), steppers for **focus / break / sessions**, **auto-start**, the **app blocker**,
  a **home-screen garden** toggle, and a **language** picker — **English / Türkçe / Polski / Deutsch /
  Français / Italiano** — applied instantly. A settings change never disturbs a pomodoro already in
  progress — it takes effect starting the next one.
- **🎨 Themes** — six live pixel themes: **Dark, Light, Mocha, Frappe, Latte, Matcha**. The system bars match the theme and
  there's no white tap ripple. Turn on **Settings → DETAILED CUSTOMISATION** for a **CUSTOM** palette: pick all seven
  colours yourself — each one labelled with where it shows up (MAIN TEXT - CLOCK, TITLES, BUTTON LABELS; PANELS -
  BUTTONS, CARDS, CHART CELLS; …). Every pick is contrast-corrected so nothing you choose can make the screen
  unreadable, and the correction moves only lightness, so what comes back is still the colour you tapped.
- **🖼️ Home wallpaper** — choose any photo from the custom theme editor, then frame it: drag to move, pinch to zoom, in a
  panel shaped like your phone's screen, and delete it from the same panel when you're done with it. Settings' home mode
  picks between **CLEAN · GARDEN · WALLPAPER**; tapping WALLPAPER before you've picked a photo tells you where to get one.
- **🧭 First-run tour** — a fresh install opens on a guided pop-up tour: the screen dims, one button at a time is
  highlighted and explained — the timer, the focus label, every icon in the top bar — and **SKIP** ends it at any point.
  **Settings → SHOW TUTORIAL** plays it again. New installs start on the **garden** home screen with the trackers and the
  detailed options switched off; everything is a switch away in Settings.

## 🧪 Testing

All app logic lives in **pure, framework-free Dart** (timer engine, labels, stats, economy, garden, flowers, the app-blocker
rules) so it can be unit-tested without a device. **303 Dart tests** plus a widget smoke test (boots the app and opens every
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
