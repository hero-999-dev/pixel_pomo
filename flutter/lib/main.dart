import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'camera.dart';
import 'engine/garden_engine.dart';
import 'engine/garden_view.dart';
import 'icons.dart';
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

Future<IconBank>? _iconsFuture;
Future<IconBank> menuIcons() => _iconsFuture ??= IconBank.load();

final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = AppStore();
  await store.load();
  runApp(PixelPomoApp(store));
}

class PixelPomoApp extends StatelessWidget {
  final AppStore store;
  const PixelPomoApp(this.store, {super.key});

  @override
  Widget build(BuildContext context) {
    store.messenger = (key) {
      messengerKey.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(t(store.lang, key), style: pixelStyle(store.lang, 11, const Color(0xFFFFFFFF))),
          duration: const Duration(seconds: 2),
        ));
    };
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
        {double fontSize = 13, EdgeInsets padding = const EdgeInsets.all(14), double opacity = 1}) =>
    PixelButton(
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
            Center(child: Text(title, style: pixelStyle(s.lang, 20, col(th.onSurface), spacing: 2))),
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
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!s.awaitingBreakPrompt) return;
            s.awaitingBreakPrompt = false; // guard against re-entry
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: col(th.panel),
                title: Text(t(lang, 'startBreakTitle'), style: pixelStyle(lang, 12, col(th.onSurface))),
                actions: [
                  TextButton(onPressed: () { Navigator.pop(ctx); s.confirmBreak(false); },
                      child: Text(t(lang, 'no'), style: pixelStyle(lang, 11, col(th.onSurfaceDim)))),
                  TextButton(onPressed: () { Navigator.pop(ctx); s.confirmBreak(true); },
                      child: Text(t(lang, 'yes'), style: pixelStyle(lang, 11, col(th.accent)))),
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
        final timerBlock = Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(modeText, style: pixelStyle(lang, 22, col(modeColor), spacing: 2).copyWith(shadows: shadows)),
            const SizedBox(height: 16),
            secondaryBtn(th, lang, s.currentLabel, () => openPanel(context, s, () => LabelScreen(s)),
                fontSize: 11, padding: const EdgeInsets.all(10)),
            const SizedBox(height: 28),
            Text(e.formattedTime(), style: pixelStyle(lang, 48, col(th.onSurface)).copyWith(shadows: shadows)),
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
            style: pixelStyle(lang, 12, col(garden ? th.onSurface : th.onSurfaceDim)).copyWith(shadows: shadows));

        return Scaffold(
          backgroundColor: col(th.bg),
          body: Stack(
            children: [
              // live garden behind the timer when HOME mode = GARDEN (#3)
              if (garden) Positioned.fill(child: _liveBackdrop(th, lang)),
              SafeArea(
                child: garden
                    // garden mode: session up top in the empty band, timer docked
                    // at the bottom over the full-strength garden (#5)
                    ? Column(children: [
                        _topBar(context, th, lang),
                        sessionText,
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

  Widget _topBar(BuildContext context, PixelTheme th, String lang) {
    // custom pixel icons (#3): left = theme/garden/stats · right = settings/store/coin (#4)
    Widget iconBtn(IconBank? bank, int sheetCol, bool fromStore, VoidCallback onTap, Key? key) {
      final child = bank == null
          ? const SizedBox(width: 30, height: 30)
          : MenuIcon(fromStore ? bank.store : bank.menu, sheetCol, size: 30);
      return IconButton(key: key, icon: child, onPressed: onTap);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: FutureBuilder<IconBank>(
        future: menuIcons(),
        builder: (context, snap) {
          final bank = snap.data;
          return Row(children: [
            iconBtn(bank, 0, false, () => openPanel(context, s, () => ThemeScreen(s)), const Key('themeButton')),
            iconBtn(bank, 1, false, () => openPanel(context, s, () => GardenScreen(s)), const Key('gardenButton')),
            iconBtn(bank, 2, false, () => openPanel(context, s, () => StatsScreen(s)), const Key('statsButton')),
            const Spacer(),
            iconBtn(bank, 3, false, () => openPanel(context, s, () => SettingsScreen(s)), const Key('settingsButton')),
            iconBtn(bank, 4, true, () => openPanel(context, s, () => ShopScreen(s)), const Key('storeButton')),
            GestureDetector(
              key: const Key('shopButton'),
              onTap: () => openPanel(context, s, () => ShopScreen(s)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(children: [
                  const GoldCoin(size: 28),
                  const SizedBox(width: 6),
                  Text('${s.coins}', style: pixelStyle(lang, 14, col(th.onSurface))),
                ]),
              ),
            ),
          ]);
        },
      ),
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

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final th = s.theme;
    final lang = s.lang;
    return overlayScaffold(context, s, t(lang, 'settings'), [
      _stepper(th, lang, t(lang, 'study'), work, 5, 300, 5, (v) => setState(() => work = v)),
      _stepper(th, lang, t(lang, 'breakMin'), brk, 1, 120, 1, (v) => setState(() => brk = v)),
      _stepper(th, lang, t(lang, 'sessions'), sess, 1, 24, 1, (v) => setState(() => sess = v)),
      const SizedBox(height: 24),
      Text(t(lang, 'language'), style: pixelStyle(lang, 12, col(th.onSurfaceDim))),
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
      Text(t(lang, 'homeMode'), style: pixelStyle(lang, 12, col(th.onSurfaceDim))),
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
      Text(t(lang, 'autoBreak'), style: pixelStyle(lang, 12, col(th.onSurfaceDim))),
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
      const SizedBox(height: 16),
      primaryBtn(th, lang, t(lang, 'save'), () {
        s.saveSettings(work, brk, sess);
        s.messenger?.call('settingsSaved');
        Navigator.pop(context);
      }, padding: const EdgeInsets.all(16)),
    ]);
  }

  Widget _stepper(PixelTheme th, String lang, String label, int value, int min, int max, int step, ValueChanged<int> onChange) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Expanded(child: Text(label, style: pixelStyle(lang, 11, col(th.onSurfaceDim)))),
          SizedBox(width: 52, child: secondaryBtn(th, lang, '-', () => onChange((value - step).clamp(min, max).toInt()), padding: const EdgeInsets.all(12))),
          Container(
            width: 56,
            alignment: Alignment.center,
            child: Text('$value', style: pixelStyle(lang, 14, col(th.onSurface))),
          ),
          SizedBox(width: 52, child: secondaryBtn(th, lang, '+', () => onChange((value + step).clamp(min, max).toInt()), padding: const EdgeInsets.all(12))),
        ],
      ),
    );
  }
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
      Text(t(lang, 'renameHint'), style: pixelStyle(lang, 8, col(th.onSurfaceDim))),
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
        title: Text(t(lang, 'renameTitle'), style: pixelStyle(lang, 12, col(th.onSurface))),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          maxLength: 12,
          style: pixelStyle(lang, 12, col(th.onSurface)),
          decoration: InputDecoration(counterText: '', filled: true, fillColor: col(th.bg)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t(lang, 'no'), style: pixelStyle(lang, 11, col(th.onSurfaceDim)))),
          TextButton(
              onPressed: () {
                s.renameLabel(label, ctrl.text);
                Navigator.pop(ctx);
              },
              child: Text(t(lang, 'save'), style: pixelStyle(lang, 11, col(th.accent)))),
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
        title: Text(t(s.lang, 'pickColor'), style: pixelStyle(s.lang, 12, col(th.onSurface))),
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
        title: Text(t(s.lang, 'removeTitle'), style: pixelStyle(s.lang, 12, col(th.onSurface))),
        content: Text(tf(s.lang, 'removeMsg', [label]), style: pixelStyle(s.lang, 10, col(th.onSurfaceDim))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t(s.lang, 'no'), style: pixelStyle(s.lang, 11, col(th.onSurfaceDim)))),
          TextButton(
              onPressed: () {
                s.deleteLabel(label);
                Navigator.pop(ctx);
              },
              child: Text(t(s.lang, 'yes'), style: pixelStyle(s.lang, 11, col(th.accent)))),
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
    final series = StatsAggregator.seriesFor(s.records, now, s.statPeriod, s.statOffset);
    final multiLine = s.statPeriod == StatPeriod.daily;
    final labelLines = multiLine
        ? [
            for (final ls in StatsAggregator.labelSeriesFor(s.records, now, s.statPeriod, s.statOffset))
              LabelLine(ls.label, s.labelColorOf(ls.label), ls.values)
          ]
        : null;

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
              Text(caption, style: pixelStyle(lang, 11, col(th.onSurfaceDim))),
              const Spacer(),
              Text(StatsAggregator.formatMinutes(minutes), style: pixelStyle(lang, 13, col(th.onSurface))),
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
              style: pixelStyle(lang, 11, col(th.onSurface))))),
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
          labelLines: labelLines,
          multiLine: multiLine,
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
      statRow(t(lang, 'today'), totals.today),
      statRow(t(lang, 'week'), totals.week),
      statRow(t(lang, 'month'), totals.month),
      statRow(t(lang, 'year'), totals.year),
      statRow(t(lang, 'all'), totals.all),
      const SizedBox(height: 16),
      Text(t(lang, 'byLabel'), style: pixelStyle(lang, 11, col(th.onSurfaceDim))),
      const SizedBox(height: 12),
      if (byLabel.isEmpty)
        Text(t(lang, 'chartNoData'), style: pixelStyle(lang, 9, col(th.onSurfaceDim)))
      else
        for (final e in byLabel)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Swatch(color: s.labelColorOf(e.key), border: th.onSurfaceDim, size: 16),
                const SizedBox(width: 10),
                Text(e.key, style: pixelStyle(lang, 11, col(th.onSurface))),
                const Spacer(),
                Text(StatsAggregator.formatMinutes(e.value), style: pixelStyle(lang, 11, col(th.onSurfaceDim))),
              ],
            ),
          ),
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

