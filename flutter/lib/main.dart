import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_blocker.dart';
import 'camera.dart';
import 'engine/garden_engine.dart';
import 'engine/garden_view.dart';
import 'logic.dart';
import 'pixel.dart';
import 'store.dart';
import 'strings.dart';
import 'tutorial.dart';

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
  // The web deployment serves the USER and TEST builds from one origin
  // (github.io project pages), and shared_preferences on web is origin-wide
  // localStorage — without a distinct prefix the test build's demo seed would
  // leak into the user build's clean slate. Web-only on purpose: Android's
  // test APK is already isolated by its own applicationId, and changing its
  // prefix would orphan existing on-device data (#v33.8).
  if (kIsWeb && const bool.fromEnvironment('TEST_BUILD')) {
    SharedPreferences.setPrefix('flutter.pptest.');
  }
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
            scrollBehavior: const _AppScrollBehavior(),
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

/// How every list in the app scrolls (#v33.7).
///
/// `BouncingScrollPhysics` for the fling curve a phone browser and a feed have
/// — Android's default clamping physics stops a fling dead and shows a glow
/// instead of carrying momentum, which is half of what "it doesn't flow" was
/// about. The overscroll glow goes with it: the bounce already shows the edge.
///
/// `dragDevices` adds the mouse, so the page can be DRAGGED on web and desktop
/// (Flutter leaves that off by default and gives you the wheel only). The
/// trackpad is deliberately NOT in the set — it scrolls by panning already, and
/// listing it here would turn two-finger scrolling into a drag gesture.
class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
      };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;
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

/// One caption line under a Focus Sessions label — it shrinks rather than wraps
/// (#v34.3).
///
/// The caption is two fields per line now, and a 3-up column on a small phone is
/// only ~97px wide, so plain [Text] would break a value in half — the exact bug
/// the old four-line caption existed to prevent. Scaling down keeps both fields
/// whole at any width, the same trick the shop's OWNED/PLACED row uses.
/// Squeeze the padding out of a caption line's separators (#v34.5).
///
/// ' · ' costs about two characters of width per separator at this size, and
/// in a 3-up column that is the difference between a readable line and one the
/// scale-down has shrunk too far. The wide one-line form keeps its spaces —
/// only the narrow two-line fallback is tight. Public so the tests apply the
/// same transform instead of hardcoding the squeezed strings.
String tightSeparators(String s) => s.replaceAll(' · ', '·');

Widget _capLine(PixelTheme th, String lang, String raw) => Align(
      alignment: Alignment.centerLeft,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Builder(builder: (_) {
          final text = tightSeparators(raw);
          return Text(text,
              maxLines: 1,
              softWrap: false,
              style: pixelStyle(lang, 8, col(th.onSurfaceDim), text: text));
        }),
      ),
    );

/// A full-screen overlay scaffold with a title and a trailing CLOSE button.
/// [themeOverride] lets a screen paint itself in a theme the app has not
/// adopted yet — the custom theme editor previews with it (#v32.3).
Widget overlayScaffold(BuildContext context, AppStore s, String title, List<Widget> children,
    {PixelTheme? themeOverride}) {
  final th = themeOverride ?? s.theme;
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
            // Each section gets its own layer (#v33.7) — one the compositor
            // moves rather than redraws.
            //
            // A ListView here was tried and REVERTED (#v34.6): these pages are
            // a handful of very tall sections, not many small ones, so the
            // viewport almost always intersects every item and nothing gets
            // culled — measured, no change. The weight is INSIDE a section
            // (Sessions in Pixels builds ~900 cell widgets), so that is where
            // it has to be fixed.
            for (final section in children) RepaintBoundary(child: section),
            const SizedBox(height: 24),
            secondaryBtn(th, s.lang, t(s.lang, 'close'), () => Navigator.pop(context), padding: const EdgeInsets.all(16)),
          ],
        ),
      ),
    ),
  );
}

/// Returns when the panel is popped, so a caller can refresh behind it (#v32.4).
Future<void> openPanel(BuildContext context, AppStore s, Widget Function() builder) {
  return Navigator.of(context).push(MaterialPageRoute(builder: (_) => AnimatedBuilder(animation: s, builder: (_, __) => builder())));
}

// ---- home / timer -----------------------------------------------------------

/// Spotlight targets for the first-run tour (#v34). File-level, not built in
/// `build`, because a GlobalKey has to be the SAME object across rebuilds —
/// only one home screen is ever alive, so one set is enough.
final _tourKeys = {
  for (final n in ['money', 'habit', 'stats', 'garden', 'theme', 'settings', 'store', 'coin', 'timer', 'label'])
    n: GlobalKey(debugLabel: 'tour_$n'),
};

class HomeScreen extends StatelessWidget {
  final AppStore s;
  const HomeScreen(this.s, {super.key});

  /// The tour, in the order the eye reads the screen: what the timer does,
  /// then every icon in the top bar. Hidden trackers drop out of the list, so
  /// the tour never spotlights an icon that isn't there.
  static List<TutorialStep> tourSteps(AppStore s) => [
        TutorialStep(null, 'tutWelcome', 'tutWelcomeBody'),
        TutorialStep(_tourKeys['timer'], 'tutTimer', 'tutTimerBody'),
        TutorialStep(_tourKeys['label'], 'label', 'tutLabelBody'),
        if (s.showMoneyTracker) TutorialStep(_tourKeys['money'], 'money', 'tutMoneyBody'),
        if (s.showHabitTracker) TutorialStep(_tourKeys['habit'], 'habits', 'tutHabitBody'),
        TutorialStep(_tourKeys['stats'], 'stats', 'tutStatsBody'),
        TutorialStep(_tourKeys['garden'], 'garden', 'tutGardenBody'),
        TutorialStep(_tourKeys['theme'], 'theme', 'tutThemeBody'),
        TutorialStep(_tourKeys['settings'], 'settings', 'tutSettingsBody'),
        TutorialStep(_tourKeys['store'], 'shop', 'tutStoreBody'),
        TutorialStep(_tourKeys['coin'], 'tutCoin', 'tutCoinBody'),
        TutorialStep(null, 'tutEnd', 'tutEndBody'),
      ];

  // web test guide auto-pops once per page-load; static so hot-reload won't respam
  static bool _testGuideShown = false;

