# v23 App Blocker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Block a user-chosen set of apps during focus (WORK) sessions on Android via a full-screen "stay focused" overlay.

**Architecture:** Pure Dart owns the *state* (enabled flag, blocked package set, derived "active") and publishes it to `FlutterSharedPreferences`; a native Kotlin **AccessibilityService** reads that state, detects the foreground app, and shows a draw-over overlay when a blocked app opens during an active session. Native lives in `flutter/android_overlay/` (CI/`apply_overlay.py` copies it into the gitignored `android/`).

**Tech Stack:** Flutter/Dart, Android Kotlin (AccessibilityService + `TYPE_APPLICATION_OVERLAY` WindowManager + MethodChannel). No new pub dependencies.

## Global Constraints
- Flutter **3.44.2 / Dart 3.12.2**; no new pub deps (platform channel only).
- **Android-only**: every UI entry point gated by `Platform.isAndroid`; iOS unaffected.
- Native code lives in **`flutter/android_overlay/`**; `apply_overlay.py` copies it + patches `AndroidManifest.xml` idempotently (mirror the existing wallpaper patch).
- Pure logic goes in **`flutter/lib/logic.dart`** (no Flutter imports) so it is unit-tested in `flutter/test/` (the CI gate is `flutter test`).
- All **6 languages** (en/tr/pl/de/fr/it) get every new string.
- Channel name **`pixel_pomo/blocker`**; SharedPreferences keys (Flutter side, so they land under the `flutter.` prefix natively): `app_blocker` (bool), `blocked_apps` (csv), `blocker_active` (bool), `block_until` (int ms), `blocker_title`/`blocker_button` (localized overlay copy).
- Version → **0.23.0+24**.

---

### Task 1: Pure `AppBlocker` logic + codec (TDD)

**Files:**
- Modify: `flutter/lib/logic.dart` (add an `AppBlocker` class near `Flowers`)
- Test: `flutter/test/app_blocker_test.dart` (create)

**Interfaces:**
- Produces:
  - `bool AppBlocker.active({required bool enabled, required bool isRunning, required bool isWork, required bool isFinished})`
  - `String AppBlocker.encode(Set<String> pkgs)` / `Set<String> AppBlocker.decode(String? csv)`
  - `bool AppBlocker.shouldBlock(String pkg, Set<String> blocked, {required String ownPkg, String? launcherPkg})`

- [ ] **Step 1: Write the failing test** — `flutter/test/app_blocker_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_pomo/logic.dart';

void main() {
  group('AppBlocker (#v23)', () {
    test('active only during a running, unfinished WORK session when enabled', () {
      bool a({bool en = true, bool run = true, bool work = true, bool fin = false}) =>
          AppBlocker.active(enabled: en, isRunning: run, isWork: work, isFinished: fin);
      expect(a(), true);
      expect(a(en: false), false); // disabled
      expect(a(run: false), false); // paused/stopped
      expect(a(work: false), false); // break
      expect(a(fin: true), false); // finished
    });

    test('blocked-apps csv codec round-trips, dedupes, drops blanks', () {
      final s = {'com.a', 'com.b'};
      expect(AppBlocker.decode(AppBlocker.encode(s)), s);
      expect(AppBlocker.decode('com.a,com.a, ,com.b'), {'com.a', 'com.b'});
      expect(AppBlocker.decode(null), <String>{});
      expect(AppBlocker.encode(<String>{}), '');
    });

    test('shouldBlock: only blocked pkgs, never our app or the launcher', () {
      final b = {'com.insta', 'com.tiktok'};
      expect(AppBlocker.shouldBlock('com.insta', b, ownPkg: 'com.pixelpomo.pixel_pomo'), true);
      expect(AppBlocker.shouldBlock('com.other', b, ownPkg: 'com.pixelpomo.pixel_pomo'), false);
      expect(AppBlocker.shouldBlock('com.pixelpomo.pixel_pomo', b, ownPkg: 'com.pixelpomo.pixel_pomo'), false);
      expect(AppBlocker.shouldBlock('com.launcher', b, ownPkg: 'x', launcherPkg: 'com.launcher'), false);
    });
  });
}
```

