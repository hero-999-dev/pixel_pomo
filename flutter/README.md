# 🍅 Pixel Pomo — Flutter port (iOS + Android)

This folder is the **cross-platform port** of the native Android app (in `../app`). One Dart
codebase builds **both** an Android APK and an **iOS `.ipa`**, so iPhone is finally covered.

## Why it's structured this way

Only the **portable** parts live here and are committed:

```
flutter/
├── pubspec.yaml          # name: pixel_pomo, deps (shared_preferences, share_plus, path_provider), pixel font, flutter_launcher_icons
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
flutter test       # logic_test.dart + engine_test.dart + widget_smoke_test.dart (31)
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
drawn by a tiny custom engine (`lib/engine/`) — no Unity/Flame. The whole screen is one projected
world: a **rectangular `cols × rows` claimed plot (starts 4×6)** sits centered inside a **forest
border** of the *same* world, so the garden reads as a clearing in the woods. **EXPAND grows the plot
from the center** (+2 ring, no cap) and **converts the inner ring of dark trees to grass** — the
forest recedes as you develop. The tilt is fixed, but you can **rotate by hand** (two-finger twist),
**pinch-zoom (1×–4×) and pan**, all **clamped** to the world. **CUSTOMIZE** shows tile gridlines.
**Lighting is flat sky-ambient** — nothing is shaded by view angle. Roads lie flat; **fences are real
low-poly 3D** — upright post meshes (brighter sky-lit top) joined by **raised 3D rails** to any
adjacent fence (wood↔dark↔stone), keeping a solid footprint from every angle; a fence can stand **on
top of a road** (flowers can't). **Flowers and forest trees are flat billboards** (depth-sorted);
**only critters** (tiny **bee/butterfly/ladybug**) use an 8-direction atlas to face their heading,
drifting in to **visit a flower** then leaving. The SHOP sells **4 road** + **3 fence** materials
(5 coins each). The wallet shows a **plain 2D gold coin**.

**New in v11 — peek, camera & backgrounds:** a bottom-left **peek** button hides *all* HUD for a clean
view; next to it a **camera mode** lets you frame any angle and **screenshot** the garden
(`RepaintBoundary` → PNG). The shot can be **set as the garden section's static backdrop** (persisted
via `path_provider`) or **saved/shared** to use as a phone wallpaper (`share_plus`). Separately,
**Settings → HOME SCREEN** toggles **`CLEAN | GARDEN`**: GARDEN renders a dimmed **live** garden
(critters wandering, wallpaper-engine style) behind the pomodoro timer — the engine doubling as a live
backdrop. (No OS live-wallpaper service: iOS has no API and Android would need native code that breaks
the no-Mac CI; the static photo is shown only in the garden section, never behind the running timer.)

Korean uses the bundled **Galmuri11** pixel font (OFL, scaled up). The launcher icon is regenerated via
`flutter_launcher_icons` so the pixel tomato survives scaffolding.

## Credits

- **Press Start 2P** — Latin pixel font (OFL), CodeMan38.
- **Galmuri11** — Korean pixel font, © 2019–2025 Lee Minseo, licensed **OFL-1.1**
  (`assets/fonts/Galmuri-OFL.txt`). Used for the Korean locale.