  @override
  Widget build(BuildContext context) {
    // The clock comes in on its own notifier (#v33.7) — this is the one screen
    // that wants a rebuild five times a second, and only while you can see it.
    // Open a panel and this route goes offstage but stays mounted, so it kept
    // rebuilding underneath: five wasted builds a second, on the same thread as
    // the scroll you are dragging up there. `TickerMode` is already false for a
    // covered route (it is what pauses animations), so it answers "am I on
    // screen" without the store having to know anything about routes.
    final onScreen = TickerMode.valuesOf(context).enabled;
    return AnimatedBuilder(
      animation: onScreen ? s.homeUpdates : s,
      builder: (context, _) {
        final th = s.theme;
        final lang = s.lang;
        final e = s.engine;
        final pomodoro = s.isPomodoroMode; // #v31.16
        final running = pomodoro ? e.isRunning : s.stopwatch.isRunning;
        final modeText = !pomodoro
            ? t(lang, 'stopwatch')
            : (e.isFinished ? t(lang, 'allDone') : (e.mode == Mode.work ? t(lang, 'work') : t(lang, 'break')));
        // focusTint, not accent: a custom theme pins the clock to its TEXT 1 so
        // picking a dark SELECTED SQUARE can't sink the countdown (#v32.4).
        final modeColor = !pomodoro ? th.focusTint : (e.isFinished ? th.accent : th.phaseColor(e.mode));
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
        // web-only: pop the test guide once per page-load (never on the phone APK).
        // Waits for the tour, or the two would stack on a fresh profile (#v34).
        if (kIsWeb && !_testGuideShown && s.tutorialDone) {
          _testGuideShown = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) _showTestGuide(context, th, lang);
          });
        }
        final garden = s.homeGardenBackdrop;
        // #v32.4: a wallpaper needs the same treatment as the garden — both are
        // imagery of unknown brightness under the timer.
        final overImage = s.homeOverImage;
        // in garden mode the timer is drawn over the live scene, so give its text
        // a hard pixel shadow for legibility instead of a scrim box (#5/#7)
        final shadows = overImage
            ? const [Shadow(offset: Offset(2, 2), color: Color(0xCC000000))]
            : const <Shadow>[];
        // over the dark garden the foreground text must be LIGHT — on light themes
        // th.onSurface is dark and was unreadable / looked "darkened" (#v19 #6).
        final overGarden = overImage ? const Color(0xFFF4F4F4) : col(th.onSurface);
        // the countdown + SESSION follow the phase colour (theme accent while
        // focusing, break colour on a break) so the main screen carries each
        // theme's identity (#v32.1); in garden mode they keep the light
        // legibility colour — the v19 rule stands.
        final phaseText = overImage ? overGarden : col(modeColor);
        final timeText = pomodoro ? e.formattedTime() : s.stopwatch.formattedTime();
        final timerBlock = Column(
          key: _tourKeys['timer'],
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(modeText, style: pixelStyle(lang, 22, col(modeColor), spacing: 2, text: modeText).copyWith(shadows: shadows)),
            const SizedBox(height: 16),
            secondaryBtn(th, lang, s.currentLabel, () => openPanel(context, s, () => LabelScreen(s)),
                fontSize: 11, padding: const EdgeInsets.all(10), key: _tourKeys['label']),
            const SizedBox(height: 28),
            Text(timeText, style: pixelStyle(lang, 48, phaseText, text: timeText).copyWith(shadows: shadows)),
            const SizedBox(height: 32),
            // no fixed duration in stopwatch mode, so no "% complete" to show
            // (#v31.16) — a plain gap keeps the buttons from crowding the clock
            if (pomodoro)
              PixelProgress(
                  percent: e.progressPercent(),
                  track: th.panel,
                  border: th.onSurfaceDim,
                  fill: e.isFinished ? th.accent : th.phaseColor(e.mode))
            else
              const SizedBox(height: 20),
            const SizedBox(height: 32),
            Row(children: [
              Expanded(
                  child: primaryBtn(th, lang, t(lang, running ? 'pause' : 'start'),
                      s.toggleStartPause, fontSize: 14, padding: const EdgeInsets.all(16))),
              const SizedBox(width: 16),
              Expanded(
                  child: secondaryBtn(th, lang, t(lang, 'reset'), s.reset,
                      fontSize: 14, padding: const EdgeInsets.all(16))),
            ]),
          ],
        );
        // "SESSION X/Y" only means anything in pomodoro mode (#v31.16)
        final sessionText = pomodoro
            ? Text(tf(lang, 'session', [e.session, e.totalSessions]),
                style: pixelStyle(lang, 12, phaseText, text: tf(lang, 'session', [e.session, e.totalSessions])).copyWith(shadows: shadows))
            : const SizedBox.shrink();

        return Scaffold(
          backgroundColor: col(th.bg),
          body: Stack(
            children: [
              // live garden behind the timer when HOME mode = GARDEN (#3)
              if (garden) Positioned.fill(child: _liveBackdrop(th, lang)),
              // ...or the user's own photo when HOME mode = WALLPAPER (#v32.4)
              if (s.homeBackdrop == 'wallpaper' && s.wallpaperPath != null)
                Positioned.fill(
                    child: wallpaperFill(s.wallpaperPath!, s.wallZoom, s.wallDx, s.wallDy)),
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
              // web/desktop test hint — shows ONLY on web (kIsWeb), never on the
              // real phone APK. IgnorePointer so it can't block the timer buttons.
              // tappable web-only hint → opens the full guide popup
              if (kIsWeb)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 2,
                  child: Center(
                    child: GestureDetector(
                      onTap: () => _showTestGuide(context, th, lang),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        color: const Color(0x99000000),
                        child: Text(
                          '[?] TEST GUIDE - tap  |  localhost:8787',
                          style: pixelStyle(lang, 9, const Color(0xFFF4F4F4),
                              text: 'TEST GUIDE tap localhost 8787'),
                        ),
                      ),
                    ),
                  ),
                ),
              // the first-run tour, last in the stack so it covers everything
              // it explains (#v34). Lives here rather than in a route because
              // it has to MEASURE the real widgets underneath it.
              if (!s.tutorialDone)
                Positioned.fill(
                  child: TutorialOverlay(
                    steps: HomeScreen.tourSteps(s),
                    theme: th,
                    lang: lang,
                    onDone: () => s.setTutorialDone(true),
                  ),
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
          forestOnly: s.homeForestBackdrop,
          // FOREST is the view from high above (#v35.0) — zoomed out so the
          // canopy reads as a treetop carpet rather than a handful of trunks.
          camera: s.homeForestBackdrop ? GardenCamera(zoom: 0.5) : null,
        );
      },
    );
  }

  // web-only test guide popup (never on the phone APK)
  void _showTestGuide(BuildContext context, PixelTheme th, String lang) {
    Widget line(String txt) => Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Text(txt, style: pixelStyle(lang, 10, col(th.onSurface), text: txt)),
        );
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: col(th.panel),
        title: Text('WEB TEST GUIDE', style: pixelStyle(lang, 13, col(th.accent), text: 'WEB TEST GUIDE')),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              line('Open (in a terminal):'),
              line('  cd pixel_pomo\\flutter'),
              line('  flutter run -d chrome --web-port 8787'),
              const SizedBox(height: 6),
              line('URL:  localhost:8787'),
              line('Phone size:  F12, then Ctrl+Shift+M'),
              line('Keys:  r reload  R restart  q quit'),
              const SizedBox(height: 6),
              line('No Chrome? server mode:'),
              line('  flutter run -d web-server'),
              line('  --web-hostname 0.0.0.0 --web-port 8787'),
              line('  then open localhost:8787'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('CLOSE', style: pixelStyle(lang, 11, col(th.accent), text: 'CLOSE')),
          ),
        ],
      ),
    );
  }

  // left = money/habit/stats/garden/theme · right = settings/store/coin
  // (user-specified order, #v30 item 1).
  Widget _topBar(BuildContext context, PixelTheme th, String lang) {
    // over the live garden wallpaper, give the coin count a hard pixel shadow +
    // a LIGHT colour (th.onSurface is dark on light themes) for legibility (#v19 #6).
    final shadows = s.homeOverImage
        ? const [Shadow(offset: Offset(2, 2), color: Color(0xCC000000))]
        : const <Shadow>[];
    final coinColor = s.homeOverImage ? const Color(0xFFF4F4F4) : col(th.onSurface);
    // 5 icons on the left; slightly bigger glyphs + looser padding so they
    // don't read as crammed into the screen corners (#v30 item 1).
    // KeyedSubtree, not a second key on the IconButton: a widget gets one key,
    // and the test keys below were already spoken for. It adds no layout, and
    // the tour measures the icon's own render box through it (#v34).
    // The bar carries up to 8 items (both trackers ship ON since #v34.9), and
    // at 30px each that overflowed a 360px phone by ~58px — a real yellow-bar
    // overflow on a fresh install. Size the glyph to whatever the width
    // actually allows instead: full size when there is room, smaller when
    // every tracker is on and the phone is narrow. Never below 18, or the
    // icons stop being recognisable.
    // 5 fixed icons + up to 2 tracker icons + the coin block.
    final iconCount = 5 + (s.showMoneyTracker ? 1 : 0) + (s.showHabitTracker ? 1 : 0);
    final avail = MediaQuery.of(context).size.width - 24; // the row's padding
    // coin disc + gap + the count (PressStart2P is monospace, so a digit is
    // about one font size wide) + the block's own padding
    final coinW = 26 + 6 + '${s.coins}'.length * 14.0 + 12;
    final glyph = (((avail - coinW) / iconCount) - 12).clamp(18.0, 30.0);

    Widget icon(String name, VoidCallback onTap, Key key) => KeyedSubtree(
          key: _tourKeys[name],
          child: IconButton(
            key: key,
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(),
            visualDensity: VisualDensity.compact,
            icon: Image.asset('assets/icon/icon_$name.png',
                width: glyph, height: glyph, filterQuality: FilterQuality.none),
            onPressed: onTap,
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      // spread all 8 evenly across the bar, not two clusters split by a
      // Spacer (that stacked them all on the left, #v30 follow-up).
      // spaceBetween redistributes evenly on its own when the money/habit
      // icons are hidden via Settings (#v32) — no manual spacing math.
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        if (s.showMoneyTracker)
          icon('money', () => openPanel(context, s, () => MoneyScreen(s)), const Key('moneyButton')),
        if (s.showHabitTracker)
          icon('habit', () => openPanel(context, s, () => HabitScreen(s)), const Key('habitButton')),
        icon('stats', () => openPanel(context, s, () => StatsScreen(s)), const Key('statsButton')),
        icon('garden', () => openPanel(context, s, () => GardenScreen(s)), const Key('gardenButton')),
        icon('theme', () => openPanel(context, s, () => ThemeScreen(s)), const Key('themeButton')),
        icon('settings', () => openPanel(context, s, () => SettingsScreen(s)), const Key('settingsButton')),
        icon('store', () => openPanel(context, s, () => ShopScreen(s)), const Key('storeButton')),
        // Flexible + scaleDown: the icons are fixed-size images, so the coin is
        // what has to give when the bar runs out of room. Without this the Row
        // overflowed by ~44px on a 360px phone once both trackers shipped ON
        // (#v34.9) — a yellow overflow bar on a fresh install.
        Flexible(
          child: KeyedSubtree(
          key: _tourKeys['coin'],
          child: GestureDetector(
            key: const Key('shopButton'),
            onTap: () => openPanel(context, s, () => ShopScreen(s)),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(children: [
                // 26, not the icons' 30: the coin is a SOLID filled disc while the
                // menu icons are line-art glyphs — at equal pixel height the disc
                // optically reads taller, which is what "the gold icon is bigger"
                // meant; the sprites' content bounds are identical (#v32).
                const GoldCoin(size: 26),
                const SizedBox(width: 6),
                Text('${s.coins}', style: pixelStyle(lang, 14, coinColor, text: '${s.coins}').copyWith(shadows: shadows)),
              ]),
              ),
            ),
          ),
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
      // timer mode, at the top: POMODORO shows the work/break/session
      // steppers below, STOPWATCH hides them (#v31.15)
      Text(t(lang, 'timerMode'), style: pixelStyle(lang, 12, col(th.onSurfaceDim), text: t(lang, 'timerMode'))),
      const SizedBox(height: 12),
      Row(
        children: [
          for (final pomodoro in const [false, true]) ...[
            if (pomodoro) const SizedBox(width: 12),
            Expanded(
              child: PixelButton(
                text: t(lang, pomodoro ? 'pomodoro' : 'stopwatch'),
                fill: s.isPomodoroMode == pomodoro ? th.accent : th.panel,
                border: s.isPomodoroMode == pomodoro ? th.onSurface : th.onSurfaceDim,
                textColor: s.isPomodoroMode == pomodoro ? th.onAccent : th.onSurface,
                shadow: th.shadow,
                lang: lang,
                fontSize: 11,
                onTap: () => s.setPomodoroMode(pomodoro),
              ),
            ),
          ],
        ],
      ),
      const SizedBox(height: 24),
      if (s.isPomodoroMode) ...[
        _stepper(th, lang, t(lang, 'study'), work, 5, 300, 5, (v) => _apply(() => work = v)),
        _stepper(th, lang, t(lang, 'breakMin'), brk, 1, 120, 1, (v) => _apply(() => brk = v)),
        _stepper(th, lang, t(lang, 'sessions'), sess, 1, 24, 1, (v) => _apply(() => sess = v)),
        const SizedBox(height: 24),
      ],
      Text(t(lang, 'language'), style: pixelStyle(lang, 12, col(th.onSurfaceDim), text: t(lang, 'language'))),
      const SizedBox(height: 12),
      ..._languagePicker(th, lang, s),
      const SizedBox(height: 24),
      Text(t(lang, 'homeMode'), style: pixelStyle(lang, 12, col(th.onSurfaceDim), text: t(lang, 'homeMode'))),
      const SizedBox(height: 12),
      // three modes since #v32.4. WALLPAPER used to be hidden until one was
      // saved, which left no hint that the mode existed — it is always on the
      // row now, and tapping it with no photo opens the how-to (#v34).
      Row(
        children: [
          for (final mode in ['clean', 'garden', 'forest', 'wallpaper']) ...[
            if (mode != 'clean') const SizedBox(width: 8),
            Expanded(
              child: PixelButton(
                key: Key('homeMode_$mode'),
                text: t(
                    lang,
                    switch (mode) {
                      'clean' => 'clean',
                      'garden' => 'gardenMode',
                      'forest' => 'forestMode',
                      _ => 'wallMode',
                    }),
                fill: s.homeBackdrop == mode ? th.accent : th.panel,
                border: s.homeBackdrop == mode ? th.onSurface : th.onSurfaceDim,
                textColor: s.homeBackdrop == mode ? th.onAccent : th.onSurface,
                shadow: th.shadow,
                lang: lang,
                fontSize: 11,
                onTap: () {
                  if (mode == 'wallpaper' && s.wallpaperPath == null) {
                    openPanel(context, s, () => WallpaperHowToScreen(s));
                  } else {
                    s.setHomeBackdrop(mode);
                  }
                },
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
      // ponytail: !kIsWeb short-circuits so dart:io Platform is never touched on web (would throw UnsupportedError)
      if (!kIsWeb && Platform.isAndroid) ...[
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
      // stats detail level (#v32): SIMPLE hides Session Timeline in a Week +
      // the SESSIONS IN PIXELS screen from Stats; DETAILED shows everything.
      const SizedBox(height: 24),
      Text(t(lang, 'statsMode'), style: pixelStyle(lang, 12, col(th.onSurfaceDim), text: t(lang, 'statsMode'))),
      const SizedBox(height: 12),
      Row(
        children: [
          for (final detailed in const [false, true]) ...[
            if (detailed) const SizedBox(width: 12),
            Expanded(
              child: PixelButton(
                text: t(lang, detailed ? 'statsDetailed' : 'statsSimple'),
                fill: s.statsDetailed == detailed ? th.accent : th.panel,
                border: s.statsDetailed == detailed ? th.onSurface : th.onSurfaceDim,
                textColor: s.statsDetailed == detailed ? th.onAccent : th.onSurface,
                shadow: th.shadow,
                lang: lang,
                fontSize: 11,
                onTap: () => s.setStatsDetailed(detailed),
              ),
            ),
          ],
        ],
      ),
      // reveals the custom theme section on the Theme screen (#v32.4)
      const SizedBox(height: 24),
      Text(t(lang, 'detailedCustom'),
          style: pixelStyle(lang, 12, col(th.onSurfaceDim), text: t(lang, 'detailedCustom'))),
      const SizedBox(height: 12),
      Row(
        children: [
          for (final on in const [true, false]) ...[
            if (!on) const SizedBox(width: 12),
            Expanded(
              child: PixelButton(
                text: on ? 'ON' : 'OFF',
                fill: s.detailedCustom == on ? th.accent : th.panel,
                border: s.detailedCustom == on ? th.onSurface : th.onSurfaceDim,
                textColor: s.detailedCustom == on ? th.onAccent : th.onSurface,
                shadow: th.shadow,
                lang: lang,
                fontSize: 11,
                onTap: () => s.setDetailedCustom(on),
              ),
            ),
          ],
        ],
      ),
      // hide whole trackers (#v32): the top-bar icon disappears (the bar
      // re-spreads evenly) and the feature goes inert while hidden.
      const SizedBox(height: 24),
      Text(t(lang, 'habits'), style: pixelStyle(lang, 12, col(th.onSurfaceDim), text: t(lang, 'habits'))),
      const SizedBox(height: 12),
      Row(
        children: [
          for (final on in const [true, false]) ...[
            if (!on) const SizedBox(width: 12),
            Expanded(
              child: PixelButton(
                text: on ? 'ON' : 'OFF',
                fill: s.showHabitTracker == on ? th.accent : th.panel,
                border: s.showHabitTracker == on ? th.onSurface : th.onSurfaceDim,
                textColor: s.showHabitTracker == on ? th.onAccent : th.onSurface,
                shadow: th.shadow,
                lang: lang,
                fontSize: 11,
                onTap: () => s.setShowHabitTracker(on),
              ),
            ),
          ],
        ],
      ),
      const SizedBox(height: 24),
      Text(t(lang, 'money'), style: pixelStyle(lang, 12, col(th.onSurfaceDim), text: t(lang, 'money'))),
      const SizedBox(height: 12),
      Row(
        children: [
          for (final on in const [true, false]) ...[
            if (!on) const SizedBox(width: 12),
            Expanded(
              child: PixelButton(
                text: on ? 'ON' : 'OFF',
                fill: s.showMoneyTracker == on ? th.accent : th.panel,
                border: s.showMoneyTracker == on ? th.onSurface : th.onSurfaceDim,
                textColor: s.showMoneyTracker == on ? th.onAccent : th.onSurface,
                shadow: th.shadow,
                lang: lang,
                fontSize: 11,
                onTap: () => s.setShowMoneyTracker(on),
              ),
            ),
          ],
        ],
      ),
      // replay the first-run tour (#v34) — SKIP is otherwise one-way, and the
      // tour is the only place several of these buttons are explained.
      const SizedBox(height: 24),
      secondaryBtn(th, lang, t(lang, 'tutReplay'), () {
        s.setTutorialDone(false);
        Navigator.pop(context); // back to the home screen, where the tour runs
      }, fontSize: 11, key: const Key('replayTutorial')),
    ]);
  }

  /// True while the language list is expanded (#v34.3).
  bool _langOpen = false;

  /// The language control: ONE button showing the language in use, with a
  /// caret on the right; tapping it drops the other five open, and picking one
  /// closes it again (#v34.3). Six buttons stacked permanently pushed
  /// everything below them a screen away, and five of them were always the
  /// wrong answer.
  List<Widget> _languagePicker(PixelTheme th, String lang, AppStore s) {
    final current = languageOptions.firstWhere((o) => o[0] == lang,
        orElse: () => languageOptions.first);
    return [
      PixelButton(
        key: const Key('languageButton'),
        // Real matched triangles, not the ASCII 'v'/'^' pair (#v34.5): '^' sits
        // high and thin against cap-height text and read as a stray mark next
        // to a full-height 'v'. Both PressStart2P and Galmuri11 carry U+25B2 /
        // U+25BC — verified against the font cmaps, not assumed.
        text: '${current[1]}   ${_langOpen ? '▲' : '▼'}',
        fill: th.accent,
        border: th.onSurface,
        textColor: th.onAccent,
        shadow: th.shadow,
        lang: current[0], // the autonym renders in its own script
        onTap: () => setState(() => _langOpen = !_langOpen),
      ),
      if (_langOpen)
        // only the languages NOT in use — the button above already IS the
        // current one, so repeating it in the list would just be a no-op row
        for (final opt in languageOptions.where((o) => o[0] != lang)) ...[
          const SizedBox(height: 8),
          PixelButton(
            text: opt[1],
            fill: th.panel,
            border: th.onSurfaceDim,
            textColor: th.onSurface,
            shadow: th.shadow,
            lang: opt[0],
            onTap: () {
              setState(() => _langOpen = false);
              s.selectLanguage(opt[0]); // rebuilds the app in the new language
            },
          ),
        ],
    ];
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
    showDialog(
      context: context,
      builder: (ctx) => _BlockerPermDialog(s),
    );
  }

  Widget _stepper(PixelTheme th, String lang, String label, int value, int min, int max, int step, ValueChanged<int> onChange) {
    return _stepperRow(th, lang, label, value, min, max, step, onChange,
        onType: () => _typeValue(th, lang, label, value, min, max, onChange));
  }

  /// Tap the number to type one instead of holding + (#v34.5).
  ///
  /// Getting from 25 to 180 minutes was 31 taps. Anything out of range is
  /// pulled to the nearest end rather than rejected — typing 500 and pressing
  /// enter gives you the maximum, which is what someone reaching for a big
  /// number meant.
  Future<void> _typeValue(PixelTheme th, String lang, String label, int value, int min,
      int max, ValueChanged<int> onChange) async {
    final typed = await showDialog<int>(
      context: context,
      builder: (_) => _StepperValueDialog(
          th: th, lang: lang, label: label, value: value, min: min, max: max),
    );
    if (typed != null) onChange(typed);
  }
}

/// The keyboard entry behind a Settings stepper (#v34.5).
///
/// A StatefulWidget purely so it owns its [TextEditingController] — disposing
/// one from the caller right after `showDialog` returns tears it down while the
/// dialog is still animating out, and the field rebuilds against a dead
/// controller ("A TextEditingController was used after being disposed").
class _StepperValueDialog extends StatefulWidget {
  final PixelTheme th;
  final String lang;
  final String label;
  final int value, min, max;
  const _StepperValueDialog(
      {required this.th,
      required this.lang,
      required this.label,
      required this.value,
      required this.min,
      required this.max});

  @override
  State<_StepperValueDialog> createState() => _StepperValueDialogState();
}

class _StepperValueDialogState extends State<_StepperValueDialog> {
  late final _controller = TextEditingController(text: '${widget.value}');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Out of range is pulled to the nearest end, never refused — someone who
  /// types 500 and hits enter wants the biggest value there is.
  void _submit() {
    final typed = int.tryParse(_controller.text.trim());
    Navigator.pop(context, typed?.clamp(widget.min, widget.max).toInt());
  }

  @override
  Widget build(BuildContext context) {
    final th = widget.th, lang = widget.lang;
    final hint = tf(lang, 'rangeHint', [widget.min, widget.max]);
    return AlertDialog(
      backgroundColor: col(th.panel),
      title: Text(widget.label,
          style: pixelStyle(lang, 12, col(th.onSurface), text: widget.label)),
      content: TextField(
        key: const Key('stepperField'),
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        style: pixelStyle(lang, 16, col(th.onSurface), text: _controller.text),
        decoration: InputDecoration(
          helperText: hint,
          helperStyle: pixelStyle(lang, 8, col(th.onSurfaceDim), text: hint),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t(lang, 'cancel'),
              style: pixelStyle(lang, 11, col(th.onSurfaceDim), text: t(lang, 'cancel'))),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(t(lang, 'save'),
              style: pixelStyle(lang, 11, col(th.accent), text: t(lang, 'save'))),
        ),
      ],
    );
  }
}

/// The app-blocker permission dialog (#v23), now with live feedback (#v32.1):
/// when the user hops to system settings, grants a permission, and comes back,
/// the granted row re-checks on app resume and renders STRUCK THROUGH — so
/// it's visible which requests are already done instead of two identical
/// buttons giving no feedback.
class _BlockerPermDialog extends StatefulWidget {
  final AppStore s;
  const _BlockerPermDialog(this.s);
  @override
  State<_BlockerPermDialog> createState() => _BlockerPermDialogState();
}

class _BlockerPermDialogState extends State<_BlockerPermDialog> with WidgetsBindingObserver {
  bool _access = false;
  bool _overlay = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _recheck();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // returning from the system settings pages lands here
    if (state == AppLifecycleState.resumed) _recheck();
  }

  Future<void> _recheck() async {
    final a = await hasAccessibility();
    final o = await hasOverlay();
    if (!mounted) return;
    setState(() {
      _access = a;
      _overlay = o;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final th = s.theme;
    final lang = s.lang;
    Widget grantRow(String key, bool granted, VoidCallback open) => TextButton(
          onPressed: granted ? null : open,
          child: Text(t(lang, key),
              style: pixelStyle(lang, 10, col(granted ? th.onSurfaceDim : th.accent), text: t(lang, key))
                  .copyWith(decoration: granted ? TextDecoration.lineThrough : null,
                      decorationColor: col(th.onSurfaceDim))),
        );
    return AlertDialog(
      backgroundColor: col(th.panel),
      title: Text(t(lang, 'blockerPermTitle'),
          style: pixelStyle(lang, 12, col(th.onSurface), text: t(lang, 'blockerPermTitle'))),
      content: Text(t(lang, 'blockerPermBody'),
          style: pixelStyle(lang, 10, col(th.onSurfaceDim), text: t(lang, 'blockerPermBody'))),
      actions: [
        grantRow('grantAccess', _access, openAccessibilitySettings),
        grantRow('grantOverlay', _overlay, openOverlaySettings),
        TextButton(
            onPressed: () async {
              Navigator.pop(context);
              if (await hasAccessibility() && await hasOverlay()) s.setAppBlocker(true);
            },
            child: Text(t(lang, 'done'),
                style: pixelStyle(lang, 10, col(th.onSurface), text: t(lang, 'done')))),
      ],
    );
  }
}

Widget _stepperRow(PixelTheme th, String lang, String label, int value, int min, int max, int step,
    ValueChanged<int> onChange, {VoidCallback? onType}) {
  // No range caption here (#v34.6). #v34.5 put one under every stepper, but
  // the typing dialog already states the range at the point you need it, and
  // the extra line pushed the rows out of alignment with each other. Back to
  // one clean row; the dialog carries the hint.
  return Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      children: [
        Expanded(child: Text(label, style: pixelStyle(lang, 11, col(th.onSurfaceDim), text: label))),
        SizedBox(width: 52, child: secondaryBtn(th, lang, '-', () => onChange((value - step).clamp(min, max).toInt()), padding: const EdgeInsets.all(12))),
        // the number itself is the shortcut to typing one (#v34.5)
        GestureDetector(
          key: Key('stepperValue_$label'),
          behavior: HitTestBehavior.opaque,
          onTap: onType,
          child: Container(
            width: 56,
            alignment: Alignment.center,
            child: Text('$value', style: pixelStyle(lang, 14, col(th.onSurface), text: '$value')),
          ),
        ),
        SizedBox(width: 52, child: secondaryBtn(th, lang, '+', () => onChange((value + step).clamp(min, max).toInt()), padding: const EdgeInsets.all(12))),
      ],
    ),
  );
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
    // A LAZY list, not overlayScaffold's Column (#v34.6). This is the longest
    // page in the app — a few hundred rows, each holding a decoded icon — and
    // every one of them was built and laid out at once whether or not it was
    // on screen. RepaintBoundary (#v33.7) only ever fixed the painting half;
    // the build and layout cost stayed, which is the "it isn't scrolling, it
    // stops the moment I lift my finger". ListView.builder builds the handful
    // in the viewport.
    return Scaffold(
      backgroundColor: col(th.bg),
      body: SafeArea(
        child: FutureBuilder<List<AppInfo>>(
          future: _apps,
          builder: (context, snap) {
            if (!snap.hasData) {
              return Center(
                  child: Text('...', style: pixelStyle(lang, 14, col(th.onSurfaceDim), text: '...')));
            }
            // Selected apps float to the top (in order), a divider, then the
            // rest (#v23 fb). snap.data is already alpha-sorted.
            final picked = snap.data!.where((a) => s.blockedApps.contains(a.package)).toList();
            final rest = snap.data!.where((a) => !s.blockedApps.contains(a.package)).toList();
            final divider = picked.isNotEmpty && rest.isNotEmpty;
            // header rows + picked + optional divider + rest + close
            final lead = 2;
            final count = lead + picked.length + (divider ? 1 : 0) + rest.length + 1;

            return ListView.builder(
              padding: const EdgeInsets.all(28),
              itemCount: count,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Column(children: [
                    const SizedBox(height: 8),
                    Center(
                        child: Text(t(lang, 'blockedApps'),
                            style: pixelStyle(lang, 20, col(th.onSurface),
                                spacing: 2, text: t(lang, 'blockedApps')))),
                    const SizedBox(height: 24),
                  ]);
                }
                if (i == 1) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(t(lang, 'pickBlocked'),
                        style: pixelStyle(lang, 9, col(th.onSurfaceDim), text: t(lang, 'pickBlocked'))),
                  );
                }
                if (i == count - 1) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: secondaryBtn(th, lang, t(lang, 'close'), () => Navigator.pop(context),
                        padding: const EdgeInsets.all(16)),
                  );
                }
                var k = i - lead;
                if (k < picked.length) return _appRow(s, th, lang, picked[k]);
                k -= picked.length;
                if (divider) {
                  if (k == 0) {
                    return Container(
                        height: 3,
                        margin: const EdgeInsets.symmetric(vertical: 10),
                        color: col(th.onSurfaceDim));
                  }
                  k -= 1;
                }
                return _appRow(s, th, lang, rest[k]);
              },
            );
          },
        ),
      ),
    );
  }

  /// One app row. ListView already gives each item its own repaint boundary,
  /// so the explicit one #v33.7 added here is gone with the Column.
  Widget _appRow(AppStore s, PixelTheme th, String lang, AppInfo a) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          a.icon != null
              ? Image.memory(a.icon!, width: 32, height: 32, filterQuality: FilterQuality.none)
              : const SizedBox(width: 32, height: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Text(a.label,
                style: pixelStyle(lang, 10, col(th.onSurface), text: a.label),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
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
    final custom = s.customTheme;
    return overlayScaffold(context, s, t(lang, 'theme'), [
      for (final pt in Themes.all)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: pt.id == th.id
              ? primaryBtn(th, lang, '> ${pt.displayName}', () => s.selectTheme(pt))
              : secondaryBtn(th, lang, pt.displayName, () => s.selectTheme(pt)),
        ),
      // The whole custom section is behind Settings → DETAILED CUSTOMISATION
      // (#v32.4): the six presets are the intended path, this is the opt-in.
      if (s.detailedCustom) ...[
        // The user's own palette gets two controls once it exists: wear it, or go
        // change it. Before that, one button that opens the editor (#v32.3).
        if (custom != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: th.id == customThemeId
                ? primaryBtn(th, lang, '> ${t(lang, 'custom')}', () => s.selectTheme(custom))
                : secondaryBtn(th, lang, t(lang, 'custom'), () => s.selectTheme(custom)),
          ),
        secondaryBtn(th, lang, t(lang, custom == null ? 'custom' : 'customEdit'),
            () => openPanel(context, s, () => CustomThemeScreen(s))),
      ],
    ]);
  }
}

// ---- custom theme editor (#v32.3) ---------------------------------------------

/// A grey ramp plus the hue families in dark/mid/light. A small fixed palette
/// keeps the app looking hand-made and rules out the mud a free RGB picker
/// invites; every slot shares it, and [PixelTheme.custom] fixes whatever
/// combination is picked. 28 colours (#v33.4 gave the teal its missing dark and
/// light, so only the pink is still a single). The order written here no longer
/// matters — [kAllSwatches] sorts the whole palette by [swatchOrder].
const List<int> kSwatches = [
  0xFF0B0B0B, 0xFF2B2B2B, 0xFF565656, 0xFF8E8E8E, 0xFFCFCFCF, 0xFFF7F7F7,
  0xFF7A1F2B, 0xFFE5484D, 0xFFF7A8AC,
  0xFFE06AA5, // pink
  0xFF7A4212, 0xFFE8801E, 0xFFF5C48A,
  0xFF6E5A10, 0xFFE8C547, 0xFFF6E9A8,
  0xFF1E4D33, 0xFF46A03C, 0xFFA6E3A1,
  0xFF14504B, 0xFF1E9E92, 0xFF9BE0D8, // teal, a full trio since #v33.4
  0xFF1B3A63, 0xFF58A6FF, 0xFFBBD9FF,
  0xFF422A63, 0xFF9D7CD8, 0xFFD9C7F5,
];