- [ ] **Step 2: Run it, expect FAIL** — `& 'C:\src\flutter\bin\flutter.bat' test test/app_blocker_test.dart` → fails (`AppBlocker` undefined).

- [ ] **Step 3: Implement in `logic.dart`**

```dart
/// Pure app-blocker rules (#v23). The native AccessibilityService mirrors
/// [shouldBlock]/[active]; keep them in sync.
class AppBlocker {
  /// Blocking is on only while a focus (WORK) session is actually counting down.
  static bool active({
    required bool enabled,
    required bool isRunning,
    required bool isWork,
    required bool isFinished,
  }) =>
      enabled && isRunning && isWork && !isFinished;

  static String encode(Set<String> pkgs) =>
      (pkgs.toList()..sort()).where((p) => p.trim().isNotEmpty).join(',');

  static Set<String> decode(String? csv) => (csv ?? '')
      .split(',')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toSet();

  static bool shouldBlock(String pkg, Set<String> blocked,
          {required String ownPkg, String? launcherPkg}) =>
      blocked.contains(pkg) && pkg != ownPkg && pkg != launcherPkg;
}
```

- [ ] **Step 4: Run it, expect PASS.**
- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat(v23): pure AppBlocker rules + blocked-apps codec"`

---

### Task 2: `app_blocker.dart` channel wrapper (TDD the codec/guards)

**Files:**
- Create: `flutter/lib/app_blocker.dart`
- Test: `flutter/test/app_blocker_channel_test.dart` (create) — mirror `wallpaper_channel_test.dart`.

**Interfaces:**
- Produces (all on `MethodChannel('pixel_pomo/blocker')`, every call try/caught → safe default so iOS/host tests don't throw):
  - `class AppInfo { final String package, label; final Uint8List? icon; }`
  - `Future<List<AppInfo>> installedApps()`
  - `Future<bool> hasAccessibility()` · `Future<void> openAccessibilitySettings()`
  - `Future<bool> hasOverlay()` · `Future<void> openOverlaySettings()`
  - `Future<void> pushBlockerState({required bool active, required String blockedCsv, required int blockUntilMs, required String title, required String button})`

- [ ] **Step 1: Write the failing test** — `flutter/test/app_blocker_channel_test.dart`

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_pomo/app_blocker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const ch = MethodChannel('pixel_pomo/blocker');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ch, (c) async {
      calls.add(c);
      if (c.method == 'hasAccessibility') return true;
      if (c.method == 'installedApps') {
        return [
          {'package': 'com.a', 'label': 'A'},
        ];
      }
      return null;
    });
  });

  test('installedApps maps the native payload', () async {
    final apps = await installedApps();
    expect(apps.single.package, 'com.a');
    expect(apps.single.label, 'A');
  });

  test('pushBlockerState forwards args to the channel', () async {
    await pushBlockerState(active: true, blockedCsv: 'com.a', blockUntilMs: 123, title: 'T', button: 'B');
    final c = calls.firstWhere((c) => c.method == 'pushState');
    expect(c.arguments['active'], true);
    expect(c.arguments['blocked'], 'com.a');
    expect(c.arguments['blockUntil'], 123);
  });

  test('hasAccessibility returns the channel value', () async {
    expect(await hasAccessibility(), true);
  });
}
```

- [ ] **Step 2: Run it, expect FAIL** (no `app_blocker.dart`).

- [ ] **Step 3: Implement `flutter/lib/app_blocker.dart`**

```dart
import 'dart:typed_data';
import 'package:flutter/services.dart';

const _ch = MethodChannel('pixel_pomo/blocker');

class AppInfo {
  final String package;
  final String label;
  final Uint8List? icon;
  const AppInfo(this.package, this.label, this.icon);
}

