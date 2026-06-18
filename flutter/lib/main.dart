import 'package:flutter/material.dart';

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
    return MaterialApp(
      title: 'Pixel Pomo',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: messengerKey,
      home: HomeScreen(store),
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
        {double fontSize = 13, EdgeInsets padding = const EdgeInsets.all(14), double opacity = 1}) =>
    PixelButton(
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
        return Scaffold(
          backgroundColor: col(th.bg),
          body: SafeArea(
            child: Column(
              children: [
                _topBar(context, th, lang),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(modeText, style: pixelStyle(lang, 22, col(modeColor), spacing: 2)),
                        const SizedBox(height: 16),
                        secondaryBtn(th, lang, s.currentLabel, () => openPanel(context, s, () => LabelScreen(s)),
                            fontSize: 11, padding: const EdgeInsets.all(10)),
                        const SizedBox(height: 28),
                        Text(e.formattedTime(), style: pixelStyle(lang, 48, col(th.onSurface))),
                        const SizedBox(height: 32),
                        PixelProgress(
                            percent: e.progressPercent(),
                            track: th.panel,
                            border: th.onSurfaceDim,
                            fill: e.isFinished ? th.accent : th.phaseColor(e.mode)),
                        const SizedBox(height: 36),
                        Row(
                          children: [
                            Expanded(
                                child: primaryBtn(th, lang, t(lang, e.isRunning ? 'pause' : 'start'),
                                    s.toggleStartPause, fontSize: 14, padding: const EdgeInsets.all(16))),
                            const SizedBox(width: 16),
                            Expanded(
                                child: secondaryBtn(th, lang, t(lang, 'reset'), s.reset,
                                    fontSize: 14, padding: const EdgeInsets.all(16))),
                          ],
                        ),
                        const SizedBox(height: 24),
                        GestureDetector(
                          onTap: s.switchMode,
                          child: Text(t(lang, 'switchMode'), style: pixelStyle(lang, 10, col(th.onSurfaceDim))),
                        ),
                        const SizedBox(height: 24),
                        Text(tf(lang, 'session', [e.session, e.totalSessions]),
                            style: pixelStyle(lang, 12, col(th.onSurfaceDim))),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _iconBtn(IconData icon, int color, VoidCallback onTap) =>
      IconButton(icon: Icon(icon, color: col(color), size: 28), onPressed: onTap);

  Widget _topBar(BuildContext context, PixelTheme th, String lang) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          _iconBtn(Icons.palette, th.onSurface, () => openPanel(context, s, () => ThemeScreen(s))),
          _iconBtn(Icons.local_florist, th.onSurface, () => openPanel(context, s, () => GardenScreen(s))),
          const Spacer(),
          _iconBtn(Icons.bar_chart, th.onSurface, () => openPanel(context, s, () => StatsScreen(s))),
          _iconBtn(Icons.settings, th.onSurface, () => openPanel(context, s, () => SettingsScreen(s))),
          GestureDetector(
            key: const Key('shopButton'),
            onTap: () => openPanel(context, s, () => ShopScreen(s)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  const GoldCoin(size: 32),
                  const SizedBox(width: 8),
                  Text('${s.coins}', style: pixelStyle(lang, 14, col(th.onSurface))),
                ],
              ),
            ),
          ),
        ],
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
            child: selected
                ? primaryBtn(th, lang, '> $label', () => s.selectLabel(label))
                : secondaryBtn(th, lang, label, () => s.selectLabel(label)),
          ),
          IconButton(
            icon: Icon(Icons.delete, color: col(th.onSurfaceDim)),
            onPressed: () => _confirmDelete(context, s, label),
          ),
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
    final totals = StatsAggregator.aggregate(s.records, DateTime.now());
    final byLabel = StatsAggregator.byLabelInMonth(s.records, s.viewYear, s.viewMonth);
    final series = StatsAggregator.dailySeries(s.records, s.viewYear, s.viewMonth);
    final monthTitle = '${monthName(lang, s.viewMonth)} ${s.viewYear}';

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
      Row(
        children: [
          secondaryBtn(th, lang, '<', () => s.shiftMonth(-1), fontSize: 13, padding: const EdgeInsets.all(12)),
          Expanded(child: Center(child: Text(monthTitle, style: pixelStyle(lang, 12, col(th.onSurface))))),
          PixelButton(
              text: '>', fill: th.panel, border: th.onSurfaceDim, textColor: th.onSurface, shadow: th.shadow,
              lang: lang, fontSize: 13, padding: const EdgeInsets.all(12),
              opacity: s.canGoNextMonth ? 1 : 0.35, onTap: () => s.shiftMonth(1)),
        ],
      ),
      const SizedBox(height: 12),
      Row(children: [chartBtn(t(lang, 'chartBar'), ChartMode.bar), chartBtn(t(lang, 'chartLine'), ChartMode.line), chartBtn(t(lang, 'chartPie'), ChartMode.pie)]),
      const SizedBox(height: 16),
      SizedBox(
        height: 190,
        child: StatsChart(
          entries: [for (final e in byLabel) ChartEntry(e.key, e.value, s.labelColorOf(e.key))],
          daySeries: series,
          mode: s.chartMode,
          lang: lang,
          axisColor: th.onSurfaceDim,
          textColor: th.onSurface,
          lineColor: th.accent,
        ),
      ),
      const SizedBox(height: 16),
      statRow(t(lang, 'today'), totals.today),
      statRow(t(lang, 'week'), totals.week),
      statRow(t(lang, 'month'), totals.month),
      statRow(t(lang, 'year'), totals.year),
      statRow(t(lang, 'all'), totals.all),
      const SizedBox(height: 16),
      Text(tf(lang, 'byLabelMonth', [monthTitle]), style: pixelStyle(lang, 11, col(th.onSurfaceDim))),
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

class GardenScreen extends StatelessWidget {
  final AppStore s;
  const GardenScreen(this.s, {super.key});

  @override
  Widget build(BuildContext context) {
    final th = s.theme;
    final lang = s.lang;
    final cost = Economy.upgradeCost(s.garden.size);

    return Scaffold(
      backgroundColor: col(th.bg),
      body: SafeArea(
        child: Column(
          children: [
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(t(lang, 'gardenHelp'), style: pixelStyle(lang, 8, col(th.onSurfaceDim))),
            ),
            const SizedBox(height: 8),
            // the live 2.5D scene fills the remaining space
            Expanded(
              child: FutureBuilder<SpriteBank>(
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
                    lang: lang,
                    tr: (k) => t(lang, k),
                  );
                },
              ),
            ),
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