/// Swatches per row in the custom editor — [kSwatches] is exactly two rows of
/// this, and the cell size is derived from the panel width so the grid ends
/// flush with the buttons above and below it (#v33).
const int kSwatchesPerRow = 13;

/// The six presets' own colours, so they can be PICKED from the palette, not
/// only reproduced by hand in the hex field (#v33.3 — "I can't see the main
/// theme colours below"). Every distinct pick across [Themes.all], in theme
/// order, minus anything already in [kSwatches] (a duplicate key would crash,
/// and it would be a wasted cell anyway). Comes out around three extra rows.
final List<int> kThemeSwatches = () {
  final base = kSwatches.toSet();
  final seen = <int>{};
  final out = <int>[];
  for (final theme in Themes.all) {
    for (final c in theme.picks) {
      if (base.contains(c) || !seen.add(c)) continue;
      out.add(c);
    }
  }
  return out;
}();

/// The whole custom palette — the hue ramp and the preset colours in ONE
/// ordering, similar next to similar (#v33.4). Appending the presets after the
/// ramp left the bottom rows scattered: a theme's blue landed between two
/// creams because they arrived in theme order, not colour order.
final List<int> kAllSwatches = [...kSwatches, ...kThemeSwatches]
  ..sort((a, b) => swatchOrder(a).compareTo(swatchOrder(b)));

class CustomThemeScreen extends StatefulWidget {
  final AppStore s;
  const CustomThemeScreen(this.s, {super.key});
  @override
  State<CustomThemeScreen> createState() => _CustomThemeScreenState();
}

class _CustomThemeScreenState extends State<CustomThemeScreen> {
  // picker order == PixelTheme.fromPicks' order == the saved spec order.
  // BREAK and INCOME reuse the strings the timer and the money screen already
  // label those colours with.
  // Each label names what the colour actually paints, not what it is called
  // internally — "TEXT 2" told nobody it was section headings and borders
  // (#v32.5). BREAK and INCOME get their own keys rather than reusing the
  // timer's and the money screen's, which have to stay short there.
  static const _slotKeys = ['cBg', 'cText1', 'cText2', 'cSelected', 'cSquares', 'cBreak', 'cIncome'];

  late List<int> picks;

  /// Which slot the bar and the swatches below the list point at (#v33.6): a
  /// small box selects, the long bar opens the wheel on whatever is selected.
  int _active = 0;

  @override
  void initState() {
    super.initState();
    final s = widget.s;
    // Start from the theme being WORN (#v33.4). Seeding from the saved picks
    // whatever was on screen is what made the editor look like it kept edits
    // nobody saved: save a custom theme, switch to MATCHA, reopen the editor
    // and it came back on the old custom instead of on MATCHA. The saved picks
    // are the right seed in exactly one case — when the custom theme is the one
    // being worn, since then they ARE the theme on screen (and they are the raw
    // picks, not the contrast-corrected result).
    picks = s.theme.id == customThemeId
        ? (customThemePicks(s.customSpec) ?? s.theme.picks)
        : s.theme.picks;
  }

  /// The long bar opens the wheel on the selected slot (#v33.6). The swatches
  /// below it are the quick path; this is the one that reaches every colour.
  void _openPicker(BuildContext context) => openPanel(
        context,
        widget.s,
        () => ColorPickerScreen(
          s: widget.s,
          slotLabel: t(widget.s.lang, _slotKeys[_active]),
          initial: picks[_active],
          themeOf: () => PixelTheme.fromPicks(picks),
          onPick: (c) => setState(() => picks[_active] = c),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final lang = s.lang;
    // The screen wears the pending theme, so the picker IS the preview — SAVE
    // and CLOSE below double as the selected/unselected square samples.
    final preview = PixelTheme.fromPicks(picks);
    return overlayScaffold(
      context,
      s,
      t(lang, 'custom'),
      [
        // the wallpaper covers the whole screen, so it OVERRIDES the background
        // colour — its controls come first, above the background swatches, not
        // buried under them (#v33)
        ..._wallpaperRow(preview, lang),
        // pick a preset as a STARTING POINT: it loads that theme's colours into
        // every slot below, then the user changes the few they want (#v33.1)
        ..._baseThemeRow(preview, lang),
        // #v33.6 — two ways to set the selected slot, in the order asked for:
        // tap a small box to select a slot, then either the LONG bar (opens the
        // wheel, reaches every colour) or the ready swatches under it. The
        // permanent hex field stayed retired — its job is inside the wheel panel.
        for (var slot = 0; slot < _slotKeys.length; slot++) _slotTile(preview, lang, slot),
        const SizedBox(height: 10),
        _activeBar(preview, lang, context),
        const SizedBox(height: 6),
        // say so, rather than leaving "any colour at all" hidden behind a tap
        Text(t(lang, 'pickHint'),
            style: pixelStyle(lang, 8, col(preview.onSurfaceDim), text: t(lang, 'pickHint'))),
        const SizedBox(height: 14),
        ..._swatchGrid(preview),
        const SizedBox(height: 18),
        primaryBtn(preview, lang, t(lang, 'save'), () {
          s.saveCustomTheme(picks);
          Navigator.pop(context);
        }),
      ],
      themeOverride: preview,
    );
  }

  /// Wallpaper controls (#v32.4). Hidden on web: `image_picker` returns a blob
  /// URL there and `Image.file` can't read it, same reason the live-wallpaper
  /// and app-blocker buttons are phone-only.
  List<Widget> _wallpaperRow(PixelTheme preview, String lang) {
    if (kIsWeb) return const [];
    final s = widget.s;
    final has = s.wallpaperPath != null;
    return [
      // ONE button (#v34.4). REMOVE WALLPAPER used to sit here as well as on
      // the panel this opens — two of the same control, and the one here was
      // the further of the two from the photo it deletes. Removing lives on
      // the edit panel now, next to what you are looking at.
      secondaryBtn(preview, lang, t(lang, has ? 'wallEdit' : 'wallChoose'), () async {
        // already have one → straight to the edit panel; the photo is the same
        final path = has ? s.wallpaperPath : await pickWallpaper();
        if (path == null || !context.mounted) return;
        if (!has) s.setWallpaper(path);
        await openPanel(context, s, () => WallpaperCropScreen(s, path));
        if (mounted) setState(() {});
      }, fontSize: 11),
      const SizedBox(height: 18),
    ];
  }

  /// The preset picker on ONE row (#v33.2): tap a preset to load its colours
  /// into every slot, then override the few you want. With the hex field below,
  /// its off-palette colours are all reproducible, so this really is a starting
  /// point for building — or rebuilding — a full theme.
  List<Widget> _baseThemeRow(PixelTheme preview, String lang) {
    final label = t(lang, 'baseTheme');
    return [
      Text(label, style: pixelStyle(lang, 9, col(preview.onSurfaceDim), text: label)),
      const SizedBox(height: 8),
      Row(
        children: [
          for (var i = 0; i < Themes.all.length; i++) ...[
            if (i != 0) const SizedBox(width: 4),
            Expanded(
              child: secondaryBtn(preview, lang, Themes.all[i].displayName,
                  () => setState(() => picks = List.of(Themes.all[i].picks)),
                  fontSize: 7, padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2)),
            ),
          ],
        ],
      ),
      const SizedBox(height: 18),
    ];
  }

  /// One slot row: name on the left, its current colour as a tappable box on
  /// the RIGHT. Tapping the row SELECTS that slot; the bar and the swatches
  /// below the list then point at it, and the selected row is outlined brightly
  /// so it is never a guess which one they are aimed at.
  Widget _slotTile(PixelTheme preview, String lang, int slot) {
    final label = t(lang, _slotKeys[slot]);
    final on = slot == _active;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _active = slot),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          decoration: BoxDecoration(
            color: on ? col(preview.panel) : null,
            border: Border.all(
                color: col(on ? preview.onSurface : preview.onSurfaceDim), width: on ? 2 : 1),
          ),
          child: Row(
            children: [
              Expanded(child: Text(label, style: pixelStyle(lang, 9, col(preview.onSurface), text: label))),
              const SizedBox(width: 10),
              Container(
                key: ValueKey('slotBox_$slot'),
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: col(picks[slot]),
                  border: Border.all(color: col(preview.onSurface), width: 2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The long bar under the list: the selected slot's colour with its code on
  /// it, and the way into the wheel (#v33.6). It is the one control that
  /// reaches a colour no swatch below has.
  Widget _activeBar(PixelTheme preview, String lang, BuildContext context) {
    final active = picks[_active];
    // text drawn ON the bar: black or white, whichever reads on that colour
    final onBar = isLightColor(active) ? 0xFF000000 : 0xFFFFFFFF;
    return GestureDetector(
      onTap: () => _openPicker(context),
      child: Container(
        key: const Key('activePreview'),
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: col(active),
          border: Border.all(color: col(preview.onSurface), width: 3),
        ),
        child: Text('#${hex6(active)}',
            style: pixelStyle(lang, 13, col(onBar), text: '#${hex6(active)}')),
      ),
    );
  }

  /// The quick picks: the hue ramp and the preset colours in one sorted grid
  /// (#v33.4). They set the selected slot outright — the wheel behind the bar
  /// above is for everything they don't carry.
  List<Widget> _swatchGrid(PixelTheme preview) => [
        LayoutBuilder(builder: (context, box) {
          const gap = 4.0;
          final cell = ((box.maxWidth - gap * (kSwatchesPerRow - 1)) / kSwatchesPerRow).floorToDouble();
          return Column(
            children: [
              for (var i = 0; i < kAllSwatches.length; i += kSwatchesPerRow)
                Padding(
                  padding: EdgeInsets.only(bottom: i + kSwatchesPerRow < kAllSwatches.length ? gap : 0),
                  child: Row(
                    // full rows spread edge-to-edge; a short final row packs left
                    // so its cells stay swatch-sized instead of stretching apart
                    mainAxisAlignment: kAllSwatches.length - i >= kSwatchesPerRow
                        ? MainAxisAlignment.spaceBetween
                        : MainAxisAlignment.start,
                    children: [
                      for (final c in kAllSwatches.skip(i).take(kSwatchesPerRow)) ...[
                        GestureDetector(
                          key: ValueKey('swatch_$c'),
                          onTap: () => setState(() => picks[_active] = c),
                          child: Container(
                            width: cell,
                            height: cell,
                            decoration: BoxDecoration(
                              color: col(c),
                              border: Border.all(
                                color: col(picks[_active] == c ? preview.onSurface : preview.onSurfaceDim),
                                width: picks[_active] == c ? 3 : 1,
                              ),
                            ),
                          ),
                        ),
                        // the left-packed final row needs its own gaps
                        // (spaceBetween supplies them for full rows)
                        if (kAllSwatches.length - i < kSwatchesPerRow) const SizedBox(width: gap),
                      ],
                    ],
                  ),
                ),
            ],
          );
        }),
      ];
}

// ---- the colour wheel panel (#v33.5) -------------------------------------------

/// `RRGGBB` of an opaque colour, and back — null until six hex digits are typed,
/// so a half-typed code doesn't flash a wrong colour.
String hex6(int argb) => (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

int? parseHex6(String s) {
  final h = s.replaceAll(RegExp('[^0-9a-fA-F]'), '');
  return h.length == 6 ? 0xFF000000 | int.parse(h, radix: 16) : null;
}

/// Any colour at all, for one slot of the custom theme — opened by tapping the
/// long colour bar in the editor.
///
/// A wheel (hue around, saturation toward the centre) over a lightness bar
/// reaches every colour there is, and the hex field takes a code outright. The
/// ready swatches stayed on the editor screen (#v33.6): they are the quick path,
/// this panel is the one for a colour they don't carry.
class ColorPickerScreen extends StatefulWidget {
  final AppStore s;
  final String slotLabel;
  final int initial;

  /// The editor's pending theme, read on every build — so picking the
  /// background repaints this panel in it too, live.
  final PixelTheme Function() themeOf;
  final ValueChanged<int> onPick;

  const ColorPickerScreen({
    super.key,
    required this.s,
    required this.slotLabel,
    required this.initial,
    required this.themeOf,
    required this.onPick,
  });

  @override
  State<ColorPickerScreen> createState() => _ColorPickerScreenState();
}

class _ColorPickerScreenState extends State<ColorPickerScreen> {
  late int color;

  /// Held alongside the colour, not derived from it on every frame: grey and
  /// black have no hue to read back, so dragging the wheel through the middle
  /// or the bar down to black would otherwise snap the hue home to red.
  late double _h, _s, _l;
  final _hex = TextEditingController();

  @override
  void initState() {
    super.initState();
    color = widget.initial;
    final hsl = hslOf(color);
    _h = hsl[0];
    _s = hsl[1];
    _l = hsl[2];
    _hex.text = hex6(color);
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  /// A colour chosen AS a colour (swatch, hex code): its HSL comes back out of
  /// it so the wheel and bar jump to where it sits.
  void _setColor(int c, {bool typing = false}) {
    final hsl = hslOf(c);
    setState(() {
      color = c;
      _h = hsl[0];
      _s = hsl[1];
      _l = hsl[2];
      if (!typing) _hex.text = hex6(c); // rewriting mid-type fights the caret
    });
    widget.onPick(c);
  }

  /// A colour chosen on the wheel or the bar: there HSL is the source and the
  /// colour is what falls out.
  void _setHsl({double? h, double? s, double? l}) {
    _h = h ?? _h;
    _s = s ?? _s;
    _l = l ?? _l;
    final c = colorFromHsl(_h, _s, _l);
    setState(() {
      color = c;
      _hex.text = hex6(c);
    });
    widget.onPick(c);
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.s.lang;
    final th = widget.themeOf();
    // drawn ON the picked colour: black or white, whichever reads on it
    final onColor = isLightColor(color) ? 0xFF000000 : 0xFFFFFFFF;
    return overlayScaffold(
      context,
      widget.s,
      t(lang, 'pickColor'),
      [
        Text(widget.slotLabel,
            style: pixelStyle(lang, 9, col(th.onSurfaceDim), text: widget.slotLabel)),
        const SizedBox(height: 8),
        Container(
          key: const Key('pickerPreview'),
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: col(color),
            border: Border.all(color: col(th.onSurface), width: 2),
          ),
          child: Text('#${hex6(color)}',
              style: pixelStyle(lang, 13, col(onColor), text: '#${hex6(color)}')),
        ),
        const SizedBox(height: 18),
        _ColorWheel(
          h: _h, s: _s, l: _l,
          border: th.onSurface, marker: onColor,
          onPick: (h, s) => _setHsl(h: h, s: s),
        ),
        const SizedBox(height: 12),
        _LightnessBar(
          h: _h, s: _s, l: _l,
          border: th.onSurface, marker: onColor,
          onPick: (l) => _setHsl(l: l),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Text('#', style: pixelStyle(lang, 12, col(th.onSurfaceDim), text: '#')),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                key: const Key('hexField'),
                controller: _hex,
                maxLength: 6,
                autocorrect: false,
                enableSuggestions: false,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]'))],
                style: pixelStyle(lang, 12, col(th.onSurface)),
                cursorColor: col(th.onSurface),
                decoration: InputDecoration(
                  counterText: '',
                  isDense: true,
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: col(th.onSurfaceDim))),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: col(th.onSurface), width: 2)),
                ),
                onChanged: (v) {
                  final c = parseHex6(v);
                  if (c != null) _setColor(c, typing: true);
                },
              ),
            ),
          ],
        ),
      ],
      themeOverride: th,
    );
  }
}

/// The round picker: hue around the rim, saturation toward the centre, drawn at
/// whatever lightness the bar below is set to.
class _ColorWheel extends StatelessWidget {
  final double h, s, l;
  final int border, marker;
  final void Function(double h, double s) onPick;

  const _ColorWheel({
    required this.h, required this.s, required this.l,
    required this.border, required this.marker, required this.onPick,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final size = math.min(box.maxWidth, 240.0);
        void pick(Offset p) {
          final r = size / 2;
          final hs = wheelHueSat(p.dx - r, p.dy - r, r);
          onPick(hs[0], hs[1]);
        }

        return Center(
          child: GestureDetector(
            key: const Key('colorWheel'),
            onTapDown: (d) => pick(d.localPosition),
            onPanStart: (d) => pick(d.localPosition),
            onPanUpdate: (d) => pick(d.localPosition),
            child: CustomPaint(
              size: Size.square(size),
              painter: _WheelPainter(h, s, l, border, marker),
            ),
          ),
        );
      });
}

class _WheelPainter extends CustomPainter {
  final double h, s, l;
  final int border, marker;
  const _WheelPainter(this.h, this.s, this.l, this.border, this.marker);

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final centre = Offset(r, r);
    final rect = Rect.fromCircle(center: centre, radius: r);
    // hue all the way round, at the lightness the bar is set to
    canvas.drawCircle(
        centre,
        r,
        Paint()
          ..shader = SweepGradient(
            colors: [for (var i = 0; i <= 12; i++) col(colorFromHsl(i * 30.0, 1, l))],
          ).createShader(rect));
    // saturation falls off toward the middle — into the grey of that same
    // lightness, so the centre of the wheel and the middle of the bar agree
    final grey = col(colorFromHsl(0, 0, l));
    canvas.drawCircle(
        centre,
        r,
        Paint()
          ..shader = RadialGradient(colors: [grey, grey.withValues(alpha: 0)]).createShader(rect));
    canvas.drawCircle(centre, r,
        Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = col(border));
    // the current pick, as a square marker — a round one would read iOS, not 8-bit
    final a = h * math.pi / 180;
    final p = centre + Offset(math.cos(a), math.sin(a)) * (s * r);
    canvas.drawRect(Rect.fromCenter(center: p, width: 12, height: 12),
        Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = col(marker));
  }

  @override
  bool shouldRepaint(_WheelPainter old) =>
      old.h != h || old.s != s || old.l != l || old.border != border || old.marker != marker;
}

/// Black → the colour → white. The wheel can't reach either end on its own.
class _LightnessBar extends StatelessWidget {
  final double h, s, l;
  final int border, marker;
  final ValueChanged<double> onPick;

  const _LightnessBar({
    required this.h, required this.s, required this.l,
    required this.border, required this.marker, required this.onPick,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth;
        void pick(Offset p) => onPick((p.dx / w).clamp(0.0, 1.0));
        return GestureDetector(
          key: const Key('lightnessBar'),
          onTapDown: (d) => pick(d.localPosition),
          onPanStart: (d) => pick(d.localPosition),
          onPanUpdate: (d) => pick(d.localPosition),
          child: CustomPaint(size: Size(w, 34), painter: _LightnessPainter(h, s, l, border, marker)),
        );
      });
}