Future<List<AppInfo>> installedApps() async {
  try {
    final raw = await _ch.invokeMethod<List<dynamic>>('installedApps') ?? [];
    final list = raw.map((e) {
      final m = (e as Map).cast<dynamic, dynamic>();
      return AppInfo(m['package'] as String, (m['label'] as String?) ?? (m['package'] as String),
          m['icon'] is Uint8List ? m['icon'] as Uint8List : null);
    }).toList();
    list.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return list;
  } catch (_) {
    return [];
  }
}

Future<bool> hasAccessibility() async {
  try {
    return await _ch.invokeMethod<bool>('hasAccessibility') ?? false;
  } catch (_) {
    return false;
  }
}

Future<bool> hasOverlay() async {
  try {
    return await _ch.invokeMethod<bool>('hasOverlay') ?? false;
  } catch (_) {
    return false;
  }
}

Future<void> openAccessibilitySettings() async {
  try {
    await _ch.invokeMethod('openAccessibilitySettings');
  } catch (_) {}
}

Future<void> openOverlaySettings() async {
  try {
    await _ch.invokeMethod('openOverlaySettings');
  } catch (_) {}
}

Future<void> pushBlockerState({
  required bool active,
  required String blockedCsv,
  required int blockUntilMs,
  required String title,
  required String button,
}) async {
  try {
    await _ch.invokeMethod('pushState', {
      'active': active,
      'blocked': blockedCsv,
      'blockUntil': blockUntilMs,
      'title': title,
      'button': button,
    });
  } catch (_) {}
}
```

- [ ] **Step 4: Run it, expect PASS.**
- [ ] **Step 5: Commit** — `git commit -am "feat(v23): pixel_pomo/blocker MethodChannel wrapper"`

---

### Task 3: AppStore state + persistence + publish

**Files:**
- Modify: `flutter/lib/store.dart`

**Interfaces:**
- Consumes: `AppBlocker.active`, `app_blocker.dart` `pushBlockerState`, `t(lang,'stayFocused'/'backToPomo')`.
- Produces: `store.appBlockerEnabled`, `store.blockedApps` (Set), `store.blockerActive` (getter), `store.setAppBlocker(bool)`, `store.setBlocked(String,bool)`, internal `_publishBlocker()`.

- [ ] **Step 1: Add fields + keys + load** (in `AppStore`)

```dart
// keys
static const _kBlocker = 'app_blocker';
static const _kBlocked = 'blocked_apps';
// state
bool appBlockerEnabled = false;
Set<String> blockedApps = {};
```
In `load()`:
```dart
appBlockerEnabled = _prefs.getBool(_kBlocker) ?? false;
blockedApps = AppBlocker.decode(_prefs.getString(_kBlocked));
```

- [ ] **Step 2: Add the derived getter + mutators + publisher**

```dart
bool get blockerActive => AppBlocker.active(
      enabled: appBlockerEnabled,
      isRunning: engine.isRunning,
      isWork: engine.mode == Mode.work,
      isFinished: engine.isFinished,
    );

void setAppBlocker(bool on) {
  appBlockerEnabled = on;
  _prefs.setBool(_kBlocker, on);
  _publishBlocker();
  notifyListeners();
}

void setBlocked(String pkg, bool on) {
  on ? blockedApps.add(pkg) : blockedApps.remove(pkg);
  _prefs.setString(_kBlocked, AppBlocker.encode(blockedApps));
  _publishBlocker();
  notifyListeners();
}

