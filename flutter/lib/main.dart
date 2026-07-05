import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_blocker.dart';
import 'camera.dart';
import 'engine/garden_engine.dart';
import 'engine/garden_view.dart';
import 'logic.dart';
import 'pixel.dart';
import 'store.dart';
import 'strings.dart';

/// Small PNG thumbnail for a garden object (road/fence), crisp pixels. Every
/// object PNG is now a single frame (fences render as 3D meshes in the garden,
/// but keep a flat post sprite for this thumbnail).
Widget objectThumb(String id, double size) {
  final img = Image.asset('assets/objects/$id.png',
      filterQuality: FilterQuality.none, fit: BoxFit.fill);
  return SizedBox(width: size, height: size, child: img);
}

/// SpriteBank is loaded once and shared across garden opens.
Future<SpriteBank>? _spritesFuture;
Future<SpriteBank> gardenSprites() => _spritesFuture ??= SpriteBank.load();

final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Draw behind the system bars so camera/peek mode can show the garden edge-to-
  // edge under transparent bars — matches the live-wallpaper preview, kills the
  // leftover gray nav-bar strip (#v22).
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final store = AppStore();
  await store.load();
  runApp(PixelPomoApp(store));
}

class PixelPomoApp extends StatefulWidget {
  final AppStore store;
  const PixelPomoApp(this.store, {super.key});
  @override
  State<PixelPomoApp> createState() => _PixelPomoAppState();
}

class _PixelPomoAppState extends State<PixelPomoApp> with WidgetsBindingObserver {
  AppStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    store.messenger = (key) {
      messengerKey.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(t(store.lang, key), style: pixelStyle(store.lang, 11, const Color(0xFFFFFFFF), text: t(store.lang, key))),
          duration: const Duration(seconds: 2),
        ));
    };
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Background mid-session → raise the ongoing countdown notification (#v23 fb);
    // AppStore's stop paths cancel it.
    if (state == AppLifecycleState.paused) store.onBackgrounded();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final th = store.theme;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: systemOverlayFor(th),
          child: MaterialApp(
            title: 'Pixel Pomo',
            debugShowCheckedModeBanner: false,
            scaffoldMessengerKey: messengerKey,
            theme: ThemeData(
              useMaterial3: false,
              scaffoldBackgroundColor: col(th.bg),
              splashFactory: NoSplash.splashFactory, // #12 no white ripple
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
            ),
            home: HomeScreen(store),
          ),
        );
      },
    );
  }
}

// ---- shared button helpers --------------------------------------------------

PixelButton primaryBtn(PixelTheme th, String lang, String text, VoidCallback? onTap,
        {double fontSize = 13, EdgeInsets padding = const EdgeInsets.all(14), double opacity = 1, Key? key}) =>
    PixelButton(
        key: key,
        text: text, fill: th.accent, border: th.onSurface, textColor: th.onAccent, shadow: th.shadow,
        lang: lang, onTap: onTap, fontSize: fontSize, padding: padding, opacity: opacity);

PixelButton secondaryBtn(PixelTheme th, String lang, String text, VoidCallback? onTap,
        {double fontSize = 13, EdgeInsets padding = const EdgeInsets.all(14), double opacity = 1, Key? key}) =>
    PixelButton(
        key: key,
        text: text, fill: th.panel, border: th.onSurfaceDim, textColor: th.onSurface, shadow: th.shadow,
        lang: lang, onTap: onTap, fontSize: fontSize, padding: padding, opacity: opacity);

/// A full-screen overlay scaffold with a title and a trailing CLOSE button.
Widget overlayScaffold(BuildContext context, AppStore s, String title, List<Widget> children) {
  final th = s.theme;
  return Scaffold(
    backgroundColor: col(th.bg),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Center(child: Text(title, style: pixelStyle(s.lang, 20, col(th.onSurface), spacing: 2, text: title))),
            const SizedBox(height: 24),
            ...children,
            const SizedBox(height: 24),
            secondaryBtn(th, s.lang, t(s.lang, 'close'), () => Navigator.pop(context), padding: const EdgeInsets.all(16)),
          ],
        ),
      ),
    ),
  );
}

void openPanel(BuildContext context, AppStore s, Widget Function() builder) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => AnimatedBuilder(animation: s, builder: (_, __) => builder())));
}

// ---- home / timer -----------------------------------------------------------

