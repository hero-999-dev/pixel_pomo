# 🍅 Pixel Pomo — Flutter port (iOS + Android)

This folder is the **cross-platform port** of the native Android app (in `../app`). One Dart
codebase builds **both** an Android APK and an **iOS `.ipa`**, so iPhone is finally covered.

## Why it's structured this way

Only the **portable** parts live here and are committed:

```
flutter/
├── pubspec.yaml          # deps (shared_preferences, share_plus, path_provider, wallpaper_manager_flutter [Android]), pixel font, flutter_launcher_icons
├── assets/
│   ├── fonts/            # PressStart2P (Latin) + Galmuri11 (OFL pixel Hangul, for Korean)
│   ├── objects/          # 24 sprites: grass/forest/tree/coin + 4 roads + 3 fences + 10 flowers (single-frame) + 3 critters (8-frame atlases)
│   └── icon/             # app_icon.png + app_icon_fg.png (the pixel-tomato launcher icon)
├── tools/
│   ├── gen_objects.py    # regenerates assets/objects/*.png (no Pillow needed)
│   └── gen_icon.py       # regenerates the launcher icon PNGs
├── lib/
│   ├── logic.dart        # pure port + Placeables (4 roads + 3 fences; road+fence tile-layering)
│   ├── strings.dart      # the six UI languages (en/tr/pl/de/ko/it) + month names
│   ├── store.dart        # AppStore (ChangeNotifier): state, persistence, countdown, buyItem
│   ├── pixel.dart        # pixel widgets + chart painter + flower sprites; fontFor('ko')→Galmuri11
│   ├── camera.dart       # garden screenshot (RepaintBoundary→PNG) + save (path_provider) + share (share_plus)
│   ├── engine/
│   │   ├── garden_engine.dart  # full-screen 2.5D renderer: rectangular Projector, WorldGrid (claimed+forest), low-poly 3D fence mesh, flat lighting, flower/tree billboards, critter atlas
│   │   └── garden_view.dart    # gesture/ticker widget: pinch-zoom + pan + two-finger rotate; peek/camera buttons; RepaintBoundary capture; interactive flag
│   └── main.dart         # screens: timer (+optional live garden backdrop) + theme/garden/stats/settings/shop/label overlays
└── test/
    ├── logic_test.dart        # Dart edge tests (gate the Flutter CI)
    ├── engine_test.dart       # geometry: projectElevated + boxCorners + rectangular Projector + WorldGrid
    └── widget_smoke_test.dart # boots the app, opens every overlay incl. the live garden (peek/camera/home-mode)
```

The generated **`ios/`** and **`android/`** Xcode/Gradle projects are **not** committed — the CI
workflow regenerates them on a macOS runner with `flutter create`, then restores these files and
builds. That keeps the repo small and avoids hand-maintaining platform scaffolding.

## Getting the builds

Push to `main` (touching `flutter/**`) or run the **Build Flutter (iOS + Android)** workflow.
It publishes to the **`latest-flutter`** prerelease:

- **Android:** `pixel_pomo_flutter.apk` — install directly (distinct app id `com.pixelpomo.pixel_pomo`, so it coexists with the native build).
- **iOS:** `pixel_pomo_ios.ipa` — **unsigned**; sideload with **SideStore/AltStore**, which signs it on-device (no Mac needed).

## Building locally (optional)

Needs the Flutter SDK (this repo is validated against **Flutter 3.44.2 / Dart 3.12.2**) plus,
for Android, **Android SDK 36 + build-tools 36** (`sdkmanager "platforms;android-36"
"build-tools;36.0.0"`). From this folder:

```bash
flutter create --org com.pixelpomo --project-name pixel_pomo --platforms=ios,android .
git checkout -- pubspec.yaml lib && rm -f test/widget_test.dart analysis_options.yaml
flutter pub get
flutter analyze
flutter test       # logic_test.dart + engine_test.dart + widget_smoke_test.dart (46)
flutter run        # or: flutter build apk / flutter build ios --no-codesign
```

> **Low-RAM note:** the generated `android/gradle.properties` requests `-Xmx8G`, which can crash
> the Gradle daemon on memory-constrained machines. Cap it in `~/.gradle/gradle.properties`
> (`GRADLE_USER_HOME`), e.g. `org.gradle.jvmargs=-Xmx2560m -XX:MaxMetaspaceSize=768m` and
> `org.gradle.daemon=false` — this overrides the template and survives `flutter create`.