void _publishBlocker() {
  final active = blockerActive;
  // wall-clock end of the running WORK session (safety so a killed app can't block forever)
  final until = active ? DateTime.now().millisecondsSinceEpoch + engine.timeLeftMillis : 0;
  // The AccessibilityService runs in a SEPARATE PROCESS and reads these from
  // SharedPreferences (native sees them under the `flutter.` prefix), so writing
  // the prefs IS the IPC — there is no channel push for state. `app_blocker` and
  // `blocked_apps` are already persisted by their setters.
  _prefs.setBool('blocker_active', active);
  _prefs.setInt('block_until', until);
  _prefs.setString('blocker_title', t(lang, 'stayFocused'));
  _prefs.setString('blocker_button', t(lang, 'backToPomo'));
}
```

> **Plan correction (self-review):** state crosses to the native service via prefs, NOT the channel. So drop `pushBlockerState` from Task 2's `app_blocker.dart` (keep only `installedApps` + the 4 permission methods) and its channel test; drop the `pushState` case from Task 8's `MainActivity` handler. The channel is only for `installedApps` + permission checks/opens.

- [ ] **Step 3: Call `_publishBlocker()` on every state change that flips `blockerActive`** — at the end of `toggleStartPause`, `reset`, `confirmBreak`, `selectLanguage`, and the `_onTick` branch that finishes a phase / advances mode (search existing methods; add `_publishBlocker();` before their `notifyListeners()`).

- [ ] **Step 4: Verify** — `& 'C:\src\flutter\bin\flutter.bat' analyze` → no issues.
- [ ] **Step 5: Commit** — `git commit -am "feat(v23): AppStore blocker state, persistence, publish-to-native"`

---

### Task 4: Strings for all 6 languages

**Files:**
- Modify: `flutter/lib/strings.dart`

- [ ] **Step 1: Add these keys to EVERY language map** (en values shown; translate per language — tr/pl/de/fr/it):

```
'appBlocker': 'APP BLOCKER',
'blockedApps': 'BLOCKED APPS',
'blockerPermTitle': 'Permissions needed',
'blockerPermBody': 'Pixel Pomo needs Accessibility (to see which app is open) and Draw-over-apps (to show the focus screen).',
'grantAccess': 'GRANT ACCESSIBILITY',
'grantOverlay': 'GRANT OVERLAY',
'stayFocused': 'STAY FOCUSED',
'backToPomo': 'BACK TO PIXEL POMO',
'pickBlocked': 'TAP APPS TO BLOCK DURING FOCUS',
```
(tr: `APP BLOCKER`/`ENGELLİ UYGULAMALAR`/`İzin gerekli`/`Pixel Pomo, hangi uygulamanın açık olduğunu görmek için Erişilebilirlik ve odak ekranını göstermek için Üstte-göster izni ister.`/`ERİŞİLEBİLİRLİK VER`/`ÜSTTE GÖSTER VER`/`ODAKLAN`/`PIXEL POMO'YA DÖN`/`ODAKTA ENGELLENECEK UYGULAMALARA DOKUN` — and equivalents for pl/de/fr/it.)

- [ ] **Step 2: Verify** `flutter analyze` clean.
- [ ] **Step 3: Commit** — `git commit -am "i18n(v23): app-blocker strings (6 langs)"`

---

### Task 5: Settings UI + AppPickerScreen + permission flow

**Files:**
- Modify: `flutter/lib/main.dart`

**Interfaces:** Consumes `store.appBlockerEnabled/blockedApps/setAppBlocker/setBlocked`, `app_blocker.dart` (`installedApps`, `hasAccessibility`, `hasOverlay`, `openAccessibilitySettings`, `openOverlaySettings`).

- [ ] **Step 1: Add an Android-only APP BLOCKER section to `SettingsScreen.build`** (after the AUTO-START BREAK block, before SAVE):

```dart
if (Platform.isAndroid) ...[
  const SizedBox(height: 24),
  Text(t(lang, 'appBlocker'), style: pixelStyle(lang, 12, col(th.onSurfaceDim), text: t(lang, 'appBlocker'))),
  const SizedBox(height: 12),
  Row(children: [
    for (final on in const [true, false]) ...[
      if (!on) const SizedBox(width: 12),
      Expanded(child: PixelButton(
        text: on ? 'ON' : 'OFF',
        fill: s.appBlockerEnabled == on ? th.accent : th.panel,
        border: s.appBlockerEnabled == on ? th.onSurface : th.onSurfaceDim,
        textColor: s.appBlockerEnabled == on ? th.onAccent : th.onSurface,
        shadow: th.shadow, lang: lang, fontSize: 11,
        onTap: () => _toggleBlocker(context, s, on),
      )),
    ],
  ]),
  const SizedBox(height: 12),
  secondaryBtn(th, lang, t(lang, 'blockedApps'),
      () => openPanel(context, s, () => AppPickerScreen(s)), fontSize: 11),
],
```