class HomeScreen extends StatelessWidget {
  final AppStore s;
  const HomeScreen(this.s, {super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: s,
      builder: (context, _) {
        final th = s.theme;
        final lang = s.lang;
        final e = s.engine;
        final modeText = e.isFinished
            ? t(lang, 'allDone')
            : (e.mode == Mode.work ? t(lang, 'work') : t(lang, 'break'));
        final modeColor = e.isFinished ? th.accent : th.phaseColor(e.mode);
        // auto-break off: ask before starting the break (#4)
        if (s.awaitingBreakPrompt) {
          // after focus the next phase is a break; after a break it's the next
          // focus session — ask the matching question (#v25 item1)
          final promptKey = e.mode == Mode.work ? 'startSessionTitle' : 'startBreakTitle';
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!s.awaitingBreakPrompt) return;
            s.awaitingBreakPrompt = false; // guard against re-entry
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: col(th.panel),
                title: Text(t(lang, promptKey), style: pixelStyle(lang, 12, col(th.onSurface), text: t(lang, promptKey))),
                actions: [
                  TextButton(onPressed: () { Navigator.pop(ctx); s.confirmBreak(false); },
                      child: Text(t(lang, 'no'), style: pixelStyle(lang, 11, col(th.onSurfaceDim), text: t(lang, 'no')))),
                  TextButton(onPressed: () { Navigator.pop(ctx); s.confirmBreak(true); },
                      child: Text(t(lang, 'yes'), style: pixelStyle(lang, 11, col(th.accent), text: t(lang, 'yes')))),
                ],
              ),
            );
          });
        }
        final garden = s.homeGardenBackdrop;
        // in garden mode the timer is drawn over the live scene, so give its text
        // a hard pixel shadow for legibility instead of a scrim box (#5/#7)
        final shadows = garden
            ? const [Shadow(offset: Offset(2, 2), color: Color(0xCC000000))]
            : const <Shadow>[];
        // over the dark garden the foreground text must be LIGHT — on light themes
        // th.onSurface is dark and was unreadable / looked "darkened" (#v19 #6).
        final overGarden = garden ? const Color(0xFFF4F4F4) : col(th.onSurface);
        final timerBlock = Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(modeText, style: pixelStyle(lang, 22, col(modeColor), spacing: 2, text: modeText).copyWith(shadows: shadows)),
            const SizedBox(height: 16),
            secondaryBtn(th, lang, s.currentLabel, () => openPanel(context, s, () => LabelScreen(s)),
                fontSize: 11, padding: const EdgeInsets.all(10)),
            const SizedBox(height: 28),
            Text(e.formattedTime(), style: pixelStyle(lang, 48, overGarden, text: e.formattedTime()).copyWith(shadows: shadows)),
            const SizedBox(height: 32),
            PixelProgress(
                percent: e.progressPercent(),
                track: th.panel,
                border: th.onSurfaceDim,
                fill: e.isFinished ? th.accent : th.phaseColor(e.mode)),
            const SizedBox(height: 36),
            Row(children: [
              Expanded(
                  child: primaryBtn(th, lang, t(lang, e.isRunning ? 'pause' : 'start'),
                      s.toggleStartPause, fontSize: 14, padding: const EdgeInsets.all(16))),
              const SizedBox(width: 16),
              Expanded(
                  child: secondaryBtn(th, lang, t(lang, 'reset'), s.reset,
                      fontSize: 14, padding: const EdgeInsets.all(16))),
            ]),
          ],
        );
        final sessionText = Text(tf(lang, 'session', [e.session, e.totalSessions]),
            style: pixelStyle(lang, 12, garden ? overGarden : col(th.onSurfaceDim), text: tf(lang, 'session', [e.session, e.totalSessions])).copyWith(shadows: shadows));

        return Scaffold(
          backgroundColor: col(th.bg),
          body: Stack(
            children: [
              // live garden behind the timer when HOME mode = GARDEN (#3)
              if (garden) Positioned.fill(child: _liveBackdrop(th, lang)),
              SafeArea(
                child: garden
                    // garden mode: SESSION on its own centered line just below the
                    // top bar (the icon row was too crowded to hold it — #v19), timer
                    // docked at the bottom over the full garden
                    ? Column(children: [
                        _topBar(context, th, lang),
                        Padding(
                          padding: const EdgeInsets.only(top: 2, bottom: 4),
                          child: sessionText,
                        ),
                        const Spacer(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                          child: timerBlock,
                        ),
                      ])
                    // clean mode: the centered timer (today's layout)
                    : Column(children: [
                        _topBar(context, th, lang),
                        Expanded(
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(mainAxisSize: MainAxisSize.min, children: [
                                timerBlock,
                                const SizedBox(height: 24),
                                sessionText,
                              ]),
                            ),
                          ),
                        ),
                      ]),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _liveBackdrop(PixelTheme th, String lang) {
    return FutureBuilder<SpriteBank>(
      future: gardenSprites(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        // full strength — no dimming wash (#7); the timer gets its own scrim
        return GardenView(
          garden: s.garden,
          sprites: snap.data!,
          customizing: false,
          onTapTile: (_) {},
          groundColor: _gardenGround,
          soilColor: _gardenSoil,
          uiColor: th.onSurface,
          panelColor: th.panel,
          lang: lang,
          tr: (k) => t(lang, k),
          interactive: false,
        );
      },
    );
  }

  // left = money/habit/stats/garden/theme · right = settings/store/coin
  // (user-specified order, #v30 item 1).
  Widget _topBar(BuildContext context, PixelTheme th, String lang) {
    // over the live garden wallpaper, give the coin count a hard pixel shadow +
    // a LIGHT colour (th.onSurface is dark on light themes) for legibility (#v19 #6).
    final shadows = s.homeGardenBackdrop
        ? const [Shadow(offset: Offset(2, 2), color: Color(0xCC000000))]
        : const <Shadow>[];
    final coinColor = s.homeGardenBackdrop ? const Color(0xFFF4F4F4) : col(th.onSurface);
    // 5 icons on the left; slightly bigger glyphs + looser padding so they
    // don't read as crammed into the screen corners (#v30 item 1).
    Widget icon(String name, VoidCallback onTap, Key key) => IconButton(
          key: key,
          padding: const EdgeInsets.all(6),
          constraints: const BoxConstraints(),
          visualDensity: VisualDensity.compact,
          icon: Image.asset('assets/icon/icon_$name.png', width: 30, height: 30, filterQuality: FilterQuality.none),
          onPressed: onTap,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      // spread all 8 evenly across the bar, not two clusters split by a
      // Spacer (that stacked them all on the left, #v30 follow-up).
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        icon('money', () => openPanel(context, s, () => MoneyScreen(s)), const Key('moneyButton')),
        icon('habit', () => openPanel(context, s, () => HabitScreen(s)), const Key('habitButton')),
        icon('stats', () => openPanel(context, s, () => StatsScreen(s)), const Key('statsButton')),
        icon('garden', () => openPanel(context, s, () => GardenScreen(s)), const Key('gardenButton')),
        icon('theme', () => openPanel(context, s, () => ThemeScreen(s)), const Key('themeButton')),
        icon('settings', () => openPanel(context, s, () => SettingsScreen(s)), const Key('settingsButton')),
        icon('store', () => openPanel(context, s, () => ShopScreen(s)), const Key('storeButton')),
        GestureDetector(
          key: const Key('shopButton'),
          onTap: () => openPanel(context, s, () => ShopScreen(s)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(children: [
              const GoldCoin(size: 32),
              const SizedBox(width: 6),
              Text('${s.coins}', style: pixelStyle(lang, 14, coinColor, text: '${s.coins}').copyWith(shadows: shadows)),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ---- settings ---------------------------------------------------------------

class SettingsScreen extends StatefulWidget {
  final AppStore s;
  const SettingsScreen(this.s, {super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late int work = widget.s.workMin;
  late int brk = widget.s.breakMin;
  late int sess = widget.s.sessions;

  // No SAVE button (#v23 fb): each stepper change applies + persists immediately,
  // like the language / auto-break / blocker toggles already do.
  void _apply(VoidCallback change) {
    setState(change);
    widget.s.saveSettings(work, brk, sess);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final th = s.theme;
    final lang = s.lang;
    return overlayScaffold(context, s, t(lang, 'settings'), [
      _stepper(th, lang, t(lang, 'study'), work, 5, 300, 5, (v) => _apply(() => work = v)),
      _stepper(th, lang, t(lang, 'breakMin'), brk, 1, 120, 1, (v) => _apply(() => brk = v)),
      _stepper(th, lang, t(lang, 'sessions'), sess, 1, 24, 1, (v) => _apply(() => sess = v)),
      const SizedBox(height: 24),
      Text(t(lang, 'language'), style: pixelStyle(lang, 12, col(th.onSurfaceDim), text: t(lang, 'language'))),
      const SizedBox(height: 12),
      for (final opt in languageOptions)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: PixelButton(
            text: (opt[0] == lang ? '> ' : '') + opt[1],
            fill: opt[0] == lang ? th.accent : th.panel,
            border: opt[0] == lang ? th.onSurface : th.onSurfaceDim,
            textColor: opt[0] == lang ? th.onAccent : th.onSurface,
            shadow: th.shadow,
            lang: opt[0], // autonym renders in its own script
            onTap: () => s.selectLanguage(opt[0]),
          ),
        ),
      const SizedBox(height: 24),
      Text(t(lang, 'homeMode'), style: pixelStyle(lang, 12, col(th.onSurfaceDim), text: t(lang, 'homeMode'))),
      const SizedBox(height: 12),
      Row(
        children: [
          for (final on in const [false, true]) ...[
            if (on) const SizedBox(width: 12),
            Expanded(
              child: PixelButton(
                text: t(lang, on ? 'gardenMode' : 'clean'),
                fill: s.homeGardenBackdrop == on ? th.accent : th.panel,
                border: s.homeGardenBackdrop == on ? th.onSurface : th.onSurfaceDim,
                textColor: s.homeGardenBackdrop == on ? th.onAccent : th.onSurface,
                shadow: th.shadow,
                lang: lang,
                fontSize: 11,
                onTap: () => s.setHomeGardenBackdrop(on),
              ),
            ),
          ],
        ],
      ),
      const SizedBox(height: 24),
      Text(t(lang, 'autoBreak'), style: pixelStyle(lang, 12, col(th.onSurfaceDim), text: t(lang, 'autoBreak'))),
      const SizedBox(height: 12),
      Row(
        children: [
          for (final on in const [true, false]) ...[
            if (!on) const SizedBox(width: 12),
            Expanded(
              child: PixelButton(
                text: on ? 'ON' : 'OFF',
                fill: s.autoBreak == on ? th.accent : th.panel,
                border: s.autoBreak == on ? th.onSurface : th.onSurfaceDim,
                textColor: s.autoBreak == on ? th.onAccent : th.onSurface,
                shadow: th.shadow,
                lang: lang,
                fontSize: 11,
                onTap: () => s.setAutoBreak(on),
              ),
            ),
          ],
        ],
      ),
      // App blocker (Android only — no blocking API on iOS) (#v23)
      if (Platform.isAndroid) ...[
        const SizedBox(height: 24),
        Text(t(lang, 'appBlocker'), style: pixelStyle(lang, 12, col(th.onSurfaceDim), text: t(lang, 'appBlocker'))),
        const SizedBox(height: 12),
        Row(children: [
          for (final on in const [true, false]) ...[
            if (!on) const SizedBox(width: 12),
            Expanded(
              child: PixelButton(
                text: on ? 'ON' : 'OFF',
                fill: s.appBlockerEnabled == on ? th.accent : th.panel,
                border: s.appBlockerEnabled == on ? th.onSurface : th.onSurfaceDim,
                textColor: s.appBlockerEnabled == on ? th.onAccent : th.onSurface,
                shadow: th.shadow,
                lang: lang,
                fontSize: 11,
                onTap: () => _toggleBlocker(context, s, on),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 12),
        secondaryBtn(th, lang, t(lang, 'blockedApps'),
            () => openPanel(context, s, () => AppPickerScreen(s)), fontSize: 11),
      ],
    ]);
  }

  /// Flip the app-blocker; turning it ON first checks the Accessibility + overlay
  /// permissions and, if missing, opens a dialog with buttons to grant them (#v23).
  Future<void> _toggleBlocker(BuildContext context, AppStore s, bool on) async {
    if (!on) {
      s.setAppBlocker(false);
      return;
    }
    if (await hasAccessibility() && await hasOverlay()) {
      s.setAppBlocker(true);
      return;
    }
    if (!context.mounted) return;
    final th = s.theme;
    final lang = s.lang;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: col(th.panel),
        title: Text(t(lang, 'blockerPermTitle'),
            style: pixelStyle(lang, 12, col(th.onSurface), text: t(lang, 'blockerPermTitle'))),
        content: Text(t(lang, 'blockerPermBody'),
            style: pixelStyle(lang, 10, col(th.onSurfaceDim), text: t(lang, 'blockerPermBody'))),
        actions: [
          TextButton(
              onPressed: openAccessibilitySettings,
              child: Text(t(lang, 'grantAccess'),
                  style: pixelStyle(lang, 10, col(th.accent), text: t(lang, 'grantAccess')))),
          TextButton(
              onPressed: openOverlaySettings,
              child: Text(t(lang, 'grantOverlay'),
                  style: pixelStyle(lang, 10, col(th.accent), text: t(lang, 'grantOverlay')))),
          TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                if (await hasAccessibility() && await hasOverlay()) s.setAppBlocker(true);
              },
              child: Text(t(lang, 'done'),
                  style: pixelStyle(lang, 10, col(th.onSurface), text: t(lang, 'done')))),
        ],
      ),
    );
  }

  Widget _stepper(PixelTheme th, String lang, String label, int value, int min, int max, int step, ValueChanged<int> onChange) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Expanded(child: Text(label, style: pixelStyle(lang, 11, col(th.onSurfaceDim), text: label))),
          SizedBox(width: 52, child: secondaryBtn(th, lang, '-', () => onChange((value - step).clamp(min, max).toInt()), padding: const EdgeInsets.all(12))),
          Container(
            width: 56,
            alignment: Alignment.center,
            child: Text('$value', style: pixelStyle(lang, 14, col(th.onSurface), text: '$value')),
          ),
          SizedBox(width: 52, child: secondaryBtn(th, lang, '+', () => onChange((value + step).clamp(min, max).toInt()), padding: const EdgeInsets.all(12))),
        ],
      ),
    );
  }
}

// ---- app blocker: app picker (#v23) -----------------------------------------

/// Lists installed (launchable) apps with a toggle each; the chosen set is what
/// the blocker covers during a focus session. Opened from Settings → BLOCKED APPS.
class AppPickerScreen extends StatefulWidget {
  final AppStore s;
  const AppPickerScreen(this.s, {super.key});
  @override
  State<AppPickerScreen> createState() => _AppPickerScreenState();
}

class _AppPickerScreenState extends State<AppPickerScreen> {
  // Fetch the installed-app list ONCE. openPanel rebuilds this screen on every
  // notifyListeners() (i.e. every block toggle), and the old `future:
  // installedApps()` in build() re-queried + re-PNG-encoded every icon natively
  // on each rebuild — that was the app-locker lag (#v23 fb). A cached future plus
  // stable icon bytes let Flutter's image cache reuse decoded icons, so the tab
  // loads once and toggles respond instantly.
  late final Future<List<AppInfo>> _apps = installedApps();

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final th = s.theme;
    final lang = s.lang;
    return overlayScaffold(context, s, t(lang, 'blockedApps'), [
      Text(t(lang, 'pickBlocked'), style: pixelStyle(lang, 9, col(th.onSurfaceDim), text: t(lang, 'pickBlocked'))),
      const SizedBox(height: 12),
      FutureBuilder<List<AppInfo>>(
        future: _apps,
        builder: (context, snap) {
          if (!snap.hasData) {
            return Center(child: Text('...', style: pixelStyle(lang, 14, col(th.onSurfaceDim), text: '...')));
          }
          // Selected apps float to the top (in order), a divider, then the rest
          // (#v23 fb). snap.data is already alpha-sorted, so `where` keeps order.
          final picked = snap.data!.where((a) => s.blockedApps.contains(a.package)).toList();
          final rest = snap.data!.where((a) => !s.blockedApps.contains(a.package)).toList();
          Widget appRow(AppInfo a) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  a.icon != null
                      ? Image.memory(a.icon!, width: 32, height: 32, filterQuality: FilterQuality.none)
                      : const SizedBox(width: 32, height: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(a.label,
                        style: pixelStyle(lang, 10, col(th.onSurface), text: a.label),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  _BlockToggle(
                    on: s.blockedApps.contains(a.package),
                    accent: th.accent,
                    off: th.onSurfaceDim,
                    knob: th.onSurface,
                    onTap: () => s.setBlocked(a.package, !s.blockedApps.contains(a.package)),
                  ),
                ]),
              );
          return Column(children: [
            for (final a in picked) appRow(a),
            if (picked.isNotEmpty && rest.isNotEmpty)
              Container(height: 3, margin: const EdgeInsets.symmetric(vertical: 10), color: col(th.onSurfaceDim)),
            for (final a in rest) appRow(a),
          ]);
        },
      ),
    ]);
  }
}

/// A hard-edged pixel on/off switch (used by the app picker).
class _BlockToggle extends StatelessWidget {
  final bool on;
  final int accent, off, knob;
  final VoidCallback onTap;
  const _BlockToggle(
      {required this.on, required this.accent, required this.off, required this.knob, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 24,
          color: col(on ? accent : off),
          alignment: on ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(width: 22, height: 24, color: col(knob)),
        ),
      );
}

// ---- theme picker -----------------------------------------------------------

class ThemeScreen extends StatelessWidget {
  final AppStore s;
  const ThemeScreen(this.s, {super.key});
  @override
  Widget build(BuildContext context) {
    final th = s.theme;
    final lang = s.lang;
    return overlayScaffold(context, s, t(lang, 'theme'), [
      for (final pt in Themes.all)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: pt.id == th.id
              ? primaryBtn(th, lang, '> ${pt.displayName}', () => s.selectTheme(pt))
              : secondaryBtn(th, lang, pt.displayName, () => s.selectTheme(pt)),
        ),
    ]);
  }
}

// ---- labels -----------------------------------------------------------------

class LabelScreen extends StatefulWidget {
  final AppStore s;
  const LabelScreen(this.s, {super.key});
  @override
  State<LabelScreen> createState() => _LabelScreenState();
}

class _LabelScreenState extends State<LabelScreen> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final th = s.theme;
    final lang = s.lang;
    return overlayScaffold(context, s, t(lang, 'label'), [
      for (final label in s.labels) _labelRow(context, s, th, lang, label),
      Text(t(lang, 'renameHint'), style: pixelStyle(lang, 8, col(th.onSurfaceDim), text: t(lang, 'renameHint'))),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              textCapitalization: TextCapitalization.characters,
              maxLength: 12,
              style: pixelStyle(lang, 11, col(th.onSurface)),
              decoration: InputDecoration(
                counterText: '',
                hintText: t(lang, 'newLabel'),
                hintStyle: pixelStyle(lang, 11, col(th.onSurfaceDim)),
                filled: true,
                fillColor: col(th.panel),
                border: const OutlineInputBorder(borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 10),
          primaryBtn(th, lang, t(lang, 'add'), () {
            if (!s.addLabel(controller.text)) return;
            controller.clear();
          }, fontSize: 12),
        ],
      ),
    ]);
  }

  Widget _labelRow(BuildContext context, AppStore s, PixelTheme th, String lang, String label) {
    final selected = label.toUpperCase() == s.currentLabel.toUpperCase();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Swatch(color: s.labelColorOf(label), border: th.onSurfaceDim, size: 24, onTap: () => _pickColor(context, s, label)),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onLongPress: () => _renameLabel(context, s, label),
              child: selected
                  ? primaryBtn(th, lang, '> $label', () => s.selectLabel(label))
                  : secondaryBtn(th, lang, label, () => s.selectLabel(label)),
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete, color: col(th.onSurfaceDim)),
            onPressed: () => _confirmDelete(context, s, label),
          ),
        ],
      ),
    );
  }

  void _renameLabel(BuildContext context, AppStore s, String label) {
    final th = s.theme;
    final lang = s.lang;
    final ctrl = TextEditingController(text: label);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: col(th.panel),
        title: Text(t(lang, 'renameTitle'), style: pixelStyle(lang, 12, col(th.onSurface), text: t(lang, 'renameTitle'))),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          maxLength: 12,
          style: pixelStyle(lang, 12, col(th.onSurface)),
          decoration: InputDecoration(counterText: '', filled: true, fillColor: col(th.bg)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t(lang, 'no'), style: pixelStyle(lang, 11, col(th.onSurfaceDim), text: t(lang, 'no')))),
          TextButton(
              onPressed: () {
                s.renameLabel(label, ctrl.text);
                Navigator.pop(ctx);
              },
              child: Text(t(lang, 'save'), style: pixelStyle(lang, 11, col(th.accent), text: t(lang, 'save')))),
        ],
      ),
    );
  }

  void _pickColor(BuildContext context, AppStore s, String label) {
    final th = s.theme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: col(th.panel),
        title: Text(t(s.lang, 'pickColor'), style: pixelStyle(s.lang, 12, col(th.onSurface), text: t(s.lang, 'pickColor'))),
        content: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final c in LabelColors.palette)
              Swatch(color: c, border: th.onSurfaceDim, size: 40, onTap: () {
                s.setLabelColor(label, c);
                Navigator.pop(ctx);
              }),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, AppStore s, String label) {
    final th = s.theme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: col(th.panel),
        title: Text(t(s.lang, 'removeTitle'), style: pixelStyle(s.lang, 12, col(th.onSurface), text: t(s.lang, 'removeTitle'))),
        content: Text(tf(s.lang, 'removeMsg', [label]), style: pixelStyle(s.lang, 10, col(th.onSurfaceDim), text: tf(s.lang, 'removeMsg', [label]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t(s.lang, 'no'), style: pixelStyle(s.lang, 11, col(th.onSurfaceDim), text: t(s.lang, 'no')))),
          TextButton(
              onPressed: () {
                s.deleteLabel(label);
                Navigator.pop(ctx);
              },
              child: Text(t(s.lang, 'yes'), style: pixelStyle(s.lang, 11, col(th.accent), text: t(s.lang, 'yes')))),
        ],
      ),
    );
  }
}

