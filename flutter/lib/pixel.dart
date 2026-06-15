import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'logic.dart';
import 'store.dart';

/// ARGB int → Flutter [Color].
Color col(int argb) => Color(argb);

/// The pixel font for Latin scripts; null (system font) for Korean, which it can't render.
String? fontFor(String lang) => lang == 'ko' ? null : 'PressStart2P';

TextStyle pixelStyle(String lang, double size, Color color, {double spacing = 0}) =>
    TextStyle(fontFamily: fontFor(lang), fontSize: size, color: color, letterSpacing: spacing);

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

/// One per-label datum for the chart.
class ChartEntry {
  final String label;
  final int value;
  final int color;
  const ChartEntry(this.label, this.value, this.color);
}

/// Bar / line / pie chart for the selected month (a port of the Android `ChartView`).
class StatsChart extends StatelessWidget {
  final List<ChartEntry> entries; // per-label (bar/pie)
  final List<int> daySeries; // per-day (line)
  final ChartMode mode;
  final String lang;
  final int axisColor, textColor, lineColor;

  const StatsChart({
    super.key,
    required this.entries,
    required this.daySeries,
    required this.mode,
    required this.lang,
    required this.axisColor,
    required this.textColor,
    required this.lineColor,
  });

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _ChartPainter(this), child: const SizedBox.expand());
}

class _ChartPainter extends CustomPainter {
  final StatsChart c;
  _ChartPainter(this.c);

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

  bool _hasData() =>
      c.mode == ChartMode.line ? c.daySeries.any((v) => v > 0) : c.entries.any((e) => e.value > 0);

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
    // strings.dart's chartNoData via lang would need an import cycle; keep a tiny inline map.
    const m = {
      'en': 'No focus minutes this month.',
      'tr': 'Bu ay odak dakikası yok.',
      'pl': 'Brak minut w tym miesiącu.',
      'de': 'Keine Minuten in diesem Monat.',
      'ko': '이번 달 기록이 없습니다.',
      'it': 'Nessun minuto questo mese.',
    };
    return m[c.lang] ?? m['en']!;
  }

  String _short(String s) => s.length <= 6 ? s : s.substring(0, 6);
  String _fmt(int min) => StatsAggregator.formatMinutes(min);

  void _bars(Canvas canvas, double w, double h) {
    const padL = 8.0, padR = 8.0, padTop = 10.0, padBottom = 26.0;
    final plotW = w - padL - padR;
    final plotH = h - padTop - padBottom;
    final maxVal = math.max(1, c.entries.map((e) => e.value).reduce(math.max));
    final n = c.entries.length;
    final slot = plotW / n;
    final barW = slot * 0.62;

    final axis = Paint()
      ..color = col(c.axisColor)
      ..strokeWidth = 2;
    canvas.drawLine(Offset(padL, padTop + plotH), Offset(padL + plotW, padTop + plotH), axis);

    final fill = Paint();
    for (var i = 0; i < n; i++) {
      final e = c.entries[i];
      final cx = padL + slot * i + slot / 2;
      final barH = plotH * (e.value / maxVal);
      final left = cx - barW / 2;
      final top = padTop + plotH - barH;
      fill.color = col(e.color);
      canvas.drawRect(Rect.fromLTWH(left, top, barW, barH), fill);
      _text(canvas, _short(e.label), cx, h - 14, 7, c.textColor, align: TextAlign.center);
      _text(canvas, _fmt(e.value), cx, top - 3, 7, c.textColor, align: TextAlign.center);
    }
  }

  void _line(Canvas canvas, double w, double h) {
    const padL = 10.0, padR = 10.0, padTop = 12.0, padBottom = 18.0;
    final plotW = w - padL - padR;
    final plotH = h - padTop - padBottom;
    final maxVal = math.max(1, c.daySeries.reduce(math.max));
    final n = c.daySeries.length;

    final axis = Paint()
      ..color = col(c.axisColor)
      ..strokeWidth = 2;
    canvas.drawLine(Offset(padL, padTop + plotH), Offset(padL + plotW, padTop + plotH), axis);

    double x(int i) => padL + plotW * (n <= 1 ? 0 : i / (n - 1));
    double y(int v) => padTop + plotH * (1 - v / maxVal);

    final path = Path();
    for (var i = 0; i < n; i++) {
      final px = x(i), py = y(c.daySeries[i]);
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }
    final stroke = Paint()
      ..color = col(c.lineColor)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawPath(path, stroke);

    final dot = Paint()..color = col(c.lineColor);
    for (var i = 0; i < n; i++) {
      canvas.drawCircle(Offset(x(i), y(c.daySeries[i])), 2, dot);
    }
    _text(canvas, '1', padL, h - 4, 7, c.textColor);
    _text(canvas, '$n', padL + plotW, h - 4, 7, c.textColor, align: TextAlign.right);
  }

  void _pie(Canvas canvas, double w, double h) {
    final total = c.entries.fold<int>(0, (a, e) => a + e.value).toDouble();
    final legendW = w * 0.42;
    final dia = math.min(h - 16, (w - legendW) - 16);
    final cx = 8 + (w - legendW - 8) / 2;
    final cy = h / 2;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: dia / 2);

    var start = -math.pi / 2;
    final fill = Paint();
    for (final e in c.entries) {
      final sweep = 2 * math.pi * (e.value / total);
      fill.color = col(e.color);
      canvas.drawArc(rect, start, sweep, true, fill);
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
  bool shouldRepaint(covariant _ChartPainter oldDelegate) => true;
}