- [ ] **Step 2: Add `_toggleBlocker` (permission flow) to `_SettingsScreenState`**

```dart
Future<void> _toggleBlocker(BuildContext context, AppStore s, bool on) async {
  if (!on) { s.setAppBlocker(false); return; }
  final ok = await hasAccessibility() && await hasOverlay();
  if (ok) { s.setAppBlocker(true); return; }
  if (!context.mounted) return;
  final th = s.theme; final lang = s.lang;
  showDialog(context: context, builder: (ctx) => AlertDialog(
    backgroundColor: col(th.panel),
    title: Text(t(lang, 'blockerPermTitle'), style: pixelStyle(lang, 12, col(th.onSurface), text: t(lang, 'blockerPermTitle'))),
    content: Text(t(lang, 'blockerPermBody'), style: pixelStyle(lang, 10, col(th.onSurfaceDim), text: t(lang, 'blockerPermBody'))),
    actions: [
      TextButton(onPressed: openAccessibilitySettings, child: Text(t(lang, 'grantAccess'), style: pixelStyle(lang, 10, col(th.accent), text: t(lang, 'grantAccess')))),
      TextButton(onPressed: openOverlaySettings, child: Text(t(lang, 'grantOverlay'), style: pixelStyle(lang, 10, col(th.accent), text: t(lang, 'grantOverlay')))),
      TextButton(onPressed: () async { Navigator.pop(ctx); if (await hasAccessibility() && await hasOverlay()) s.setAppBlocker(true); },
          child: Text(t(lang, 'done'), style: pixelStyle(lang, 10, col(th.onSurface), text: t(lang, 'done')))),
    ],
  ));
}
```
Add `import 'dart:io';` (Platform) and `import 'app_blocker.dart';` if not present.

- [ ] **Step 3: Add `AppPickerScreen`** (new StatefulWidget in main.dart)

```dart
class AppPickerScreen extends StatelessWidget {
  final AppStore s;
  const AppPickerScreen(this.s, {super.key});
  @override
  Widget build(BuildContext context) {
    final th = s.theme; final lang = s.lang;
    return overlayScaffold(context, s, t(lang, 'blockedApps'), [
      Text(t(lang, 'pickBlocked'), style: pixelStyle(lang, 9, col(th.onSurfaceDim), text: t(lang, 'pickBlocked'))),
      const SizedBox(height: 12),
      FutureBuilder<List<AppInfo>>(
        future: installedApps(),
        builder: (context, snap) {
          if (!snap.hasData) return Center(child: Text('...', style: pixelStyle(lang, 14, col(th.onSurfaceDim), text: '...')));
          return Column(children: [
            for (final a in snap.data!)
              Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [
                a.icon != null
                    ? Image.memory(a.icon!, width: 32, height: 32, filterQuality: FilterQuality.none)
                    : const SizedBox(width: 32, height: 32),
                const SizedBox(width: 12),
                Expanded(child: Text(a.label, style: pixelStyle(lang, 10, col(th.onSurface), text: a.label), maxLines: 1, overflow: TextOverflow.ellipsis)),
                _Toggle(on: s.blockedApps.contains(a.package), onTap: () => s.setBlocked(a.package, !s.blockedApps.contains(a.package))),
              ])),
          ]);
        },
      ),
    ]);
  }
}

class _Toggle extends StatelessWidget {
  final bool on; final VoidCallback onTap;
  const _Toggle({required this.on, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: onTap, child: Container(
    width: 44, height: 24, color: on ? const Color(0xFF46E08A) : const Color(0xFF555555),
    alignment: on ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(width: 22, height: 24, color: const Color(0xFFF4F4F4)),
  ));
}
```
(Wrap `AppPickerScreen` in `AnimatedBuilder(animation: s, ...)` via `openPanel`, which already does so — the toggles rebuild live.)