// ---- stats ------------------------------------------------------------------

class StatsScreen extends StatelessWidget {
  final AppStore s;
  const StatsScreen(this.s, {super.key});

  @override
  Widget build(BuildContext context) {
    final th = s.theme;
    final lang = s.lang;
    final now = DateTime.now();
    final totals = StatsAggregator.aggregate(s.records, now);
    final byLabel = StatsAggregator.byLabelInWindow(s.records, now, s.statPeriod, s.statOffset);
    final trend = s.chartMode == ChartMode.line;
    // TREND + DAILY shows the day filling up hour by hour; everything else is per-bucket totals.
    final series = trend && s.statPeriod == StatPeriod.daily
        ? StatsAggregator.dailyCumulative(s.records, now, s.statOffset)
        : StatsAggregator.seriesFor(s.records, now, s.statPeriod, s.statOffset);
    final stats = StatsAggregator.periodStats(s.records, now, s.statPeriod, s.statOffset);

    Widget periodBtn(String text, StatPeriod p) {
      final sel = s.statPeriod == p;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: sel
              ? primaryBtn(th, lang, text, () => s.setStatPeriod(p), fontSize: 8, padding: const EdgeInsets.all(8))
              : secondaryBtn(th, lang, text, () => s.setStatPeriod(p), fontSize: 8, padding: const EdgeInsets.all(8)),
        ),
      );
    }

    Widget chartBtn(String text, ChartMode m) {
      final sel = s.chartMode == m;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: sel
              ? primaryBtn(th, lang, text, () => s.setChartMode(m), fontSize: 9, padding: const EdgeInsets.all(12))
              : secondaryBtn(th, lang, text, () => s.setChartMode(m), fontSize: 9, padding: const EdgeInsets.all(12)),
        ),
      );
    }

    Widget statRow(String caption, int minutes) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Text(caption, style: pixelStyle(lang, 11, col(th.onSurfaceDim), text: caption)),
              const Spacer(),
              Text(StatsAggregator.formatMinutes(minutes), style: pixelStyle(lang, 13, col(th.onSurface), text: StatsAggregator.formatMinutes(minutes))),
            ],
          ),
        );

    return overlayScaffold(context, s, t(lang, 'stats'), [
      Row(children: [
        periodBtn(t(lang, 'pDaily'), StatPeriod.daily),
        periodBtn(t(lang, 'pWeekly'), StatPeriod.weekly),
        periodBtn(t(lang, 'pMonthly'), StatPeriod.monthly),
        periodBtn(t(lang, 'pYearly'), StatPeriod.yearly),
        periodBtn(t(lang, 'pAll'), StatPeriod.allTime),
      ]),
      const SizedBox(height: 12),
      Row(children: [chartBtn(t(lang, 'chartBar'), ChartMode.bar), chartBtn(t(lang, 'chartLine'), ChartMode.line), chartBtn(t(lang, 'chartPie'), ChartMode.pie)]),
      // history navigator — browse previous day/week/month/year (#1)
      if (s.statPeriod != StatPeriod.allTime) ...[
        const SizedBox(height: 10),
        Row(children: [
          SizedBox(
            width: 52,
            child: secondaryBtn(th, lang, '<', () => s.shiftStatOffset(1),
                key: const Key('statPrev'), fontSize: 13, padding: const EdgeInsets.all(10)),
          ),
          Expanded(child: Center(child: Text(_periodLabel(s, lang),
              style: pixelStyle(lang, 11, col(th.onSurface), text: _periodLabel(s, lang))))),
          SizedBox(
            width: 52,
            child: PixelButton(
                text: '>', fill: th.panel, border: th.onSurfaceDim, textColor: th.onSurface, shadow: th.shadow,
                lang: lang, fontSize: 13, padding: const EdgeInsets.all(10),
                opacity: s.statOffset > 0 ? 1 : 0.35,
                onTap: () => s.shiftStatOffset(-1)),
          ),
        ]),
      ],
      const SizedBox(height: 16),
      SizedBox(
        height: 200,
        child: StatsChart(
          entries: [for (final e in byLabel) ChartEntry(e.key, e.value, s.labelColorOf(e.key))],
          series: series,
          average: stats.$2,
          mode: s.chartMode,
          lang: lang,
          axisColor: th.onSurfaceDim,
          textColor: th.onSurface,
          lineColor: th.accent,
          panelColor: th.panel,
          panelBorder: th.onSurfaceDim,
        ),
      ),
      const SizedBox(height: 16),
      if (trend) ...[
        statRow(t(lang, 'statCurrent'), stats.$1),
        statRow(t(lang, 'statAverage'), stats.$2),
        statRow(t(lang, 'statBest'), stats.$3),
      ] else ...[
        statRow(t(lang, 'today'), totals.today),
        statRow(t(lang, 'week'), totals.week),
        statRow(t(lang, 'month'), totals.month),
        statRow(t(lang, 'year'), totals.year),
        statRow(t(lang, 'all'), totals.all),
      ],
      const SizedBox(height: 16),
      Text(t(lang, 'byLabel'), style: pixelStyle(lang, 11, col(th.onSurfaceDim), text: t(lang, 'byLabel'))),
      const SizedBox(height: 12),
      if (byLabel.isEmpty)
        Text(t(lang, 'chartNoData'), style: pixelStyle(lang, 9, col(th.onSurfaceDim), text: t(lang, 'chartNoData')))
      else
        for (final e in byLabel)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Swatch(color: s.labelColorOf(e.key), border: th.onSurfaceDim, size: 16),
                const SizedBox(width: 10),
                Text(e.key, style: pixelStyle(lang, 11, col(th.onSurface), text: e.key)),
                const Spacer(),
                Text(StatsAggregator.formatMinutes(e.value), style: pixelStyle(lang, 11, col(th.onSurfaceDim), text: StatsAggregator.formatMinutes(e.value))),
              ],
            ),
          ),
      // focus-session heatmaps, relocated out of the habit tracker (#v30 item 6)
      const SizedBox(height: 20),
      FocusSessionsSection(th: th, lang: lang, s: s, today: epochDayOf(now)),
      // a paginated list of every past session (tap a row to relabel) — sits
      // right above the auto-appended CLOSE button (#v25 item3)
      const SizedBox(height: 20),
      secondaryBtn(th, lang, t(lang, 'logHistory'),
          () => openPanel(context, s, () => LogHistoryScreen(s)),
          padding: const EdgeInsets.all(14)),
    ]);
  }

  /// Label for the history navigator, matching the selected period's granularity.
  String _periodLabel(AppStore s, String lang) {
    final now = DateTime.now();
    final a = StatsAggregator.anchorFor(now, s.statPeriod, s.statOffset);
    switch (s.statPeriod) {
      case StatPeriod.daily:
        return '${monthName(lang, a.month)} ${a.day}';
      case StatPeriod.weekly:
        final (lo, hi) = StatsAggregator.windowDays(a, StatPeriod.weekly);
        final loD = dateOfEpochDay(lo), hiD = dateOfEpochDay(hi);
        return '${loD.day}–${hiD.day} ${monthName(lang, hiD.month)}';
      case StatPeriod.monthly:
        return '${monthName(lang, a.month)} ${a.year}';
      case StatPeriod.yearly:
        return '${a.year}';
      case StatPeriod.allTime:
        return t(lang, 'pAll');
    }
  }
}