// ---- shop -------------------------------------------------------------------

class ShopScreen extends StatelessWidget {
  final AppStore s;
  const ShopScreen(this.s, {super.key});

  @override
  Widget build(BuildContext context) {
    final th = s.theme;
    final lang = s.lang;
    return overlayScaffold(context, s, t(lang, 'shop'), [
      Text(t(lang, 'shopHelp'), style: pixelStyle(lang, 9, col(th.onSurfaceDim))),
      const SizedBox(height: 20),
      for (final f in Flowers.all)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            children: [
              FlowerSprite(flower: f, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(f.nameIn(lang), style: pixelStyle(lang, 12, col(th.onSurface))),
                    const SizedBox(height: 6),
                    Text(tf(lang, 'owned', [s.owned[f.id] ?? 0]), style: pixelStyle(lang, 8, col(th.onSurfaceDim))),
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
        ),
      const SizedBox(height: 8),
      Text(t(lang, 'shopObjects'), style: pixelStyle(lang, 12, col(th.onSurfaceDim))),
      const SizedBox(height: 14),
      for (final id in Placeables.objectIds) _objectRow(s, th, lang, id),
    ]);
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
                Text(t(lang, id), style: pixelStyle(lang, 12, col(th.onSurface))),
                const SizedBox(height: 6),
                Text(tf(lang, 'owned', [s.owned[id] ?? 0]), style: pixelStyle(lang, 8, col(th.onSurfaceDim))),
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
        title: Text(t(lang, 'camera'), style: pixelStyle(lang, 12, col(th.onSurface))),
        children: [
          // SET AS LIVE WALLPAPER — sets the phone's home-screen wallpaper to the
          // captured frame (Android only; iOS has no API, so the option is hidden).
          if (Platform.isAndroid)
            SimpleDialogOption(
              onPressed: () async {
                final ok = await setPhoneWallpaper(bytes);
                if (ctx.mounted) Navigator.pop(ctx);
                if (ok) s.messenger?.call('wallpaperSet');
                _exitCamera();
              },
              child: Text(t(lang, 'setLiveWallpaper'), style: pixelStyle(lang, 11, col(th.onSurface))),
            ),
          SimpleDialogOption(
            onPressed: () async {
              final path = await saveBackdropPng(bytes);
              s.setGardenBackdrop(path);
              if (ctx.mounted) Navigator.pop(ctx);
              _exitCamera();
            },
            child: Text(t(lang, 'setBackdrop'), style: pixelStyle(lang, 11, col(th.onSurface))),
          ),
          SimpleDialogOption(
            onPressed: () async {
              await sharePng(bytes, 'pixel_pomo_garden.png');
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(t(lang, 'share'), style: pixelStyle(lang, 11, col(th.onSurface))),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t(lang, 'cancel'), style: pixelStyle(lang, 11, col(th.accent))),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final th = s.theme;
    final lang = s.lang;
    final cost = Economy.upgradeCost(s.garden.cols, s.garden.rows);
    // the static photo replaces the live scene in the garden section only when
    // not actively customizing or framing a new shot.
    final showStatic = s.gardenBackdropPath != null && !_camera && !s.customizing;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // while peeking, let the forest run edge-to-edge behind transparent bars (#5)
      value: _hudHidden
          ? const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent, systemNavigationBarColor: Colors.transparent)
          : systemOverlayFor(th),
      child: Scaffold(
      backgroundColor: col(th.bg),
      body: SafeArea(
        top: !_hudHidden,
        bottom: !_hudHidden,
        child: Column(
          children: [
            if (!_hudHidden)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Row(
                  children: [
                    Text(t(lang, 'garden'), style: pixelStyle(lang, 20, col(th.onSurface), spacing: 2)),
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
                child: Text(t(lang, 'gardenHelp'), style: pixelStyle(lang, 8, col(th.onSurfaceDim))),
              ),
            if (!_hudHidden) const SizedBox(height: 8),
            // the live 2.5D scene (or the static photo) fills the remaining space
            Expanded(
              child: showStatic
                  ? _staticBackdrop(s, th, lang)
                  : FutureBuilder<SpriteBank>(
                      future: gardenSprites(),
                      builder: (context, snap) {
                        if (!snap.hasData) {
                          return Center(child: Text('...', style: pixelStyle(lang, 16, col(th.onSurfaceDim))));
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
                          onPeek: () => setState(() => _peek = !_peek),
                          onCamera: _enterCamera,
                        );
                      },
                    ),
            ),
            if (_camera)
              Padding(
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
              )
            else if (!_peek)
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
      ),
    );
  }

  /// The captured static photo as the garden section's backdrop, with controls
  /// to retake (camera) or clear it (back to the live garden).
  Widget _staticBackdrop(AppStore s, PixelTheme th, String lang) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(File(s.gardenBackdropPath!), fit: BoxFit.cover, filterQuality: FilterQuality.none),
        Positioned(
          left: 6,
          bottom: 4,
          child: IconButton(
            key: const Key('cameraButton'),
            icon: Icon(Icons.photo_camera, size: 22, color: col(th.onSurface)),
            tooltip: t(lang, 'camera'),
            onPressed: _enterCamera,
          ),
        ),
        Positioned(
          right: 6,
          bottom: 4,
          child: TextButton(
            onPressed: () => s.setGardenBackdrop(null),
            child: Text(t(lang, 'clearBackdrop'), style: pixelStyle(lang, 9, col(th.onSurface))),
          ),
        ),
      ],
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
        title: Text(t(lang, current == null ? 'pickFlower' : 'garden'), style: pixelStyle(lang, 12, col(th.onSurface))),
        children: [
          if (current != null)
            SimpleDialogOption(
              onPressed: () {
                s.clearTile(index);
                Navigator.pop(ctx);
              },
              child: Text(t(lang, 'clearTile'), style: pixelStyle(lang, 11, col(th.accent))),
            ),
          for (final f in flowers)
            _placeOption(ctx, s, th, lang, index, f.id, FlowerSprite(flower: f, size: 24), f.nameIn(lang)),
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
          Text('$name  x${s.availableOf(id)}', style: pixelStyle(lang, 11, col(th.onSurface))),
        ],
      ),
    );
  }
}