- [ ] **Step 4: Verify** `flutter analyze` clean; `flutter test` (smoke still boots).
- [ ] **Step 5: Commit** — `git commit -am "feat(v23): settings app-blocker toggle + permission flow + app picker screen"`

---

### Task 6: Native `BlockerData.kt`

**Files:**
- Create: `flutter/android_overlay/app/src/main/kotlin/com/pixelpomo/pixel_pomo/BlockerData.kt`

- [ ] **Step 1: Implement** (reads the Flutter-published prefs; mirrors Dart `shouldBlock`/`active`)

```kotlin
package com.pixelpomo.pixel_pomo

import android.content.Context

object BlockerData {
    private fun prefs(ctx: Context) =
        ctx.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

    fun active(ctx: Context): Boolean {
        val p = prefs(ctx)
        if (!p.getBoolean("flutter.blocker_active", false)) return false
        val until = p.getLong("flutter.block_until", 0L)
        return System.currentTimeMillis() < until
    }

    fun blocked(ctx: Context): Set<String> =
        (p(ctx, "flutter.blocked_apps") ?: "").split(",").map { it.trim() }.filter { it.isNotEmpty() }.toSet()

    fun title(ctx: Context) = p(ctx, "flutter.blocker_title") ?: "STAY FOCUSED"
    fun button(ctx: Context) = p(ctx, "flutter.blocker_button") ?: "BACK TO PIXEL POMO"
    fun themeBg(ctx: Context): Int {
        // mirror PixelTheme bg for the active theme id; default dark
        return when (p(ctx, "flutter.theme_id")) {
            "light", "latte" -> 0xFFF2F2F4.toInt()
            else -> 0xFF161616.toInt()
        }
    }

    private fun p(ctx: Context, k: String): String? = prefs(ctx).getString(k, null)

    fun shouldBlock(ctx: Context, pkg: String, own: String, launcher: String?): Boolean =
        active(ctx) && blocked(ctx).contains(pkg) && pkg != own && pkg != launcher
}
```

- [ ] **Step 2: Commit** — `git add -A && git commit -m "feat(v23): native BlockerData reads published blocker state"`

---

### Task 7: Native `AppBlockerService.kt` (AccessibilityService + overlay)

**Files:**
- Create: `flutter/android_overlay/app/src/main/kotlin/com/pixelpomo/pixel_pomo/AppBlockerService.kt`
- Create: `flutter/android_overlay/app/src/main/res/xml/app_blocker_accessibility.xml`

- [ ] **Step 1: Accessibility config** — `app_blocker_accessibility.xml`

```xml
<?xml version="1.0" encoding="utf-8"?>
<accessibility-service xmlns:android="http://schemas.android.com/apk/res/android"
    android:accessibilityEventTypes="typeWindowStateChanged"
    android:accessibilityFeedbackType="feedbackGeneric"
    android:notificationTimeout="100"
    android:canRetrieveWindowContent="false" />
```

- [ ] **Step 2: Service + overlay** — `AppBlockerService.kt`