// ---- log history ------------------------------------------------------------

/// A paginated list of every past focus session (newest first, 50 a page).
/// Tap a row to reassign that session's label (#v25 item3).
class LogHistoryScreen extends StatefulWidget {
  final AppStore s;
  const LogHistoryScreen(this.s, {super.key});
  @override
  State<LogHistoryScreen> createState() => _LogHistoryScreenState();
}

class _LogHistoryScreenState extends State<LogHistoryScreen> {
  static const _perPage = 50;
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final th = s.theme;
    final lang = s.lang;
    // newest first, keeping each record's ORIGINAL index so we can relabel it.
    final ordered = [for (var i = 0; i < s.records.length; i++) (i, s.records[i])]
      ..sort((a, b) {
        final byDay = b.$2.epochDay.compareTo(a.$2.epochDay);
        return byDay != 0 ? byDay : (b.$2.minuteOfDay ?? 0).compareTo(a.$2.minuteOfDay ?? 0);
      });
    final pages = Paging.pageCount(ordered.length, _perPage);
    if (_page >= pages) _page = pages - 1;
    final shown = Paging.page(ordered, _page, _perPage);

    return overlayScaffold(context, s, t(lang, 'logHistory'), [
      if (ordered.isEmpty)
        Text(t(lang, 'noLogs'), style: pixelStyle(lang, 10, col(th.onSurfaceDim), text: t(lang, 'noLogs')))
      else ...[
        for (final (idx, r) in shown) _logRow(context, s, th, lang, idx, r),
        const SizedBox(height: 14),
        Row(children: [
          SizedBox(
            width: 52,
            child: secondaryBtn(th, lang, '<',
                () => setState(() => _page = (_page - 1).clamp(0, pages - 1)),
                fontSize: 13, padding: const EdgeInsets.all(10)),
          ),
          Expanded(
            child: Center(
              child: Text(tf(lang, 'pageOf', [_page + 1, pages]),
                  style: pixelStyle(lang, 10, col(th.onSurface), text: tf(lang, 'pageOf', [_page + 1, pages]))),
            ),
          ),
          SizedBox(
            width: 52,
            child: PixelButton(
                text: '>', fill: th.panel, border: th.onSurfaceDim, textColor: th.onSurface, shadow: th.shadow,
                lang: lang, fontSize: 13, padding: const EdgeInsets.all(10),
                opacity: _page < pages - 1 ? 1 : 0.35,
                onTap: () => setState(() => _page = (_page + 1).clamp(0, pages - 1))),
          ),
        ]),
      ],
    ]);
  }

  Widget _logRow(BuildContext context, AppStore s, PixelTheme th, String lang, int index, SessionRecord r) {
    final d = dateOfEpochDay(r.epochDay);
    final time = r.minuteOfDay == null
        ? ''
        : '${(r.minuteOfDay! ~/ 60).toString().padLeft(2, '0')}:${(r.minuteOfDay! % 60).toString().padLeft(2, '0')}';
    // 3-letter month keeps the date column narrow enough that the bigger font
    // still fits four aligned columns on a phone (#v27 feedback). Rows from
    // another year show a 2-digit year — the seeded 2025 history made
    // "12 NOV" sort after "14 APR" look wrong without it (#v27.1 feedback).
    final month = monthName(lang, d.month);
    final year = d.year == DateTime.now().year ? '' : ' ${d.year % 100}';
    final date = '${d.day} ${month.length > 3 ? month.substring(0, 3) : month}$year';
    final dur = StatsAggregator.formatMinutes(r.minutes);
    // Fixed columns so every row lines up: date | time (toward the centre) |
    // label (left-justified) | duration. The duration sits in a FLEX column
    // right-aligned — as a bare Text its per-row width let every other
    // column edge wander row to row, the "not in order" look (#v27.1). Fonts
    // and the swatch bumped again (#v27.1 feedback: still too small).
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _changeLabel(context, s, index, r),
        child: Row(children: [
          Swatch(color: s.labelColorOf(r.label), border: th.onSurfaceDim, size: 18),
          const SizedBox(width: 8),
          Expanded(
              flex: 9,
              child: Text(date,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: pixelStyle(lang, 10, col(th.onSurfaceDim), text: date))),
          Expanded(
              flex: 5,
              child: Text(time, style: pixelStyle(lang, 10, col(th.onSurfaceDim), text: time))),
          Expanded(
              flex: 10,
              child: Text(r.label,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: pixelStyle(lang, 11, col(th.onSurface), text: r.label))),
          Expanded(
              flex: 6,
              child: Text(dur,
                  maxLines: 1,
                  textAlign: TextAlign.right,
                  style: pixelStyle(lang, 10, col(th.onSurfaceDim), text: dur))),
        ]),
      ),
    );
  }

  void _changeLabel(BuildContext context, AppStore s, int index, SessionRecord r) {
    final th = s.theme;
    final lang = s.lang;
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: col(th.panel),
        title: Text(t(lang, 'changeLabel'), style: pixelStyle(lang, 11, col(th.onSurface), text: t(lang, 'changeLabel'))),
        children: [
          for (final label in s.labels)
            SimpleDialogOption(
              onPressed: () {
                s.relabelRecord(index, label);
                Navigator.pop(ctx);
                setState(() {});
              },
              child: Row(children: [
                Swatch(color: s.labelColorOf(label), border: th.onSurfaceDim, size: 14),
                const SizedBox(width: 10),
                Text(label,
                    style: pixelStyle(lang, 10,
                        col(label.toUpperCase() == r.label.toUpperCase() ? th.accent : th.onSurface),
                        text: label)),
              ]),
            ),
        ],
      ),
    );
  }
}

// ---- shop -------------------------------------------------------------------

class ShopScreen extends StatefulWidget {
  final AppStore s;
  const ShopScreen(this.s, {super.key});
  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  int _tab = 0; // 0 flowers · 1 outer decor · 2 inner decor · 3 pets (#6)

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final th = s.theme;
    final lang = s.lang;
    Widget tabBtn(String text, int i) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: _tab == i
                ? primaryBtn(th, lang, text, () => setState(() => _tab = i), fontSize: 8, padding: const EdgeInsets.all(8))
                : secondaryBtn(th, lang, text, () => setState(() => _tab = i), fontSize: 8, padding: const EdgeInsets.all(8)),
          ),
        );
    return overlayScaffold(context, s, t(lang, 'shop'), [
      Row(children: [
        tabBtn(t(lang, 'catFlowers'), 0),
        tabBtn(t(lang, 'catOuter'), 1),
        tabBtn(t(lang, 'catInner'), 2),
        tabBtn(t(lang, 'catPets'), 3),
      ]),
      const SizedBox(height: 16),
      if (_tab == 0) ...[
        for (final f in Flowers.all) _flowerRow(s, th, lang, f),
      ] else if (_tab == 1) ...[
        for (final id in Placeables.objectIds) _objectRow(s, th, lang, id),
      ] else
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Center(child: Text(t(lang, 'comingSoon'), style: pixelStyle(lang, 12, col(th.onSurfaceDim), text: t(lang, 'comingSoon')))),
        ),
    ]);
  }

  Widget _flowerRow(AppStore s, PixelTheme th, String lang, Flower f) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          objectThumb('flower_${f.id}', 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f.nameIn(lang), style: pixelStyle(lang, 12, col(th.onSurface), text: f.nameIn(lang))),
                const SizedBox(height: 6),
                Text(tf(lang, 'owned', [s.owned[f.id] ?? 0]), style: pixelStyle(lang, 8, col(th.onSurfaceDim), text: tf(lang, 'owned', [s.owned[f.id] ?? 0]))),
              ],
            ),
          ),
          PixelButton(
            text: '${t(lang, 'buy')} ${Economy.flowerCost}',
            fill: th.accent, border: th.onSurface, textColor: th.onAccent, shadow: th.shadow,
            lang: lang, fontSize: 11, padding: const EdgeInsets.all(12),
            opacity: s.coins >= Economy.flowerCost ? 1 : 0.45,
            onTap: () => s.buyFlower(f),
          ),
        ],
      ),
    );
  }

  Widget _objectRow(AppStore s, PixelTheme th, String lang, String id) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          objectThumb(id, 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t(lang, id), style: pixelStyle(lang, 12, col(th.onSurface), text: t(lang, id))),
                const SizedBox(height: 6),
                Text(tf(lang, 'owned', [s.owned[id] ?? 0]), style: pixelStyle(lang, 8, col(th.onSurfaceDim), text: tf(lang, 'owned', [s.owned[id] ?? 0]))),
              ],
            ),
          ),
          PixelButton(
            text: '${t(lang, 'buy')} ${Economy.objectCost}',
            fill: th.accent, border: th.onSurface, textColor: th.onAccent, shadow: th.shadow,
            lang: lang, fontSize: 11, padding: const EdgeInsets.all(12),
            opacity: s.coins >= Economy.objectCost ? 1 : 0.45,
            onTap: () => s.buyItem(id),
          ),
        ],
      ),
    );
  }
}

