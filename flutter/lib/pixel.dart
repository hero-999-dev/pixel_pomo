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

/// The pixel font. Press Start 2P has no Hangul, so Korean uses Galmuri11 — a
/// pixel font (OFL) that covers Korean while keeping the retro look.
String fontFor(String lang) => lang == 'ko' ? 'Galmuri11' : 'PressStart2P';

/// Galmuri11's glyphs sit smaller in the em box than Press Start 2P, so Korean
/// text needs a bump to stay legible at the same nominal sizes.
double _fontScale(String lang) => lang == 'ko' ? 1.5 : 1.0;

TextStyle pixelStyle(String lang, double size, Color color, {double spacing = 0}) =>
    TextStyle(fontFamily: fontFor(lang), fontSize: size * _fontScale(lang), color: color, letterSpacing: spacing);

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

/// One per-label line (daily multi-line mode).
class LabelLine {
  final String label;
  final int color;
  final List<int> values;
  const LabelLine(this.label, this.color, this.values);
}

/// Bar / line / pie chart for the selected stats period. Line mode is tappable:
/// tapping a bucket shows its total + per-label breakdown (#10). DAILY draws one
/// line per label (#10 multi-line); other periods draw one total line.
class StatsChart extends StatefulWidget {
  final List<ChartEntry> entries; // by-label for bar/pie
  final StatSeries series; // totals + tick labels + per-bucket by-label
  final List<LabelLine>? labelLines; // non-null + multiLine → daily per-label
  final bool multiLine;
  final ChartMode mode;
  final String lang;
  final int axisColor, textColor, lineColor, panelColor, panelBorder;

  const StatsChart({
    super.key,
    required this.entries,
    required this.series,
    required this.labelLines,
    required this.multiLine,
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

  String _short(String s) => s.length <= 6 ? s : s.substring(0, 6);
  String _fmt(int min) => StatsAggregator.formatMinutes(min);

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
      _text(canvas, _short(e.label), cx, h - 14, 7, c.textColor, align: TextAlign.center);
      _text(canvas, _fmt(e.value), cx, padTop + plotH - barH - 3, 7, c.textColor, align: TextAlign.center);
    }
  }

  void _line(Canvas canvas, double w, double h) {
    const padL = 10.0, padR = 10.0, padTop = 12.0, padBottom = 18.0;
    final plotW = w - padL - padR, plotH = h - padTop - padBottom;
    final totals = c.series.totals;
    final n = totals.length;
    final lines = (c.multiLine && c.labelLines != null && c.labelLines!.isNotEmpty)
        ? c.labelLines!
        : null;
    final maxVal = math.max(
        1,
        lines == null
            ? totals.reduce(math.max)
            : lines.expand((l) => l.values).fold(1, math.max));
    final axis = Paint()..color = col(c.axisColor)..strokeWidth = 2;
    canvas.drawLine(Offset(padL, padTop + plotH), Offset(padL + plotW, padTop + plotH), axis);
    double x(int i) => padL + plotW * (n <= 1 ? 0 : i / (n - 1));
    double y(int v) => padTop + plotH * (1 - v / maxVal);

    void drawSeries(List<int> vals, int color) {
      final path = Path();
      for (var i = 0; i < vals.length; i++) {
        final px = x(i), py = y(vals[i]);
        i == 0 ? path.moveTo(px, py) : path.lineTo(px, py);
      }
      canvas.drawPath(
          path, Paint()..color = col(color)..style = PaintingStyle.stroke..strokeWidth = 2.5);
      final dot = Paint()..color = col(color);
      for (var i = 0; i < vals.length; i++) {
        canvas.drawCircle(Offset(x(i), y(vals[i])), 2, dot);
      }
    }

    if (lines == null) {
      drawSeries(totals, c.lineColor);
    } else {
      for (final l in lines) {
        drawSeries(l.values, l.color);
      }
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
      final detail = c.series.byLabel[s];
      final lines2 = <String>[
        '${c.series.tickLabels[s]} · ${_fmt(totals[s])}',
        for (final e in detail) '${_short(e.key)} ${_fmt(e.value)}',
      ];
      _callout(canvas, w, sx, padTop + 4, lines2);
    }
  }

  void _callout(Canvas canvas, double w, double anchorX, double top, List<String> lines) {
    const fs = 7.0, pad = 4.0, lh = 11.0;
    var maxW = 0.0;
    for (final s in lines) {
      final tp = TextPainter(
        text: TextSpan(text: s, style: pixelStyle(c.lang, fs, col(c.textColor))),
        textDirection: TextDirection.ltr,
      )..layout();
      maxW = math.max(maxW, tp.width);
    }
    final boxW = maxW + pad * 2;
    final boxH = lines.length * lh + pad * 2;
    var left = anchorX + 6;
    if (left + boxW > w) left = anchorX - 6 - boxW;
    if (left < 0) left = 0;
    final rect = Rect.fromLTWH(left, top, boxW, boxH);
    canvas.drawRect(rect, Paint()..color = col(c.panelColor));
    canvas.drawRect(rect, Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = col(c.panelBorder));
    var ty = top + pad + lh;
    for (final s in lines) {
      _text(canvas, s, left + pad, ty, fs, c.textColor);
      ty += lh;
    }
  }

  void _pie(Canvas canvas, double w, double h) {
    final total = c.entries.fold<int>(0, (a, e) => a + e.value).toDouble();
    final legendW = w * 0.42;
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
    final lx = w - legendW + 6;
    var ly = cy - (c.entries.length * 13) / 2 + 8;
    for (final e in c.entries) {
      fill.color = col(e.color);
      canvas.drawRect(Rect.fromLTWH(lx, ly - 7, 8, 8), fill);
      final pct = (100 * e.value / total).round();
      _text(canvas, '${_short(e.label)} $pct%', lx + 12, ly + 1, 7, c.textColor);
      ly += 13;
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) => true;
}
