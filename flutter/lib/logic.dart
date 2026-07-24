// Pure, framework-free app logic — a direct Dart port of the Android app's Kotlin classes
// (PomodoroEngine, PixelTheme, Flowers, Economy, Garden, Labels, LabelColors, Stats). No
// Flutter imports here on purpose, so the same rules can be unit-tested and reused unchanged.

import 'dart:math' as math;

// ---- timer engine -----------------------------------------------------------

enum Mode { work, breakMode }

class PomodoroEngine {
  final int workMillis;
  final int breakMillis;
  final int totalSessions;
  Mode mode = Mode.work;
  int timeLeftMillis;
  bool isRunning = false;
  int session = 1;
  bool isFinished = false;

  PomodoroEngine({
    int workMillis = 25 * 60 * 1000,
    int breakMillis = 5 * 60 * 1000,
    this.totalSessions = 4,
  })  : workMillis = workMillis,
        breakMillis = breakMillis,
        timeLeftMillis = workMillis;

  int durationOf(Mode t) => t == Mode.work ? workMillis : breakMillis;

  /// True once a run has been started and hasn't fully finished — a
  /// settings change made while this holds should wait to apply until it's
  /// false again, so editing work/break minutes mid-session doesn't yank
  /// the current pomodoro's progress out from under the user (#v31.15).
  bool get inProgress =>
      !isFinished && (isRunning || session > 1 || mode != Mode.work || timeLeftMillis != workMillis);

  void start() {
    if (!isFinished && timeLeftMillis > 0) isRunning = true;
  }

  void pause() => isRunning = false;

  void reset() {
    isRunning = false;
    isFinished = false;
    session = 1;
    mode = Mode.work;
    timeLeftMillis = workMillis;
  }

  void switchMode() {
    isRunning = false;
    isFinished = false;
    mode = mode == Mode.work ? Mode.breakMode : Mode.work;
    timeLeftMillis = durationOf(mode);
  }

  void setTimeLeft(int millis) {
    timeLeftMillis = millis.clamp(0, durationOf(mode)).toInt();
  }

  Mode finishPhase() {
    final finished = mode;
    isRunning = false;
    if (finished == Mode.work) {
      mode = Mode.breakMode;
      timeLeftMillis = breakMillis;
    } else if (session >= totalSessions) {
      isFinished = true;
      mode = Mode.work;
      timeLeftMillis = workMillis;
    } else {
      session++;
      mode = Mode.work;
      timeLeftMillis = workMillis;
    }
    return finished;
  }

  int progressPercent() {
    final total = durationOf(mode);
    if (total <= 0) return 0;
    return ((timeLeftMillis * 100) ~/ total).clamp(0, 100).toInt();
  }

