import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'logic.dart';
import 'store.dart';

/// ARGB int → Flutter [Color].
Color col(int argb) => Color(argb);

/// True if [argb] is a light color (perceived luminance) — used to choose
/// contrasting system-bar icon brightness (#2) and on-scene contrast.
bool isLightColor(int argb) {
  final r = (argb >> 16) & 0xFF, g = (argb >> 8) & 0xFF, b = argb & 0xFF;
  return (0.299 * r + 0.587 * g + 0.114 * b) > 140;
}

/// System status + navigation bars colored to the theme background, with icon
/// brightness that contrasts it (#2).
SystemUiOverlayStyle systemOverlayFor(PixelTheme th) {
  final light = isLightColor(th.bg);
  final iconBrightness = light ? Brightness.dark : Brightness.light;
  return SystemUiOverlayStyle(
    statusBarColor: col(th.bg),
    statusBarIconBrightness: iconBrightness,
    statusBarBrightness: light ? Brightness.light : Brightness.dark, // iOS
    systemNavigationBarColor: col(th.bg),
    systemNavigationBarIconBrightness: iconBrightness,
  );
}

/// Press Start 2P (Latin) is the primary face for EVERY language. It has no
/// Hangul, so Galmuri11 (a Korean pixel font, OFL) is only a *fallback* that kicks
/// in for Korean glyphs. Keeping Press Start 2P primary means Latin text looks the
/// same in every language, and there's no per-language size bump — Korean renders
/// at the same sizes as the others. (#v22: Korean used to force Galmuri everywhere
/// at 1.5×, which changed the Latin glyphs and inflated every size.) [lang] is kept
/// for call-site compatibility; the fallback handles language differences now.
const List<String> _pixelFontFallback = ['Galmuri11'];
// Korean (#v23): make Galmuri11 the PRIMARY face. Drawing Hangul from its own font
// keeps the baseline aligned (no mixed-font shift / "kayma"), and a small x1.15
// bump makes it read a tick larger (Galmuri fills less of the em than Press Start
// 2P, so at equal size it looks small). Korean-only — the old #v22 1.5x-on-every-
// language bug that also inflated Latin is NOT reintroduced.
const List<String> _koFontFallback = ['PressStart2P'];
const double _koFontScale = 1.15;

TextStyle pixelStyle(String lang, double size, Color color, {double spacing = 0}) {
  final ko = lang == 'ko';
  return TextStyle(
    fontFamily: ko ? 'Galmuri11' : 'PressStart2P',
    fontFamilyFallback: ko ? _koFontFallback : _pixelFontFallback,
    fontSize: ko ? size * _koFontScale : size,
    color: color,
    letterSpacing: spacing,
  );
}

/// A plain 2D gold coin (no "$", no smiley, no animation — #5). Just the flat
/// struck-gold sprite, drawn crisp. The [animate] flag is kept (a no-op) so old
/// call sites / tests that toggle it still compile.
class GoldCoin extends StatelessWidget {
  static bool animate = false;
  final double size;
  const GoldCoin({super.key, this.size = 32});

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/objects/coin.png',
        width: size,
        height: size,
        filterQuality: FilterQuality.none,
      );
}

/// A hard-edged pixel button: solid fill, contrasting border, offset drop-shadow (no blur).
class PixelButton extends StatelessWidget {
  final String text;
  final int fill, border, textColor, shadow;
  final VoidCallback? onTap;
  final String lang;
  final double fontSize;
  final EdgeInsets padding;
  final double opacity;

  const PixelButton({
    super.key,
    required this.text,
    required this.fill,
    required this.border,
    required this.textColor,
    required this.shadow,
    required this.lang,
    this.onTap,
    this.fontSize = 13,
    this.padding = const EdgeInsets.all(14),
    this.opacity = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: col(fill),
            border: Border.all(color: col(border), width: 3),
            boxShadow: [BoxShadow(color: col(shadow), offset: const Offset(5, 5), blurRadius: 0)],
          ),
          child: Center(
            widthFactor: 1,
            child: Text(text, textAlign: TextAlign.center, style: pixelStyle(lang, fontSize, col(textColor))),
          ),
        ),
      ),
    );
  }
}

/// A small solid color square with a hard border (label swatch / palette dialog).
class Swatch extends StatelessWidget {
  final int color;
  final int border;
  final double size;
  final VoidCallback? onTap;
  const Swatch({super.key, required this.color, required this.border, this.size = 22, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: col(color), border: Border.all(color: col(border), width: 2)),
      ),
    );
  }
}