// ---- garden -----------------------------------------------------------------

/// Natural garden palette (theme-independent — a garden is always green).
const int _gardenGround = 0xFF4E9E3E;
const int _gardenSoil = 0xFF6B4A2B;

class GardenScreen extends StatefulWidget {
  final AppStore s;
  const GardenScreen(this.s, {super.key});

  @override
  State<GardenScreen> createState() => _GardenScreenState();
}

class _GardenScreenState extends State<GardenScreen> {
  bool _peek = false; // hide all HUD, just the garden (#2)
  bool _camera = false; // framing a screenshot (#2)
  final GlobalKey _captureKey = GlobalKey();
  // owned here (not inside GardenView) so we can read the framing the user picks
  // in camera mode and reproduce it in the live wallpaper (v15).
  final GardenCamera _wallpaperCam = GardenCamera();

  bool get _hudHidden => _peek || _camera;

  void _enterCamera() => setState(() => _camera = true);
  void _exitCamera() => setState(() {
        _camera = false;
        _peek = false;
      });

  /// Screenshot the framed garden, then offer to set it as the static backdrop
  /// or share it. Capture itself is on-device only (toImage hangs in tests).
  Future<void> _capture() async {
    final bytes = await captureBoundary(_captureKey);
    if (bytes == null || !mounted) return;
    final s = widget.s;
    final th = s.theme;
    final lang = s.lang;
    await showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: col(th.panel),
        title: Text(t(lang, 'camera'), style: pixelStyle(lang, 12, col(th.onSurface), text: t(lang, 'camera'))),
        children: [
          SimpleDialogOption(
            onPressed: () async {
              await sharePng(bytes, 'pixel_pomo_garden.png');
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(t(lang, 'share'), style: pixelStyle(lang, 11, col(th.onSurface), text: t(lang, 'share'))),
          ),
          // set the live wallpaper at the framed angle, below save/share (#v16, Android only)
          if (Platform.isAndroid)
            SimpleDialogOption(
              onPressed: () async {
                if (ctx.mounted) Navigator.pop(ctx);
                await _setLiveWallpaper();
              },
              child: Text(t(lang, 'setLiveWallpaper'), style: pixelStyle(lang, 11, col(th.onSurface), text: t(lang, 'setLiveWallpaper'))),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t(lang, 'cancel'), style: pixelStyle(lang, 11, col(th.accent), text: t(lang, 'cancel'))),
          ),
        ],
      ),
    );
  }

  /// Save the angle the user framed in camera mode and open Android's live-
  /// wallpaper picker for our GardenWallpaperService (v15). Pan is stored as a
  /// fraction of the tile size so it reproduces at the wallpaper's surface size.
  Future<void> _setLiveWallpaper() async {
    final s = widget.s;
    final size = MediaQuery.of(context).size;
    final p = Projector.fit(s.garden.cols, s.garden.rows, _wallpaperCam, size);
    final t = p.t == 0 ? 1.0 : p.t;
    s.setWallpaperCamera(
        _wallpaperCam.yaw, _wallpaperCam.zoom, _wallpaperCam.panX / t, _wallpaperCam.panY / t);
    final ok = await setLiveWallpaper();
    if (!mounted) return;
    if (ok) {
      _exitCamera();
    } else {
      s.messenger?.call('wallpaperFailed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final th = s.theme;
    final lang = s.lang;
    final cost = Economy.upgradeCost(s.garden.cols, s.garden.rows);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // while peeking, let the forest run edge-to-edge behind transparent bars (#5)
      value: _hudHidden
          ? const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent, systemNavigationBarColor: Colors.transparent)
          : systemOverlayFor(th),
      child: Scaffold(
      backgroundColor: col(th.bg),
      body: Stack(children: [
        SafeArea(
        top: !_hudHidden,
        bottom: !_hudHidden,
        child: Column(
          children: [
            if (!_hudHidden)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Row(
                  children: [
                    Text(t(lang, 'garden'), style: pixelStyle(lang, 20, col(th.onSurface), spacing: 2, text: t(lang, 'garden'))),
                    const Spacer(),
                    PixelButton(
                      text: tf(lang, 'upgrade', [cost]),
                      fill: th.accent, border: th.onSurface, textColor: th.onAccent, shadow: th.shadow,
                      lang: lang, fontSize: 10, padding: const EdgeInsets.all(12),
                      opacity: s.coins >= cost ? 1 : 0.45, onTap: s.upgradeGarden,
                    ),
                  ],
                ),
              ),
            if (!_hudHidden)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(t(lang, 'gardenHelp'), style: pixelStyle(lang, 8, col(th.onSurfaceDim), text: t(lang, 'gardenHelp'))),
              ),
            if (!_hudHidden) const SizedBox(height: 8),
            // the live 2.5D scene fills the remaining space
            Expanded(
              child: FutureBuilder<SpriteBank>(
                      future: gardenSprites(),
                      builder: (context, snap) {
                        if (!snap.hasData) {
                          return Center(child: Text('...', style: pixelStyle(lang, 16, col(th.onSurfaceDim), text: '...')));
                        }
                        return GardenView(
                          garden: s.garden,
                          sprites: snap.data!,
                          customizing: s.customizing,
                          onTapTile: (index) => _onTileTap(context, s, index),
                          groundColor: _gardenGround,
                          soilColor: _gardenSoil,
                          uiColor: th.onSurface,
                          panelColor: th.panel,
                          lang: lang,
                          tr: (k) => t(lang, k),
                          captureKey: _captureKey,
                          cameraMode: _camera,
                          camera: _wallpaperCam,
                          onPeek: () => setState(() => _peek = !_peek),
                          onCamera: _enterCamera,
                        );
                      },
                    ),
            ),
            // CAPTURE/CANCEL float over the full-bleed scene in camera mode (Stack below)
            if (!_camera && !_peek)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: primaryBtn(th, lang, t(lang, s.customizing ? 'done' : 'customize'),
                          s.toggleCustomizing, padding: const EdgeInsets.all(16)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: secondaryBtn(th, lang, t(lang, 'close'), () => Navigator.pop(context),
                          padding: const EdgeInsets.all(16)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
          // camera-mode controls float over the edge-to-edge garden — no opaque
          // band below the buttons, so the forest fills the whole screen (#v23)
          if (_camera)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: primaryBtn(th, lang, t(lang, 'capture'), _capture,
                            padding: const EdgeInsets.all(16)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: secondaryBtn(th, lang, t(lang, 'cancel'), _exitCamera,
                            padding: const EdgeInsets.all(16)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      ),
    );
  }

  void _onTileTap(BuildContext context, AppStore s, int index) {
    final lang = s.lang;
    final current = s.garden.flowerAt(index);
    // flowers can't grow on a road; fences can stand on one (#2).
    final hasRoad = s.garden.groundAt(index) != null;
    // everything the player owns and hasn't placed yet (flowers + objects)
    final flowers =
        hasRoad ? <Flower>[] : Flowers.all.where((f) => s.availableOf(f.id) > 0).toList();
    final objects = Placeables.objectIds.where((id) => s.availableOf(id) > 0).toList();
    if (current == null && flowers.isEmpty && objects.isEmpty) {
      s.messenger?.call(s.owned.isEmpty ? 'needFlowers' : 'noneLeft');
      return;
    }
    final th = s.theme;
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: col(th.panel),
        title: Text(t(lang, current == null ? 'pickFlower' : 'garden'), style: pixelStyle(lang, 12, col(th.onSurface), text: t(lang, current == null ? 'pickFlower' : 'garden'))),
        children: [
          if (current != null)
            SimpleDialogOption(
              onPressed: () {
                s.clearTile(index);
                Navigator.pop(ctx);
              },
              child: Text(t(lang, 'clearTile'), style: pixelStyle(lang, 11, col(th.accent), text: t(lang, 'clearTile'))),
            ),
          for (final f in flowers)
            _placeOption(ctx, s, th, lang, index, f.id, objectThumb('flower_${f.id}', 24), f.nameIn(lang)),
          for (final id in objects)
            _placeOption(ctx, s, th, lang, index, id, objectThumb(id, 24), t(lang, id)),
        ],
      ),
    );
  }

  Widget _placeOption(BuildContext ctx, AppStore s, PixelTheme th, String lang, int index,
      String id, Widget icon, String name) {
    return SimpleDialogOption(
      onPressed: () {
        s.plantTile(index, id);
        Navigator.pop(ctx);
      },
      child: Row(
        children: [
          icon,
          const SizedBox(width: 10),
          Text('$name  x${s.availableOf(id)}', style: pixelStyle(lang, 11, col(th.onSurface), text: '$name  x${s.availableOf(id)}')),
        ],
      ),
    );
  }
}

// ---- habit tracker (#v29) ---------------------------------------------------
// Daylio-style daily mood + HabitKit-style habit cards. Manual habits (with a
// +1 tap) plus focus-session labels as AUTOMATIC habits ("7 days · 15 times").
// No icons on the rows — text labels only, per the brief.

// Mood colors 1..5 (awful..great), matching gen_objects.py's face_grid palette.
const List<int> _moodColors = [0xFFE5484D, 0xFFF2994A, 0xFFF2C94C, 0xFFA8D93A, 0xFF46A03C];

// Mood history heatmap — one colour per recorded day (#v30 items 7/9). Shared
// by the Mood tab and Year in Pixels.
Widget _moodHeatmap(AppStore s, PixelTheme th, int today) => _HabitHeatmap(
      days: const {},
      color: th.onSurfaceDim,
      today: today,
      maxCellSize: double.infinity,
      colorForDay: (d) {
        final m = s.moods[d];
        return m == null ? null : _moodColors[m - 1];
      },
    );

// How much trailing history a Focus Sessions heatmap shows (#v30 follow-up).
enum _HeatPeriod { weekly, monthly, days126, yearly }

int _heatWeeks(_HeatPeriod p) => switch (p) {
      _HeatPeriod.weekly => 1,
      _HeatPeriod.monthly => 5, // ~30 days
      _HeatPeriod.days126 => 18, // the original default (126 days)
      _HeatPeriod.yearly => 53, // ~365 days
    };

// Focus-session heatmaps as a plain list — full-width cells, no card frame,
// no "FOCUS LABEL" caption (#v30 item 6), with its own WEEKLY/MONTHLY/126
// DAYS/YEARLY period picker (#v30 follow-up). Shared by Stats + Year in
// Pixels; owns its own period state so neither parent screen needs to.
class FocusSessionsSection extends StatefulWidget {
  final PixelTheme th;
  final String lang;
  final AppStore s;
  final int today;
  const FocusSessionsSection(
      {super.key, required this.th, required this.lang, required this.s, required this.today});
  @override
  State<FocusSessionsSection> createState() => _FocusSessionsSectionState();
}

class _FocusSessionsSectionState extends State<FocusSessionsSection> {
  _HeatPeriod _period = _HeatPeriod.days126;

  @override
  Widget build(BuildContext context) {
    final th = widget.th, lang = widget.lang, s = widget.s, today = widget.today;
    final labelCounts = s.labelHabitCounts;
    if (labelCounts.isEmpty) return const SizedBox.shrink();

    Widget periodBtn(String text, _HeatPeriod p) {
      final sel = _period == p;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: sel
              ? primaryBtn(th, lang, text, () => setState(() => _period = p), fontSize: 8, padding: const EdgeInsets.all(8))
              : secondaryBtn(th, lang, text, () => setState(() => _period = p), fontSize: 8, padding: const EdgeInsets.all(8)),
        ),
      );
    }

    final weeks = _heatWeeks(_period);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t(lang, 'focusSessions'), style: pixelStyle(lang, 11, col(th.onSurfaceDim), text: t(lang, 'focusSessions'))),
        const SizedBox(height: 10),
        Row(children: [
          periodBtn(t(lang, 'pWeekly'), _HeatPeriod.weekly),
          periodBtn(t(lang, 'pMonthly'), _HeatPeriod.monthly),
          periodBtn(t(lang, 'p126Days'), _HeatPeriod.days126),
          periodBtn(t(lang, 'pYearly'), _HeatPeriod.yearly),
        ]),
        const SizedBox(height: 12),
        for (final e in labelCounts.entries) ...[
          Text(e.key, style: pixelStyle(lang, 10, col(s.labelColorOf(e.key)), text: e.key)),
          const SizedBox(height: 2),
          Text(tf(lang, 'daysTimes', [HabitLog.daysDone(e.value), HabitLog.totalTimes(e.value)]),
              style: pixelStyle(lang, 8, col(th.onSurfaceDim),
                  text: tf(lang, 'daysTimes', [HabitLog.daysDone(e.value), HabitLog.totalTimes(e.value)]))),
          const SizedBox(height: 4),
          _HabitHeatmap(days: e.value, color: s.labelColorOf(e.key), today: today, maxCellSize: double.infinity, weeks: weeks),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}

// "Your Year in Pixels" — every daily heatmap in one place: mood, manual
// habits/goals, and focus sessions (#v30 items 6/9 — "(all data)").
Widget _yearInPixelsContent(PixelTheme th, String lang, AppStore s, int today) {
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Text(t(lang, 'moodTracker'), style: pixelStyle(lang, 11, col(th.onSurfaceDim), text: t(lang, 'moodTracker'))),
    const SizedBox(height: 10),
    _moodHeatmap(s, th, today),
    const SizedBox(height: 20),
    for (final h in s.habits) ...[
      Text(h.name, style: pixelStyle(lang, 10, col(h.color), text: h.name)),
      const SizedBox(height: 4),
      _HabitHeatmap(days: s.habitLog[h.name] ?? const {}, color: h.color, today: today, maxCellSize: double.infinity),
      const SizedBox(height: 14),
    ],
    FocusSessionsSection(th: th, lang: lang, s: s, today: today),
  ]);
}

class HabitScreen extends StatefulWidget {
  final AppStore s;
  const HabitScreen(this.s, {super.key});
  @override
  State<HabitScreen> createState() => _HabitScreenState();
}

class _HabitScreenState extends State<HabitScreen> {
  // 0 = mood tracker, 1 = year in pixels (all data), 2 = goals (#v30 items 6/7/9)
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final th = s.theme;
    final lang = s.lang;
    final today = epochDayOf(DateTime.now());

    Widget tabBtn(String text, int i, Key key) {
      final sel = _tab == i;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: sel
              ? primaryBtn(th, lang, text, () => setState(() => _tab = i), fontSize: 8, padding: const EdgeInsets.all(8), key: key)
              : secondaryBtn(th, lang, text, () => setState(() => _tab = i), fontSize: 8, padding: const EdgeInsets.all(8), key: key),
        ),
      );
    }

    return overlayScaffold(context, s, t(lang, 'habits'), [
      Row(children: [
        tabBtn(t(lang, 'moodTracker'), 0, const Key('moodTabButton')),
        tabBtn(t(lang, 'yearInPixels'), 1, const Key('yearInPixelsTabButton')),
        tabBtn(t(lang, 'goals'), 2, const Key('goalsTabButton')),
      ]),
      const SizedBox(height: 20),
      if (_tab == 0)
        _moodTab(s, th, lang, today)
      else if (_tab == 1)
        _yearInPixelsContent(th, lang, s, today)
      else
        _goalsTab(s, th, lang, today),
    ]);
  }

  // --- mood tracker: today's picker + its own recorded history (#v30 item 7) ---
  Widget _moodTab(AppStore s, PixelTheme th, String lang, int today) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(t(lang, 'mood'), style: pixelStyle(lang, 12, col(th.onSurfaceDim), text: t(lang, 'mood'))),
      const SizedBox(height: 10),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var m = 1; m <= 5; m++)
            GestureDetector(
              onTap: () => s.setMood(m),
              child: Opacity(
                opacity: s.todayMood == null || s.todayMood == m ? 1 : 0.35,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: col(s.todayMood == m ? th.onSurface : th.bg), width: 2),
                  ),
                  child: Image.asset('assets/objects/face_$m.png',
                      width: 40, height: 40, filterQuality: FilterQuality.none),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 24),
      _moodHeatmap(s, th, today),
    ]);
  }

  Widget _goalsTab(AppStore s, PixelTheme th, String lang, int today) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final h in s.habits)
        _habitCard(s, th, lang, today, h.name, h.color, s.habitLog[h.name] ?? const {}),
      if (s.habits.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(t(lang, 'noHabits'),
              textAlign: TextAlign.center,
              style: pixelStyle(lang, 10, col(th.onSurfaceDim), text: t(lang, 'noHabits'))),
        ),
      const SizedBox(height: 8),
      primaryBtn(th, lang, t(lang, 'addHabit'), () => _addHabit(context, s),
          fontSize: 12, padding: const EdgeInsets.all(14)),
    ]);
  }

  Widget _habitCard(AppStore s, PixelTheme th, String lang, int today, String name,
      int color, Map<int, int> days) {
    final doneToday = (days[today] ?? 0) > 0;
    final subtitle = tf(lang, 'daysTimes',
        [HabitLog.daysDone(days), HabitLog.totalTimes(days)]);
    final streak = HabitLog.streak(days, today);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: col(th.panel),
        border: Border.all(color: col(th.onSurfaceDim), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: pixelStyle(lang, 12, col(th.onSurface), text: name)),
                  const SizedBox(height: 4),
                  Text(
                      streak > 1 ? '$subtitle · ${tf(lang, 'streakN', [streak])}' : subtitle,
                      style: pixelStyle(lang, 8, col(th.onSurfaceDim),
                          text: streak > 1 ? '$subtitle · ${tf(lang, 'streakN', [streak])}' : subtitle)),
                ],
              ),
            ),
            // long-press a goal card to delete it.
            GestureDetector(
              onTap: () => s.bumpHabit(name, doneToday ? -1 : 1),
              onLongPress: () => _removeHabit(context, s, name),
              child: Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: col(doneToday ? color : th.bg),
                  border: Border.all(color: col(color), width: 2),
                ),
                child: Text(doneToday ? '✓' : '+',
                    style: pixelStyle(lang, 16, col(doneToday ? th.onAccent : color),
                        text: doneToday ? '✓' : '+')),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          _HabitHeatmap(days: days, color: color, today: today),
        ],
      ),
    );
  }

  void _addHabit(BuildContext context, AppStore s) {
    final th = s.theme;
    final lang = s.lang;
    final ctrl = TextEditingController();
    var color = LabelColors.palette.first;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: col(th.panel),
          title: Text(t(lang, 'addHabit'), style: pixelStyle(lang, 12, col(th.onSurface), text: t(lang, 'addHabit'))),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                style: pixelStyle(lang, 11, col(th.onSurface), text: 'Aa'),
                decoration: InputDecoration(
                  hintText: t(lang, 'habitName'),
                  hintStyle: pixelStyle(lang, 10, col(th.onSurfaceDim), text: t(lang, 'habitName')),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in LabelColors.palette)
                    GestureDetector(
                      onTap: () => setLocal(() => color = c),
                      child: Swatch(color: c, border: color == c ? th.onSurface : th.onSurfaceDim, size: color == c ? 26 : 22),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            secondaryBtn(th, lang, t(lang, 'cancel'), () => Navigator.pop(ctx), fontSize: 10, padding: const EdgeInsets.all(10)),
            primaryBtn(th, lang, t(lang, 'add'), () {
              s.addHabit(ctrl.text, color);
              Navigator.pop(ctx);
            }, fontSize: 10, padding: const EdgeInsets.all(10)),
          ],
        ),
      ),
    );
  }

  void _removeHabit(BuildContext context, AppStore s, String name) {
    final th = s.theme;
    final lang = s.lang;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: col(th.panel),
        content: Text(tf(lang, 'removeHabitMsg', [name]),
            style: pixelStyle(lang, 11, col(th.onSurface), text: tf(lang, 'removeHabitMsg', [name]))),
        actions: [
          secondaryBtn(th, lang, t(lang, 'no'), () => Navigator.pop(ctx), fontSize: 10, padding: const EdgeInsets.all(10)),
          primaryBtn(th, lang, t(lang, 'yes'), () {
            s.removeHabit(name);
            Navigator.pop(ctx);
          }, fontSize: 10, padding: const EdgeInsets.all(10)),
        ],
      ),
    );
  }
}