class _LightnessPainter extends CustomPainter {
  final double h, s, l;
  final int border, marker;
  const _LightnessPainter(this.h, this.s, this.l, this.border, this.marker);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(colors: [
            col(colorFromHsl(h, s, 0)),
            col(colorFromHsl(h, s, 0.5)),
            col(colorFromHsl(h, s, 1)),
          ]).createShader(rect));
    canvas.drawRect(
        rect, Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = col(border));
    final x = (l * size.width).clamp(3.0, size.width - 3);
    canvas.drawRect(Rect.fromCenter(center: Offset(x, size.height / 2), width: 8, height: size.height),
        Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = col(marker));
  }

  @override
  bool shouldRepaint(_LightnessPainter old) =>
      old.h != h || old.s != s || old.l != l || old.border != border || old.marker != marker;
}

// ---- home wallpaper (#v32.4) --------------------------------------------------

/// The wallpaper as it fills whatever box it is given.
///
/// `BoxFit.cover` plus a normalised [Alignment] is exactly "which part of an
/// overflowing photo shows", and neither it nor [zoom] depends on the box's
/// pixel size — so the crop panel's preview and the real home screen agree
/// without ever writing a cropped file.
Widget wallpaperFill(String path, double zoom, double dx, double dy) {
  // One alignment drives both: `cover` uses it to pick which part of an
  // overflowing photo shows, and the scale anchors on the same point so zooming
  // in keeps it framed instead of always pulling back to the centre — that is
  // what makes the edges reachable at zoom > 1.
  final at = Alignment(dx, dy);
  return ClipRect(
    child: Transform.scale(
      scale: zoom,
      alignment: at,
      child: Image.file(File(path), fit: BoxFit.cover, alignment: at),
    ),
  );
}

/// Where to go when HOME SCREEN > WALLPAPER is tapped with no photo saved
/// (#v34). The wallpaper picker lives inside the custom theme editor, which is
/// itself behind a Settings switch — two hops nobody would guess, so this
/// screen just says them.
class WallpaperHowToScreen extends StatelessWidget {
  final AppStore s;
  const WallpaperHowToScreen(this.s, {super.key});

  @override
  Widget build(BuildContext context) {
    final lang = s.lang;
    final th = s.theme;
    Widget step(String key) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(t(lang, key), style: pixelStyle(lang, 11, col(th.onSurface), text: t(lang, key))),
        );
    return overlayScaffold(context, s, t(lang, 'wallHowTitle'), [
      Text(t(lang, 'wallHowBody'),
          style: pixelStyle(lang, 10, col(th.onSurfaceDim), text: t(lang, 'wallHowBody'))),
      const SizedBox(height: 20),
      step('wallHow1'),
      step('wallHow2'),
      step('wallHow3'),
    ]);
  }
}

/// Frame the photo the way the phone's own wallpaper cropper does: drag to
/// choose which part shows, pinch to zoom in (#v32.4).
class WallpaperCropScreen extends StatefulWidget {
  final AppStore s;
  final String path;
  const WallpaperCropScreen(this.s, this.path, {super.key});
  @override
  State<WallpaperCropScreen> createState() => _WallpaperCropScreenState();
}

class _WallpaperCropScreenState extends State<WallpaperCropScreen> {
  late double zoom = widget.s.wallZoom;
  late double dx = widget.s.wallDx;
  late double dy = widget.s.wallDy;
  // `ScaleUpdateDetails.scale` is cumulative since the fingers went down, so
  // zoom is measured against where it started; `focalPointDelta` is per-frame,
  // so panning accumulates instead.
  late double _zoom0 = zoom;

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final lang = s.lang;
    final th = s.theme;
    // the preview frame mirrors the phone's own shape, so what the user frames
    // here is what the home screen shows
    final screen = MediaQuery.of(context).size;
    return overlayScaffold(context, s, t(lang, 'wallCrop'), [
      Text(t(lang, 'wallHint'),
          style: pixelStyle(lang, 9, col(th.onSurfaceDim), text: t(lang, 'wallHint'))),
      const SizedBox(height: 12),
      LayoutBuilder(builder: (_, box) {
        final w = box.maxWidth;
        final h = w * screen.height / screen.width;
        return GestureDetector(
          key: const Key('wallpaperCrop'),
          onScaleStart: (_) => _zoom0 = zoom,
          onScaleUpdate: (d) => setState(() {
            zoom = (_zoom0 * d.scale).clamp(1.0, 3.0);
            // Alignment spans -1..1 across the frame, so dividing the drag by
            // half the frame moves the photo at roughly finger speed. Dragging
            // right reveals what is off to the left, hence the minus.
            dx = (dx - d.focalPointDelta.dx / (w / 2)).clamp(-1.0, 1.0);
            dy = (dy - d.focalPointDelta.dy / (h / 2)).clamp(-1.0, 1.0);
          }),
          child: Container(
            width: w,
            height: h,
            decoration: BoxDecoration(border: Border.all(color: col(th.onSurfaceDim), width: 2)),
            child: wallpaperFill(widget.path, zoom, dx, dy),
          ),
        );
      }),
      const SizedBox(height: 16),
      primaryBtn(th, lang, t(lang, 'save'), () {
        s.setWallpaperCrop(zoom, dx, dy);
        Navigator.pop(context);
      }),
      const SizedBox(height: 10),
      // drop the photo from here too (#v34) — this is the screen the user is
      // already on when they decide they don't want to keep it, and the copy
      // the app made is the only one deleted; their own photo is untouched.
      secondaryBtn(th, lang, t(lang, 'wallRemove'), () {
        s.removeWallpaper();
        Navigator.pop(context);
      }, fontSize: 11, key: const Key('wallpaperRemove')),
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
          Swatch(color: s.labelColorOf(label), border: th.onSurfaceDim, size: 24, plain: true, onTap: () => _pickColor(context, s, label)),
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
              // square, like every other swatch in the app (#v34.6)
              Swatch(color: c, border: th.onSurfaceDim, size: 40, plain: true, onTap: () {
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
    // totals follow the ◀▶ navigator like everything else on this screen —
    // they used to stay pinned to the real now, so after paging back the
    // TODAY/WEEK/MONTH/YEAR rows read one period AHEAD of the chart and
    // BY LABEL below them (#v32.1).
    final statAnchor = StatsAggregator.anchorFor(now, s.statPeriod, s.statOffset);
    final totals = StatsAggregator.aggregate(s.records, statAnchor);
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
          Expanded(child: Center(child: Text(periodWindowLabel(lang, s.statPeriod, s.statOffset),
              style: pixelStyle(lang, 11, col(th.onSurface), text: periodWindowLabel(lang, s.statPeriod, s.statOffset))))),
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
        // name WHICH average this is — periodStats buckets by the selected
        // period's unit (ALL TIME buckets by year), and a bare "AVERAGE"
        // left that unit invisible (#v32.1)
        statRow(
            t(lang, switch (s.statPeriod) {
              StatPeriod.daily => 'avgDaily',
              StatPeriod.weekly => 'avgWeekly',
              StatPeriod.monthly => 'avgMonthly',
              StatPeriod.yearly || StatPeriod.allTime => 'avgYearly',
            }),
            stats.$2),
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
                Swatch(color: s.labelColorOf(e.key), border: th.onSurfaceDim, size: 16, plain: true),
                const SizedBox(width: 10),
                Text(e.key, style: pixelStyle(lang, 11, col(th.onSurface), text: e.key)),
                const Spacer(),
                Text(StatsAggregator.formatMinutes(e.value), style: pixelStyle(lang, 11, col(th.onSurfaceDim), text: StatsAggregator.formatMinutes(e.value))),
              ],
            ),
          ),
      // the session timeline, relocated out of the habit tracker (#v30 item 6),
      // follows the ◀▶ history navigator above (#v31.2 item 3) and stays
      // right here on Stats (#v31.5) — Focus Sessions moved into its own
      // screen below, merged with Session Heatmap as SESSIONS IN PIXELS.
      // SIMPLE stats mode (#v32) hides both; only DETAILED shows them.
      if (s.statsDetailed) ...[
        const SizedBox(height: 20),
        SessionsTimelineWeek(
            th: th, lang: lang, s: s, today: epochDayOf(now),
            anchor: epochDayOf(StatsAggregator.anchorFor(now, s.statPeriod, s.statOffset))),
        // opens its own screen, like LOG HISTORY: the all-history contiguous
        // strip PLUS the per-label Focus Sessions heatmaps, one screen (#v31.5)
        const SizedBox(height: 20),
        secondaryBtn(th, lang, t(lang, 'sessionsInPixels'),
            () => openPanel(context, s, () => SessionsInPixelsScreen(s)),
            padding: const EdgeInsets.all(14)),
      ],
      // a paginated list of every past session (tap a row to relabel) — sits
      // right above the auto-appended CLOSE button (#v25 item3)
      const SizedBox(height: 12),
      secondaryBtn(th, lang, t(lang, 'logHistory'),
          () => openPanel(context, s, () => LogHistoryScreen(s)),
          padding: const EdgeInsets.all(14)),
    ]);
  }

}

/// Label for a period window [offset] periods back from now, matching the
/// period's granularity — shared by the Stats history navigator and the money
/// chart's ◀▶ navigator (#v30.9 rec 4).
String periodWindowLabel(String lang, StatPeriod p, int offset) {
  final now = DateTime.now();
  final a = StatsAggregator.anchorFor(now, p, offset);
  switch (p) {
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

// ---- log history ------------------------------------------------------------

/// Shared date | time | label | duration row layout for Log History and the
/// Recycle Bin (#v31.16) — [onTap] differs per screen (change label vs.
/// permanently delete).
Widget _historyRow(AppStore s, PixelTheme th, String lang, SessionRecord r, VoidCallback onTap) {
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
      onTap: onTap,
      child: Row(children: [
        Swatch(color: s.labelColorOf(r.label), border: th.onSurfaceDim, size: 18, plain: true),
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

/// A paginated list of every past focus session (newest first, 50 a page).
/// Tap a row to reassign that session's label or remove it to the Recycle
/// Bin (#v25 item3, #v31.16).
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
      secondaryBtn(th, lang, t(lang, 'recycleBin'), () => openPanel(context, s, () => RecycleBinScreen(s)),
          key: const Key('recycleBinButton'), fontSize: 10, padding: const EdgeInsets.all(10)),
      const SizedBox(height: 16),
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

  Widget _logRow(BuildContext context, AppStore s, PixelTheme th, String lang, int index, SessionRecord r) =>
      _historyRow(s, th, lang, r, () => _changeLabel(context, s, index, r));

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
                // plain: square, borderless — matches the Log History rows
                // this dialog opens from (#v34.1; the rows went plain in #v31.16
                // and this swatch was left rounded).
                Swatch(color: s.labelColorOf(label), border: th.onSurfaceDim, size: 14, plain: true),
                const SizedBox(width: 10),
                Text(label,
                    style: pixelStyle(lang, 10,
                        col(label.toUpperCase() == r.label.toUpperCase() ? th.accent : th.onSurface),
                        text: label)),
              ]),
            ),
          const Divider(height: 20),
          // soft-delete: moves to the Recycle Bin, stops counting in stats
          // immediately, but stays recoverable-by-not-purging (#v31.16)
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              _confirmRemoveLog(context, s, index, r);
            },
            child: Text(t(lang, 'removeLog'),
                style: pixelStyle(lang, 10, col(th.accent), text: t(lang, 'removeLog'))),
          ),
        ],
      ),
    );
  }

  void _confirmRemoveLog(BuildContext context, AppStore s, int index, SessionRecord r) {
    final th = s.theme;
    final lang = s.lang;
    final desc = '${r.label} · ${StatsAggregator.formatMinutes(r.minutes)}';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: col(th.panel),
        title: Text(t(lang, 'removeLogTitle'), style: pixelStyle(lang, 12, col(th.onSurface), text: t(lang, 'removeLogTitle'))),
        content: Text(tf(lang, 'removeLogMsg', [desc]),
            style: pixelStyle(lang, 10, col(th.onSurfaceDim), text: tf(lang, 'removeLogMsg', [desc]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: Text(t(lang, 'no'), style: pixelStyle(lang, 11, col(th.onSurfaceDim), text: t(lang, 'no')))),
          TextButton(
              onPressed: () {
                s.removeRecord(index);
                Navigator.pop(ctx);
                setState(() {});
              },
              child: Text(t(lang, 'yes'), style: pixelStyle(lang, 11, col(th.accent), text: t(lang, 'yes')))),
        ],
      ),
    );
  }
}

// ---- recycle bin --------------------------------------------------------------

/// Soft-deleted logs from Log History (#v31.16) — excluded from stats while
/// here (they're simply not in [AppStore.records] anymore). Permanent delete
/// per entry (tap → confirm, same pattern as Log History's remove) or all at
/// once via CLEAN RECYCLE BIN.
class RecycleBinScreen extends StatefulWidget {
  final AppStore s;
  const RecycleBinScreen(this.s, {super.key});
  @override
  State<RecycleBinScreen> createState() => _RecycleBinScreenState();
}

class _RecycleBinScreenState extends State<RecycleBinScreen> {
  static const _perPage = 50;
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final th = s.theme;
    final lang = s.lang;
    final ordered = [for (var i = 0; i < s.deletedRecords.length; i++) (i, s.deletedRecords[i])]
      ..sort((a, b) {
        final byDay = b.$2.epochDay.compareTo(a.$2.epochDay);
        return byDay != 0 ? byDay : (b.$2.minuteOfDay ?? 0).compareTo(a.$2.minuteOfDay ?? 0);
      });
    final pages = Paging.pageCount(ordered.length, _perPage);
    if (_page >= pages) _page = pages - 1;
    final shown = Paging.page(ordered, _page, _perPage);

    return overlayScaffold(context, s, t(lang, 'recycleBin'), [
      if (ordered.isNotEmpty) ...[
        secondaryBtn(th, lang, t(lang, 'cleanRecycleBin'), () => _confirmClean(context, s),
            key: const Key('cleanRecycleBinButton'), fontSize: 10, padding: const EdgeInsets.all(10)),
        const SizedBox(height: 16),
      ],
      if (ordered.isEmpty)
        Text(t(lang, 'noRecycled'), style: pixelStyle(lang, 10, col(th.onSurfaceDim), text: t(lang, 'noRecycled')))
      else ...[
        for (final (idx, r) in shown)
          _historyRow(s, th, lang, r, () => _rowActions(context, s, idx, r)),
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

  /// Tapping a Recycle Bin row offers RESTORE (immediate, reversible — no
  /// confirm needed) or DELETE FOREVER (routes to the existing confirm
  /// dialog, unchanged) (#v31.17).
  void _rowActions(BuildContext context, AppStore s, int index, SessionRecord r) {
    final th = s.theme;
    final lang = s.lang;
    final desc = '${r.label} · ${StatsAggregator.formatMinutes(r.minutes)}';
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: col(th.panel),
        title: Text(desc, style: pixelStyle(lang, 11, col(th.onSurface), text: desc)),
        children: [
          SimpleDialogOption(
            onPressed: () {
              s.restoreRecord(index);
              Navigator.pop(ctx);
              setState(() {});
            },
            child: Text(t(lang, 'restoreLog'),
                style: pixelStyle(lang, 10, col(th.onSurface), text: t(lang, 'restoreLog'))),
          ),
          const Divider(height: 20),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              _confirmPurge(context, s, index, r);
            },
            child: Text(t(lang, 'deleteForever'),
                style: pixelStyle(lang, 10, col(th.accent), text: t(lang, 'deleteForever'))),
          ),
        ],
      ),
    );
  }

  void _confirmPurge(BuildContext context, AppStore s, int index, SessionRecord r) {
    final th = s.theme;
    final lang = s.lang;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: col(th.panel),
        title: Text(t(lang, 'permanentDeleteTitle'), style: pixelStyle(lang, 12, col(th.onSurface), text: t(lang, 'permanentDeleteTitle'))),
        content: Text(t(lang, 'permanentDeleteMsg'), style: pixelStyle(lang, 10, col(th.onSurfaceDim), text: t(lang, 'permanentDeleteMsg'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: Text(t(lang, 'no'), style: pixelStyle(lang, 11, col(th.onSurfaceDim), text: t(lang, 'no')))),
          TextButton(
              onPressed: () {
                s.purgeRecord(index);
                Navigator.pop(ctx);
                setState(() {});
              },
              child: Text(t(lang, 'yes'), style: pixelStyle(lang, 11, col(th.accent), text: t(lang, 'yes')))),
        ],
      ),
    );
  }

  void _confirmClean(BuildContext context, AppStore s) {
    final th = s.theme;
    final lang = s.lang;
    final count = s.deletedRecords.length;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: col(th.panel),
        title: Text(t(lang, 'cleanRecycleBinTitle'), style: pixelStyle(lang, 12, col(th.onSurface), text: t(lang, 'cleanRecycleBinTitle'))),
        content: Text(tf(lang, 'cleanRecycleBinMsg', [count]),
            style: pixelStyle(lang, 10, col(th.onSurfaceDim), text: tf(lang, 'cleanRecycleBinMsg', [count]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: Text(t(lang, 'no'), style: pixelStyle(lang, 11, col(th.onSurfaceDim), text: t(lang, 'no')))),
          TextButton(
              onPressed: () {
                s.cleanRecycleBin();
                Navigator.pop(ctx);
                setState(() {});
              },
              child: Text(t(lang, 'yes'), style: pixelStyle(lang, 11, col(th.accent), text: t(lang, 'yes')))),
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
    final info = _ownedInfo(s, lang, f.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          objectThumb('flower_${f.id}', 40),
          const SizedBox(width: 12),
          // 2:3 against the buttons (#v33.4): on a wide enough row the buttons
          // still come out at their natural size, and on a narrow one they
          // scale down instead of shoving the name column to nothing — which
          // is how "SPRZEDAJ 5" pushed a Polish shop row past a 320px screen.
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f.nameIn(lang), style: pixelStyle(lang, 12, col(th.onSurface), text: f.nameIn(lang))),
                const SizedBox(height: 6),
                _infoLine(th, lang, info),
              ],
            ),
          ),
          Flexible(flex: 3, child: _buySell(s, th, lang, f.id, Economy.flowerCost, () => s.buyFlower(f))),
        ],
      ),
    );
  }

  /// "OWNED n   PLACED m" on ONE line, always (#v33.4). The counters sit in the
  /// narrow column left of BUY/SELL, and in the longer languages (SAHİP/BAHÇEDE,
  /// W OGRODZIE) PLACED used to wrap under OWNED on a small screen. Scaling the
  /// line down keeps both readable at any width; wrapping is what was rejected.
  Widget _infoLine(PixelTheme th, String lang, String info) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(info,
            maxLines: 1,
            softWrap: false,
            style: pixelStyle(lang, 8, col(th.onSurfaceDim), text: info)),
      );

  // "OWNED n   PLACED m" — m = units currently in the garden (can't be sold).
  String _ownedInfo(AppStore s, String lang, String id) =>
      '${tf(lang, 'owned', [s.owned[id] ?? 0])}   ${tf(lang, 'placed', [s.garden.countPlanted(id)])}';

  // BUY (accent) LEFT, SELL (panel) RIGHT — side by side, not stacked (#v33.1).
  // SELL dims + no-ops unless at least one un-placed unit exists
  // (availableOf > 0) — placed units are never sold.
  Widget _buySell(AppStore s, PixelTheme th, String lang, String id, int cost, VoidCallback onBuy) {
    return Row(
      // Fill the flex slot and push the pair to its RIGHT edge (#v34.1). With
      // MainAxisSize.min the row shrink-wrapped and sat at the START of the
      // slot, so every row's buttons stopped wherever their own price text
      // happened to end — BUY 10 / BUY 5, SELL 5 / SELL 2 — and the column
      // looked shifted. Anchored right, every row's right edge lines up with
      // the screen's.
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // Flexible so a squeezed row shrinks the two boxes evenly and their
        // labels scale inside (PixelButton scales down, never wraps) — before
        // this the pair kept its natural width and overflowed (#v33.4).
        Flexible(
          child: PixelButton(
            text: '${t(lang, 'buy')} $cost',
            fill: th.accent, border: th.onSurface, textColor: th.onAccent, shadow: th.shadow,
            lang: lang, fontSize: 10, padding: const EdgeInsets.all(10),
            opacity: s.coins >= cost ? 1 : 0.45,
            onTap: onBuy,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: PixelButton(
            text: '${t(lang, 'sell')} ${Economy.sellPrice(id)}',
            fill: th.panel, border: th.onSurface, textColor: th.onSurface, shadow: th.shadow,
            lang: lang, fontSize: 10, padding: const EdgeInsets.all(10),
            opacity: s.availableOf(id) > 0 ? 1 : 0.45,
            onTap: () => s.sellItem(id),
          ),
        ),
      ],
    );
  }

  Widget _objectRow(AppStore s, PixelTheme th, String lang, String id) {
    final info = _ownedInfo(s, lang, id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          objectThumb(id, 40),
          const SizedBox(width: 12),
          // 2:3 against the buttons (#v33.4): on a wide enough row the buttons
          // still come out at their natural size, and on a narrow one they
          // scale down instead of shoving the name column to nothing — which
          // is how "SPRZEDAJ 5" pushed a Polish shop row past a 320px screen.
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t(lang, id), style: pixelStyle(lang, 12, col(th.onSurface), text: t(lang, id))),
                const SizedBox(height: 6),
                _infoLine(th, lang, info),
              ],
            ),
          ),
          Flexible(flex: 3, child: _buySell(s, th, lang, id, Economy.objectCost, () => s.buyItem(id))),
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
          if (!kIsWeb && Platform.isAndroid)
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
// by the Mood tab and Year in Pixels. Tapping a past day opens the 5-face
// picker for THAT day, so mood history is editable (#v30.9).
Widget _moodHeatmap(BuildContext context, AppStore s, PixelTheme th, String lang, int today) => _HabitHeatmap(
      days: const {},
      color: th.onSurfaceDim,
      today: today,
      maxCellSize: double.infinity,
      colorForDay: (d) {
        final m = s.moods[d];
        return m == null ? null : _moodColors[m - 1];
      },
      onDayTap: (day) => _pickMoodFor(context, s, th, lang, day),
    );

