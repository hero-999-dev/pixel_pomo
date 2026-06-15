# 🍅 Pixel Pomo — Flutter port (iOS + Android)

This folder is the **cross-platform port** of the native Android app (in `../app`). One Dart
codebase builds **both** an Android APK and an **iOS `.ipa`**, so iPhone is finally covered.

## Why it's structured this way

Only the **portable** parts live here and are committed:

```
flutter/
├── pubspec.yaml          # name: pixel_pomo, deps (shared_preferences), the pixel font
├── assets/fonts/PressStart2P-Regular.ttf
├── lib/
│   ├── logic.dart        # pure port of PomodoroEngine/Themes/Flowers/Economy/Garden/Labels/Stats/TestData
│   ├── strings.dart      # the six UI languages (en/tr/pl/de/ko/it) + month names
│   ├── store.dart        # AppStore (ChangeNotifier): state, persistence, countdown
│   ├── pixel.dart        # pixel widgets + the bar/line/pie chart painter + flower sprites
│   └── main.dart         # screens: timer + theme/garden/stats/settings/shop/label overlays
└── test/logic_test.dart  # Dart edge tests (gate the Flutter CI)
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
flutter test       # logic_test.dart + widget_smoke_test.dart
flutter run        # or: flutter build apk / flutter build ios --no-codesign
```

> **Low-RAM note:** the generated `android/gradle.properties` requests `-Xmx8G`, which can crash
> the Gradle daemon on memory-constrained machines. Cap it in `~/.gradle/gradle.properties`
> (`GRADLE_USER_HOME`), e.g. `org.gradle.jvmargs=-Xmx2560m -XX:MaxMetaspaceSize=768m` and
> `org.gradle.daemon=false` — this overrides the template and survives `flutter create`.

## Status / parity

Faithful port of v0.5.0: timer + sessions, 5 themes, focus labels with colors, stats (month
navigator + bar/line/pie charts), coins + shop with localized flowers, garden (plant/upgrade),
6 languages, and the first-launch test fixture (1000 coins + sample history). The pure logic is
shared test-for-test with the Kotlin original.