## Status / parity

Faithful port of v0.5.0: timer + sessions, 5 themes, focus labels with colors, stats (month
navigator + bar/line/pie charts), coins + shop with localized flowers, 6 languages, and the
first-launch test fixture (1000 coins + sample history). The pure logic is shared test-for-test
with the Kotlin original.

**Flutter-exclusive garden** (richer than the native grid): a **full-screen, portrait, 2.5D world**
drawn by a tiny custom engine (`lib/engine/`) — no Unity/Flame. A **rectangular `cols × rows` claimed
plot (starts 4×6)** is the grass **clearing**; the **forest fills the rest of the screen** — the painter
stamps a tree billboard on every visible tile outside the plot (grounded with a contact shadow), so the
woods cover the screen at any pan/zoom with no void. **EXPAND grows the plot from the center** (+2 ring,
no cap), eating into the woods. The tilt is fixed, but you can **rotate by hand** (two-finger twist),
**pinch-zoom (1×–4×) and pan/roam** the surrounding forest. **CUSTOMIZE** shows tile gridlines.
**Lighting is flat sky-ambient** — nothing is shaded by view angle. Roads lie flat; **fences are real
low-poly 3D** — upright post meshes (brighter sky-lit top) joined by **raised 3D rails** to any
adjacent fence (wood↔dark↔stone), keeping a solid footprint from every angle; a fence can stand **on
top of a road** (flowers can't). **Flowers and forest trees are flat billboards** (depth-sorted);
**only critters** (tiny **bee/butterfly/ladybug**) use an 8-direction atlas to face their heading,
drifting in to **visit a flower** then leaving. The SHOP sells **4 road** + **3 fence** materials
(5 coins each). The wallet shows a **plain 2D gold coin**.

**Garden size & forest (v13):** the plot is a **ratio-aware 10×16** (fills the portrait screen; `Garden.atLeast`
migrates older saves), and the forest is **varied** — `forestPropAt(c,r)` deterministically scatters **20 trees +
10 bushes + 5 rocks** (with grass gaps) instead of one repeated tree.

**Peek, camera & wallpaper:** a bottom-left **peek** button hides *all* HUD (full-bleed, system bars
matched); a **camera mode** frames + **screenshots** the garden. The shot → **SET AS LIVE WALLPAPER** (sets the
Android home-screen wallpaper via `wallpaper_manager_flutter`, Android-only — hidden on iOS) or **save/share**
(`share_plus`). **Settings → HOME SCREEN `CLEAN | GARDEN`** renders the full-strength **live** garden behind the
timer — in garden mode the **session sits up top and the timer docks at the bottom** (no scrim, text shadows).
*(True animated OS live wallpaper is **v14**; iOS keeps Save/Share.)*

**Top bar, timer & store (v13):** custom **pixel icons** (sliced from the user's sheets in `lib/icons.dart`) —
**theme/garden/stats · settings/store/coin**. The timer mode reads **FOCUS**; **SWITCH MODE** is gone (a focus
session **auto-starts the break**, or with **Settings → AUTO-START BREAK off** asks first). **Cancelling a
started session pays out the spent minutes.** The **shop** has tabs **FLOWERS / OUTER DECOR / INNER DECOR /
PETS** (last two coming soon).

**Theming & stats:** the **status + navigation bars match the theme** (`SystemChrome`); **no white tap ripple**.
**Labels rename** (long-press). **Stats** has a **DAILY/WEEKLY/MONTHLY/YEARLY/ALL-TIME** selector **plus a ◀▶
history navigator** to browse earlier periods; **bar tops show minutes**, the **pie** lists full labels with
right-aligned %, the **line is tappable** (callout: `TOTAL` + per-label, the day on the bottom axis), and
**DAILY** draws one line per label with a legend.

Korean uses the bundled **Galmuri11** pixel font (OFL, scaled up). The launcher icon is regenerated via
`flutter_launcher_icons` so the pixel tomato survives scaffolding.

## Credits

- **Press Start 2P** — Latin pixel font (OFL), CodeMan38.
- **Galmuri11** — Korean pixel font, © 2019–2025 Lee Minseo, licensed **OFL-1.1**
  (`assets/fonts/Galmuri-OFL.txt`). Used for the Korean locale.