/// The chunky horizontal progress bar (track + border + clipped fill).
class PixelProgress extends StatelessWidget {
  final int percent; // 0..100
  final int track, border, fill;
  const PixelProgress({super.key, required this.percent, required this.track, required this.border, required this.fill});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 18,
      decoration: BoxDecoration(color: col(track), border: Border.all(color: col(border), width: 3)),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: (percent / 100).clamp(0.0, 1.0),
          child: Container(color: col(fill)),
        ),
      ),
    );
  }
}

/// Renders a [Flower]'s char-grid as crisp pixel rectangles.
class FlowerSprite extends StatelessWidget {
  final Flower flower;
  final double size;
  const FlowerSprite({super.key, required this.flower, this.size = 40});

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: size, height: size, child: CustomPaint(painter: _FlowerPainter(flower)));
}

class _FlowerPainter extends CustomPainter {
  final Flower flower;
  _FlowerPainter(this.flower);

  @override
  void paint(Canvas canvas, Size size) {
    final cols = flower.grid.map((r) => r.length).reduce(math.max);
    final rows = flower.grid.length;
    final cw = size.width / cols;
    final ch = size.height / rows;
    final p = Paint()..isAntiAlias = false;
    for (var r = 0; r < rows; r++) {
      final line = flower.grid[r];
      for (var c = 0; c < line.length; c++) {
        final ch0 = line[c];
        int? color;
        if (ch0 == 'P') {
          color = flower.petal;
        } else if (ch0 == 'C') {
          color = flower.center;
        } else if (ch0 == 'S' || ch0 == 'L') {
          color = flowerGreen;
        } else {
          continue;
        }
        p.color = col(color);
        canvas.drawRect(Rect.fromLTWH(c * cw, r * ch, cw + 0.5, ch + 0.5), p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FlowerPainter oldDelegate) => oldDelegate.flower.id != flower.id;
}

/// One per-label datum for bar/pie.
class ChartEntry {
  final String label;
  final int value;
  final int color;
  const ChartEntry(this.label, this.value, this.color);
}

/// Bar / TREND / pie chart for the selected stats period. TREND mode draws one
/// progress line (daily = cumulative; else per-bucket totals) and is tappable —
/// the tap shows the bucket's FOCUS total + the period AVG (#2).
class StatsChart extends StatefulWidget {
  final List<ChartEntry> entries; // by-label for bar/pie
  final StatSeries series; // totals + tick labels + per-bucket by-label
  final int average; // period average bucket (trend callout AVG)
  final ChartMode mode;
  final String lang;
  final int axisColor, textColor, lineColor, panelColor, panelBorder;

  const StatsChart({
    super.key,
    required this.entries,
    required this.series,
    required this.average,
    required this.mode,
    required this.lang,
    required this.axisColor,
    required this.textColor,
    required this.lineColor,
    required this.panelColor,
    required this.panelBorder,
  });

  @override
  State<StatsChart> createState() => _StatsChartState();
}

class _StatsChartState extends State<StatsChart> {
  int? _sel; // selected bucket index (line mode)

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.mode == ChartMode.line ? _onTap : null,
      child: CustomPaint(
        painter: _ChartPainter(widget, _sel),
        child: const SizedBox.expand(),
      ),
    );
  }

  void _onTap(TapDownDetails d) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final w = box.size.width;
    final n = widget.series.totals.length;
    if (n == 0) return;
    const padL = 10.0, padR = 10.0;
    final plotW = w - padL - padR;
    final rel = ((d.localPosition.dx - padL) / (plotW <= 0 ? 1 : plotW)).clamp(0.0, 1.0);
    setState(() => _sel = (rel * (n - 1)).round());
  }
}

class _ChartPainter extends CustomPainter {
  final StatsChart c;
  final int? sel;
  _ChartPainter(this.c, this.sel);