void _pickMoodFor(BuildContext context, AppStore s, PixelTheme th, String lang, int day) {
  final d = dateOfEpochDay(day);
  final title = '${d.day} ${monthName(lang, d.month)} ${d.year}';
  showDialog(
    context: context,
    builder: (ctx) => SimpleDialog(
      backgroundColor: col(th.panel),
      title: Text(title, style: pixelStyle(lang, 11, col(th.onSurface), text: title)),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var m = 1; m <= 5; m++)
                GestureDetector(
                  onTap: () {
                    s.setMoodOn(day, m);
                    Navigator.pop(ctx);
                  },
                  child: Opacity(
                    opacity: s.moods[day] == null || s.moods[day] == m ? 1 : 0.35,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        border: Border.all(color: col(s.moods[day] == m ? th.onSurface : th.panel), width: 2),
                      ),
                      child: Image.asset('assets/objects/face_$m.png',
                          width: 36, height: 36, filterQuality: FilterQuality.none),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

// "Session Timeline in a Week" — individual completed sessions (not
// day-aggregated) as small colour-by-label boxes in chronological order,
// oldest to newest left-to-right, grouped by day with a bordered rectangle
// per day. Fixed trailing 7 days (today and the 6 before it). Sits above
// Focus Sessions in both Stats and Year in Pixels (#v30 follow-up).
class SessionsTimelineWeek extends StatefulWidget {
  final PixelTheme th;
  final String lang;
  final AppStore s;
  final int today;
  // which calendar week to show — follows the Stats ◀▶ navigator (#v31.2
  // item 3); defaults to the week containing today.
  final int? anchor;
  const SessionsTimelineWeek(
      {super.key, required this.th, required this.lang, required this.s, required this.today,
      this.anchor});
  @override
  State<SessionsTimelineWeek> createState() => _SessionsTimelineWeekState();
}

class _SessionsTimelineWeekState extends State<SessionsTimelineWeek> {
  (int, int)? _sel; // (epochDay, index within that day's sorted sessions)

  @override
  Widget build(BuildContext context) {
    final th = widget.th, lang = widget.lang, s = widget.s, today = widget.today;
    final a = widget.anchor ?? today;
    // the calendar week (Mon..Sun) containing the anchor day
    final monday = a - (dateOfEpochDay(a).weekday - 1);
    final byDay = _sessionsByDay(s.records, monday, monday + 6);
    // hide only for a brand-new user; a NAVIGATED week with no sessions still
    // shows its 7 empty day frames, so the ◀▶ browsing reads as working (#v31.2)
    if (s.records.isEmpty) return const SizedBox.shrink();

    SessionRecord? selRec;
    if (_sel != null) {
      final list = byDay[_sel!.$1];
      if (list != null && _sel!.$2 < list.length) selRec = list[_sel!.$2];
    }

    final weekdayShorts = t(lang, 'weekdayShort').split(',');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t(lang, 'sessionsTimelineWeek'),
            style: pixelStyle(lang, 11, col(th.onSurfaceDim), text: t(lang, 'sessionsTimelineWeek'))),
        const SizedBox(height: 10),
        LayoutBuilder(builder: (context, box) {
          // session squares use the SAME cell formula as the label heatmaps
          // above/below, so both read at one scale (#v31 item 7)
          final cell = ((box.maxWidth - 18 * 2) / 18).clamp(4.0, double.infinity);

          Widget dayGroup(int day) => _sessionDayGroup(
                th: th, lang: lang, s: s, cell: cell,
                sessions: byDay[day] ?? const <SessionRecord>[],
                weekdayLabel: weekdayShorts[(dateOfEpochDay(day).weekday - 1) % 7],
                isSelected: (i) => _sel == (day, i),
                onTapSession: (i) => setState(() => _sel = _sel == (day, i) ? null : (day, i)),
              );

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            // spread the 7 day groups evenly across the full width instead of
            // packing them left with a dead gap on the right; overflow (a very
            // busy day) still scrolls (#v31 item 3)
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: box.maxWidth),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var d = monday; d <= monday + 6; d++)
                    Padding(
                      padding: EdgeInsets.only(right: d == monday + 6 ? 0 : 6),
                      child: dayGroup(d),
                    ),
                ],
              ),
            ),
          );
        }),
        if (selRec != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: _infoCallout(th, lang, [
              selRec.label,
              '${StatsAggregator.formatMinutes(selRec.minutes)}${_sessionTimeSuffix(selRec)}',
            ]),
          ),
        ],
      ],
    );
  }
}

/// Groups [records] within [lo]..[hi] (inclusive) by epochDay, each day's
/// list sorted chronologically by time-of-day — shared by Session Timeline
/// in a Week and Session Heatmap (#v31.8).
Map<int, List<SessionRecord>> _sessionsByDay(List<SessionRecord> records, int lo, int hi) {
  final byDay = <int, List<SessionRecord>>{};
  for (final r in records) {
    if (r.epochDay < lo || r.epochDay > hi) continue;
    byDay.putIfAbsent(r.epochDay, () => []).add(r);
  }
  for (final list in byDay.values) {
    list.sort((a, b) => (a.minuteOfDay ?? 0).compareTo(b.minuteOfDay ?? 0));
  }
  return byDay;
}

String _sessionTimeSuffix(SessionRecord r) {
  final m = r.minuteOfDay;
  if (m == null) return '';
  return ' · ${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}

/// One day's sessions as a bordered rectangle of small colour-by-label boxes,
/// chronological by time-of-day — the shared building block behind Session
/// Timeline in a Week and Session Heatmap (#v31.8).
Widget _sessionDayGroup({
  required PixelTheme th,
  required String lang,
  required AppStore s,
  required double cell,
  required List<SessionRecord> sessions,
  required bool Function(int i) isSelected,
  required void Function(int i) onTapSession,
  String? weekdayLabel,
}) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(border: Border.all(color: col(th.onSurfaceDim), width: 1)),
        child: Row(
          children: [
            for (var i = 0; i < sessions.length; i++)
              GestureDetector(
                // tap shows what was studied (#v31 item 8)
                onTap: () => onTapSession(i),
                child: Container(
                  width: cell,
                  height: cell,
                  margin: EdgeInsets.only(right: i == sessions.length - 1 ? 0 : 2),
                  decoration: BoxDecoration(
                    color: col(s.labelColorOf(sessions[i].label)),
                    border: isSelected(i) ? Border.all(color: col(th.onSurface), width: 2) : null,
                  ),
                ),
              ),
            if (sessions.isEmpty) SizedBox(width: cell, height: cell),
          ],
        ),
      ),
      if (weekdayLabel != null) ...[
        const SizedBox(height: 3),
        // weekday initials anchor the boxes to actual days (#v30.9 rec 6)
        Text(weekdayLabel, style: pixelStyle(lang, 7, col(th.onSurfaceDim), text: weekdayLabel)),
      ],
    ],
  );
}

/// Small TREND-callout-styled info box (panel fill + 1px border, pixel rows) —
/// shown on tap instead of a long-press Tooltip (#v31 item 5/8).
Widget _infoCallout(PixelTheme th, String lang, List<String> rows) => Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: col(th.panel),
        border: Border.all(color: col(th.onSurfaceDim), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Text(r, style: pixelStyle(lang, 8, col(th.onSurface), text: r)),
            ),
        ],
      ),
    );

// SESSION HEATMAP granularity (#v31.3 item 5).
enum _HeatUnit { day, week, month, year }

/// "Sessions in Pixels" — its own screen, opened from Stats like LOG HISTORY:
/// the all-history Session Heatmap strip PLUS the per-label Focus Sessions
/// heatmaps, one screen (#v31.5 — Focus Sessions used to sit inline on Stats;
/// merging the two here matches the existing "Year in Pixels" naming/shape —
/// several heatmap sections stacked under one roof).
///
/// SESSION HEATMAP: ALL focus history as one contiguous left→right strip of
/// boxes — one box per day/week/month/year, picked from a classic button
/// row — coloured when that unit had any session, faint otherwise. Scrolls
/// sideways, starts at the most recent end (an explicit `ScrollController` +
/// post-frame `jumpTo(maxScrollExtent)` — `reverse: true` alone was tried
/// first and actually opens on the OLDEST end: it anchors the child's own
/// leading edge, i.e. the first box built, to the far side of the viewport,
/// which is backwards without also feeding it in reverse order; found in the
/// #v31.5 bug report). Tapping an active box floats the usual callout with
/// the unit + count + total time.
class SessionsInPixelsScreen extends StatefulWidget {
  final AppStore s;
  const SessionsInPixelsScreen(this.s, {super.key});
  @override
  State<SessionsInPixelsScreen> createState() => _SessionsInPixelsScreenState();
}

// _HeatUnit and StatPeriod's first four cases mean the same thing — reuse
// StatsAggregator's already-tested window/anchor/label math instead of
// hand-rolling it a second time (#v31.10).
StatPeriod _asStatPeriod(_HeatUnit u) => switch (u) {
      _HeatUnit.day => StatPeriod.daily,
      _HeatUnit.week => StatPeriod.weekly,
      _HeatUnit.month => StatPeriod.monthly,
      _HeatUnit.year => StatPeriod.yearly,
    };

class _SessionsInPixelsScreenState extends State<SessionsInPixelsScreen> {
  _HeatUnit _unit = _HeatUnit.day;
  int _offset = 0; // periods back from now — browse earlier day/week/month/year (#v31.10)
  int? _selIdx; // index into the flat, chronological session list

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final th = s.theme;
    final lang = s.lang;
    final now = DateTime.now();
    if (s.records.isEmpty) {
      return overlayScaffold(context, s, t(lang, 'sessionsInPixels'), [
        Text(t(lang, 'noSessionsPeriod'),
            style: pixelStyle(lang, 9, col(th.onSurfaceDim), text: t(lang, 'noSessionsPeriod'))),
      ]);
    }

    // One box per SESSION, no day framing at all (#v31.9 — "tek sırada
    // soldan sağa gitsin, Monday Tuesday diye kapatılmasın, sadece kutular
    // olsun"): the period picker chooses a calendar WINDOW to pull sessions
    // from — DAILY = today, WEEKLY = this week, MONTHLY = this month,
    // YEARLY = this year — and every session in that window becomes exactly
    // one box in one flat chronological sequence; box count == session
    // count, no padding, no per-day borders/labels. A ◀▶ navigator (#v31.10)
    // browses to earlier days/weeks/months/years via the same anchor/offset
    // mechanism Stats and the Money chart already use.
    final period = _asStatPeriod(_unit);
    final anchor = StatsAggregator.anchorFor(now, period, _offset);
    final (lo, hi) = StatsAggregator.windowDays(anchor, period);
    final sessions = [for (final r in s.records) if (r.epochDay >= lo && r.epochDay <= hi) r]
      ..sort((a, b) {
        final byDay = a.epochDay.compareTo(b.epochDay);
        return byDay != 0 ? byDay : (a.minuteOfDay ?? 0).compareTo(b.minuteOfDay ?? 0);
      });

    Widget unitBtn(String text, _HeatUnit u) {
      final sel = _unit == u;
      void pick() => setState(() {
            _unit = u;
            _offset = 0;
            _selIdx = null;
          });

      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: sel
              ? primaryBtn(th, lang, text, pick, fontSize: 8, padding: const EdgeInsets.all(8))
              : secondaryBtn(th, lang, text, pick, fontSize: 8, padding: const EdgeInsets.all(8)),
        ),
      );
    }

    return overlayScaffold(context, s, t(lang, 'sessionsInPixels'), [
      Text(t(lang, 'sessionHeatmap'), style: pixelStyle(lang, 11, col(th.onSurfaceDim), text: t(lang, 'sessionHeatmap'))),
      const SizedBox(height: 10),
      Row(children: [
        unitBtn(t(lang, 'pDaily'), _HeatUnit.day),
        unitBtn(t(lang, 'pWeekly'), _HeatUnit.week),
        unitBtn(t(lang, 'pMonthly'), _HeatUnit.month),
        unitBtn(t(lang, 'pYearly'), _HeatUnit.year),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        SizedBox(
          width: 52,
          key: const Key('heatmapPrev'),
          child: secondaryBtn(th, lang, '<', () => setState(() {
                _offset++;
                _selIdx = null;
              }), fontSize: 13, padding: const EdgeInsets.all(10)),
        ),
        Expanded(
          child: Center(
            child: Text(periodWindowLabel(lang, period, _offset),
                style: pixelStyle(lang, 11, col(th.onSurface), text: periodWindowLabel(lang, period, _offset))),
          ),
        ),
        SizedBox(
          width: 52,
          key: const Key('heatmapNext'),
          child: PixelButton(
              text: '>', fill: th.panel, border: th.onSurfaceDim, textColor: th.onSurface, shadow: th.shadow,
              lang: lang, fontSize: 13, padding: const EdgeInsets.all(10),
              opacity: _offset > 0 ? 1 : 0.35,
              onTap: () {
                if (_offset > 0) setState(() {
                  _offset--;
                  _selIdx = null;
                });
              }),
        ),
      ]),
      // how much this window actually holds, and the mean over the days that
      // had any focus at all (#v32.6) — rest days stay out of the divisor,
      // so DAILY reads the day itself and MONTHLY reads "on a day I study".
      if (sessions.isNotEmpty) ...[
        const SizedBox(height: 8),
        Builder(builder: (_) {
          final (total, _, avg) = StatsAggregator.windowAverage(sessions, lo, hi);
          final line = tf(lang, 'windowSummary', [
            sessions.length,
            StatsAggregator.formatMinutes(total),
            StatsAggregator.formatMinutes(avg),
          ]);
          return Text(line,
              key: const Key('sessionsWindowSummary'),
              textAlign: TextAlign.center,
              style: pixelStyle(lang, 8, col(th.onSurfaceDim), text: line));
        }),
      ],
      const SizedBox(height: 12),
      if (sessions.isEmpty)
        Text(t(lang, 'noSessionsPeriod'),
            style: pixelStyle(lang, 9, col(th.onSurfaceDim), text: t(lang, 'noSessionsPeriod')))
      else
        LayoutBuilder(builder: (context, box) {
          // uniform cells wrapping left-to-right, top-to-bottom — the same
          // shape v31.7 used for buckets, now holding one box per session
          const target = 16.0;
          final colsPerRow = math.max(1, (box.maxWidth / (target + 1)).floor());
          final cell = _crispCell((box.maxWidth - colsPerRow * 1) / colsPerRow, 4.0, 24.0);
          final rows = (sessions.length / colsPerRow).ceil();

          // ONE painted grid, not a GestureDetector + Container per session
          // (#v34.7). At a thousand-plus sessions this section alone was
          // ~900 of each, and it is the reason the page did not scroll.
          final grid = CellGrid(
            key: const Key('sessionHeatmap'),
            cols: colsPerRow,
            count: sessions.length,
            cell: cell,
            uniformGap: 1,
            rowGap: 1,
            radius: 0, // the session boxes are hard-cornered
            fillOf: (i) => s.labelColorOf(sessions[i].label),
            selectedIndex: _selIdx,
            selectionColor: th.onSurface,
            onTapCell: (i) => setState(() => _selIdx = _selIdx == i ? null : i),
          );

          Widget content = grid;
          if (_selIdx != null && _selIdx! < sessions.length) {
            final rec = sessions[_selIdx!];
            final row = _selIdx! ~/ colsPerRow, colInRow = _selIdx! % colsPerRow;
            // pop above the cell on the last row instead of below, so the
            // callout doesn't overflow past the bottom of the grid
            final top = row == rows - 1
                ? math.max(0.0, row * (cell + 1) - 60)
                : row * (cell + 1) + cell + 4;
            final d = dateOfEpochDay(rec.epochDay);
            content = Stack(clipBehavior: Clip.none, children: [
              grid,
              Positioned(
                left: (colInRow * (cell + 1)).clamp(0.0, math.max(0.0, box.maxWidth - 160)),
                top: top,
                child: _infoCallout(th, lang, [
                  '${d.day} ${monthName(lang, d.month)}',
                  rec.label,
                  '${StatsAggregator.formatMinutes(rec.minutes)}${_sessionTimeSuffix(rec)}',
                ]),
              ),
            ]);
          }
          return content;
        }),
      const SizedBox(height: 24),
      FocusSessionsSection(th: th, lang: lang, s: s, today: epochDayOf(now)),
    ]);
  }
}