```kotlin
package com.pixelpomo.pixel_pomo

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

class AppBlockerService : AccessibilityService() {
    private var overlay: View? = null
    private val handler = Handler(Looper.getMainLooper())
    private val tick = object : Runnable {
        override fun run() {
            if (!BlockerData.active(this@AppBlockerService)) hide()
            handler.postDelayed(this, 1000)
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        handler.postDelayed(tick, 1000)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val pkg = event?.packageName?.toString() ?: return
        val launcher = launcherPkg()
        if (BlockerData.shouldBlock(this, pkg, packageName, launcher)) show() else hide()
    }

    override fun onInterrupt() {}

    private fun launcherPkg(): String? {
        val i = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        return packageManager.resolveActivity(i, 0)?.activityInfo?.packageName
    }

    private fun show() {
        if (overlay != null) return
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(BlockerData.themeBg(this@AppBlockerService))
            addView(TextView(context).apply {
                text = BlockerData.title(this@AppBlockerService)
                setTextColor(Color.WHITE); textSize = 22f; gravity = Gravity.CENTER
            })
            addView(Button(context).apply {
                text = BlockerData.button(this@AppBlockerService)
                setOnClickListener {
                    val li = packageManager.getLaunchIntentForPackage(packageName)
                        ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                    if (li != null) startActivity(li)
                    hide()
                }
            })
        }
        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            android.graphics.PixelFormat.OPAQUE,
        )
        try { wm.addView(root, lp); overlay = root } catch (_: Exception) {}
    }

    private fun hide() {
        val o = overlay ?: return
        try { (getSystemService(WINDOW_SERVICE) as WindowManager).removeView(o) } catch (_: Exception) {}
        overlay = null
    }

    override fun onDestroy() {
        handler.removeCallbacks(tick); hide(); super.onDestroy()
    }
}
```

- [ ] **Step 3: Commit** — `git add -A && git commit -m "feat(v23): AccessibilityService + draw-over focus overlay"`

---

### Task 8: Native `MainActivity.kt` channel (apps + permissions + pushState)

**Files:**
- Modify: `flutter/android_overlay/app/src/main/kotlin/com/pixelpomo/pixel_pomo/MainActivity.kt`

- [ ] **Step 1: Register the `pixel_pomo/blocker` channel** in `configureFlutterEngine` (alongside the existing wallpaper channel):

```kotlin
MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pixel_pomo/blocker").setMethodCallHandler { call, result ->
    when (call.method) {
        "installedApps" -> result.success(installedApps())
        "hasAccessibility" -> result.success(isAccessibilityOn())
        "openAccessibilitySettings" -> { startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)); result.success(null) }
        "hasOverlay" -> result.success(Settings.canDrawOverlays(this))
        "openOverlaySettings" -> {
            startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
            result.success(null)
        }
        "pushState" -> result.success(null) // state already written to prefs by Flutter shared_preferences
        else -> result.notImplemented()
    }
}
```

- [ ] **Step 2: Add helpers**

```kotlin
private fun isAccessibilityOn(): Boolean {
    val flat = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: return false
    return flat.contains("$packageName/.AppBlockerService")
}

private fun installedApps(): List<Map<String, Any?>> {
    val pm = packageManager
    val main = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
    return pm.queryIntentActivities(main, 0)
        .map { it.activityInfo.packageName }
        .filter { it != packageName }
        .distinct()
        .map { pkg ->
            val label = try { pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString() } catch (_: Exception) { pkg }
            mapOf("package" to pkg, "label" to label, "icon" to iconPng(pkg))
        }
}

private fun iconPng(pkg: String): ByteArray? = try {
    val d = packageManager.getApplicationIcon(pkg)
    val bmp = android.graphics.Bitmap.createBitmap(48, 48, android.graphics.Bitmap.Config.ARGB_8888)
    val c = android.graphics.Canvas(bmp); d.setBounds(0, 0, 48, 48); d.draw(c)
    val bos = java.io.ByteArrayOutputStream(); bmp.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, bos); bos.toByteArray()
} catch (_: Exception) { null }
```
Add imports: `android.content.Intent`, `android.net.Uri`, `android.provider.Settings`, `io.flutter.plugin.common.MethodChannel`.

- [ ] **Step 3: Commit** — `git add -A && git commit -m "feat(v23): blocker channel — installedApps, perms, pushState"`

---

### Task 9: Manifest patch in `apply_overlay.py` + res copy

**Files:**
- Modify: `flutter/android_overlay/apply_overlay.py`