  void _text(Canvas canvas, String s, double x, double y, double size, int color, {TextAlign align = TextAlign.left}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: pixelStyle(c.lang, size, col(color))),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout();
    var dx = x;
    if (align == TextAlign.center) dx = x - tp.width / 2;
    if (align == TextAlign.right) dx = x - tp.width;
    tp.paint(canvas, Offset(dx, y - tp.height));
  }

  bool _hasData() => c.mode == ChartMode.line
      ? c.series.totals.any((v) => v > 0)
      : c.entries.any((e) => e.value > 0);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    if (!_hasData()) {
      _text(canvas, _noData(), w / 2, h / 2 + 6, 9, c.textColor, align: TextAlign.center);
      return;
    }
    switch (c.mode) {
      case ChartMode.bar:
        _bars(canvas, w, h);
        break;
      case ChartMode.line:
        _line(canvas, w, h);
        break;
      case ChartMode.pie:
        _pie(canvas, w, h);
        break;
    }
  }

  String _noData() {
    const m = {
      'en': 'No focus minutes here.',
      'tr': 'Burada odak dakikası yok.',
      'pl': 'Brak minut tutaj.',
      'de': 'Keine Minuten hier.',
      'ko': '기록이 없습니다.',
      'it': 'Nessun minuto qui.',
    };
    return m[c.lang] ?? m['en']!;
  }

  String _cap(String s) => s.length <= 12 ? s : s.substring(0, 12);
  String _fmt(int min) => StatsAggregator.formatMinutes(min);

  String _focus() {
    const m = {'en': 'FOCUS', 'tr': 'ODAK', 'pl': 'SKUPIENIE', 'de': 'FOKUS', 'ko': '집중', 'it': 'FOCUS'};
    return m[c.lang] ?? m['en']!;
  }

  String _avg() {
    const m = {'en': 'AVG', 'tr': 'ORT', 'pl': 'ŚR', 'de': 'DSCHN', 'ko': '평균', 'it': 'MEDIA'};
    return m[c.lang] ?? m['en']!;
  }

  /// Draw rows as two columns: left label, right value right-aligned to [right].
  void _alignedRows(Canvas canvas, List<(String, String)> rows, double left,
      double top, double right, {double fs = 7, double lh = 11}) {
    var ty = top + lh;
    for (final (l, r) in rows) {
      _text(canvas, l, left, ty, fs, c.textColor);
      _text(canvas, r, right, ty, fs, c.textColor, align: TextAlign.right);
      ty += lh;
    }
  }

  void _bars(Canvas canvas, double w, double h) {
    const padL = 8.0, padR = 8.0, padTop = 10.0, padBottom = 26.0;
    final plotW = w - padL - padR, plotH = h - padTop - padBottom;
    final maxVal = math.max(1, c.entries.map((e) => e.value).reduce(math.max));
    final n = c.entries.length;
    final slot = plotW / n, barW = slot * 0.62;
    final axis = Paint()..color = col(c.axisColor)..strokeWidth = 2;
    canvas.drawLine(Offset(padL, padTop + plotH), Offset(padL + plotW, padTop + plotH), axis);
    final fill = Paint();
    for (var i = 0; i < n; i++) {
      final e = c.entries[i];
      final cx = padL + slot * i + slot / 2;
      final barH = plotH * (e.value / maxVal);
      fill.color = col(e.color);
      canvas.drawRect(Rect.fromLTWH(cx - barW / 2, padTop + plotH - barH, barW, barH), fill);
      _text(canvas, _cap(e.label), cx, h - 14, 7, c.textColor, align: TextAlign.center);
      _text(canvas, '${e.value}', cx, padTop + plotH - barH - 3, 7, c.textColor, align: TextAlign.center); // minutes (#1)
    }
  }

  void _line(Canvas canvas, double w, double h) {
    const padL = 10.0, padR = 10.0, padTop = 12.0, padBottom = 18.0;
    final plotW = w - padL - padR, plotH = h - padTop - padBottom;
    final totals = c.series.totals;
    final n = totals.length;
    final maxVal = math.max(1, totals.isEmpty ? 1 : totals.reduce(math.max));
    final axis = Paint()..color = col(c.axisColor)..strokeWidth = 2;
    canvas.drawLine(Offset(padL, padTop + plotH), Offset(padL + plotW, padTop + plotH), axis);
    double x(int i) => padL + plotW * (n <= 1 ? 0 : i / (n - 1));
    double y(int v) => padTop + plotH * (1 - v / maxVal);

    final path = Path();
    for (var i = 0; i < n; i++) {
      final px = x(i), py = y(totals[i]);
      i == 0 ? path.moveTo(px, py) : path.lineTo(px, py);
    }
    canvas.drawPath(
        path, Paint()..color = col(c.lineColor)..style = PaintingStyle.stroke..strokeWidth = 2.5);
    final dot = Paint()..color = col(c.lineColor);
    for (var i = 0; i < n; i++) {
      canvas.drawCircle(Offset(x(i), y(totals[i])), 2, dot);
    }

    if (c.series.tickLabels.isNotEmpty) {
      _text(canvas, c.series.tickLabels.first, padL, h - 4, 7, c.textColor);
      _text(canvas, c.series.tickLabels.last, padL + plotW, h - 4, 7, c.textColor, align: TextAlign.right);
    }

    final s = sel;
    if (s != null && s >= 0 && s < n) {
      final sx = x(s);
      canvas.drawLine(Offset(sx, padTop), Offset(sx, padTop + plotH),
          Paint()..color = col(c.axisColor)..strokeWidth = 1);
      // selected bucket's tick at the bottom axis, highlighted (#2) — but NOT at
      // the first/last bucket: a fixed gray label already sits there (above), so a
      // red one would land right on top of it and the number would show twice. The
      // ends keep their fixed labels; every other bucket shows the highlighted one
      // on tap (#v21).
      if (s != 0 && s != n - 1) {
        _text(canvas, c.series.tickLabels[s], sx, h - 4, 7, c.lineColor, align: TextAlign.center);
      }
      final detail = c.series.byLabel[s];
      // the bucket label is already drawn on the bottom axis (above), so the
      // callout starts at FOCUS — no duplicated month/year/day/hour (#v19).
      final rows = <(String, String)>[
        (_focus(), _fmt(totals[s])),
        (_avg(), _fmt(c.average)),
        for (final e in detail) (_cap(e.key), _fmt(e.value)),
      ];
      _callout(canvas, w, h, sx, rows);
    }
  }

  /// A bordered callout with right-aligned values (#2), clamped fully inside the
  /// chart so the text never spills outside the plot.
  void _callout(Canvas canvas, double w, double h, double anchorX, List<(String, String)> rows) {
    const fs = 7.0, pad = 4.0, lh = 11.0, gap = 8.0;
    double colW(String s) {
      final tp = TextPainter(
        text: TextSpan(text: s, style: pixelStyle(c.lang, fs, col(c.textColor))),
        textDirection: TextDirection.ltr,
      )..layout();
      return tp.width;
    }
    var lW = 0.0, rW = 0.0;
    for (final (l, r) in rows) {
      lW = math.max(lW, colW(l));
      rW = math.max(rW, colW(r));
    }
    final boxW = lW + gap + rW + pad * 2;
    final boxH = rows.length * lh + pad * 2;
    final left = (anchorX + 6).clamp(0.0, math.max(0.0, w - boxW)).toDouble();
    final top = (12.0).clamp(0.0, math.max(0.0, h - boxH)).toDouble(); // stay inside the chart
    final rect = Rect.fromLTWH(left, top, boxW, boxH);
    canvas.drawRect(rect, Paint()..color = col(c.panelColor));
    canvas.drawRect(rect, Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = col(c.panelBorder));
    _alignedRows(canvas, rows, left + pad, top + pad - lh, left + boxW - pad, fs: fs, lh: lh);
  }

  void _pie(Canvas canvas, double w, double h) {
    final total = c.entries.fold<int>(0, (a, e) => a + e.value).toDouble();
    final legendW = w * 0.5; // wider so full (≤12-char) labels fit (#1)
    final dia = math.min(h - 16, (w - legendW) - 16);
    final cx = 8 + (w - legendW - 8) / 2, cy = h / 2;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: dia / 2);
    var start = -math.pi / 2;
    final fill = Paint();
    final sep = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = col(c.panelColor); // #9 separator in the panel/bg color
    for (final e in c.entries) {
      final sweep = 2 * math.pi * (e.value / total);
      fill.color = col(e.color);
      canvas.drawArc(rect, start, sweep, true, fill);
      canvas.drawArc(rect, start, sweep, true, sep); // wedge outline separates same-colored slices
      start += sweep;
    }
    // legend: swatch + full label left, % right-aligned to a common edge (#1)
    final lx = w - legendW + 4;
    final rightEdge = w - 4;
    var ly = cy - (c.entries.length * 13) / 2;
    for (final e in c.entries) {
      fill.color = col(e.color);
      canvas.drawRect(Rect.fromLTWH(lx, ly + 2, 8, 8), fill);
      final pct = (100 * e.value / total).round();
      _text(canvas, _cap(e.label), lx + 12, ly + 11, 7, c.textColor);
      _text(canvas, '$pct%', rightEdge, ly + 11, 7, c.textColor, align: TextAlign.right);
      ly += 13;
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) => true;
}