// How much trailing history a Focus Sessions heatmap shows (#v30 follow-up).
enum _HeatPeriod { weekly, monthly, days126, yearly }

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
  // periods back from today — an independent ◀▶ navigator (#v31.13), no
  // longer inherited from the parent Stats screen's own navigator (matches
  // Session Heatmap's own self-contained browsing, #v31.10).
  int _offset = 0;
  String? _selLabel; // tapped cell → TREND-style callout (#v31 item 5)
  int? _selDay;
  // user-chosen subset of labels for 18 WEEKS and YEARLY (#v31.2 item 1,
  // YEARLY unified onto the same multi-select #v31.13 — was single-select).
  Set<String>? _chosenLabels;
  // YEARLY's grid shape (#v31.13): horizontal default, or Daylio-style vertical.
  _YearStyle _yearStyle = _YearStyle.horizontal;

  /// The inclusive epochDay span each period's shape displays, around the
  /// navigated [anchor] — labels with no session inside it are hidden (#v31
  /// item 6, anchored per #v31.2 item 3).
  (int, int) _windowFor(_HeatPeriod p, int anchor) {
    final a = dateOfEpochDay(anchor);
    final monday = anchor - (a.weekday - 1);
    switch (p) {
      case _HeatPeriod.weekly:
        return (monday, monday + 6);
      case _HeatPeriod.monthly:
        return (epochDayOf(DateTime.utc(a.year, a.month, 1)), epochDayOf(DateTime.utc(a.year, a.month + 1, 0)));
      case _HeatPeriod.days126:
        return (monday - 17 * 7, monday + 6);
      case _HeatPeriod.yearly:
        // the CALENDAR year ("never used it in 2026 → not in yearly")
        return (epochDayOf(DateTime.utc(a.year, 1, 1)), epochDayOf(DateTime.utc(a.year, 12, 31)));
    }
  }

  /// [_offset] periods back from [today], in the same day-1-anchored way
  /// StatsAggregator.anchorFor uses for months/years (sidesteps "Feb 31
  /// doesn't exist") — 18 WEEKS steps a full 126-day block at a time so
  /// browsing shows entirely fresh history instead of a mostly-overlapping
  /// one-week nudge.
  int _navAnchorFor(_HeatPeriod p, int today, int offset) {
    if (offset <= 0) return today;
    final d = dateOfEpochDay(today);
    switch (p) {
      case _HeatPeriod.weekly:
        return today - offset * 7;
      case _HeatPeriod.monthly:
        return epochDayOf(DateTime.utc(d.year, d.month - offset, 1));
      case _HeatPeriod.days126:
        return today - offset * 126;
      case _HeatPeriod.yearly:
        return epochDayOf(DateTime.utc(d.year - offset, 1, 1));
    }
  }

  String _navLabel(String lang, _HeatPeriod p, int anchor) {
    final d = dateOfEpochDay(anchor);
    switch (p) {
      case _HeatPeriod.weekly:
        final monday = anchor - (d.weekday - 1);
        final loD = dateOfEpochDay(monday), hiD = dateOfEpochDay(monday + 6);
        return '${loD.day}–${hiD.day} ${monthName(lang, hiD.month)}';
      case _HeatPeriod.monthly:
        return '${monthName(lang, d.month)} ${d.year}';
      case _HeatPeriod.days126:
        final (lo, hi) = _windowFor(p, anchor);
        final loD = dateOfEpochDay(lo), hiD = dateOfEpochDay(hi);
        return '${loD.day} ${monthName(lang, loD.month)} – ${hiD.day} ${monthName(lang, hiD.month)}';
      case _HeatPeriod.yearly:
        return '${d.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = widget.th, lang = widget.lang, s = widget.s, today = widget.today;
    final anchor = _navAnchorFor(_period, today, _offset);
    final labelCounts = s.labelHabitCounts;
    final title = Text(t(lang, 'focusSessions'),
        style: pixelStyle(lang, 11, col(th.onSurfaceDim), text: t(lang, 'focusSessions')));
    final noSessions = Text(t(lang, 'noSessionsPeriod'),
        style: pixelStyle(lang, 9, col(th.onSurfaceDim), text: t(lang, 'noSessionsPeriod')));
    // never any session at all → just the text (#v31 item 6)
    if (labelCounts.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        title,
        const SizedBox(height: 10),
        noSessions,
      ]);
    }
    final labelMinutes = LabelHabits.minutesFromRecords(s.records);
    final (lo, hi) = _windowFor(_period, anchor);
    final inWindow = [
      for (final e in labelCounts.entries)
        if (e.value.keys.any((d) => d >= lo && d <= hi)) e
    ];
    // 18 WEEKS and YEARLY: same multi-select filter (an all-filtered-out
    // choice falls back to everything) — YEARLY used to be exactly one label
    // (#v31.3 item 3), unified onto the same picker #v31.13.
    final yearly = _period == _HeatPeriod.yearly;
    final filterable = _period == _HeatPeriod.days126 || yearly;
    var visible = inWindow;
    if (filterable && _chosenLabels != null) {
      final picked = [for (final e in inWindow) if (_chosenLabels!.contains(e.key)) e];
      if (picked.isNotEmpty) visible = picked;
    }

    Widget periodBtn(String text, _HeatPeriod p) {
      final sel = _period == p;
      void pick() => setState(() {
            _period = p;
            _offset = 0;
            _selLabel = null;
            _selDay = null;
          });
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: sel
              ? primaryBtn(th, lang, text, pick, fontSize: 8, padding: const EdgeInsets.all(8))
              : secondaryBtn(th, lang, text, pick, fontSize: 8, padding: const EdgeInsets.all(8)),
        ),
      );
    }

    // tap a day with data → callout; tap it again or an empty day → clear
    void onTap(MapEntry<String, Map<int, int>> e, int day) {
      setState(() {
        if ((e.value[day] ?? 0) == 0 || (_selLabel == e.key && _selDay == day)) {
          _selLabel = null;
          _selDay = null;
        } else {
          _selLabel = e.key;
          _selDay = day;
        }
      });
    }

    // the floating callout for a tapped cell, handed INTO the heatmap so it
    // can position it right next to the cell, like the trend chart (#v31.1)
    Widget? calloutFor(MapEntry<String, Map<int, int>> e) {
      if (_selLabel != e.key || _selDay == null) return null;
      final d = dateOfEpochDay(_selDay!);
      final n = e.value[_selDay!] ?? 0;
      final mins = labelMinutes[e.key]?[_selDay!] ?? 0;
      return _infoCallout(th, lang, [
        '${d.day} ${monthName(lang, d.month)}',
        '${n}x · ${StatsAggregator.formatMinutes(mins)}',
      ]);
    }

    int? selFor(MapEntry<String, Map<int, int>> e) => _selLabel == e.key ? _selDay : null;

    // every period is the SAME 18-weeks-style band grid over a different
    // span (#v31.1 item 1), anchored to the Stats navigator (#v31.2 item 3):
    // weekly = the anchor's week, monthly = the anchor's month (3 side by
    // side), 18 weeks = trailing up to the anchor's week, yearly = the
    // anchor's calendar year banded 18 + 18 + the rest.
    Widget heatmapFor(MapEntry<String, Map<int, int>> e) {
      final color = s.labelColorOf(e.key);
      // the grid's own root sizes itself to the cells it lays out, so this key
      // is how a test measures whether it actually fills its column (#v33)
      final gridKey = ValueKey('labelGrid_${e.key}');
      switch (_period) {
        case _HeatPeriod.weekly:
          return _WeekRow(
              key: gridKey,
              days: e.value, color: color, today: today, anchor: anchor,
              onDayTap: (d) => onTap(e, d), selectedDay: selFor(e), callout: calloutFor(e));
        case _HeatPeriod.monthly:
          return _HabitHeatmap(
              key: gridKey,
              days: e.value, color: color, today: today, maxCellSize: double.infinity, fitCols: true,
              spanStart: lo, spanEnd: hi,
              onDayTap: (d) => onTap(e, d), selectedDay: selFor(e), callout: calloutFor(e));
        case _HeatPeriod.yearly:
          // horizontal (default): 12 months as their own squares, 4 per row.
          // vertical: Daylio's Year in Pixels shape (#v31.13).
          return _yearStyle == _YearStyle.vertical
              ? _YearGridVertical(
                  key: gridKey,
                  days: e.value, color: color, today: today, lang: lang,
                  year: dateOfEpochDay(anchor).year, frameColor: th.onSurfaceDim,
                  onDayTap: (d) => onTap(e, d), callout: calloutFor(e))
              : _YearGridHorizontal(
                  key: gridKey,
                  days: e.value, color: color, today: today,
                  year: dateOfEpochDay(anchor).year, frameColor: th.onSurfaceDim,
                  onDayTap: (d) => onTap(e, d), callout: calloutFor(e));
        case _HeatPeriod.days126:
          return _HabitHeatmap(
              key: gridKey,
              days: e.value, color: color, today: today, maxCellSize: double.infinity,
              spanStart: lo, spanEnd: hi,
              onDayTap: (d) => onTap(e, d), selectedDay: selFor(e), callout: calloutFor(e));
      }
    }

    Widget labelBlock(MapEntry<String, Map<int, int>> e) {
      // count days/times INSIDE the displayed window only — the caption used
      // to sum the label's entire history, so YEARLY read "91 days · 101
      // times" while the grid showed this year's two boxes (#v31.4 bug).
      final winDays = {
        for (final kv in e.value.entries)
          if (kv.key >= lo && kv.key <= hi) kv.key: kv.value
      };
      // total AND the mean over the days this label was actually used inside
      // the window (#v32.6) — same divisor rule as the Session Heatmap's
      // summary, so the two screens never disagree.
      final (winMinutes, _, winAvg) = StatsAggregator.dayMapAverage(
          labelMinutes[e.key] ?? const <int, int>{}, lo, hi);
      // FOUR fixed lines, one per field, instead of one long wrapping
      // string. The single line was 312px at fontSize 8 and no column is
      // that wide (3-up gives 113px, 2-up 173px), so it broke wherever it
      // ran out of room — which put "92h" on one line and "45m" on the
      // next, half a value on each. Giving each field its own line means a
      // value can never be split at any column width; DAYS and TIMES now
      // split too (#v32.12), which removes the last ` · ` a break could
      // land on. ponytail: split the joined string instead of adding two
      // more keys × 6 languages — every table uses ` · `, and a table that
      // ever doesn't just keeps them on one line, which is today's layout.
      // TWO lines, not four (#v34.3): days+times on one, total+average on the
      // next. Four separate lines was solving the wrap problem with height —
      // the pair below solves it with [_capLine]'s scale-down instead, so a
      // value still cannot be broken in half at any column width and the block
      // costs half the vertical space above every grid.
      final capLines = [
        tf(lang, 'capDaysTimes', [HabitLog.daysDone(winDays), HabitLog.totalTimes(winDays)]),
        '${StatsAggregator.formatMinutes(winMinutes)} · '
            '${tf(lang, 'capAvg', [StatsAggregator.formatMinutes(winAvg)])}',
      ];
      final capJoined = capLines.join(' · ');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(e.key, style: pixelStyle(lang, 10, col(s.labelColorOf(e.key)), text: e.key)),
          // shown for every period, including the narrow 2-up/3-up
          // weekly/monthly layouts (#v31.13 — used to skip those so the
          // grids fit, #v31.2/#v31.5)
          const SizedBox(height: 2),
          LayoutBuilder(builder: (context, box) {
            // ONE line wherever it actually fits (#v32.11). The full-width
            // periods — 18 WEEKS and YEARLY HORIZONTAL — give the block 358px
            // against a ~320px caption, so splitting those into three lines
            // was spending height for nothing. Measured against the real
            // style rather than a guessed width threshold, so it stays right
            // in every language and at any screen size; the narrow 2-up/3-up
            // columns can't take it and keep the per-field lines, which is
            // what stops a value being cut in half (#v32.9).
            final joinedStyle = pixelStyle(lang, 8, col(th.onSurfaceDim), text: capJoined);
            final tp = TextPainter(
              text: TextSpan(text: capJoined, style: joinedStyle),
              textDirection: Directionality.of(context),
              maxLines: 1,
            )..layout();
            if (tp.width <= box.maxWidth) return Text(capJoined, style: joinedStyle);
            // 3px between the two lines (#v34.5): they were sitting flush
            // and read as one wrapped string rather than two fields.
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < capLines.length; i++) ...[
                  if (i != 0) const SizedBox(height: 3),
                  _capLine(th, lang, capLines[i]),
                ],
              ],
            );
          }),
          const SizedBox(height: 4),
          heatmapFor(e),
        ],
      );
    }

    // label picker for the long views: multi-select with the app blocker's
    // pixel on/off switch (the old ✓ read unclear, #v31.3 item 2) — YEARLY
    // used to be single-select-only (tap a row to pick THE one label); now
    // the same picker as 18 WEEKS (#v31.13). Rows sit right under the title,
    // bigger text.
    void pickLabels() {
      void toggle(String key) => setState(() {
            final set = _chosenLabels ?? inWindow.map((x) => x.key).toSet();
            set.contains(key) ? set.remove(key) : set.add(key);
            _chosenLabels = set;
            _selLabel = null;
            _selDay = null;
          });
      showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            backgroundColor: col(th.panel),
            titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
            contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            title: Text(t(lang, 'label'), style: pixelStyle(lang, 12, col(th.onSurface), text: t(lang, 'label'))),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final e in inWindow)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setLocal(() => toggle(e.key)),
                        child: Row(children: [
                          // square, like every other label swatch (#v34.5)
                          Swatch(color: s.labelColorOf(e.key), border: th.onSurfaceDim, size: 18, plain: true),
                          const SizedBox(width: 12),
                          Expanded(child: Text(e.key, style: pixelStyle(lang, 13, col(th.onSurface), text: e.key))),
                          _BlockToggle(
                            on: _chosenLabels?.contains(e.key) ?? true,
                            accent: th.accent,
                            off: th.onSurfaceDim,
                            knob: th.onSurface,
                            onTap: () => setLocal(() => toggle(e.key)),
                          ),
                        ]),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              primaryBtn(th, lang, t(lang, 'close'), () => Navigator.pop(ctx),
                  fontSize: 10, padding: const EdgeInsets.all(10)),
            ],
          ),
        ),
      );
    }

    // YEARLY's grid-shape picker (#v31.13): horizontal (12 month squares,
    // 4 per row) or vertical (Daylio's Year in Pixels shape). Each row ends
    // in a bordered CHECKBOX square the tick sits inside — a bare floating ✓
    // gave no visible tap target on the unselected row (#v32).
    void pickYearStyle() {
      Widget checkSquare(bool on) => Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: on ? col(th.accent) : col(th.panel),
              border: Border.all(color: col(on ? th.onSurface : th.onSurfaceDim), width: 2),
            ),
            child: on ? Icon(Icons.check, color: col(th.onAccent), size: 14) : null,
          );
      Widget row(String text, _YearStyle style) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                setState(() => _yearStyle = style);
                Navigator.pop(context);
              },
              child: Row(children: [
                Expanded(child: Text(text, style: pixelStyle(lang, 13, col(th.onSurface), text: text))),
                checkSquare(_yearStyle == style),
              ]),
            ),
          );
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: col(th.panel),
          titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
          contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          title: Text(t(lang, 'style'), style: pixelStyle(lang, 12, col(th.onSurface), text: t(lang, 'style'))),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            row(t(lang, 'styleHorizontal'), _YearStyle.horizontal),
            row(t(lang, 'styleVertical'), _YearStyle.vertical),
          ]),
          actions: [
            primaryBtn(th, lang, t(lang, 'close'), () => Navigator.pop(ctx),
                fontSize: 10, padding: const EdgeInsets.all(10)),
          ],
        ),
      );
    }

    // narrow grids side by side instead of one full-width stack (#v31.2 item 2,
    // weekly added #v31.5 item 4) — the label heatmaps' own LayoutBuilder sizes
    // their cells to whatever width the Expanded column gives them, so this
    // alone shrinks the boxes. [perRow] is a fixed count, never derived from
    // the width: the row structure must not reflow when the screen changes
    // (#v34.1).
    Widget perRowGrid(int perRow) => Column(children: [
          for (var i = 0; i < visible.length; i += perRow)
            Padding(
              // 24, not 14 (#v34.1): row 2's label name sat almost against
              // row 1's grid, and the two rows read as one block.
              padding: const EdgeInsets.only(bottom: 24),
              child: Builder(builder: (_) {
                final batch = visible.skip(i).take(perRow).toList();
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // EQUAL columns: the gap is a real SizedBox between the
                    // Expanded blocks, not right-padding inside them — padding
                    // shrank the earlier columns' content while the last kept
                    // its full width, so the 3rd label read bigger than the
                    // other two (#v33.2). Now every block is one flex unit wide.
                    for (var j = 0; j < perRow; j++) ...[
                      if (j != 0) const SizedBox(width: 6),
                      Expanded(child: j < batch.length ? labelBlock(batch[j]) : const SizedBox()),
                    ],
                  ],
                );
              }),
            ),
        ]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        title,
        const SizedBox(height: 10),
        Row(children: [
          periodBtn(t(lang, 'pWeekly'), _HeatPeriod.weekly),
          periodBtn(t(lang, 'pMonthly'), _HeatPeriod.monthly),
          periodBtn(t(lang, 'p18Weeks'), _HeatPeriod.days126),
          periodBtn(t(lang, 'pYearly'), _HeatPeriod.yearly),
        ]),
        const SizedBox(height: 10),
        // an independent ◀▶ navigator (#v31.13) — no longer inherited from
        // the parent Stats screen's own navigator, matching Session
        // Heatmap's self-contained browsing (#v31.10).
        Row(children: [
          SizedBox(
            width: 52,
            key: const Key('focusSessionsPrev'),
            child: secondaryBtn(th, lang, '<', () => setState(() {
                  _offset++;
                  _selLabel = null;
                  _selDay = null;
                }), fontSize: 13, padding: const EdgeInsets.all(10)),
          ),
          Expanded(
            child: Center(
              child: Text(_navLabel(lang, _period, anchor),
                  key: const Key('focusSessionsNavLabel'),
                  style: pixelStyle(lang, 11, col(th.onSurface), text: _navLabel(lang, _period, anchor))),
            ),
          ),
          SizedBox(
            width: 52,
            key: const Key('focusSessionsNext'),
            child: PixelButton(
                text: '>', fill: th.panel, border: th.onSurfaceDim, textColor: th.onSurface, shadow: th.shadow,
                lang: lang, fontSize: 13, padding: const EdgeInsets.all(10),
                opacity: _offset > 0 ? 1 : 0.35,
                onTap: () {
                  if (_offset > 0) setState(() {
                    _offset--;
                    _selLabel = null;
                    _selDay = null;
                  });
                }),
          ),
        ]),
        const SizedBox(height: 12),
        if (filterable && inWindow.isNotEmpty) ...[
          Row(children: [
            Expanded(
              child: secondaryBtn(
                  th,
                  lang,
                  '${t(lang, 'label')} (${visible.length}/${inWindow.length})',
                  pickLabels,
                  key: const Key('labelFilterButton'),
                  fontSize: 10,
                  padding: const EdgeInsets.all(10)),
            ),
            // the grid-shape picker only makes sense for YEARLY (#v31.13) —
            // weekly/monthly/18 weeks don't have a vertical/horizontal choice
            if (yearly) ...[
              const SizedBox(width: 6),
              Expanded(
                child: secondaryBtn(th, lang, t(lang, 'style'), pickYearStyle,
                    key: const Key('yearStyleButton'), fontSize: 10, padding: const EdgeInsets.all(10)),
              ),
            ],
          ]),
          const SizedBox(height: 12),
        ],
        // Combined figure for the labels currently on screen — "when I pick
        // the labels, tell me the average for that time range" (#v32.6).
        // Minutes are merged per DAY before averaging, so a day on which two
        // picked labels were both used counts as ONE active day; summing the
        // per-label averages instead would drift upward the more labels are
        // picked.
        // With exactly ONE label on screen the block is dead weight — its two
        // lines say what that label's own caption says a few pixels below
        // (#v32.8: "tek bir label seçtiğimizde üstteki kısım gizlensin …
        // çünkü tekrar ediyor"). It earns its place only while it is
        // combining something.
        if (visible.length > 1) ...[
          Builder(builder: (_) {
            final merged = <int, int>{};
            for (final e in visible) {
              for (final kv in (labelMinutes[e.key] ?? const <int, int>{}).entries) {
                if (kv.key < lo || kv.key > hi) continue;
                merged[kv.key] = (merged[kv.key] ?? 0) + kv.value;
              }
            }
            final (total, _, avg) = StatsAggregator.dayMapAverage(merged, lo, hi);
            final line = tf(lang, 'labelWindowSummary', [
              StatsAggregator.formatMinutes(total),
              StatsAggregator.formatMinutes(avg),
            ]);
            // Nothing filtered out → say "all of them" in a couple of words
            // rather than listing the picker's entire contents back (#v32.8).
            final picked = visible.length < inWindow.length
                ? tf(lang, 'selectedLabels', [visible.map((e) => e.key).join(', ')])
                : tf(lang, 'allLabels', [visible.length]);
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(picked,
                  key: const Key('focusSessionsSelected'),
                  style: pixelStyle(lang, 8, col(th.onSurfaceDim), text: picked)),
              const SizedBox(height: 3),
              Text(line,
                  key: const Key('focusSessionsSummary'),
                  style: pixelStyle(lang, 9, col(th.onSurface), text: line)),
            ]);
          }),
          const SizedBox(height: 12),
        ],
        if (visible.isEmpty)
          // labels exist but none were used inside this period's window
          noSessions
        // WEEKLY 2 across, MONTHLY 3 (#v34.3). #v34.1 put both on 2, which was
        // half a misread — only weekly was meant to change. A month grid is
        // wider than a week strip and reads fine at three. Both counts are
        // fixed literals, never derived from the width, so neither reflows.
        else if (_period == _HeatPeriod.weekly)
          perRowGrid(2)
        else if (_period == _HeatPeriod.monthly)
          perRowGrid(3)
        else if (_period == _HeatPeriod.yearly && _yearStyle == _YearStyle.vertical)
          // the narrow Daylio-style year column leaves half the width empty —
          // two labels' year grids fit side by side (#v32)
          perRowGrid(2)
        else
          for (final e in visible) ...[
            labelBlock(e),
            const SizedBox(height: 14),
          ],
      ],
    );
  }
}

