import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Decoded menu icon sheets (5 icons per row, a label band below each). Sliced
/// at runtime by [MenuIcon] so the user's pixel art is used verbatim (#3).
class IconBank {
  final ui.Image menu; // Main menu.png: palette / flower / bar-chart / gear / market
  final ui.Image store; // Only Get Store.png: …/veggie stall (col 4 = store icon)
  const IconBank(this.menu, this.store);

  static Future<IconBank> load() async {
    Future<ui.Image> grab(String a) async {
      final d = await rootBundle.load(a);
      final c = await ui.instantiateImageCodec(d.buffer.asUint8List());
      return (await c.getNextFrame()).image;
    }
    return IconBank(
        await grab('assets/icon/menu_sheet.png'), await grab('assets/icon/store_sheet.png'));
  }
}

/// One icon sliced from a 5-column sheet. [column] selects the icon; a square is
/// taken from the top of the cell (the label band below is cropped out).
class MenuIcon extends StatelessWidget {
  final ui.Image sheet;
  final int column;
  final double size;
  const MenuIcon(this.sheet, this.column, {super.key, this.size = 30});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(size, size), painter: _IconPainter(sheet, column));
}

class _IconPainter extends CustomPainter {
  final ui.Image sheet;
  final int column;
  _IconPainter(this.sheet, this.column);

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = sheet.width / 5.0;
    const topPad = 24.0; // skip the cell's top padding
    final side = cellW; // square crop from the top of the cell holds the icon
    final src = Rect.fromLTWH(column * cellW, topPad, side, side);
    final dst = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawImageRect(sheet, src, dst, Paint()..filterQuality = FilterQuality.none);
  }

  @override
  bool shouldRepaint(covariant _IconPainter old) => old.column != column || old.sheet != sheet;
}