  String formattedTime() {
    final totalSeconds = (timeLeftMillis + 999) ~/ 1000;
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// A plain count-up timer for Stopwatch mode (#v31.16) — no work/break
/// cycling, no fixed duration, no session count; the user decides when to
/// stop. HH only appears once elapsed passes an hour.
class StopwatchTimer {
  bool isRunning = false;
  int elapsedMillis = 0;

  void start() => isRunning = true;
  void pause() => isRunning = false;

  void reset() {
    isRunning = false;
    elapsedMillis = 0;
  }

  void setElapsed(int millis) => elapsedMillis = millis < 0 ? 0 : millis;

  String formattedTime() {
    final totalSeconds = elapsedMillis ~/ 1000;
    final h = totalSeconds ~/ 3600;
    final m = ((totalSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '${h.toString().padLeft(2, '0')}:$m:$s' : '$m:$s';
  }
}

// ---- themes -----------------------------------------------------------------

class PixelTheme {
  final String id;
  final String displayName;
  final int bg, panel, accent, work, breakColor, onSurface, onSurfaceDim, onAccent, shadow;

  /// Overrides the focus-phase colour for themes that must not tie it to the
  /// accent (#v32.4). Null on every preset, so they keep the #v32.1 behaviour.
  final int? focusColor;

  const PixelTheme({
    required this.id,
    required this.displayName,
    required this.bg,
    required this.panel,
    required this.accent,
    required this.work,
    required this.breakColor,
    required this.onSurface,
    required this.onSurfaceDim,
    required this.onAccent,
    required this.shadow,
    this.focusColor,
  });

  // FOCUS wears the theme's own accent so the home screen carries each
  // theme's identity (the per-theme `work` greens all read the same, #v32.1);
  // BREAK keeps the per-theme break colour. `work` itself stays for the
  // money tracker's income/expense colouring.
  int get focusTint => focusColor ?? accent;

  int phaseColor(Mode m) => m == Mode.work ? focusTint : breakColor;

  /// A user-built theme (#v32.3). Every colour the user can point at on screen
  /// is picked outright — background, the two text colours, the selected
  /// square, the other squares, BREAK and the money tracker's income colour.
  /// `onAccent` and `shadow` are the only derived ones, and only because they
  /// are mechanical rather than chosen: the label inside the selected square
  /// has to stay readable *on* that square whatever it is, and the pixel shadow
  /// is the background's own dark edge.
  ///
  /// Every pick is contrast-corrected against what it is drawn on, so no
  /// combination can produce an unreadable screen — see [nudgeContrast].
  factory PixelTheme.custom({
    required int bg,
    required int onSurface,
    required int onSurfaceDim,
    required int accent,
    required int panel,
    required int breakColor,
    required int work,
  }) {
    // The squares have to separate from the background (the stats grid and the
    // pixel logs are `panel` cells), and the selected one from the others.
    final fixedPanel = nudgeContrast(panel, bg, kMinFillContrast);
    final fixedAccent = nudgeContrast(accent, fixedPanel, kMinFillContrast);
    return PixelTheme(
      id: customThemeId,
      displayName: 'CUSTOM',
      bg: bg,
      panel: fixedPanel,
      accent: fixedAccent,
      // BREAK is a big countdown and income is a money row: both are measured
      // against the background, the surface they mostly sit on, at the large-text
      // bar — holding them to the body-text bar would wash the pick out.
      work: nudgeContrast(work, bg, kMinDimTextContrast),
      breakColor: nudgeContrast(breakColor, bg, kMinDimTextContrast),
      // Corrected against the background, the surface they are mostly read on.
      // Where they land on a button instead, `PixelButton` corrects them against
      // that button's own fill (#v32.5) — demanding one colour clear both is
      // often unsatisfiable, and it is headings that would pay for it.
      onSurface: nudgeContrast(onSurface, bg, kMinTextContrast),
      onSurfaceDim: nudgeContrast(onSurfaceDim, bg, kMinDimTextContrast),
      onAccent: nudgeContrast(onSurface, fixedAccent, kMinTextContrast),
      // A light theme's shadow is its own background gone a little darker; only
      // a dark one wants near-black. The single 0.6 mix put hard black bars
      // under every button of a cream custom theme, which is a good part of why
      // a preset rebuilt here "didn't go together" (#v33.4).
      shadow: mixColors(bg, 0xFF000000, _relLuminance(bg) > 0.35 ? 0.18 : 0.6),
      // The countdown must not follow the selected square (#v32.4): picking a
      // dark square used to sink the clock into the background. TEXT 1 is
      // already contrast-corrected against the background, so it always reads.
      focusColor: nudgeContrast(onSurface, bg, kMinTextContrast),
    );
  }

  /// [PixelTheme.custom] fed from the picker's slot order — the one place that
  /// order is spelled out, shared by the editor and the saved spec.
  ///
  /// A preset loaded in the editor and left alone comes back as ITSELF (#v33.4).
  /// [PixelTheme.custom] derives `shadow`, `onAccent` and `focusColor` by
  /// formula, so LATTE rebuilt through it was a visibly different theme than
  /// LATTE — "pressing latte in custom doesn't give the same thing". Only picks
  /// the user actually changed go through the derivation.
  factory PixelTheme.fromPicks(List<int> p) {
    for (final preset in Themes.all) {
      if (_samePicks(preset.picks, p)) return preset.asCustom;
    }
    return PixelTheme.custom(
      bg: p[0],
      onSurface: p[1],
      onSurfaceDim: p[2],
      accent: p[3],
      panel: p[4],
      breakColor: p[5],
      work: p[6],
    );
  }

  /// This theme's colours as editor picks, so the editor can start from any theme.
  List<int> get picks => [bg, onSurface, onSurfaceDim, accent, panel, breakColor, work];

  /// This theme wearing the custom id, so a preset loaded whole in the editor
  /// can be saved and worn as the user's own without losing a single colour.
  PixelTheme get asCustom => PixelTheme(
        id: customThemeId,
        displayName: 'CUSTOM',
        bg: bg,
        panel: panel,
        accent: accent,
        work: work,
        breakColor: breakColor,
        onSurface: onSurface,
        onSurfaceDim: onSurfaceDim,
        onAccent: onAccent,
        shadow: shadow,
        focusColor: focusColor,
      );
}

// ---- custom theme colour maths (#v32.3) ---------------------------------------

const String customThemeId = 'custom';

/// Body text against its background — WCAG AA.
const double kMinTextContrast = 4.5;

/// Dim/secondary text against its background — WCAG AA for large text.
const double kMinDimTextContrast = 3.0;

/// A filled square against what sits behind it. Far below the text bar on
/// purpose: two squares only need to be *told apart*, not read.
const double kMinFillContrast = 1.25;

/// WCAG relative luminance of an opaque ARGB colour.
double _relLuminance(int argb) {
  double channel(int shift) {
    final s = ((argb >> shift) & 0xFF) / 255.0;
    return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0);
}

/// WCAG contrast ratio between two opaque colours: 1.0 (identical) … 21.0
/// (black on white).
double contrastRatio(int a, int b) {
  final la = _relLuminance(a), lb = _relLuminance(b);
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// [a] blended [t] of the way toward [b] (0 = a, 1 = b), always opaque.
int mixColors(int a, int b, double t) {
  int channel(int shift) {
    final av = (a >> shift) & 0xFF, bv = (b >> shift) & 0xFF;
    return (av + (bv - av) * t).round().clamp(0, 255);
  }

  return 0xFF000000 | (channel(16) << 16) | (channel(8) << 8) | channel(0);
}

/// An opaque colour as `[hue 0..360, saturation 0..1, lightness 0..1]`.
/// Hand-rolled rather than `HSLColor` so this file stays framework-free.
List<double> _toHsl(int argb) {
  final r = ((argb >> 16) & 0xFF) / 255, g = ((argb >> 8) & 0xFF) / 255, b = (argb & 0xFF) / 255;
  final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
  final l = (mx + mn) / 2;
  final d = mx - mn;
  if (d == 0) return [0, 0, l]; // grey: no hue or saturation to keep
  final s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
  final h = mx == r
      ? (g - b) / d % 6
      : mx == g
          ? (b - r) / d + 2
          : (r - g) / d + 4;
  return [(h * 60 + 360) % 360, s, l];
}

int _fromHsl(double h, double s, double l) {
  if (s == 0) {
    final v = (l * 255).round().clamp(0, 255);
    return 0xFF000000 | (v << 16) | (v << 8) | v;
  }
  final q = l < 0.5 ? l * (1 + s) : l + s - l * s;
  final p = 2 * l - q;
  int channel(double t) {
    var x = (t + 360) % 360 / 360;
    final v = x < 1 / 6
        ? p + (q - p) * 6 * x
        : x < 1 / 2
            ? q
            : x < 2 / 3
                ? p + (q - p) * (2 / 3 - x) * 6
                : p;
    return (v * 255).round().clamp(0, 255);
  }

  return 0xFF000000 | (channel(h + 120) << 16) | (channel(h) << 8) | channel(h - 120);
}

/// [fg] made lighter or darker until it clears [min] contrast against [bg].
///
/// Only *lightness* moves; hue and saturation are held (#v32.5). Blending
/// toward black in RGB — what this used to do — scales every channel, and
/// therefore scales chroma with it: a bright yellow pushed dark enough to read
/// came back a near-grey olive, which is why picked colours "didn't feel like
/// they landed". Moving lightness in HSL keeps roughly five times the chroma
/// at the same brightness, so the result still reads as the colour that was
/// tapped.
///
/// Some combinations cannot reach [min] anywhere (grey on grey caps out around
/// 5:1); the best attempt is returned rather than refusing the save, so the
/// picker never dead-ends.
int nudgeContrast(int fg, int bg, double min) {
  var best = fg, bestRatio = contrastRatio(fg, bg);
  if (bestRatio >= min) return fg;
  final hsl = _toHsl(fg);
  // Of every lightness that clears the bar, keep the one that holds the most
  // colour rather than the one closest to the pick's own lightness. Those are
  // not the same choice: a pale lavender on mid-grey clears three steps up, at
  // pure white — the nearest, and the one answer with no colour left in it.
  // Darkening has to cross a contrast trough first, but comes out the other
  // side still lavender. Greys have no chroma to compare, so they fall through
  // to the first (nearest) candidate that clears, as before.
  int? kept;
  var keptChroma = -1.0;
  for (var step = 1; step <= 20; step++) {
    for (final dir in const [-1, 1]) {
      final candidate = _fromHsl(hsl[0], hsl[1], (hsl[2] + dir * step / 20).clamp(0.0, 1.0));
      final ratio = contrastRatio(candidate, bg);
      if (ratio >= min) {
        final chroma = _chroma(candidate);
        if (chroma > keptChroma) {
          keptChroma = chroma;
          kept = candidate;
        }
      } else if (ratio > bestRatio) {
        bestRatio = ratio;
        best = candidate;
      }
    }
  }
  return kept ?? best;
}

/// How much colour an opaque ARGB value carries, 0 (grey) … 1.
double _chroma(int argb) {
  final r = (argb >> 16) & 0xFF, g = (argb >> 8) & 0xFF, b = argb & 0xFF;
  return (math.max(r, math.max(g, b)) - math.min(r, math.min(g, b))) / 255;
}

/// An opaque colour as `[hue 0…360, saturation 0…1, lightness 0…1]`, and back
/// (#v33.5) — the colour wheel works in HSL, the rest of the app in ARGB.
List<double> hslOf(int argb) => _toHsl(argb);
int colorFromHsl(double h, double s, double l) => _fromHsl(h, s, l);

/// The hue and saturation under a point on a colour wheel: [dx]/[dy] measured
/// from its CENTRE, [radius] the wheel's own (#v33.5).
///
/// Outside the rim it clamps to full saturation instead of refusing, so a drag
/// that runs off the circle keeps picking rather than sticking at the edge.
List<double> wheelHueSat(double dx, double dy, double radius) {
  final hue = (math.atan2(dy, dx) * 180 / math.pi + 360) % 360;
  if (radius <= 0) return [hue, 0];
  return [hue, (math.sqrt(dx * dx + dy * dy) / radius).clamp(0.0, 1.0)];
}

bool _samePicks(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Where a colour belongs in a palette laid out similar-next-to-similar
/// (#v33.4): greys first darkest→lightest, then the hues in colour-wheel order
/// with each family's dark/mid/light shades together. One comparable number, so
/// ordering a palette is a plain `sort`.
///
/// Hues are grouped into 12 bins CENTRED on the primary hues rather than
/// starting at 0°: a family's shades drift a few degrees apart (this palette's
/// dark orange measures 28°, its light one 33°), and bins starting on the
/// boundary would split that trio across two of them.
double swatchOrder(int argb) {
  final hsl = _toHsl(argb);
  if (_chroma(argb) < 0.08) return hsl[2]; // greys: 0…1, below every hue
  final bin = (((hsl[0] + 15) % 360) ~/ 30);
  return 2 + bin * 2 + hsl[2]; // 2 apart so lightness can never cross bins
}

/// How many colours a custom theme is built from — see [customThemePicks].
const int kCustomSlots = 7;

/// `aarrggbb×7` holding the RAW picks — reopening the editor then shows what
/// the user chose, not the contrast-corrected result it was saved as.
String encodeCustomTheme(List<int> picks) => picks.map((c) => c.toRadixString(16)).join(',');

/// The seven raw picks in picker order — background, text 1, text 2, selected
/// square, squares, BREAK, income — or null if [spec] is missing or corrupt (an
/// older or hand-edited prefs value must not crash boot).
List<int>? customThemePicks(String? spec) {
  if (spec == null) return null;
  final parts = spec.split(',');
  if (parts.length != kCustomSlots) return null;
  final picks = <int>[];
  for (final p in parts) {
    final v = int.tryParse(p, radix: 16);
    if (v == null) return null;
    picks.add(v | 0xFF000000);
  }
  return picks;
}

PixelTheme? decodeCustomTheme(String? spec) {
  final picks = customThemePicks(spec);
  if (picks == null) return null;
  return PixelTheme.fromPicks(picks);
}

class Themes {
  static const dark = PixelTheme(
      id: 'dark', displayName: 'DARK',
      bg: 0xFF161616, panel: 0xFF262626, accent: 0xFFFF5A5F, work: 0xFF46E08A,
      breakColor: 0xFF58A6FF, onSurface: 0xFFF4F4F4, onSurfaceDim: 0xFF8E8E8E,
      onAccent: 0xFF1A1A1A, shadow: 0xFF000000);
  // Every theme gets its OWN accent hue (#v32; light/latte reworked #v32.1 —
  // the pure-white bg + blue accent light theme "tired the eyes": LIGHT now
  // wears the old latte cream palette with a slightly darker peach accent,
  // and LATTE went darker — deep cream + coffee-brown tones).
  static const light = PixelTheme(
      id: 'light', displayName: 'LIGHT',
      bg: 0xFFF7EFDD, panel: 0xFFFFFBF0, accent: 0xFFE85C0A, work: 0xFF40A02B,
      breakColor: 0xFF1E66F5, onSurface: 0xFF4C4F69, onSurfaceDim: 0xFF8A7F6A,
      onAccent: 0xFFFFFFFF, shadow: 0xFFD9CBB0);
  static const mocha = PixelTheme(
      id: 'mocha', displayName: 'MOCHA',
      bg: 0xFF1E1E2E, panel: 0xFF313244, accent: 0xFFF38BA8, work: 0xFFA6E3A1,
      breakColor: 0xFF89B4FA, onSurface: 0xFFCDD6F4, onSurfaceDim: 0xFFA6ADC8,
      onAccent: 0xFF1E1E2E, shadow: 0xFF11111B);
  static const frappe = PixelTheme(
      id: 'frappe', displayName: 'FRAPPE',
      bg: 0xFF303446, panel: 0xFF414559, accent: 0xFF81C8BE, work: 0xFFA6D189,
      breakColor: 0xFF8CAAEE, onSurface: 0xFFC6D0F5, onSurfaceDim: 0xFFA5ADCE,
      onAccent: 0xFF303446, shadow: 0xFF232634);
  static const latte = PixelTheme(
      id: 'latte', displayName: 'LATTE',
      bg: 0xFFEFE2C2, panel: 0xFFF6ECD4, accent: 0xFF6F4E37, work: 0xFF40A02B,
      breakColor: 0xFFB5793B, onSurface: 0xFF3E2F23, onSurfaceDim: 0xFF8A7355,
      onAccent: 0xFFF7EFDD, shadow: 0xFFCDB98F);
  // a green "matcha" theme matching the garden, in the Catppuccin family (#v19)
  static const matcha = PixelTheme(
      id: 'matcha', displayName: 'MATCHA',
      bg: 0xFF1A2420, panel: 0xFF2A3A30, accent: 0xFFA6E3A1, work: 0xFF94D977,
      breakColor: 0xFF89DCEB, onSurface: 0xFFCAD9C4, onSurfaceDim: 0xFF9DB09A,
      onAccent: 0xFF1A2420, shadow: 0xFF0F1611);

  static const all = [dark, light, mocha, frappe, latte, matcha];
  static const fallback = dark;

  static PixelTheme byId(String? id) {
    for (final t in all) {
      if (t.id == id) return t;
    }
    return fallback;
  }
}

// ---- flowers ----------------------------------------------------------------

const int flowerGreen = 0xFF46A03C;

class Flower {
  final String id;
  final Map<String, String> names;
  final int petal, center;
  final List<String> grid;
  const Flower(this.id, this.names, this.petal, this.center, this.grid);

  String get nameTr => names['tr'] ?? names['en'] ?? id;
  String nameIn(String lang) => names[lang] ?? names['en'] ?? nameTr;
}

const List<String> _bloom = [
  '..PPP...', '.PPPPP..', '.PPCPP..', '.PPPPP..',
  '..PPP...', '...S....', '..LSL...', '...S....',
];
const List<String> _tulip = [
  '.P.P.P..', '.PPPPP..', '.PPPPP..', '..PPP...',
  '...S....', '..LS....', '...SL...', '...S....',
];
const List<String> _cactus = [
  '...C....', '..PPP...', 'P.PPP...', 'PPPPP...',
  '..PPP...', '..PPP...', '..PPP...', '..PPP...',
];

Map<String, String> _loc(String en, String tr, String pl, String de, String ko, String it) =>
    {'en': en, 'tr': tr, 'pl': pl, 'de': de, 'ko': ko, 'it': it};

class Flowers {
  static const langs = ['en', 'tr', 'pl', 'de', 'ko', 'it'];

  static final all = <Flower>[
    Flower('gul', _loc('Rose', 'Gül', 'Róża', 'Rose', '장미', 'Rosa'), 0xFFE5484D, 0xFFB01030, _bloom),
    Flower('papatya', _loc('Daisy', 'Papatya', 'Stokrotka', 'Gänseblümchen', '데이지', 'Margherita'), 0xFFFFFFFF, 0xFFF2C94C, _bloom),
    Flower('lale', _loc('Tulip', 'Lale', 'Tulipan', 'Tulpe', '튤립', 'Tulipano'), 0xFFE0457B, 0xFFC02060, _tulip),
    Flower('kaktusf', _loc('Flower Cactus', 'Çiçekli Kaktüs', 'Kaktus kwitnący', 'Blühender Kaktus', '꽃선인장', 'Cactus fiorito'), 0xFFF06A92, 0xFFF2C94C, _cactus),
    Flower('kaktusd', _loc('Desert Cactus', 'Çöl Kaktüsü', 'Kaktus pustynny', 'Wüstenkaktus', '사막선인장', 'Cactus del deserto'), 0xFF46A03C, 0xFF5FBF4A, _cactus),
    Flower('kasimpati', _loc('Chrysanthemum', 'Kasımpatı', 'Chryzantema', 'Chrysantheme', '국화', 'Crisantemo'), 0xFFF2994A, 0xFFC9710B, _bloom),
    Flower('menekse', _loc('Violet', 'Menekşe', 'Fiołek', 'Veilchen', '제비꽃', 'Viola'), 0xFF8E4FE0, 0xFFF2C94C, _bloom),
    Flower('nilufer', _loc('Water Lily', 'Nilüfer', 'Lilia wodna', 'Seerose', '수련', 'Ninfea'), 0xFFF4A6C0, 0xFFF2C94C, _bloom),
    Flower('orkide', _loc('Orchid', 'Orkide', 'Orchidea', 'Orchidee', '난초', 'Orchidea'), 0xFFC24FE0, 0xFF7A2EA0, _bloom),
    Flower('begonya', _loc('Begonia', 'Begonya', 'Begonia', 'Begonie', '베고니아', 'Begonia'), 0xFFF2585B, 0xFFFFD9A0, _bloom),
    Flower('kamelya', _loc('Camellia', 'Kamelya', 'Kamelia', 'Kamelie', '동백', 'Camelia'), 0xFFE02C6D, 0xFFFFFFFF, _bloom),
  ];

  static Flower? byId(String? id) {
    for (final f in all) {
      if (f.id == id) return f;
    }
    return null;
  }

  /// How many distinct sprite variants a species has; a random one is chosen each
  /// time the flower is planted (#v22). Every species now has 2 hand-authored
  /// models in one consistent APICO/Littlewood style (rose is the reference;
  /// the rest were rolled out from the user's per-flower guide sheets, #v24).
  static const variantCounts = <String, int>{
    'gul': 2, 'lale': 2, 'kamelya': 2, 'kasimpati': 2,
    'menekse': 2, 'papatya': 2, 'nilufer': 2, 'begonya': 2, 'orkide': 2,
    'kaktusf': 2, 'kaktusd': 2, // cactus 2.0 from the guide-sheet study (#v26)
  };
  static int variantsFor(String id) => variantCounts[id] ?? 1;

  /// Species removed from the catalogue → replacement (#v27: the original
  /// blind-ASCII `kaktus` was superseded by the studied cactuses). Old saves
  /// migrate on load; the legacy PNGs are still generated so a not-yet-opened
  /// app's live wallpaper keeps rendering pre-migration prefs.
  static const legacyIds = <String, String>{'kaktus': 'kaktusd'};

  /// Map one tile value (possibly `road+flower~v` composite) through
  /// [legacyIds], keeping any `~variant` suffix.
  static String migrateId(String id) => id.split('+').map((part) {
        final base = Placeables.flowerBase(part);
        final to = legacyIds[base];
        return to == null ? part : part.replaceFirst(base, to);
      }).join('+');

  /// Returns [g] itself when nothing needed migrating.
  static Garden migrateGarden(Garden g) {
    var changed = false;
    final tiles = <int, String>{};
    g.tiles.forEach((k, v) {
      final nv = migrateId(v);
      if (nv != v) changed = true;
      tiles[k] = nv;
    });
    return changed ? Garden(cols: g.cols, rows: g.rows, tiles: tiles) : g;
  }

  /// Returns [owned] itself when nothing needed migrating.
  static Map<String, int> migrateOwned(Map<String, int> owned) {
    if (!owned.keys.any(legacyIds.containsKey)) return owned;
    final out = <String, int>{};
    owned.forEach((id, n) {
      final to = legacyIds[id] ?? id;
      out[to] = (out[to] ?? 0) + n;
    });
    return out;
  }
}

/// Pure app-blocker rules (#v23). The native AccessibilityService mirrors
/// [shouldBlock] / [active]; keep them in sync.
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

// ---- placeable objects (non-flower) -----------------------------------------

/// Garden objects that aren't flowers. They live in the same tile map (value =
/// the id). Roads lie flat on the ground; fences stand up. Adjacent same-kind
/// tiles abut, so they read as continuous paths/fences with no extra logic.
///
/// A tile can hold up to two things: a flat **ground** layer (a road) and a
/// standing **prop** (a flower or a fence). Fences may stand on top of a road,
/// so such a tile is stored as the composite `"<road>+<fence>"`. Flowers only
/// grow on bare grass. A plain id (no `+`) is a single occupant.
class Placeables {
  // 4 road surfaces + 3 fence materials.
  static const roadIds = ['road_concrete', 'road_wood', 'road_dirt', 'road_stone'];
  static const fenceIds = ['fence_wood', 'fence_dark', 'fence_stone'];
  static const objectIds = [...roadIds, ...fenceIds];

  static bool isObject(String id) => objectIds.contains(id);
  static bool isRoad(String id) => roadIds.contains(id);
  static bool isFence(String id) => fenceIds.contains(id);
  static bool isFlower(String id) => id.isNotEmpty && !isObject(id);

  /// Split a stored tile value into (road, prop). prop is the standing
  /// flower/fence; road is the flat ground beneath it (or null).
  static (String?, String?) split(String value) {
    String? road, prop;
    for (final p in value.split('+')) {
      if (p.isEmpty) continue;
      if (isRoad(p)) {
        road = p;
      } else {
        prop = p;
      }
    }
    return (road, prop);
  }

  static String? groundOf(String? value) => value == null ? null : split(value).$1;
  static String? propOf(String? value) => value == null ? null : split(value).$2;

  /// Re-join a (road, prop) pair into a stored value (road first).
  static String combine(String? road, String? prop) =>
      (road != null && prop != null) ? '$road+$prop' : (road ?? prop)!;

  /// A planted flower may carry a `~N` variant suffix (e.g. "gul~2" = rose model 2),
  /// picked at random when planted (#v22). The base id (for catalogue lookup and
  /// counting) drops the suffix; ids without one are returned unchanged.
  static String flowerBase(String id) {
    final i = id.indexOf('~');
    return i < 0 ? id : id.substring(0, i);
  }
}

// ---- economy ----------------------------------------------------------------

class Economy {
  static const flowerCost = 10;
  static const objectCost = 5; // roads + fences
  static const baseGardenCols = 4; // small start (#v23 fb — was 10×20); still the
  static const baseGardenRows = 8; // 1:2 portrait, grows +2×+4 per upgrade (first ⊕ now 2*(4+8)+1=25)
  static const startingGold = 50; // real users' one-time first-launch grant (#v31.11)

  /// What a fresh install grants, once, before anything is persisted: the
  /// full pretend `TestData` history in a debug build (a dev/demo
  /// convenience — screenshots, local testing — that must never reach a
  /// real release build), or just [startingGold] and nothing else for an
  /// actual user, whose real data genuinely starts the day they install
  /// (#v31.11). Kept as pure decision logic (not gated on `kDebugMode`
  /// directly) so both branches are independently unit-testable.
  static (List<SessionRecord> records, int coins, List<String> labels) firstLaunchSeed(
      bool debug, DateTime now) {
    return debug
        ? (TestData.records(now), TestData.seedCoins, TestData.labels)
        : (const <SessionRecord>[], startingGold, const <String>[]);
  }

  static int coinsFor(int minutes) => minutes <= 0 ? 0 : minutes ~/ 5;

  /// Whole focus minutes spent so far in a [workMin] session with [timeLeftMillis]
  /// remaining (uses the displayed ceil-minutes, so 14 left in a 25 reads as 11).
  static int elapsedFocusMinutes(int workMin, int timeLeftMillis) {
    final leftMin = (timeLeftMillis + 59999) ~/ 60000; // ceil
    final spent = workMin - leftMin;
    return spent < 0 ? 0 : spent;
  }

  /// EXPAND price — rises with the plot's perimeter so each ring costs more.
  static int upgradeCost(int cols, int rows) => 2 * (cols + rows) + 1;

  /// Buy price for any catalogue id (flower or object).
  static int costOf(String id) => Placeables.isObject(id) ? objectCost : flowerCost;

  /// Coins refunded for selling one un-placed unit: half the buy price, floored
  /// (flowers 10->5, decor 5->2). A mild sink so buy/sell isn't coin-neutral.
  static int sellPrice(String id) => costOf(id) ~/ 2;
}

// ---- garden -----------------------------------------------------------------

class Garden {
  final int cols;
  final int rows;
  final Map<int, String> tiles;
  const Garden({
    this.cols = Economy.baseGardenCols,
    this.rows = Economy.baseGardenRows,
    this.tiles = const {},
  });

  int get tileCount => cols * rows;
  bool isValidIndex(int i) => i >= 0 && i < tileCount;

  /// Raw stored value for a tile (may be a `"road+fence"` composite).
  String? flowerAt(int i) => tiles[i];

  /// The flat ground layer (a road) on a tile, or null.
  String? groundAt(int i) => Placeables.groundOf(tiles[i]);

  /// The standing prop (flower or fence) on a tile, or null.
  String? propAt(int i) => Placeables.propOf(tiles[i]);

  /// Place [id] on [index], honouring the layering rules:
  /// • a flower only grows on bare grass (rejected if a road is there);
  /// • a fence stands on grass or on top of a road (keeps the road);
  /// • a road slides under an existing fence (keeps the fence) but clears a
  ///   flower, since flowers can't sit on roads.
  Garden plant(int index, String id) {
    if (!isValidIndex(index) || id.trim().isEmpty) return this;
    final current = tiles[index];
    final (road, prop) = current == null ? (null, null) : Placeables.split(current);

    final String value;
    if (Placeables.isRoad(id)) {
      final keepFence = prop != null && Placeables.isFence(prop) ? prop : null;
      value = Placeables.combine(id, keepFence);
    } else if (Placeables.isFence(id)) {
      value = Placeables.combine(road, id);
    } else {
      // flower — only on bare grass
      if (road != null) return this;
      value = id;
    }
    return Garden(cols: cols, rows: rows, tiles: {...tiles, index: value});
  }

  Garden clear(int index) {
    if (!tiles.containsKey(index)) return this;
    final next = {...tiles}..remove(index);
    return Garden(cols: cols, rows: rows, tiles: next);
  }

  /// Expand the plot, centred, growing **taller faster than wider** (+2 cols /
  /// +4 rows) so it keeps reading as a portrait garden as it grows (#v19).
  /// Existing tiles shift by (+1 col, +2 rows) into the larger grid.
  Garden grow() {
    final nc = cols + 2;
    final nr = rows + 4;
    final remapped = <int, String>{};
    tiles.forEach((index, id) {
      final r = index ~/ cols;
      final c = index % cols;
      remapped[(r + 2) * nc + (c + 1)] = id;
    });
    return Garden(cols: nc, rows: nr, tiles: remapped);
  }

  /// Pad the plot (centred) up to at least [cols]×[rows], each axis independently —
  /// so a legacy *wide* plot gains rows to read as portrait WITHOUT also widening
  /// (symmetric grow() couldn't do that). Migration only; keeps plantings centred.
  Garden atLeast(int cols, int rows) {
    final nc = this.cols > cols ? this.cols : cols;
    final nr = this.rows > rows ? this.rows : rows;
    if (nc == this.cols && nr == this.rows) return this;
    final dc = (nc - this.cols) ~/ 2;
    final dr = (nr - this.rows) ~/ 2;
    final remapped = <int, String>{};
    tiles.forEach((index, id) {
      final r = index ~/ this.cols;
      final c = index % this.cols;
      remapped[(r + dr) * nc + (c + dc)] = id;
    });
    return Garden(cols: nc, rows: nr, tiles: remapped);
  }

  int countPlanted(String flowerId) => tiles.values.where((v) {
        final (road, prop) = Placeables.split(v);
        // a planted flower prop may carry a ~variant suffix → compare the base id.
        return road == flowerId ||
            (prop != null && Placeables.flowerBase(prop) == flowerId);
      }).length;

  String encode() {
    final b = StringBuffer('cols:$cols\nrows:$rows');
    final keys = tiles.keys.toList()..sort();
    for (final k in keys) {
      b.write('\n$k:${tiles[k]}');
    }
    return b.toString();
  }

  static Garden decode(String? text) {
    if (text == null || text.trim().isEmpty) return const Garden();
    var cols = Economy.baseGardenCols;
    var rows = Economy.baseGardenRows;
    final tiles = <int, String>{};
    for (final line in text.split('\n')) {
      if (line.trim().isEmpty) continue;
      final i = line.indexOf(':');
      if (i < 0) continue;
      final key = line.substring(0, i).trim();
      final value = line.substring(i + 1).trim();
      if (key == 'size') {
        final s = int.tryParse(value); // legacy square gardens
        if (s != null && s >= 1) {
          cols = s;
          rows = s;
        }
      } else if (key == 'cols') {
        final s = int.tryParse(value);
        if (s != null && s >= 1) cols = s;
      } else if (key == 'rows') {
        final s = int.tryParse(value);
        if (s != null && s >= 1) rows = s;
      } else {
        final idx = int.tryParse(key);
        if (idx != null && idx >= 0 && value.isNotEmpty) tiles[idx] = value;
      }
    }
    tiles.removeWhere((k, v) => k >= cols * rows);
    return Garden(cols: cols, rows: rows, tiles: tiles);
  }
}

// ---- live wallpaper framing -------------------------------------------------

/// The camera framing the user chose for the live wallpaper: rotation [yaw]
/// (radians), [zoom], and pan as a fraction of the projector tile size so it
/// reproduces across the camera-preview vs. wallpaper surface sizes. Persisted as
/// a compact "yaw,zoom,panXFrac,panYFrac" string and read natively (v15).
class WallpaperCam {
  final double yaw, zoom, panXFrac, panYFrac;
  const WallpaperCam(this.yaw, this.zoom, this.panXFrac, this.panYFrac);

  static const WallpaperCam none = WallpaperCam(0, 1, 0, 0);

  String encode() => '$yaw,$zoom,$panXFrac,$panYFrac';

  static WallpaperCam decode(String? s) {
    if (s == null || s.isEmpty) return none;
    final p = s.split(',');
    if (p.length != 4) return none;
    final y = double.tryParse(p[0]), z = double.tryParse(p[1]);
    final px = double.tryParse(p[2]), py = double.tryParse(p[3]);
    if (y == null || z == null || px == null || py == null) return none;
    return WallpaperCam(y, z, px, py);
  }
}

// ---- focus labels + colors --------------------------------------------------

class Labels {
  static const defaultLabel = 'STUDY';
  static const maxLen = 12;
  static const seed = ['STUDY', 'MATH', 'CODING', 'READING'];

  static String? normalize(String raw) {
    final cleaned = raw
        .toUpperCase()
        .split('')
        .map((ch) => RegExp(r'[A-Z0-9 ]').hasMatch(ch) ? ch : ' ')
        .join()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return null;
    final capped = cleaned.length > maxLen ? cleaned.substring(0, maxLen) : cleaned;
    return capped.trim();
  }

  static List<String> add(List<String> list, String raw) {
    final label = normalize(raw);
    if (label == null) return list;
    if (list.any((l) => l.toUpperCase() == label.toUpperCase())) return list;
    return [...list, label];
  }

  static List<String> remove(List<String> list, String label) {
    if (list.length <= 1) return list;
    return list.where((l) => l.toUpperCase() != label.toUpperCase()).toList();
  }

  /// Rename [oldLabel] to a normalized [raw]. Returns the list unchanged if the
  /// new name is empty, would collide with another label, or [oldLabel] is absent.
  static List<String> rename(List<String> list, String oldLabel, String raw) {
    final next = normalize(raw);
    if (next == null) return list;
    final oldU = oldLabel.toUpperCase();
    if (!list.any((l) => l.toUpperCase() == oldU)) return list;
    if (next.toUpperCase() != oldU && list.any((l) => l.toUpperCase() == next.toUpperCase())) {
      return list;
    }
    return [for (final l in list) l.toUpperCase() == oldU ? next : l];
  }
}

class LabelColors {
  static const palette = [
    0xFFE5484D, 0xFFF2994A, 0xFFF2C94C, 0xFF46A03C, 0xFF2A9D8F,
    0xFF2A7DE1, 0xFF8E4FE0, 0xFFE0457B, 0xFF9C6B4A, 0xFF8E8E8E,
    0xFF56CCF2, 0xFFA8D93A, 0xFFD138C9, 0xFFEDEDED, // sky/lime/magenta/white (#v27.1)
  ];

  /// Hash-derived defaults stay in the ORIGINAL 10 — growing the palette must
  /// not silently recolor every label the user never customized (#v27.1). The
  /// new colors are reachable through the picker only.
  static const _defaultCount = 10;

  static int _stableHash(String s) {
    var h = 0;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h;
  }

  static int defaultFor(String label) {
    final key = label.trim().toUpperCase();
    return palette[_stableHash(key) % _defaultCount];
  }

  static int colorFor(String label, Map<String, int> chosen) =>
      chosen[label.toUpperCase()] ?? defaultFor(label);

  static String encode(Map<String, int> colors) =>
      colors.entries.map((e) => '${e.key.toUpperCase()}:${e.value}').join('\n');

  static Map<String, int> decode(String? text) {
    final out = <String, int>{};
    if (text == null || text.trim().isEmpty) return out;
    for (final line in text.split('\n')) {
      if (line.trim().isEmpty) continue;
      final i = line.indexOf(':');
      if (i < 0) continue;
      final name = line.substring(0, i).trim().toUpperCase();
      final color = int.tryParse(line.substring(i + 1).trim());
      if (name.isNotEmpty && color != null) out[name] = color;
    }
    return out;
  }
}

// ---- stats ------------------------------------------------------------------

class SessionRecord {
  final int epochDay;
  final int minutes;
  final String label;
  final int? minuteOfDay; // 0..1439 start-of-session; null = legacy (#2)
  const SessionRecord(this.epochDay, this.minutes, this.label, {this.minuteOfDay});

  /// Copy with a new [label], preserving the timestamp (used by log-history
  /// relabel and rename so the daily trend keeps its hourly shape). (#v25)
  SessionRecord copyWith({String? label}) =>
      SessionRecord(epochDay, minutes, label ?? this.label, minuteOfDay: minuteOfDay);
}

class StatTotals {
  final int today, week, month, year, all;
  const StatTotals(this.today, this.week, this.month, this.year, this.all);
}

int epochDayOf(DateTime d) =>
    DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/ 86400000;

DateTime dateOfEpochDay(int e) =>
    DateTime.fromMillisecondsSinceEpoch(e * 86400000, isUtc: true);

/// What the timer should do when a phase ends mid-run (#v25 item1): auto-start
/// on → roll into the next phase; off → ask first, for BOTH focus→break AND
/// break→next-session (previously only focus→break prompted).
enum PhaseEnd { autoStart, prompt, done }

PhaseEnd phaseEndAction({required bool isFinished, required bool autoBreak}) =>
    isFinished ? PhaseEnd.done : (autoBreak ? PhaseEnd.autoStart : PhaseEnd.prompt);

/// Pure pagination for the log-history list (#v25 item3): 50 records a page.
class Paging {
  static int pageCount(int total, int perPage) =>
      total <= 0 ? 1 : (total + perPage - 1) ~/ perPage;

  static List<T> page<T>(List<T> items, int pageIndex, int perPage) {
    final start = pageIndex * perPage;
    if (start < 0 || start >= items.length) return <T>[];
    final end = (start + perPage) > items.length ? items.length : start + perPage;
    return items.sublist(start, end);
  }
}

enum StatPeriod { daily, weekly, monthly, yearly, allTime }

/// Per-x-bucket chart data for a [StatPeriod] window: total minutes, x tick
/// labels, and the per-label breakdown for each bucket (used by the tappable
/// line callout).
class StatSeries {
  final List<int> totals;
  final List<String> tickLabels;
  final List<List<MapEntry<String, int>>> byLabel;
  const StatSeries(this.totals, this.tickLabels, this.byLabel);
}

/// One label's series across the buckets (daily multi-line chart).
class LabelSeries {
  final String label;
  final List<int> values;
  const LabelSeries(this.label, this.values);
}

class StatsAggregator {
  static StatTotals aggregate(List<SessionRecord> records, DateTime today) {
    final todayE = epochDayOf(today);
    final weekStart = todayE - (today.weekday - 1);
    var day = 0, week = 0, month = 0, year = 0, all = 0;
    for (final r in records) {
      final min = r.minutes < 0 ? 0 : r.minutes;
      all += min;
      final d = dateOfEpochDay(r.epochDay);
      if (d.year == today.year) {
        year += min;
        if (d.month == today.month) month += min;
      }
      if (r.epochDay >= weekStart && r.epochDay <= todayE) week += min;
      if (r.epochDay == todayE) day += min;
    }
    return StatTotals(day, week, month, year, all);
  }

  static bool _inMonth(int epochDay, int year, int month) {
    final d = dateOfEpochDay(epochDay);
    return d.year == year && d.month == month;
  }

  static int monthTotal(List<SessionRecord> records, int year, int month) {
    var sum = 0;
    for (final r in records) {
      if (_inMonth(r.epochDay, year, month)) sum += r.minutes < 0 ? 0 : r.minutes;
    }
    return sum;
  }

  static List<MapEntry<String, int>> byLabelInMonth(
      List<SessionRecord> records, int year, int month) {
    final map = <String, int>{};
    for (final r in records) {
      if (!_inMonth(r.epochDay, year, month)) continue;
      map[r.label] = (map[r.label] ?? 0) + (r.minutes < 0 ? 0 : r.minutes);
    }
    final list = map.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return list;
  }

  static List<MapEntry<String, int>> byLabelAll(List<SessionRecord> records) {
    final map = <String, int>{};
    for (final r in records) {
      map[r.label] = (map[r.label] ?? 0) + (r.minutes < 0 ? 0 : r.minutes);
    }
    return map.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  }

  static List<int> dailySeries(List<SessionRecord> records, int year, int month) {
    final days = DateTime(year, month + 1, 0).day;
    final out = List<int>.filled(days, 0);
    for (final r in records) {
      if (!_inMonth(r.epochDay, year, month)) continue;
      final dom = dateOfEpochDay(r.epochDay).day - 1;
      out[dom] += r.minutes < 0 ? 0 : r.minutes;
    }
    return out;
  }

  /// Total minutes, how many days actually had focus time, and the mean
  /// minutes per ACTIVE day, over the inclusive epoch-day window [lo, hi]
  /// (#v32.6). Rest days are deliberately left out of the divisor: the
  /// question this answers is "on a day I study, how long do I study" — a
  /// calendar-diluted mean would say 36m for someone who does 2h four times
  /// a week. Returns a 0 average for an empty window rather than dividing
  /// by zero.
  static (int total, int activeDays, int avgPerActiveDay) windowAverage(
      List<SessionRecord> records, int lo, int hi) {
    var total = 0;
    final days = <int>{};
    for (final r in records) {
      if (r.epochDay < lo || r.epochDay > hi) continue;
      final m = r.minutes < 0 ? 0 : r.minutes;
      if (m <= 0) continue; // a 0-minute record is not an active day
      total += m;
      days.add(r.epochDay);
    }
    return (total, days.length, days.isEmpty ? 0 : total ~/ days.length);
  }

  /// [windowAverage] over an already-bucketed epochDay -> minutes map, which
  /// is the shape the Focus Sessions heatmaps already hold their data in
  /// (`LabelHabits.minutesFromRecords`) — saves re-walking every record per
  /// label.
  static (int total, int activeDays, int avgPerActiveDay) dayMapAverage(
      Map<int, int> minutesByDay, int lo, int hi) {
    var total = 0, days = 0;
    for (final e in minutesByDay.entries) {
      if (e.key < lo || e.key > hi) continue;
      final m = e.value < 0 ? 0 : e.value;
      if (m <= 0) continue;
      total += m;
      days++;
    }
    return (total, days, days == 0 ? 0 : total ~/ days);
  }

  /// Inclusive [startEpochDay, endEpochDay] window for a period relative to [now].
  static (int, int) windowDays(DateTime now, StatPeriod p) {
    final todayE = epochDayOf(now);
    switch (p) {
      case StatPeriod.daily:
        return (todayE, todayE);
      case StatPeriod.weekly:
        final monday = todayE - (now.weekday - 1);
        return (monday, monday + 6);
      case StatPeriod.monthly:
        final first = epochDayOf(DateTime(now.year, now.month, 1));
        final lastDay = DateTime(now.year, now.month + 1, 0).day;
        return (first, first + lastDay - 1);
      case StatPeriod.yearly:
        return (epochDayOf(DateTime(now.year, 1, 1)), epochDayOf(DateTime(now.year, 12, 31)));
      case StatPeriod.allTime:
        return (-100000000, todayE);
    }
  }

  /// Anchor date for browsing earlier periods: [offset] periods before [now].
  static DateTime anchorFor(DateTime now, StatPeriod p, int offset) {
    if (offset <= 0) return now;
    switch (p) {
      case StatPeriod.daily:
        return now.subtract(Duration(days: offset));
      case StatPeriod.weekly:
        return now.subtract(Duration(days: offset * 7));
      case StatPeriod.monthly:
        return DateTime(now.year, now.month - offset, 1);
      case StatPeriod.yearly:
        return DateTime(now.year - offset, 1, 1);
      case StatPeriod.allTime:
        return now;
    }
  }

  /// By-label totals (desc) within a period's window.
  static List<MapEntry<String, int>> byLabelInWindow(
      List<SessionRecord> records, DateTime now, StatPeriod p, [int offset = 0]) {
    final (lo, hi) = windowDays(anchorFor(now, p, offset), p);
    final map = <String, int>{};
    for (final r in records) {
      if (r.epochDay < lo || r.epochDay > hi) continue;
      map[r.label] = (map[r.label] ?? 0) + (r.minutes < 0 ? 0 : r.minutes);
    }
    final list = map.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return list;
  }

  /// Time-series (per bucket) for a period: totals, x tick labels, and the
  /// per-bucket by-label breakdown.
  static StatSeries seriesFor(List<SessionRecord> records, DateTime now, StatPeriod p,
      [int offset = 0]) {
    final now0 = anchorFor(now, p, offset);
    late int n;
    late int Function(SessionRecord) idx;
    late List<String> ticks;
    switch (p) {
      case StatPeriod.daily:
        n = 7;
        final endE = epochDayOf(now0);
        idx = (r) => r.epochDay - (endE - 6);
        ticks = [for (var i = 0; i < 7; i++) '${dateOfEpochDay(endE - 6 + i).day}'];
        break;
      case StatPeriod.weekly:
        n = 7;
        final mon = epochDayOf(now0) - (now0.weekday - 1);
        idx = (r) => r.epochDay - mon;
        ticks = [for (var i = 0; i < 7; i++) '${dateOfEpochDay(mon + i).day}'];
        break;
      case StatPeriod.monthly:
        n = DateTime(now0.year, now0.month + 1, 0).day;
        idx = (r) {
          final d = dateOfEpochDay(r.epochDay);
          return (d.year == now0.year && d.month == now0.month) ? d.day - 1 : -1;
        };
        ticks = [for (var i = 1; i <= n; i++) '$i'];
        break;
      case StatPeriod.yearly:
        n = 12;
        idx = (r) {
          final d = dateOfEpochDay(r.epochDay);
          return d.year == now0.year ? d.month - 1 : -1;
        };
        ticks = [for (var i = 1; i <= 12; i++) '$i'];
        break;
      case StatPeriod.allTime:
        var minY = now0.year;
        for (final r in records) {
          final y = dateOfEpochDay(r.epochDay).year;
          if (y < minY) minY = y;
        }
        if (minY < 2025) minY = 2025; // never show years before 2025 (#v19)
        n = now0.year - minY + 1;
        idx = (r) => dateOfEpochDay(r.epochDay).year - minY;
        ticks = [for (var i = 0; i < n; i++) '${minY + i}'];
        break;
    }
    final totals = List<int>.filled(n, 0);
    final maps = List.generate(n, (_) => <String, int>{});
    for (final r in records) {
      final i = idx(r);
      if (i < 0 || i >= n) continue;
      final m = r.minutes < 0 ? 0 : r.minutes;
      totals[i] += m;
      maps[i][r.label] = (maps[i][r.label] ?? 0) + m;
    }
    final byLabel = [
      for (final m in maps)
        (m.entries.where((e) => e.value > 0).toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
    ];
    return StatSeries(totals, ticks, byLabel);
  }

  /// One series per label across the period's buckets (daily multi-line).
  static List<LabelSeries> labelSeriesFor(
      List<SessionRecord> records, DateTime now, StatPeriod p, [int offset = 0]) {
    final s = seriesFor(records, now, p, offset);
    final n = s.totals.length;
    final totalByLabel = <String, int>{};
    for (final bucket in s.byLabel) {
      for (final e in bucket) {
        totalByLabel[e.key] = (totalByLabel[e.key] ?? 0) + e.value;
      }
    }
    final labels = totalByLabel.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final l in labels)
        LabelSeries(l.key, [
          for (var i = 0; i < n; i++)
            s.byLabel[i]
                .firstWhere((e) => e.key == l.key, orElse: () => MapEntry(l.key, 0))
                .value
        ])
    ];
  }

  /// Cumulative focus minutes through the anchored day at hours [0,4,8,12,16,20,24]
  /// (legacy records without a [SessionRecord.minuteOfDay] are not placed on the curve).
  static StatSeries dailyCumulative(List<SessionRecord> records, DateTime now, [int offset = 0]) {
    final a = anchorFor(now, StatPeriod.daily, offset);
    final dayE = epochDayOf(a);
    const hours = [0, 4, 8, 12, 16, 20, 24];
    final totals = List<int>.filled(hours.length, 0);
    for (final r in records) {
      if (r.epochDay != dayE || r.minuteOfDay == null) continue;
      final m = r.minutes < 0 ? 0 : r.minutes;
      for (var i = 0; i < hours.length; i++) {
        if (r.minuteOfDay! <= hours[i] * 60) totals[i] += m; // counted once that hour is reached
      }
    }
    final ticks = [for (final h in hours) h.toString().padLeft(2, '0')];
    return StatSeries(totals, ticks, [for (final _ in hours) const <MapEntry<String, int>>[]]);
  }

  /// (current, average, best) period totals across all history for the trend
  /// comparison block. Buckets by the period's unit; average is over non-empty buckets.
  static (int, int, int) periodStats(
      List<SessionRecord> records, DateTime now, StatPeriod p, [int offset = 0]) {
    int keyOf(int epochDay) {
      final d = dateOfEpochDay(epochDay);
      switch (p) {
        case StatPeriod.daily:
          return epochDay;
        case StatPeriod.weekly:
          return epochDay - (d.weekday - 1); // Monday epoch-day
        case StatPeriod.monthly:
          return d.year * 12 + d.month;
        case StatPeriod.yearly:
        case StatPeriod.allTime:
          return d.year;
      }
    }

    final buckets = <int, int>{};
    for (final r in records) {
      final k = keyOf(r.epochDay);
      buckets[k] = (buckets[k] ?? 0) + (r.minutes < 0 ? 0 : r.minutes);
    }
    final a = anchorFor(now, p, offset);
    final (lo, hi) = windowDays(a, p);
    var current = 0;
    for (final r in records) {
      if (r.epochDay >= lo && r.epochDay <= hi) current += r.minutes < 0 ? 0 : r.minutes;
    }
    if (buckets.isEmpty) return (current, 0, 0);
    var best = 0, sum = 0;
    for (final v in buckets.values) {
      if (v > best) best = v;
      sum += v;
    }
    return (current, sum ~/ buckets.length, best);
  }

  static String formatMinutes(int min) {
    final safe = min < 0 ? 0 : min;
    final h = safe ~/ 60;
    final m = safe % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }
}

class StatsCodec {
  static String encode(List<SessionRecord> records) => records
      .map((r) => '${r.epochDay},${r.minutes},${r.minuteOfDay ?? ''},${r.label}')
      .join('\n');

  static List<SessionRecord> decode(String? text) {
    final out = <SessionRecord>[];
    if (text == null || text.trim().isEmpty) return out;
    for (final line in text.split('\n')) {
      if (line.trim().isEmpty) continue;
      final parts = line.split(',');
      if (parts.length < 3) continue;
      final day = int.tryParse(parts[0].trim());
      final min = int.tryParse(parts[1].trim());
      if (day == null || min == null) continue;
      int? minute;
      String label;
      if (parts.length >= 4) {
        // new format: day,min,minOfDay,label (labels are comma-free)
        minute = int.tryParse(parts[2].trim());
        label = parts.sublist(3).join(',').trim();
      } else {
        label = parts.sublist(2).join(',').trim(); // legacy day,min,label
      }
      if (label.isEmpty) continue;
      out.add(SessionRecord(day, min, label, minuteOfDay: minute));
    }
    return out;
  }
}

// ---- first-launch test fixture ----------------------------------------------

class TestData {
  static const seedCoins = 1000;
  static const labels = ['MATH', 'HISTORY', 'ENGLISH', 'CODING', 'SCIENCE', 'TURKISH', 'READING'];

  static List<SessionRecord> records(DateTime today) {
    final out = <SessionRecord>[];
    // [minute] = start-of-session minute-of-day, so the DAILY trend curve has real
    // hourly shape on the seeded data (untimestamped records don't appear on it).
    void add(DateTime date, int min, String label, int minute) =>
        out.add(SessionRecord(epochDayOf(date), min, label, minuteOfDay: minute));

    add(today, 60, 'MATH', 8 * 60); // 08:00
    add(today, 100, 'HISTORY', 10 * 60 + 30); // 10:30
    add(today, 40, 'ENGLISH', 13 * 60); // 13:00
    add(today, 160, 'CODING', 15 * 60 + 30); // 15:30

    add(today.subtract(const Duration(days: 1)), 200, 'MATH', 9 * 60);
    add(today.subtract(const Duration(days: 2)), 100, 'SCIENCE', 11 * 60);
    add(today.subtract(const Duration(days: 2)), 40, 'ENGLISH', 16 * 60);

    add(today.subtract(const Duration(days: 9)), 150, 'TURKISH', 14 * 60);
    add(today.subtract(const Duration(days: 14)), 150, 'TURKISH', 19 * 60);

    add(DateTime(today.year, today.month - 1, 10), 120, 'CODING', 20 * 60);
    add(DateTime(today.year, today.month - 1, 18), 90, 'MATH', 7 * 60 + 30);
    add(DateTime(today.year, today.month - 2, 6), 75, 'READING', 22 * 60);
    add(DateTime(today.year, today.month - 2, 22), 130, 'HISTORY', 12 * 60);
    add(DateTime(today.year, today.month - 3, 14), 60, 'ENGLISH', 17 * 60);

    // ...and a FULL, natural-looking history behind them, running from
    // [firstFillDay] right up to YESTERDAY.
    out.addAll(fill(firstFillDay, epochDayOf(today) - 1));

    return out;
  }

  /// Where the generated pretend history starts: 1 Jan 2024 (#v32.6 — was
  /// 2025-01-01, so YEARLY had only one full past year to browse).
  static final int firstFillDay = epochDayOf(DateTime(2024, 1, 1));

  /// Deterministic pretend history for the inclusive epoch-day range
  /// [fromDay, toDay]: most days active, ~1-in-4 rest days, 1-8h per active
  /// day split over 1-3 sessions across varied labels, so every month
  /// Sessions in Pixels can browse to has real data instead of sparse gaps.
  ///
  /// Each day is generated from its OWN seed rather than from one running
  /// LCG (#v32.6). That makes the function range-independent — `fill(a, c)`
  /// is exactly `fill(a, b) + fill(b+1, c)` — which is what lets the store
  /// top the history up on every launch (`_topUpDemoData`) and still produce
  /// the same history a fresh install would have generated in one pass.
  /// Sticks to plain integer maths: this file stays free of dart:math, and
  /// every product below stays under 2^53 so the web build agrees with
  /// native.
  static List<SessionRecord> fill(int fromDay, int toDay) {
    final out = <SessionRecord>[];
    for (var d = fromDay; d <= toDay; d++) {
      var h = ((d + 1000000) * 2654435 + 0x9E37) % 0x7FFFFFFF;
      int rnd(int n) {
        h = (h * 48271) % 0x7FFFFFFF;
        return h % n;
      }

      if (rnd(4) == 0) continue; // natural gaps
      final total = 60 + rnd(421); // 1h .. 8h
      final parts = 1 + rnd(3); // 1-3 sessions
      var left = total;
      var minute = 8 * 60 + rnd(120);
      for (var i = 0; i < parts; i++) {
        final m = i == parts - 1 ? left : (left ~/ (parts - i));
        left -= m;
        if (m <= 0) continue;
        out.add(SessionRecord(d, m, labels[rnd(labels.length)],
            minuteOfDay: minute > 1380 ? 1380 : minute));
        minute += m + 10 + rnd(60);
      }
    }
    return out;
  }
}

// ---- habit tracker (#v29) -----------------------------------------------------
// HabitKit-style manual habits + Daylio-style daily mood. Manual habits are a
// SEPARATE list from the home-screen focus labels (never shown in the label
// picker); focus-session labels additionally act as AUTOMATIC habits, derived
// straight from the session records.

const String _us = ''; // unit separator for user-typed fields

class Habit {
  final String name;
  final int color;
  const Habit(this.name, this.color);
}

class Habits {
  static String _clean(String s) =>
      s.replaceAll('\n', ' ').replaceAll(_us, ' ').trim().toUpperCase();

  static String encode(List<Habit> hs) =>
      hs.map((h) => '${h.name}$_us${h.color}').join('\n');

  static List<Habit> decode(String? s) {
    final out = <Habit>[];
    if (s == null || s.trim().isEmpty) return out;
    for (final line in s.split('\n')) {
      final parts = line.split(_us);
      if (parts.length < 2 || parts[0].trim().isEmpty) continue;
      final color = int.tryParse(parts[1]);
      if (color == null) continue;
      out.add(Habit(parts[0], color));
    }
    return out;
  }

  /// Returns the list unchanged for an empty or duplicate (case-insensitive) name.
  static List<Habit> add(List<Habit> hs, String name, int color) {
    final n = _clean(name);
    if (n.isEmpty || hs.any((h) => h.name == n)) return hs;
    return [...hs, Habit(n, color)];
  }

  static List<Habit> remove(List<Habit> hs, String name) =>
      [for (final h in hs) if (h.name != name) h];
}

/// Per-habit completion counts: habit name -> epochDay -> count. A habit may be
/// completed several times a day, but the heatmap renders a day BINARY (once or
/// more looks identical — the user's HabitKit rule).
class HabitLog {
  static String encode(Map<String, Map<int, int>> log) => [
        for (final e in log.entries)
          if (e.value.isNotEmpty)
            '${e.key}$_us${e.value.entries.map((d) => '${d.key}:${d.value}').join(',')}'
      ].join('\n');

  static Map<String, Map<int, int>> decode(String? s) {
    final out = <String, Map<int, int>>{};
    if (s == null || s.trim().isEmpty) return out;
    for (final line in s.split('\n')) {
      final parts = line.split(_us);
      if (parts.length < 2 || parts[0].isEmpty) continue;
      final days = <int, int>{};
      for (final cell in parts[1].split(',')) {
        final kv = cell.split(':');
        if (kv.length != 2) continue;
        final d = int.tryParse(kv[0]), n = int.tryParse(kv[1]);
        if (d == null || n == null || n <= 0) continue;
        days[d] = n;
      }
      if (days.isNotEmpty) out[parts[0]] = days;
    }
    return out;
  }

  /// New map with [delta] applied to (habit, day); counts clamp at 0 and empty
  /// entries are dropped.
  static Map<String, Map<int, int>> bump(
      Map<String, Map<int, int>> log, String habit, int day,
      [int delta = 1]) {
    final out = {
      for (final e in log.entries) e.key: Map<int, int>.from(e.value)
    };
    final days = out.putIfAbsent(habit, () => <int, int>{});
    final n = (days[day] ?? 0) + delta;
    if (n <= 0) {
      days.remove(day);
      if (days.isEmpty) out.remove(habit);
    } else {
      days[day] = n;
    }
    return out;
  }

  static int daysDone(Map<int, int> days) => days.length;

  static int totalTimes(Map<int, int> days) =>
      days.values.fold(0, (a, b) => a + b);

  /// Consecutive done-days ending today (or yesterday, so an unbroken streak
  /// isn't shown as 0 before today's completion).
  static int streak(Map<int, int> days, int today) {
    var start = today;
    if (!days.containsKey(start)) {
      if (!days.containsKey(start - 1)) return 0;
      start = start - 1;
    }
    var n = 0;
    while (days.containsKey(start - n)) {
      n++;
    }
    return n;
  }
}

/// Focus-session labels as automatic habits ("you studied TURKISH 7 days and
/// 15 times"): label -> epochDay -> completed-session count, straight from the
/// stats records — no extra storage, always in sync with the timer.
class LabelHabits {
  static Map<String, Map<int, int>> fromRecords(List<SessionRecord> records) {
    final out = <String, Map<int, int>>{};
    for (final r in records) {
      final days = out.putIfAbsent(r.label, () => <int, int>{});
      days[r.epochDay] = (days[r.epochDay] ?? 0) + 1;
    }
    return out;
  }

  /// Same shape as [fromRecords] but sums MINUTES instead of session count —
  /// feeds the heatmap tap-for-details tooltip (#v30 follow-up).
  static Map<String, Map<int, int>> minutesFromRecords(List<SessionRecord> records) {
    final out = <String, Map<int, int>>{};
    for (final r in records) {
      final days = out.putIfAbsent(r.label, () => <int, int>{});
      days[r.epochDay] = (days[r.epochDay] ?? 0) + (r.minutes < 0 ? 0 : r.minutes);
    }
    return out;
  }
}

/// Daily mood, 1 (awful) .. 5 (great) — one per epochDay.
class Moods {
  static String encode(Map<int, int> m) =>
      m.entries.map((e) => '${e.key}:${e.value}').join('\n');

  static Map<int, int> decode(String? s) {
    final out = <int, int>{};
    if (s == null || s.trim().isEmpty) return out;
    for (final line in s.split('\n')) {
      final kv = line.split(':');
      if (kv.length != 2) continue;
      final d = int.tryParse(kv[0]), v = int.tryParse(kv[1]);
      if (d == null || v == null || v < 1 || v > 5) continue;
      out[d] = v;
    }
    return out;
  }
}

// ---- money manager (#v29) ------------------------------------------------------
// Simple single ledger: income/expense entries with a category, entered in any
// currency, aggregated in the user's MAIN currency via the cached USD-based
// rates. Spending under the user's DAILY RATE earns +1 garden coin per day.

class MoneyTx {
  final int epochDay;
  final int minuteOfDay;
  final int amountMinor; // always positive, in cents of [currency]
  final String currency;
  final String category;
  final bool isExpense;
  final String note;
  const MoneyTx(this.epochDay, this.minuteOfDay, this.amountMinor, this.currency,
      this.category, this.isExpense,
      [this.note = '']);
}

class MoneyBook {
  static String _clean(String s) =>
      s.replaceAll('\n', ' ').replaceAll(_us, ' ').trim();

  static String encode(List<MoneyTx> txs) => txs
      .map((t) => [
            t.epochDay,
            t.minuteOfDay,
            t.amountMinor,
            t.currency,
            t.isExpense ? 1 : 0,
            _clean(t.category),
            _clean(t.note),
          ].join(_us))
      .join('\n');

  static List<MoneyTx> decode(String? s) {
    final out = <MoneyTx>[];
    if (s == null || s.trim().isEmpty) return out;
    for (final line in s.split('\n')) {
      final p = line.split(_us);
      if (p.length < 6) continue;
      final day = int.tryParse(p[0]), min = int.tryParse(p[1]);
      final amt = int.tryParse(p[2]), exp = int.tryParse(p[4]);
      if (day == null || min == null || amt == null || exp == null || amt <= 0) {
        continue;
      }
      out.add(MoneyTx(day, min, amt, p[3], p[5], exp == 1,
          p.length > 6 ? p.sublist(6).join(_us) : ''));
    }
    return out;
  }

  /// Amount in the MAIN currency (rates are per-USD; a missing rate falls back
  /// to the raw amount so the book never crashes on an unknown currency).
  static double toMain(MoneyTx t, Map<String, double> rates, String main) {
    final v = t.amountMinor / 100.0;
    if (t.currency == main) return v;
    final rc = rates[t.currency], rm = rates[main];
    if (rc == null || rm == null || rc == 0) return v;
    return v / rc * rm;
  }

  static double spentOnDay(
      List<MoneyTx> txs, int day, Map<String, double> rates, String main) {
    var sum = 0.0;
    for (final t in txs) {
      if (t.isExpense && t.epochDay == day) sum += toMain(t, rates, main);
    }
    return sum;
  }

  /// (income, expense) for a calendar month in the main currency.
  static (double, double) monthTotals(List<MoneyTx> txs, int year, int month,
      Map<String, double> rates, String main) {
    var inc = 0.0, exp = 0.0;
    for (final t in txs) {
      final d = dateOfEpochDay(t.epochDay);
      if (d.year != year || d.month != month) continue;
      final v = toMain(t, rates, main);
      if (t.isExpense) {
        exp += v;
      } else {
        inc += v;
      }
    }
    return (inc, exp);
  }

  /// Month's expenses per category (main currency), biggest first.
  static List<MapEntry<String, double>> byCategory(List<MoneyTx> txs, int year,
      int month, Map<String, double> rates, String main) {
    final sums = <String, double>{};
    for (final t in txs) {
      if (!t.isExpense) continue;
      final d = dateOfEpochDay(t.epochDay);
      if (d.year != year || d.month != month) continue;
      sums[t.category] = (sums[t.category] ?? 0) + toMain(t, rates, main);
    }
    final out = sums.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return out;
  }

  /// (income, expense) within an inclusive epochDay window (main currency) —
  /// feeds the daily/weekly/monthly bar chart (#v30 item 11).
  static (double, double) totalsInWindow(List<MoneyTx> txs, int startDay,
      int endDay, Map<String, double> rates, String main) {
    var inc = 0.0, exp = 0.0;
    for (final t in txs) {
      if (t.epochDay < startDay || t.epochDay > endDay) continue;
      final v = toMain(t, rates, main);
      if (t.isExpense) {
        exp += v;
      } else {
        inc += v;
      }
    }
    return (inc, exp);
  }

  /// Expenses per category within an inclusive epochDay window (main
  /// currency), biggest first — feeds the pie chart (#v30 item 11).
  static List<MapEntry<String, double>> byCategoryInWindow(List<MoneyTx> txs,
      int startDay, int endDay, Map<String, double> rates, String main) {
    final sums = <String, double>{};
    for (final t in txs) {
      if (!t.isExpense || t.epochDay < startDay || t.epochDay > endDay) continue;
      sums[t.category] = (sums[t.category] ?? 0) + toMain(t, rates, main);
    }
    final out = sums.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return out;
  }
}

/// USD-based rate cache. Refreshed from open.er-api.com when the app is online
/// and the cache is older than [ttlMs] (1 hour — the upstream data itself
/// updates about daily, so this also satisfies "update every 24h").
class Fx {
  static const ttlMs = 3600 * 1000;

  /// Picker seed before the first successful fetch.
  static const seedCurrencies = [
    'USD', 'EUR', 'TRY', 'GBP', 'JPY', 'CNY', 'KRW', 'INR', 'BRL', 'CAD',
    'AUD', 'CHF', 'SEK', 'NOK', 'DKK', 'PLN', 'CZK', 'HUF', 'RON', 'BGN',
    'UAH', 'RUB', 'AED', 'SAR', 'QAR', 'EGP', 'MXN', 'ARS', 'CLP', 'COP',
    'ZAR', 'NGN', 'ILS', 'THB', 'IDR', 'MYR', 'PHP', 'SGD', 'HKD', 'NZD',
  ];

  static String encode(Map<String, double> rates, int fetchedAtMs) =>
      '$fetchedAtMs\n${rates.entries.map((e) => '${e.key}:${e.value}').join(',')}';

  static (Map<String, double>, int) decode(String? s) {
    if (s == null || s.trim().isEmpty) return (<String, double>{}, 0);
    final nl = s.indexOf('\n');
    if (nl < 0) return (<String, double>{}, 0);
    final at = int.tryParse(s.substring(0, nl)) ?? 0;
    final rates = <String, double>{};
    for (final cell in s.substring(nl + 1).split(',')) {
      final kv = cell.split(':');
      if (kv.length != 2) continue;
      final v = double.tryParse(kv[1]);
      if (v == null || v <= 0) continue;
      rates[kv[0]] = v;
    }
    return (rates, at);
  }

  static bool needsRefresh(int nowMs, int fetchedAtMs) =>
      nowMs - fetchedAtMs > ttlMs;
}

/// The daily-budget coin: every COMPLETED day whose expenses stayed strictly
/// under the daily rate earns 1 coin. Evaluated lazily (on app load): walks the
/// days after [lastDoneDay] up to yesterday and returns (coins, newCursor).
/// A rate of 0 turns the feature off (the cursor still advances so enabling it
/// later never awards the past).
class MoneyReward {
  static (int, int) accrue({
    required List<MoneyTx> txs,
    required int rateMinor,
    required int lastDoneDay,
    required int today,
    required Map<String, double> rates,
    required String main,
  }) {
    final cursor = today - 1;
    if (cursor <= lastDoneDay) return (0, lastDoneDay);
    if (rateMinor <= 0) return (0, cursor);
    var coins = 0;
    for (var d = lastDoneDay + 1; d <= cursor; d++) {
      if (MoneyBook.spentOnDay(txs, d, rates, main) < rateMinor / 100.0) {
        coins++;
      }
    }
    return (coins, cursor);
  }
}