// ---- money manager (#v29) ---------------------------------------------------
// Simple single ledger: income/expense entries in any currency, aggregated in
// the user's MAIN currency via cached rates. Monthly totals + category bars,
// in-screen settings (main currency + daily budget), daily-budget coin.

const _expenseCats = [
  'catFood', 'catTransport', 'catHome', 'catFun',
  'catHealth', 'catShopping', 'catEducation', 'catOther'
];
const _incomeCats = ['catSalary', 'catGift', 'catOther'];

String _money(double v, String cur) {
  final s = v.abs().toStringAsFixed(2);
  return '$cur $s';
}

class MoneyScreen extends StatefulWidget {
  final AppStore s;
  const MoneyScreen(this.s, {super.key});
  @override
  State<MoneyScreen> createState() => _MoneyScreenState();
}

class _MoneyScreenState extends State<MoneyScreen> {
  int _offset = 0; // months back from now
  StatPeriod _chartPeriod = StatPeriod.monthly; // #v30 item 11
  ChartMode _chartMode = ChartMode.bar;

  @override
  void initState() {
    super.initState();
    widget.s.refreshFx(); // fetch on open if the cache is stale (>1h)
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final th = s.theme;
    final lang = s.lang;
    final cur = s.mainCurrency;
    final now = DateTime.now();
    final view = DateTime(now.year, now.month - _offset);
    final (income, expense) = MoneyBook.monthTotals(s.money, view.year, view.month, s.fxRates, cur);
    final cats = MoneyBook.byCategory(s.money, view.year, view.month, s.fxRates, cur);
    final maxCat = cats.isEmpty ? 1.0 : cats.first.value;
    final monthTxs = s.money
        .where((t) {
          final d = dateOfEpochDay(t.epochDay);
          return d.year == view.year && d.month == view.month;
        })
        .toList()
      ..sort((a, b) => b.epochDay != a.epochDay
          ? b.epochDay - a.epochDay
          : b.minuteOfDay - a.minuteOfDay);
    return overlayScaffold(context, s, t(lang, 'money'), [
      // --- month navigator ---
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: () => setState(() => _offset++),
            icon: Text('<', style: pixelStyle(lang, 18, col(th.onSurface), text: '<')),
          ),
          Text('${monthName(lang, view.month)} ${view.year}',
              style: pixelStyle(lang, 13, col(th.onSurface), text: '${monthName(lang, view.month)} ${view.year}')),
          IconButton(
            onPressed: _offset == 0 ? null : () => setState(() => _offset--),
            icon: Text('>', style: pixelStyle(lang, 18, col(_offset == 0 ? th.onSurfaceDim : th.onSurface), text: '>')),
          ),
        ],
      ),
      // --- income / expense totals ---
      Row(children: [
        Expanded(child: _total(th, lang, t(lang, 'income'), _money(income, cur), th.work)),
        Expanded(child: _total(th, lang, t(lang, 'expense'), _money(expense, cur), th.accent)),
      ]),
      const SizedBox(height: 10),
      Center(
        child: _total(th, lang, t(lang, 'net'),
            '${income - expense >= 0 ? '+' : '-'}${_money(income - expense, cur)}',
            income - expense >= 0 ? th.work : th.accent),
      ),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: primaryBtn(th, lang, t(lang, 'addExpense'), () => _addTx(context, s, true), fontSize: 10, padding: const EdgeInsets.all(12))),
        const SizedBox(width: 10),
        Expanded(child: secondaryBtn(th, lang, t(lang, 'addIncome'), () => _addTx(context, s, false), fontSize: 10, padding: const EdgeInsets.all(12))),
      ]),
      const SizedBox(height: 20),
      // --- income/expense charts: bar + pie, daily/weekly/monthly (#v30 item 11) ---
      _moneyChart(th, lang, s),
      const SizedBox(height: 20),
      // --- category bars (this month's expenses) ---
      if (cats.isNotEmpty) ...[
        for (final e in cats) _catBar(th, lang, e.key, e.value, maxCat, cur),
        const SizedBox(height: 16),
      ],
      // --- entries ---
      if (monthTxs.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(t(lang, 'noTx'),
              textAlign: TextAlign.center,
              style: pixelStyle(lang, 10, col(th.onSurfaceDim), text: t(lang, 'noTx'))),
        )
      else
        for (final tx in monthTxs.take(40)) _txRow(context, s, th, lang, tx, cur),
      const SizedBox(height: 20),
      _moneySettings(context, s, th, lang),
    ]);
  }

  // income/expense bar + pie chart, current daily/weekly/monthly window
  // (#v30 item 11) — reuses the same StatsChart widget the Stats screen uses.
  Widget _moneyChart(PixelTheme th, String lang, AppStore s) {
    final now = DateTime.now();
    final (start, end) = StatsAggregator.windowDays(now, _chartPeriod);
    final (inc, exp) = MoneyBook.totalsInWindow(s.money, start, end, s.fxRates, s.mainCurrency);
    final byCat = MoneyBook.byCategoryInWindow(s.money, start, end, s.fxRates, s.mainCurrency);
    final entries = _chartMode == ChartMode.pie
        ? [for (final e in byCat) ChartEntry(t(lang, e.key), e.value.round(), LabelColors.defaultFor(e.key))]
        : [
            ChartEntry(t(lang, 'income'), inc.round(), th.work),
            ChartEntry(t(lang, 'expense'), exp.round(), th.accent),
          ];

    Widget periodBtn(String text, StatPeriod p) {
      final sel = _chartPeriod == p;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: sel
              ? primaryBtn(th, lang, text, () => setState(() => _chartPeriod = p), fontSize: 8, padding: const EdgeInsets.all(8))
              : secondaryBtn(th, lang, text, () => setState(() => _chartPeriod = p), fontSize: 8, padding: const EdgeInsets.all(8)),
        ),
      );
    }

    Widget modeBtn(String text, ChartMode m) {
      final sel = _chartMode == m;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: sel
              ? primaryBtn(th, lang, text, () => setState(() => _chartMode = m), fontSize: 9, padding: const EdgeInsets.all(12))
              : secondaryBtn(th, lang, text, () => setState(() => _chartMode = m), fontSize: 9, padding: const EdgeInsets.all(12)),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        periodBtn(t(lang, 'pDaily'), StatPeriod.daily),
        periodBtn(t(lang, 'pWeekly'), StatPeriod.weekly),
        periodBtn(t(lang, 'pMonthly'), StatPeriod.monthly),
      ]),
      const SizedBox(height: 12),
      Row(children: [modeBtn(t(lang, 'chartBar'), ChartMode.bar), modeBtn(t(lang, 'chartPie'), ChartMode.pie)]),
      const SizedBox(height: 16),
      SizedBox(
        height: 200,
        child: StatsChart(
          entries: entries,
          series: const StatSeries([], [], []),
          average: 0,
          mode: _chartMode,
          lang: lang,
          axisColor: th.onSurfaceDim,
          textColor: th.onSurface,
          lineColor: th.accent,
          panelColor: th.panel,
          panelBorder: th.onSurfaceDim,
        ),
      ),
    ]);
  }

  Widget _total(PixelTheme th, String lang, String label, String value, int accent) => Column(
        children: [
          Text(label, style: pixelStyle(lang, 9, col(th.onSurfaceDim), text: label)),
          const SizedBox(height: 4),
          Text(value, style: pixelStyle(lang, 12, col(accent), text: value)),
        ],
      );

  Widget _catBar(PixelTheme th, String lang, String cat, double value, double max, String cur) {
    final label = t(lang, cat);
    final color = LabelColors.defaultFor(cat);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(label, style: pixelStyle(lang, 9, col(th.onSurface), text: label)),
            Text(_money(value, cur), style: pixelStyle(lang, 9, col(th.onSurfaceDim), text: _money(value, cur))),
          ]),
          const SizedBox(height: 3),
          LayoutBuilder(builder: (context, box) {
            final w = (box.maxWidth * (max <= 0 ? 0 : value / max)).clamp(3.0, box.maxWidth);
            return Stack(children: [
              Container(height: 8, color: col(th.panel)),
              Container(height: 8, width: w, color: col(color)),
            ]);
          }),
        ],
      ),
    );
  }

  Widget _txRow(BuildContext context, AppStore s, PixelTheme th, String lang, MoneyTx tx, String cur) {
    final d = dateOfEpochDay(tx.epochDay);
    final main = s.moneyToMain(tx);
    final sign = tx.isExpense ? '-' : '+';
    final amt = '$sign${_money(main, cur)}';
    return GestureDetector(
      onLongPress: () => _deleteTx(context, s, tx),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Swatch(color: LabelColors.defaultFor(tx.category), border: th.onSurfaceDim, size: 12),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${d.day} ${monthName(lang, d.month).substring(0, monthName(lang, d.month).length.clamp(0, 3))}  ${t(lang, tx.category)}',
                maxLines: 1, overflow: TextOverflow.clip,
                style: pixelStyle(lang, 9, col(th.onSurface), text: t(lang, tx.category))),
          ),
          Text(amt, style: pixelStyle(lang, 9, col(tx.isExpense ? th.accent : th.work), text: amt)),
        ]),
      ),
    );
  }

  void _addTx(BuildContext context, AppStore s, bool isExpense) {
    final th = s.theme;
    final lang = s.lang;
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    // built-ins + the user's own custom categories, in one picker (#v30 item 10)
    var cats = [...(isExpense ? _expenseCats : _incomeCats), ...s.customCategories];
    var cat = cats.first;
    var currency = s.mainCurrency;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: col(th.panel),
          title: Text(t(lang, isExpense ? 'addExpense' : 'addIncome'),
              style: pixelStyle(lang, 11, col(th.onSurface), text: t(lang, isExpense ? 'addExpense' : 'addIncome'))),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: amountCtrl,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: pixelStyle(lang, 13, col(th.onSurface), text: '0'),
                      decoration: InputDecoration(
                        hintText: t(lang, 'amount'),
                        hintStyle: pixelStyle(lang, 10, col(th.onSurfaceDim), text: t(lang, 'amount')),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  DropdownButton<String>(
                    value: currency,
                    dropdownColor: col(th.panel),
                    style: pixelStyle(lang, 10, col(th.onSurface), text: currency),
                    items: [for (final c in s.currencyOptions) DropdownMenuItem(value: c, child: Text(c))],
                    onChanged: (v) => setLocal(() => currency = v ?? currency),
                  ),
                ]),
                const SizedBox(height: 12),
                Text(t(lang, 'category'), style: pixelStyle(lang, 9, col(th.onSurfaceDim), text: t(lang, 'category'))),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final c in cats)
                      GestureDetector(
                        onTap: () => setLocal(() => cat = c),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: col(cat == c ? th.accent : th.bg),
                            border: Border.all(color: col(th.onSurfaceDim), width: 1),
                          ),
                          child: Text(t(lang, c),
                              style: pixelStyle(lang, 8, col(cat == c ? th.onAccent : th.onSurface), text: t(lang, c))),
                        ),
                      ),
                    GestureDetector(
                      onTap: () => _addCategory(context, s, th, lang,
                          (name) => setLocal(() {
                                cats = [...cats, name];
                                cat = name;
                              })),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: col(th.bg),
                          border: Border.all(color: col(th.onSurfaceDim), width: 1),
                        ),
                        child: Text('+ ${t(lang, 'addCategory')}',
                            style: pixelStyle(lang, 8, col(th.onSurfaceDim), text: '+ ${t(lang, 'addCategory')}')),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: noteCtrl,
                  style: pixelStyle(lang, 10, col(th.onSurface), text: 'Aa'),
                  decoration: InputDecoration(
                    hintText: t(lang, 'note'),
                    hintStyle: pixelStyle(lang, 9, col(th.onSurfaceDim), text: t(lang, 'note')),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            secondaryBtn(th, lang, t(lang, 'cancel'), () => Navigator.pop(ctx), fontSize: 10, padding: const EdgeInsets.all(10)),
            primaryBtn(th, lang, t(lang, 'add'), () {
              final v = double.tryParse(amountCtrl.text.replaceAll(',', '.'));
              if (v != null && v > 0) {
                s.addMoneyTx((v * 100).round(), currency, cat, isExpense, noteCtrl.text.trim());
              }
              Navigator.pop(ctx);
            }, fontSize: 10, padding: const EdgeInsets.all(10)),
          ],
        ),
      ),
    );
  }

  // user-defined category (#v30 item 10) — persists to AppStore, then hands
  // the new name back so the still-open add-tx dialog can select it.
  void _addCategory(BuildContext context, AppStore s, PixelTheme th, String lang,
      void Function(String) onAdded) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: col(th.panel),
        title: Text(t(lang, 'addCategory'), style: pixelStyle(lang, 12, col(th.onSurface), text: t(lang, 'addCategory'))),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: pixelStyle(lang, 11, col(th.onSurface), text: 'Aa'),
          decoration: InputDecoration(
            hintText: t(lang, 'categoryNameHint'),
            hintStyle: pixelStyle(lang, 10, col(th.onSurfaceDim), text: t(lang, 'categoryNameHint')),
          ),
        ),
        actions: [
          secondaryBtn(th, lang, t(lang, 'cancel'), () => Navigator.pop(ctx), fontSize: 10, padding: const EdgeInsets.all(10)),
          primaryBtn(th, lang, t(lang, 'add'), () {
            final n = ctrl.text.trim().toUpperCase();
            if (n.isNotEmpty) {
              s.addCustomCategory(n);
              onAdded(n);
            }
            Navigator.pop(ctx);
          }, fontSize: 10, padding: const EdgeInsets.all(10)),
        ],
      ),
    );
  }

  void _deleteTx(BuildContext context, AppStore s, MoneyTx tx) {
    final th = s.theme;
    final lang = s.lang;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: col(th.panel),
        content: Text('${t(lang, tx.category)} · ${_money(s.moneyToMain(tx), s.mainCurrency)}',
            style: pixelStyle(lang, 11, col(th.onSurface), text: t(lang, tx.category))),
        actions: [
          secondaryBtn(th, lang, t(lang, 'no'), () => Navigator.pop(ctx), fontSize: 10, padding: const EdgeInsets.all(10)),
          primaryBtn(th, lang, t(lang, 'yes'), () {
            s.deleteMoneyTx(tx);
            Navigator.pop(ctx);
          }, fontSize: 10, padding: const EdgeInsets.all(10)),
        ],
      ),
    );
  }

  Widget _moneySettings(BuildContext context, AppStore s, PixelTheme th, String lang) {
    final rate = (s.dailyRateMinor / 100).toStringAsFixed(0);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: col(th.onSurfaceDim), width: 2)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t(lang, 'moneySettings'), style: pixelStyle(lang, 11, col(th.onSurface), text: t(lang, 'moneySettings'))),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(t(lang, 'mainCurrency'), style: pixelStyle(lang, 10, col(th.onSurfaceDim), text: t(lang, 'mainCurrency'))),
            DropdownButton<String>(
              value: s.mainCurrency,
              dropdownColor: col(th.panel),
              style: pixelStyle(lang, 11, col(th.onSurface), text: s.mainCurrency),
              items: [for (final c in s.currencyOptions) DropdownMenuItem(value: c, child: Text(c))],
              onChanged: (v) { if (v != null) s.setMainCurrency(v); },
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: Text(t(lang, 'dailyRate'), style: pixelStyle(lang, 10, col(th.onSurfaceDim), text: t(lang, 'dailyRate')))),
            SizedBox(
              width: 110,
              child: TextField(
                controller: TextEditingController(text: rate == '0' ? '' : rate),
                keyboardType: TextInputType.number,
                textAlign: TextAlign.right,
                style: pixelStyle(lang, 12, col(th.onSurface), text: rate),
                decoration: InputDecoration(
                  hintText: '0',
                  suffixText: ' ${s.mainCurrency}',
                  suffixStyle: pixelStyle(lang, 9, col(th.onSurfaceDim), text: s.mainCurrency),
                ),
                onSubmitted: (v) {
                  final d = double.tryParse(v.replaceAll(',', '.')) ?? 0;
                  s.setDailyRate((d * 100).round());
                },
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text(t(lang, 'dailyRateHelp'), style: pixelStyle(lang, 8, col(th.onSurfaceDim), text: t(lang, 'dailyRateHelp'))),
        ],
      ),
    );
  }
}