// "Your Year in Pixels" — every daily heatmap in one place: mood, manual
// habits/goals, and focus sessions (#v30 items 6/9 — "(all data)").
Widget _yearInPixelsContent(BuildContext context, PixelTheme th, String lang, AppStore s, int today) {
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Text(t(lang, 'moodTracker'), style: pixelStyle(lang, 11, col(th.onSurfaceDim), text: t(lang, 'moodTracker'))),
    const SizedBox(height: 10),
    _moodHeatmap(context, s, th, lang, today),
    const SizedBox(height: 20),
    for (final h in s.habits) ...[
      Text(h.name, style: pixelStyle(lang, 10, col(h.color), text: h.name)),
      const SizedBox(height: 4),
      _HabitHeatmap(
        days: s.habitLog[h.name] ?? const {},
        color: h.color,
        today: today,
        maxCellSize: double.infinity,
        tooltipFor: (day) {
          final n = (s.habitLog[h.name] ?? const {})[day] ?? 0;
          return n == 0 ? null : '${n}x';
        },
      ),
      const SizedBox(height: 14),
    ],
    SessionsTimelineWeek(th: th, lang: lang, s: s, today: today),
    const SizedBox(height: 20),
    FocusSessionsSection(th: th, lang: lang, s: s, today: today),
  ]);
}

class HabitScreen extends StatefulWidget {
  final AppStore s;
  const HabitScreen(this.s, {super.key});

  /// Last-open tab, remembered for the app session so reopening the tracker
  /// lands where the user left off instead of always on Mood (#v30.9 rec 5).
  static int lastTab = 0;

  @override
  State<HabitScreen> createState() => _HabitScreenState();
}

class _HabitScreenState extends State<HabitScreen> {
  // 0 = mood tracker, 1 = year in pixels (all data), 2 = goals (#v30 items 6/7/9)
  int _tab = HabitScreen.lastTab;

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
              ? primaryBtn(th, lang, text, () => setState(() => _tab = HabitScreen.lastTab = i), fontSize: 8, padding: const EdgeInsets.all(8), key: key)
              : secondaryBtn(th, lang, text, () => setState(() => _tab = HabitScreen.lastTab = i), fontSize: 8, padding: const EdgeInsets.all(8), key: key),
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
        _yearInPixelsContent(context, th, lang, s, today)
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
      _moodHeatmap(context, s, th, lang, today),
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
  int _chartOffset = 0; // chart windows back from now (#v30.9 rec 4)
  int _txPage = 0; // entry-list page, newest first (#v30.9 rec 3)

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
            onPressed: () => setState(() {
              _offset++;
              _txPage = 0;
            }),
            icon: Text('<', style: pixelStyle(lang, 18, col(th.onSurface), text: '<')),
          ),
          Text('${monthName(lang, view.month)} ${view.year}',
              style: pixelStyle(lang, 13, col(th.onSurface), text: '${monthName(lang, view.month)} ${view.year}')),
          IconButton(
            onPressed: _offset == 0
                ? null
                : () => setState(() {
                      _offset--;
                      _txPage = 0;
                    }),
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
      // rates never loaded → conversions silently fall back to raw amounts;
      // say so instead of letting mixed-currency totals lie (#v30.9)
      if (s.fxRates.isEmpty) ...[
        const SizedBox(height: 8),
        Text(t(lang, 'noRates'),
            textAlign: TextAlign.center,
            style: pixelStyle(lang, 8, col(th.onSurfaceDim), text: t(lang, 'noRates'))),
      ],
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
      else ...[
        // paged, not silently capped at 40 like before (#v30.9 rec 3)
        for (final tx in Paging.page(monthTxs, _txPage, 50)) _txRow(context, s, th, lang, tx, cur),
        if (Paging.pageCount(monthTxs.length, 50) > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              SizedBox(
                width: 52,
                child: PixelButton(
                    text: '<', fill: th.panel, border: th.onSurfaceDim, textColor: th.onSurface, shadow: th.shadow,
                    lang: lang, fontSize: 13, padding: const EdgeInsets.all(10),
                    opacity: _txPage + 1 < Paging.pageCount(monthTxs.length, 50) ? 1 : 0.35,
                    onTap: () {
                      if (_txPage + 1 < Paging.pageCount(monthTxs.length, 50)) setState(() => _txPage++);
                    }),
              ),
              Expanded(
                child: Center(
                  child: Text(tf(lang, 'pageOf', [_txPage + 1, Paging.pageCount(monthTxs.length, 50)]),
                      style: pixelStyle(lang, 10, col(th.onSurface),
                          text: tf(lang, 'pageOf', [_txPage + 1, Paging.pageCount(monthTxs.length, 50)]))),
                ),
              ),
              SizedBox(
                width: 52,
                child: PixelButton(
                    text: '>', fill: th.panel, border: th.onSurfaceDim, textColor: th.onSurface, shadow: th.shadow,
                    lang: lang, fontSize: 13, padding: const EdgeInsets.all(10),
                    opacity: _txPage > 0 ? 1 : 0.35,
                    onTap: () {
                      if (_txPage > 0) setState(() => _txPage--);
                    }),
              ),
            ]),
          ),
      ],
      const SizedBox(height: 20),
      _moneySettings(context, s, th, lang),
    ]);
  }

  // income/expense bar + pie chart, current daily/weekly/monthly window
  // (#v30 item 11) — reuses the same StatsChart widget the Stats screen uses.
  Widget _moneyChart(PixelTheme th, String lang, AppStore s) {
    final now = DateTime.now();
    // browse earlier windows with the same anchor mechanism Stats uses (#v30.9 rec 4)
    final anchor = StatsAggregator.anchorFor(now, _chartPeriod, _chartOffset);
    final (start, end) = StatsAggregator.windowDays(anchor, _chartPeriod);
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
      void pick() => setState(() {
            _chartPeriod = p;
            _chartOffset = 0;
          });
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: sel
              ? primaryBtn(th, lang, text, pick, fontSize: 8, padding: const EdgeInsets.all(8))
              : secondaryBtn(th, lang, text, pick, fontSize: 8, padding: const EdgeInsets.all(8)),
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
      const SizedBox(height: 10),
      Row(children: [
        SizedBox(
          width: 52,
          child: secondaryBtn(th, lang, '<', () => setState(() => _chartOffset++),
              fontSize: 13, padding: const EdgeInsets.all(10)),
        ),
        Expanded(
          child: Center(
            child: Text(periodWindowLabel(lang, _chartPeriod, _chartOffset),
                style: pixelStyle(lang, 11, col(th.onSurface),
                    text: periodWindowLabel(lang, _chartPeriod, _chartOffset))),
          ),
        ),
        SizedBox(
          width: 52,
          child: PixelButton(
              text: '>', fill: th.panel, border: th.onSurfaceDim, textColor: th.onSurface, shadow: th.shadow,
              lang: lang, fontSize: 13, padding: const EdgeInsets.all(10),
              opacity: _chartOffset > 0 ? 1 : 0.35,
              onTap: () {
                if (_chartOffset > 0) setState(() => _chartOffset--);
              }),
        ),
      ]),
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
          noDataText: t(lang, 'noMoneyData'),
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
    final sign = tx.isExpense ? '-' : '+';
    // the entry KEEPS its original currency (spend złoty on holiday, earn in
    // euro — the 150 PLN stays 150 PLN); the main-currency equivalent shows
    // as a dim second line, and ONLY when both rates are actually known —
    // the old converted-only display fell back to the raw number when rates
    // were missing, so 150 PLN read as "EUR 150.00" (#v30.9).
    final orig = '$sign${_money(tx.amountMinor / 100.0, tx.currency)}';
    final sameCur = tx.currency == cur;
    final ratesKnown = s.fxRates[tx.currency] != null && s.fxRates[cur] != null;
    final conv = '= ${_money(s.moneyToMain(tx), cur)}';
    final amtColor = col(tx.isExpense ? th.accent : th.work);
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
          if (sameCur)
            Text(orig, style: pixelStyle(lang, 9, amtColor, text: orig))
          else
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(orig, style: pixelStyle(lang, 9, amtColor, text: orig)),
              if (ratesKnown)
                Text(conv, style: pixelStyle(lang, 7, col(th.onSurfaceDim), text: conv)),
            ]),
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
                        // custom categories delete on long-press, like habit
                        // cards; built-ins have no handler (#v30.9 rec 2)
                        onLongPress: !s.customCategories.contains(c)
                            ? null
                            : () => showDialog(
                                  context: ctx,
                                  builder: (ctx2) => AlertDialog(
                                    backgroundColor: col(th.panel),
                                    content: Text(tf(lang, 'removeCategoryMsg', [c]),
                                        style: pixelStyle(lang, 11, col(th.onSurface), text: tf(lang, 'removeCategoryMsg', [c]))),
                                    actions: [
                                      secondaryBtn(th, lang, t(lang, 'no'), () => Navigator.pop(ctx2), fontSize: 10, padding: const EdgeInsets.all(10)),
                                      primaryBtn(th, lang, t(lang, 'yes'), () {
                                        s.removeCustomCategory(c);
                                        setLocal(() {
                                          cats = [for (final x in cats) if (x != c) x];
                                          if (cat == c) cat = cats.first;
                                        });
                                        Navigator.pop(ctx2);
                                      }, fontSize: 10, padding: const EdgeInsets.all(10)),
                                    ],
                                  ),
                                ),
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
            SizedBox(width: 110, child: _BudgetField(s: s, th: th, lang: lang)),
          ]),
          const SizedBox(height: 6),
          Text(t(lang, 'dailyRateHelp'), style: pixelStyle(lang, 8, col(th.onSurfaceDim), text: t(lang, 'dailyRateHelp'))),
        ],
      ),
    );
  }
}

/// The DAILY BUDGET input. Owns its controller in State — the old inline
/// `TextEditingController(...)` in the parent's build() was recreated on
/// EVERY AppStore notification, wiping an in-progress edit (the fx refresh
/// fired seconds after the screen opened, which is exactly when the user is
/// typing here — found in the #v30.8 bug sweep). Also fixes the controller
/// leak (the inline one was never disposed).
class _BudgetField extends StatefulWidget {
  final AppStore s;
  final PixelTheme th;
  final String lang;
  const _BudgetField({required this.s, required this.th, required this.lang});
  @override
  State<_BudgetField> createState() => _BudgetFieldState();
}

class _BudgetFieldState extends State<_BudgetField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    final rate = (widget.s.dailyRateMinor / 100).toStringAsFixed(0);
    _ctrl = TextEditingController(text: rate == '0' ? '' : rate);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s, th = widget.th, lang = widget.lang;
    return TextField(
      controller: _ctrl,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.right,
      style: pixelStyle(lang, 12, col(th.onSurface), text: _ctrl.text),
      decoration: InputDecoration(
        hintText: '0',
        suffixText: ' ${s.mainCurrency}',
        suffixStyle: pixelStyle(lang, 9, col(th.onSurfaceDim), text: s.mainCurrency),
      ),
      onSubmitted: (v) {
        final d = double.tryParse(v.replaceAll(',', '.')) ?? 0;
        s.setDailyRate((d * 100).round());
      },
    );
  }
}

/// Shared cell painter used by [_WeekRow] and [_MonthCalendar] so the three
/// heatmap shapes (column grid, single week row, calendar month) all render
/// a day cell identically (#v30 follow-up).
/// Cell size for a pixel-art grid, always a WHOLE logical pixel (#v32.10).
///
/// Dividing the available width by the column count almost never lands on an
/// integer — WEEKLY at 3-up gave 16.1905 — and a fractional cell makes the
/// whole label block a fractional height (78.19). In a multi-column grid that
/// puts the SECOND row of labels at y = 284.19, and at a 3x device pixel ratio
/// 284.19 is 852.57 physical pixels: every box in that row gets resampled
/// across a pixel boundary and goes soft, while the first row (y = 192, a
/// clean 576) stays sharp. That is the "the labels after the first three lose
/// their sharpness" report — nothing to do with the labels themselves, only
/// with where their row happened to start.
///
/// Flooring costs at most one pixel of grid width and keeps every row on the
/// device pixel grid.
double _crispCell(double raw, double min, double max) =>
    raw.clamp(min, max).floorToDouble().clamp(min, max);

/// Tile [n] columns edge-to-edge across [width] with NO trailing gap, every
/// value a whole pixel (#v33.1). Flooring one cell size and adding a fixed 2px
/// margin left up to ~n px unfilled on the right ("kareler tam kaplamıyor,
/// sağda boşluk"). Here the cell is still floored — so cells stay crisp, the
/// v32.10 win — and the leftover pixels are spread one at a time into the
/// leftmost GAPS instead of piling up at the edge. Returns the cell size and
/// the n-1 inter-column gaps; a partial row that reuses `gaps[0..k-1]` still
/// lines up column-for-column under a full row, because the left edges are the
/// same running sum in both.
(double, List<double>) _tileRow(double width, int n, {double minGap = 2, double minCell = 4}) {
  if (n <= 1) return (width.clamp(minCell, double.infinity), const []);
  final cell = ((width - (n - 1) * minGap) / n).floorToDouble().clamp(minCell, double.infinity);
  var extra = (width - n * cell - (n - 1) * minGap).floor(); // ≥0 unless cells overflow
  if (extra < 0) extra = 0;
  final gaps = [for (var i = 0; i < n - 1; i++) minGap + (i < extra ? 1 : 0)];
  return (cell, gaps);
}

/// The fill a heatmap cell ends up with, as a resolved ARGB (#v34.7).
///
/// Lifted out of [_dayCell] unchanged so the painted grids below and the
/// widget-built ones cannot drift apart, and so the rule is testable on its
/// own. A blank slot is a faint tint rather than nothing — fully invisible
/// slots read as holes in the grid (#v32).
int cellFill({required bool blank, required int? dayColor, required int color}) {
  if (blank) return (col(color).withValues(alpha: 0.07)).toARGB32();
  return (col(dayColor ?? color).withValues(alpha: dayColor != null ? 1 : 0.18)).toARGB32();
}

/// A whole grid of heatmap cells drawn in ONE pass (#v34.7).
///
/// Public so tests can count the cells it draws — they used to count Container
/// widgets, which no longer exist for these grids.
///
/// Sessions in Pixels was building a `Container` **and** a `GestureDetector`
/// per cell — 899 of each, 9,749 widgets on the page — and a page that big is
/// what "it doesn't scroll, it stops when I lift my finger" was. The cells are
/// flat coloured squares; they do not need to be widgets. One `CustomPaint`
/// draws them all and one `GestureDetector` maps a tap back to an index by
/// arithmetic.
///
/// Geometry matches the Row/Column it replaces exactly: [gaps] holds the
/// `cols - 1` inter-column gaps from [_tileRow] (or is empty, meaning
/// [uniformGap] everywhere), and rows are separated by [rowGap].
class CellGrid extends StatelessWidget {
  final int cols;
  final int count; // cells, row-major
  final double cell;
  final List<double> gaps;
  final double uniformGap;
  final double rowGap;
  final int Function(int index) fillOf;
  final void Function(int index)? onTapCell;

  /// Optional ring around one cell — the session heatmap's selection (#v34.7).
  final int? selectedIndex;
  final int? selectionColor;

  /// Cells are square with a 1px rounding by default; the session heatmap's
  /// boxes are hard-cornered.
  final double radius;

  const CellGrid({
    super.key,
    required this.cols,
    required this.count,
    required this.cell,
    required this.fillOf,
    this.gaps = const [],
    this.uniformGap = 2,
    this.rowGap = 2,
    this.onTapCell,
    this.selectedIndex,
    this.selectionColor,
    this.radius = 1,
  });

  double _gapAfter(int c) =>
      c >= cols - 1 ? 0 : (gaps.isEmpty ? uniformGap : (c < gaps.length ? gaps[c] : uniformGap));

  /// Left edge of column [c] — the same running sum the Row produced.
  double _xOf(int c) {
    var x = 0.0;
    for (var i = 0; i < c; i++) {
      x += cell + _gapAfter(i);
    }
    return x;
  }

  /// Where cell [i] is drawn, in the grid's own coordinates. The painter uses
  /// it, and a test can use it to tap a specific cell.
  Rect rectOfIndex(int i) => Rect.fromLTWH(
      _xOf(i % cols), (i ~/ cols) * (cell + rowGap), cell, cell);

  int get _rows => (count / cols).ceil();
  double get _width => _xOf(cols - 1) + cell;
  double get _height => _rows * cell + (_rows - 1) * rowGap;

  /// Which cell is under [p], or -1. Used for taps; also the unit under test.
  int indexAt(Offset p) {
    if (p.dx < 0 || p.dy < 0) return -1;
    final r = (p.dy / (cell + rowGap)).floor();
    if (r < 0 || r >= _rows) return -1;
    if (p.dy - r * (cell + rowGap) > cell) return -1; // in the gap between rows
    for (var c = 0; c < cols; c++) {
      final x = _xOf(c);
      if (p.dx >= x && p.dx <= x + cell) {
        final i = r * cols + c;
        return i < count ? i : -1;
      }
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    final painter = CellGridPainter(this);
    Widget grid = CustomPaint(size: Size(_width, _height), painter: painter);
    if (onTapCell != null) {
      grid = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          final i = indexAt(d.localPosition);
          if (i >= 0) onTapCell!(i);
        },
        child: grid,
      );
    }
    return SizedBox(width: _width, height: _height, child: grid);
  }
}

