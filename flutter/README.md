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

Needs the Flutter SDK. From this folder:

```bash
flutter create --org com.pixelpomo --project-name pixel_pomo --platforms=ios,android .
git checkout -- pubspec.yaml lib && rm -f test/widget_test.dart
flutter pub get
flutter test
flutter run        # or: flutter build apk / flutter build ios --no-codesign
```

## Status / parity

Faithful port of v0.5.0: timer + sessions, 5 themes, focus labels with colors, stats (month
navigator + bar/line/pie charts), coins + shop with localized flowers, garden (plant/upgrade),
6 languages, and the first-launch test fixture (1000 coins + sample history). The pure logic is
shared test-for-test with the Kotlin original.