- [ ] **Step 1: Ensure `res/xml` + the new Kotlin are copied** — `copy_tree("kotlin")` / `copy_tree("res")` already recurse; confirm `app_blocker_accessibility.xml` lands. No code change if `res` is already copied; otherwise add `copy_tree(os.path.join("res", "xml"))`.

- [ ] **Step 2: Add a manifest patch for the blocker** (new function, called from `main`, mirroring `patch_manifest`):

```python
def patch_blocker(xml):
    if "AppBlockerService" not in xml:
        svc = (
            '        <service\n'
            '            android:name=".AppBlockerService"\n'
            '            android:exported="false"\n'
            '            android:permission="android.permission.BIND_ACCESSIBILITY_SERVICE">\n'
            '            <intent-filter>\n'
            '                <action android:name="android.accessibilityservice.AccessibilityService" />\n'
            '            </intent-filter>\n'
            '            <meta-data android:name="android.accessibilityservice"\n'
            '                android:resource="@xml/app_blocker_accessibility" />\n'
            '        </service>\n'
        )
        xml = xml.replace("</application>", svc + "    </application>")
    for perm in ("android.permission.SYSTEM_ALERT_WINDOW", "android.permission.QUERY_ALL_PACKAGES"):
        if perm not in xml:
            xml = xml.replace("<application", f'<uses-permission android:name="{perm}" />\n    <application', 1)
    return xml
```
Wire it: read manifest, `xml = patch_blocker(xml)` (in addition to the existing wallpaper patch), write back. Keep idempotent.

- [ ] **Step 3: Run it** — `cd flutter && python android_overlay/apply_overlay.py` → prints copies, "manifest already patched"/patches; no error.
- [ ] **Step 4: Commit** — `git add -A && git commit -m "build(v23): apply_overlay copies + patches manifest for the app blocker"`

---

### Task 10: Smoke test, version bump, build, deliver

**Files:**
- Modify: `flutter/test/widget_smoke_test.dart`, `flutter/pubspec.yaml`, docs (`log.md`, `prompt.md`, `TESTING.md`, `README.md`, `flutter/README.md`).

- [ ] **Step 1: Extend the smoke test** — open Settings, assert the `appBlocker` text shows (Android path runs in the test host? `Platform.isAndroid` is false in `flutter test` on desktop → the section is hidden). So instead assert the **store** path: `store.setAppBlocker(true)`, `store.setBlocked('com.x', true)`, then `expect(store.blockedApps.contains('com.x'), true)` and `expect(store.blockerActive, ...)` for a running work session. Add as a widget/unit test block.

- [ ] **Step 2: Bump version** — `pubspec.yaml`: `version: 0.23.0+24`.

- [ ] **Step 3: analyze + test** — `flutter analyze` clean; `flutter test` all green (Task 1/2 tests + smoke).

- [ ] **Step 4: Build release** — `python android_overlay/apply_overlay.py` then `flutter build apk --release`; confirm it builds.

- [ ] **Step 5: Docs** — add a v23 entry to `log.md`, update `prompt.md` (new App Blocker section + the Settings/permissions), `TESTING.md` (new tests + device-verify notes), READMEs (mention the Android app blocker).

- [ ] **Step 6: Commit, merge, deliver** — commit docs; merge `v23-app-blocker` → `main` (`--no-ff`); push; build APK → `gh release create flutter-v23 ... pixel_pomo_flutter.apk` (or upload); Android-only (no iOS — macOS minutes out).

---

## Notes for the implementer
- The Accessibility service, overlay, app list, and permission grants are **device-verified by the user** — `flutter test` cannot exercise them. The pure rules (Task 1), the channel wrapper (Task 2), and the store derivation are the automated safety net.
- Keep Dart `AppBlocker.shouldBlock`/`active` and Kotlin `BlockerData` in sync.
- Mirror the wallpaper plumbing you already have (`GardenData`/prefs/`apply_overlay.py`) — this feature is the same shape.