class CellGridPainter extends CustomPainter {
  final CellGrid g;
  const CellGridPainter(this.g);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final radius = Radius.circular(g.radius);
    for (var i = 0; i < g.count; i++) {
      paint.color = col(g.fillOf(i));
      canvas.drawRRect(RRect.fromRectAndRadius(g.rectOfIndex(i), radius), paint);
    }
    // the selection ring last, so it is never painted over by a neighbour
    final sel = g.selectedIndex;
    if (sel != null && sel >= 0 && sel < g.count && g.selectionColor != null) {
      canvas.drawRect(
        g.rectOfIndex(sel).deflate(1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = col(g.selectionColor!),
      );
    }
  }

  // the grid is rebuilt whenever anything it draws changes, so a repaint is
  // only ever asked for on a real change
  @override
  bool shouldRepaint(CellGridPainter old) => true;
}

Widget _dayCell({
  required double cell,
  required bool blank,
  required int? dayColor,
  required int color,
  required String? tooltip,
  VoidCallback? onTap,
  double gap = 2, // right margin; a tiled row passes its per-column gap (#v33.1)
}) {
  Widget box = Container(
    width: cell,
    height: cell,
    margin: EdgeInsets.only(right: gap),
    decoration: BoxDecoration(
      // one shared rule with the painted grids (#v34.7) — see [cellFill]
      color: col(cellFill(blank: blank, dayColor: dayColor, color: color)),
      borderRadius: BorderRadius.circular(1),
    ),
  );
  if (!blank && tooltip != null && tooltip.isNotEmpty) box = Tooltip(message: tooltip, child: box);
  // tap coexists with the Tooltip: its trigger is long-press, so a plain tap
  // stays free for the handler (#v30.9 — editable past moods).
  if (!blank && onTap != null) box = GestureDetector(onTap: onTap, child: box);
  return box;
}

/// Weekly view: a single HORIZONTAL row of 7 days (the calendar week
/// containing today, Mon..Sun) — the column grid would otherwise render a
/// 1-week span as a vertical 7-row strip, which read wrong (#v30 follow-up).
class _WeekRow extends StatelessWidget {
  final Map<int, int> days;
  final int color, today;
  // which calendar week to show — the Stats ◀▶ navigator hands an earlier
  // week's day here (#v31.2 item 3); defaults to today's week.
  final int? anchor;
  final void Function(int day)? onDayTap;
  final int? selectedDay;
  final Widget? callout;
  const _WeekRow(
      {super.key,
      required this.days, required this.color, required this.today, this.anchor, this.onDayTap,
      this.selectedDay, this.callout});

  @override
  Widget build(BuildContext context) {
    final a = anchor ?? today;
    final monday = a - (dateOfEpochDay(a).weekday - 1);
    return LayoutBuilder(builder: (context, box) {
      const cols = 7;
      // tiled so the 7 boxes span the full width with no dead strip on the
      // right, at any screen size, and stay crisp (#v33 / #v33.1)
      final (cell, gaps) = _tileRow(box.maxWidth, cols);
      // painted, not seven widgets (#v34.7)
      final row = CellGrid(
        cols: cols,
        count: cols,
        cell: cell,
        gaps: gaps,
        fillOf: (i) {
          final day = monday + i;
          // future days stay boxed but faint and inert, so the week always
          // shows all 7 boxes (#v31.1 item 2)
          final dayColor = day > today ? null : ((days[day] ?? 0) > 0 ? color : null);
          return cellFill(blank: false, dayColor: dayColor, color: color);
        },
        onTapCell: onDayTap == null
            ? null
            : (i) {
                final day = monday + i;
                if (day <= today) onDayTap!(day);
              },
      );
      if (selectedDay == null || callout == null) return row;
      final c = (selectedDay! - monday).clamp(0, 6);
      const estW = 140.0;
      return Stack(clipBehavior: Clip.none, children: [
        row,
        Positioned(
          left: (c * (cell + 2)).clamp(0.0, math.max(0.0, box.maxWidth - estW)),
          top: cell + 4,
          child: callout!,
        ),
      ]);
    });
  }
}

/// Yearly view: ONE horizontal band of the calendar year's ~53 week columns,
/// reading left→right and scrolling sideways, with each month's weeks wrapped
/// in a bordered frame like the session timeline's day rectangles — no month
/// captions (tapping a cell already shows its date, #v31.3 item 4). Boundary
/// weeks belong to the month containing their Thursday.
// Which layout YEARLY draws its per-label year grid in (#v31.13) — replaced
// _YearBand entirely: its week-aligned month "frames" could bleed a few days
// from the adjacent month into a given month's box count, which read wrong.
enum _YearStyle { horizontal, vertical }

/// HORIZONTAL: 12 months as their own bordered squares, 4 per row (3 rows) —
/// each frame holds EXACTLY that month's day count (28-31), wrapped 7-wide
/// like a small calendar, no bleed from neighbouring months (#v31.13).
class _YearGridHorizontal extends StatelessWidget {
  final Map<int, int> days;
  final int color, today, year, frameColor;
  final void Function(int day)? onDayTap;
  final Widget? callout;
  const _YearGridHorizontal(
      {super.key,
      required this.days, required this.color, required this.today, required this.year,
      required this.frameColor, this.onDayTap, this.callout});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      const monthsPerRow = 4;
      const cols = 7; // a calendar-week-wide mini grid per month
      // Real widths, all accounted for: every _dayCell carries a built-in 2px
      // right margin, and each month block adds 3+3 padding + 1+1 border = 8.
      // The old formula ignored both, so 4 months per row overflowed the
      // screen by ~64px ("the year doesn't fit, it goes off the screen") and
      // the clamp's 4px floor never engaged to save it (#v32).
      const monthChrome = 8.0 + cols * 2.0; // padding+border + per-cell margins
      // uncapped (#v33): the twelve months fill whatever width they are given
      final cell = _crispCell(
          (box.maxWidth - monthsPerRow * monthChrome - (monthsPerRow - 1) * 6) /
              (monthsPerRow * cols),
          4.0,
          double.infinity);

      Widget monthBlock(int m) {
        final first = epochDayOf(DateTime.utc(year, m, 1));
        final lastDay = DateTime.utc(year, m + 1, 0).day;
        final rows = (lastDay / cols).ceil();
        return Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(border: Border.all(color: col(frameColor), width: 1)),
          // one painted grid per month instead of rows x 7 widgets (#v34.7)
          child: CellGrid(
            cols: cols,
            count: rows * cols,
            cell: cell,
            fillOf: (i) {
              final dNum = i + 1;
              // past the month's length: faint filler, not an invisible hole
              // (#v32) — a hole reads as a missing day
              if (dNum > lastDay) {
                return cellFill(blank: true, dayColor: null, color: color);
              }
              final day = first + dNum - 1;
              final active = day <= today && (days[day] ?? 0) > 0;
              return cellFill(
                  blank: false, dayColor: day > today ? null : (active ? color : null), color: color);
            },
            onTapCell: onDayTap == null
                ? null
                : (i) {
                    final dNum = i + 1;
                    if (dNum > lastDay) return;
                    final day = first + dNum - 1;
                    if (day <= today) onDayTap!(day);
                  },
          ),
        );
      }

      final grid = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var row = 0; row < 3; row++)
            Padding(
              padding: EdgeInsets.only(bottom: row == 2 ? 0 : 8),
              // spaceBetween spreads the 4 month blocks evenly edge-to-edge
              // instead of packing them left with a dead strip on the right
              // ("yearly horizontal tam eşit dağılmıyor", #v33.2)
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var c = 0; c < monthsPerRow; c++)
                    monthBlock(row * monthsPerRow + c + 1),
                ],
              ),
            ),
        ],
      );

      if (callout == null) return grid;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        grid,
        const SizedBox(height: 8),
        callout!,
      ]);
    });
  }
}

/// VERTICAL: Daylio's "Year in Pixels" shape — 12 month columns × up to 31
/// day rows, one cell per calendar day, squares instead of Daylio's dots
/// (#v31.13, reference: feedback signal-2026-07-08-00-59-41-671.png).
class _YearGridVertical extends StatelessWidget {
  final Map<int, int> days;
  final int color, today, year, frameColor;
  final String lang;
  final void Function(int day)? onDayTap;
  final Widget? callout;
  const _YearGridVertical(
      {super.key,
      required this.days, required this.color, required this.today, required this.year,
      required this.frameColor, required this.lang, this.onDayTap, this.callout});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      const dayColW = 16.0; // fits "31"
      // tile the 12 month columns across the width left of the day-number
      // gutter, so the grid fills edge-to-edge with no dead strip and stays
      // crisp — "yearly vertical de aynı şekilde" (#v33.2)
      final (cell, gaps) = _tileRow(box.maxWidth - dayColW, 12);
      double gapAt(int c) => c < gaps.length ? gaps[c] : 0.0;

      Widget monthInitial(int m) {
        final text = monthName(lang, m)[0].toUpperCase();
        return SizedBox(
          width: cell,
          child: Center(child: Text(text, style: pixelStyle(lang, 7, col(frameColor), text: text))),
        );
      }

      Widget dayRow(int dNum) => Padding(
            padding: EdgeInsets.only(bottom: dNum == 31 ? 0 : 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: dayColW,
                  child: Text('$dNum', style: pixelStyle(lang, 7, col(frameColor), text: '$dNum')),
                ),
                for (var m = 1; m <= 12; m++)
                  Builder(builder: (_) {
                    final lastDay = DateTime.utc(year, m + 1, 0).day;
                    final gap = m < 12 ? gapAt(m - 1) : 0.0;
                    if (dNum > lastDay) {
                      // faint filler for the short months' tails (#v32)
                      return _dayCell(
                          cell: cell, blank: true, dayColor: null, color: color, tooltip: null, gap: gap);
                    }
                    final day = epochDayOf(DateTime.utc(year, m, dNum));
                    final future = day > today;
                    final active = !future && (days[day] ?? 0) > 0;
                    return _dayCell(
                      cell: cell,
                      blank: false,
                      dayColor: future ? null : (active ? color : null),
                      color: color,
                      tooltip: null,
                      gap: gap,
                      onTap: future || onDayTap == null ? null : () => onDayTap!(day),
                    );
                  }),
              ],
            ),
          );

      final grid = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const SizedBox(width: dayColW),
            for (var m = 1; m <= 12; m++) ...[
              monthInitial(m),
              if (m < 12) SizedBox(width: gapAt(m - 1)),
            ],
          ]),
          const SizedBox(height: 4),
          for (var d = 1; d <= 31; d++) dayRow(d),
        ],
      );

      if (callout == null) return grid;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        grid,
        const SizedBox(height: 8),
        callout!,
      ]);
    });
  }
}

/// HabitKit-style contribution grid: 7 rows (weekdays) × N week columns. A day
/// is BINARY — completed once or many looks identical (full habit color);
/// empty days are a faint theme square (the user's rule), and FUTURE days
/// inside the span render the same faint square, so the grid is always fully
/// boxed — e.g. the current week always shows all 7 boxes and Wednesday's box
/// colours in when Wednesday is focused (#v31.1 item 2).
///
/// The span is either trailing 18 weeks ending at the current week (default —
/// the rolling 18-weeks view drops the oldest column as a new week starts) or
/// an explicit [spanStart]..[spanEnd] window (monthly = the calendar month,
/// yearly = the calendar year). Columns are Monday-aligned weeks; days outside
/// the span render blank. Past one band's width (18 columns, tuned to fit a
/// phone) the grid stacks bands downward IN CHRONOLOGICAL ORDER — full 18-week
/// bands first, the partial remainder LAST (#v31.1 item 3: yearly reads
/// 18 + 18 + the rest of the year).
///
/// [selectedDay] + [callout] float a TREND-style callout next to the tapped
/// cell, overlaying the grid like the chart's own callout (#v31.1 item 2).
class _HabitHeatmap extends StatelessWidget {
  final Map<int, int> days;
  final int color, today;
  // optional per-day color override (e.g. mood level) instead of the binary
  // done/not-done color (#v30). optional upper bound on cell size so a
  // relocated, frameless heatmap can stretch edge-to-edge (#v30 item 6).
  final int? Function(int day)? colorForDay;
  final double maxCellSize;
  final int? spanStart, spanEnd; // explicit window (epochDays), else trailing 18 weeks
  // optional tap-for-details text shown in a Tooltip (goals cards keep this).
  final String? Function(int day)? tooltipFor;
  // optional tap handler for in-span, non-future cells (#v30.9 — the mood
  // heatmap edits past days; focus sessions show the callout).
  final void Function(int day)? onDayTap;
  final int? selectedDay;
  final Widget? callout;
  // size cells to the ACTUAL column count instead of the 18-column budget —
  // lets a ~5-column month grid stay readable inside a third-width slot
  // (#v31.2 item 2: monthly is 3 labels side by side again).
  final bool fitCols;
  const _HabitHeatmap(
      {super.key,
      required this.days, required this.color, required this.today,
      this.colorForDay, this.maxCellSize = 12.0,
      this.spanStart, this.spanEnd, this.tooltipFor, this.onDayTap,
      this.selectedDay, this.callout, this.fitCols = false});

  static const _bandCols = 18; // per-band width, tuned to fit a phone

  @override
  Widget build(BuildContext context) {
    final todayWeekday = dateOfEpochDay(today).weekday; // 1=Mon
    // default = trailing 18 weeks ending on Sunday of the current week
    final hi = spanEnd ?? (today - (todayWeekday - 1) + 6);
    final lo = spanStart ?? (hi - 6 - 17 * 7);
    final startMonday = lo - (dateOfEpochDay(lo).weekday - 1);
    final endMonday = hi - (dateOfEpochDay(hi).weekday - 1);
    final cols = (endMonday - startMonday) ~/ 7 + 1;
    final numBands = (cols / _bandCols).ceil().clamp(1, 1000000);
    return LayoutBuilder(builder: (context, box) {
      // every cell (incl. the last) carries a 2px right margin, so the
      // budget must divide out bandCols*2, not (bandCols-1)*2 — the old
      // formula under-budgeted by one gap, always rendering 2px too wide.
      // Masked for years by the 12px cap; exposed once a caller removes the
      // cap to stretch full-width (#v30 item 6).
      final divisor = fitCols ? math.min(cols, _bandCols) : _bandCols;
      // tile the full-band width, then cap: a capped cell can't fill the row,
      // so when maxCellSize bites we fall back to a fixed 2px gap and let the
      // grid sit left (the caller asked for a small readable grid, not a
      // stretched one). Uncapped (the Focus Sessions / Session Heatmap case,
      // maxCellSize == infinity) the tiled gaps fill the width exactly (#v33.1).
      var (cell, gaps) = _tileRow(box.maxWidth, divisor);
      if (cell > maxCellSize) {
        cell = maxCellSize;
        gaps = [for (var i = 0; i < divisor - 1; i++) 2.0];
      }
      final grid = Column(
        children: [
          // chronological: oldest full band on top, the partial remainder last
          for (var b = 0; b < numBands; b++) ...[
            if (b != 0) const SizedBox(height: 6),
            _band(b, math.min(_bandCols, cols - b * _bandCols), startMonday, lo, hi, cell, gaps),
          ],
        ],
      );
      if (selectedDay == null || callout == null || selectedDay! < lo || selectedDay! > hi) {
        return grid;
      }
      // float the callout right next to the tapped cell, like the trend
      // chart's callout (#v31.1 item 2 — it used to sit bottom-left).
      final selMonday = selectedDay! - (dateOfEpochDay(selectedDay!).weekday - 1);
      final selCol = (selMonday - startMonday) ~/ 7;
      final b = selCol ~/ _bandCols, c = selCol % _bandCols;
      final row = dateOfEpochDay(selectedDay!).weekday - 1;
      final bandH = 7 * (cell + 2);
      // cell left edge = running sum of the tiled gaps before column c (#v33.1)
      var cellX = 0.0;
      for (var i = 0; i < c && i < gaps.length; i++) {
        cellX += cell + gaps[i];
      }
      final cellY = b * (bandH + 6) + row * (cell + 2);
      final totalH = numBands * bandH + (numBands - 1) * 6;
      const estW = 140.0, estH = 44.0;
      final left = cellX.clamp(0.0, math.max(0.0, box.maxWidth - estW)).toDouble();
      final top = (cellY + cell + 4 + estH > totalH + estH / 2
              ? math.max(0.0, cellY - estH) // bottom rows: pop above the cell
              : cellY + cell + 4)
          .toDouble();
      return Stack(clipBehavior: Clip.none, children: [
        grid,
        Positioned(left: left, top: top, child: callout!),
      ]);
    });
  }

  Widget _band(int b, int colsInBand, int startMonday, int lo, int hi, double cell, List<double> gaps) {
    // The band is 7 rows x up to 18 columns, PER LABEL — on Sessions in Pixels
    // that came to ~900 Containers and ~900 GestureDetectors, the bulk of the
    // 9,749 widgets that stopped the page scrolling (#v34.7). Paint it in one
    // pass instead. The widget path stays for the Year-in-Pixels habit cards,
    // which attach a per-cell Tooltip (long-press) that a painted grid has no
    // way to carry.
    if (tooltipFor == null) {
      int dayAt(int i) => startMonday + (b * _bandCols + (i % colsInBand)) * 7 + (i ~/ colsInBand);
      return CellGrid(
        cols: colsInBand,
        count: 7 * colsInBand,
        cell: cell,
        gaps: gaps,
        rowGap: 2,
        fillOf: (i) {
          final day = dayAt(i);
          final blank = day < lo || day > hi; // outside the span
          final future = !blank && day > today; // boxed but faint, inert
          final dayColor = blank || future
              ? null
              : (colorForDay != null ? colorForDay!(day) : ((days[day] ?? 0) > 0 ? color : null));
          return cellFill(blank: blank, dayColor: dayColor, color: color);
        },
        onTapCell: onDayTap == null
            ? null
            : (i) {
                final day = dayAt(i);
                if (day >= lo && day <= hi && day <= today) onDayTap!(day);
              },
      );
    }
    return Column(
      children: [
        for (var row = 0; row < 7; row++)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              children: [
                for (var c = 0; c < colsInBand; c++)
                  Builder(builder: (_) {
                    final day = startMonday + (b * _bandCols + c) * 7 + row;
                    final blank = day < lo || day > hi; // outside the span
                    final future = !blank && day > today; // boxed but faint, inert
                    final dayColor = blank || future
                        ? null
                        : (colorForDay != null ? colorForDay!(day) : ((days[day] ?? 0) > 0 ? color : null));
                    return _dayCell(
                        cell: cell, blank: blank, dayColor: dayColor, color: color,
                        // last real column gets no trailing gap, so a full band
                        // ends flush on the right; a partial band just stops
                        // short but still lines up under the full ones (#v33.1)
                        gap: c < colsInBand - 1 && c < gaps.length ? gaps[c] : 0,
                        tooltip: blank || future ? null : tooltipFor?.call(day),
                        onTap: blank || future || onDayTap == null ? null : () => onDayTap!(day));
                  }),
              ],
            ),
          ),
      ],
    );
  }
}