/// HabitKit-style contribution grid: 7 rows (weekdays) × N week columns, right
/// edge = this week. A day is BINARY — completed once or many looks identical
/// (full habit color); empty days are a faint theme square (the user's rule).
/// [weeks] is how much trailing history to show; once it exceeds one band's
/// width (18 columns, tuned to fit a phone) the grid STACKS more bands
/// growing downward instead of stretching wider than the screen — oldest
/// band on top, the band containing today at the bottom (#v30 follow-up).
class _HabitHeatmap extends StatelessWidget {
  final Map<int, int> days;
  final int color, today;
  // optional per-day color override (e.g. mood level) instead of the binary
  // done/not-done color (#v30). optional upper bound on cell size so a
  // relocated, frameless heatmap can stretch edge-to-edge (#v30 item 6).
  final int? Function(int day)? colorForDay;
  final double maxCellSize;
  final int weeks;
  const _HabitHeatmap(
      {required this.days, required this.color, required this.today,
      this.colorForDay, this.maxCellSize = 12.0, this.weeks = 18});

  static const _bandCols = 18; // per-band width, tuned to fit a phone

  @override
  Widget build(BuildContext context) {
    // align the right column of the bottom band to the week containing
    // today (Mon..Sun rows)
    final todayWeekday = dateOfEpochDay(today).weekday; // 1=Mon
    final lastColStart = today - (todayWeekday - 1);
    final numBands = (weeks / _bandCols).ceil().clamp(1, 1000000);
    return LayoutBuilder(builder: (context, box) {
      // every cell (incl. the last) carries a 2px right margin, so the
      // budget must divide out bandCols*2, not (bandCols-1)*2 — the old
      // formula under-budgeted by one gap, always rendering 2px too wide.
      // Masked for years by the 12px cap; exposed once a caller removes the
      // cap to stretch full-width (#v30 item 6).
      final cell = ((box.maxWidth - _bandCols * 2) / _bandCols).clamp(4.0, maxCellSize);
      return Column(
        children: [
          for (var b = numBands - 1; b >= 0; b--) ...[
            if (b != numBands - 1) const SizedBox(height: 6),
            _band(b, b == numBands - 1 ? weeks - b * _bandCols : _bandCols, lastColStart, cell),
          ],
        ],
      );
    });
  }

  Widget _band(int b, int colsInBand, int lastColStart, double cell) {
    return Column(
      children: [
        for (var row = 0; row < 7; row++)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end, // right-align a partial (oldest) band
              children: [
                for (var c = 0; c < colsInBand; c++)
                  Builder(builder: (_) {
                    final weeksAgo = b * _bandCols + (colsInBand - 1 - c);
                    final day = lastColStart - weeksAgo * 7 + row;
                    final future = day > today;
                    final dayColor = future
                        ? null
                        : (colorForDay != null ? colorForDay!(day) : ((days[day] ?? 0) > 0 ? color : null));
                    return Container(
                      width: cell,
                      height: cell,
                      margin: const EdgeInsets.only(right: 2),
                      decoration: BoxDecoration(
                        // empty/not-done days are a DIM shade of the row's
                        // own colour (HabitKit style — screen_1.png), not a
                        // separate neutral tone: an "empty" cell using the
                        // screen's own bg colour was invisible once the
                        // heatmap lost its card frame (#v30 follow-up).
                        color: future
                            ? Colors.transparent
                            : col(dayColor ?? color).withValues(alpha: dayColor != null ? 1 : 0.18),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    );
                  }),
              ],
            ),
          ),
      ],
    );
  }
}
