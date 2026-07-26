import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pixel_pomo/logic.dart';
import 'package:pixel_pomo/main.dart';
import 'package:pixel_pomo/pixel.dart';
import 'package:pixel_pomo/store.dart';
import 'package:pixel_pomo/strings.dart';

/// #v33 — "the screen changes size and the layout does not follow it".
///
/// Three separate failures were reported from a browser being narrowed and
/// widened, and each gets a property here rather than a screenshot:
///  1. button labels wrapped inside their own box ("MONTHL/Y"),
///  2. the custom editor's swatches packed left and left a dead strip,
///  3. the label heatmaps stopped growing at a capped cell size, so a wide
///     column ended with empty space on its right.
///
/// All three are measured against the REAL rendered geometry at several widths,
/// because every one of them looks correct at exactly one screen size.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppStore> boot() async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore();
    await s.load();
    return s;
  }

  /// Set the logical screen size for one test.
  void sizeTo(WidgetTester tester, double w, double h) {
    tester.view.physicalSize = Size(w * 3, h * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  Widget focusHost(AppStore s) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              // the same 28px the real overlay scaffold pads with
              padding: const EdgeInsets.all(28),
              child: FocusSessionsSection(
                  th: Themes.dark, lang: 'en', s: s, today: epochDayOf(DateTime.now())),
            ),
          ),
        ),
      );

  group('button labels stay on one line and inside their box', () {
    // 320 is the narrowest phone worth supporting; 360/390 are the common ones.
    for (final width in [320.0, 360.0, 390.0]) {
      testWidgets('at ${width.toInt()}px wide', (tester) async {
        sizeTo(tester, width, 900);
        final s = await boot();
        await tester.pumpWidget(focusHost(s));
        await tester.pumpAndSettle();

        for (final label in ['WEEKLY', 'MONTHLY', '18 WEEKS', 'YEARLY']) {
          final text = find.text(label).first;
          final button = find.ancestor(of: text, matching: find.byType(PixelButton)).first;
          // ONE line — comparing the text box to the button box is not enough:
          // a wrapped label makes its BUTTON taller, so both still "fit". The
          // paragraph's own laid-out height (before the FittedBox scales it)
          // against the same string forced onto one line is the real test.
          // Reference span taken from the render object itself, so it carries
          // the RESOLVED style (the ambient DefaultTextStyle adds line height
          // the widget's own `style` does not show).
          final paragraph = tester.renderObject<RenderParagraph>(text);
          final oneLine = TextPainter(
            text: paragraph.text,
            textDirection: TextDirection.ltr,
            maxLines: 1,
          )..layout();
          expect(paragraph.size.height, lessThanOrEqualTo(oneLine.height + 0.5),
              reason: '"$label" wrapped onto a second line at ${width.toInt()}px');
          // ...and still inside it: getRect goes through the FittedBox's
          // transform, so this is the SCALED text, i.e. what is on screen.
          final t = tester.getRect(text), b = tester.getRect(button);
          expect(t.width, lessThanOrEqualTo(b.width + 0.5),
              reason: '"$label" overflows its button at ${width.toInt()}px');
        }
      });
    }
  });

  testWidgets('the editor palette shows every colour, 13 per row, spanning the panel',
      (tester) async {
    sizeTo(tester, 390, 1400);
    final s = await boot();
    await tester.pumpWidget(MaterialApp(home: CustomThemeScreen(s)));
    await tester.pumpAndSettle();

    // one shared palette (#v33.2), keyed by colour without the slot; the hue
    // ramp and the preset colours are one sorted grid since #v33.4
    final swatches = [for (final c in kAllSwatches) find.byKey(ValueKey('swatch_$c'))];
    expect(kSwatches.length, 28, reason: 'the teal gained its dark and light (#v33.4)');
    for (final f in swatches) {
      expect(f, findsOneWidget);
    }

    // full rows: the first 13 share a top, the next 13 share a lower one
    final tops = [for (final f in swatches) tester.getRect(f).top];
    expect(tops.take(kSwatchesPerRow).toSet().length, 1, reason: 'row 1 is not one row');
    expect(tops.skip(kSwatchesPerRow).take(kSwatchesPerRow).toSet().length, 1,
        reason: 'row 2 is not one row');
    expect(tops.first, lessThan(tops.last), reason: 'later swatches must sit lower');

    // and the row spans the full content width — the same edges the buttons
    // above/below it use, which is what "align it with the boxes" asked for
    final content = 390.0 - 28 * 2;
    final rowLeft = tester.getRect(swatches.first).left;
    final rowRight = tester.getRect(swatches[kSwatchesPerRow - 1]).right;
    expect(rowRight - rowLeft, closeTo(content, 1.0),
        reason: 'the swatch row leaves a dead strip instead of filling the panel');
  });

  group('every overlay survives being narrowed and widened', () {
    // The report was "I resize the browser and it stops fitting". Flutter
    // reports an overflowing Row/Column as an exception in tests, so pumping
    // each screen at the extremes is a cheap net for the whole app — one that
    // the fixed 800×600 test surface never caught.
    for (final width in [320.0, 900.0]) {
      testWidgets('at ${width.toInt()}px wide', (tester) async {
        sizeTo(tester, width, 2400);
        final s = await boot();
        final screens = <String, Widget Function()>{
          'stats': () => StatsScreen(s),
          'sessions in pixels': () => SessionsInPixelsScreen(s),
          'custom theme': () => CustomThemeScreen(s),
          'colour picker': () => ColorPickerScreen(
                s: s,
                slotLabel: t(s.lang, 'cBg'),
                initial: 0xFF1B3A63,
                themeOf: () => Themes.dark,
                onPick: (_) {},
              ),
          'shop': () => ShopScreen(s),
          'habits': () => HabitScreen(s),
          'settings': () => SettingsScreen(s),
          'labels': () => LabelScreen(s),
          'money': () => MoneyScreen(s),
        };
        for (final e in screens.entries) {
          await tester.pumpWidget(MaterialApp(home: e.value()));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull,
              reason: '${e.key} overflows at ${width.toInt()}px');
        }
      });
    }
  });

  testWidgets('shop BUY sits left of SELL, on the same row (#v33.1)', (tester) async {
    sizeTo(tester, 390, 1400);
    final s = await boot();
    await tester.pumpWidget(MaterialApp(home: ShopScreen(s)));
    await tester.pumpAndSettle();

    final buy = tester.getRect(find.textContaining('BUY').first);
    final sell = tester.getRect(find.textContaining('SELL').first);
    expect(buy.right, lessThanOrEqualTo(sell.left + 1),
        reason: 'BUY must be entirely left of SELL, not stacked above it');
    // same row: their vertical centres line up
    expect((buy.center.dy - sell.center.dy).abs(), lessThan(4),
        reason: 'BUY and SELL are on different rows');
  });

  group('shop OWNED/PLACED stays on one line (#v33.4)', () {
    // "it slides underneath on a small screen — keep it on one row". TR and PL
    // are the long ones: "SAHİP 0   BAHÇEDE 0", "MASZ 0   W OGRODZIE 0".
    for (final lang in ['en', 'tr', 'pl']) {
      testWidgets('$lang at 320px', (tester) async {
        sizeTo(tester, 320, 1600);
        final s = await boot();
        s.selectLanguage(lang);
        await tester.pumpWidget(MaterialApp(home: ShopScreen(s)));
        await tester.pumpAndSettle();

        // the counters line of the first shop row, whatever language it is in
        final word = t(lang, 'placed').split(' ').first;
        final text = find.textContaining(word).first;
        // the paragraph's own laid-out height against the same string forced
        // onto one line — the FittedBox scales what is on screen, so measuring
        // the rendered rect would hide a wrap (same trick as the buttons above)
        final paragraph = tester.renderObject<RenderParagraph>(text);
        final oneLine = TextPainter(
          text: paragraph.text,
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
        expect(paragraph.size.height, lessThanOrEqualTo(oneLine.height + 0.5),
            reason: 'OWNED/PLACED wrapped onto a second line in $lang at 320px');
      });
    }
  });

  testWidgets('monthly 3-up columns are equal width — the 3rd was bigger (#v33.2)', (tester) async {
    sizeTo(tester, 390, 2400);
    final s = await boot();
    await tester.pumpWidget(focusHost(s));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MONTHLY'));
    await tester.pumpAndSettle();

    // every seeded label that shows this month has a keyed grid; group them
    // into rows by their top and check the first full row's widths match.
    final rects = <Rect>[];
    for (final lbl in TestData.labels) {
      final f = find.byKey(ValueKey('labelGrid_$lbl'));
      if (f.evaluate().isNotEmpty) rects.add(tester.getRect(f.first));
    }
    expect(rects.length, greaterThanOrEqualTo(3), reason: 'need a full first row to compare');
    final top0 = rects.map((r) => r.top).reduce(math.min);
    final row0 = rects.where((r) => (r.top - top0).abs() < 2).map((r) => r.width).toList();
    expect(row0.length, 3, reason: 'monthly should pack 3 per row (#v34.3)');
    for (final w in row0) {
      expect((w - row0.first).abs(), lessThan(2), reason: 'columns unequal: $row0');
    }
  });

  group('a label heatmap fills the column it is given', () {
    // MONTHLY packs 3 per row (#v34.3); 18 WEEKS and YEARLY(horizontal) are full width.
    for (final (period, perRow) in [('MONTHLY', 3), ('18 WEEKS', 1), ('YEARLY', 1)]) {
      for (final width in [360.0, 800.0]) {
        testWidgets('$period at ${width.toInt()}px', (tester) async {
          sizeTo(tester, width, 2400);
          final s = await boot();
          await tester.pumpWidget(focusHost(s));
          await tester.pumpAndSettle();
          await tester.tap(find.text(period));
          await tester.pumpAndSettle();

          final grid = find.byKey(const ValueKey('labelGrid_MATH'));
          expect(grid, findsOneWidget, reason: '$period lost MATH');
          // Measure the CELLS, not the label block: the block stretches its
          // children, so its own box is the column width whatever size the
          // cells came out — which is exactly how a capped grid used to hide
          // in a half-empty column.
          //
          // Two shapes since #v34.7: painted grids size themselves to their
          // cells, so their render box IS the painted extent; the widget cells
          // that remain are measured one by one as before.
          var left = double.infinity, right = 0.0;
          void span(double x, double w) {
            left = math.min(left, x);
            right = math.max(right, x + w);
          }

          final grids = find.descendant(of: grid, matching: find.byType(CellGrid));
          for (final el in grids.evaluate()) {
            final box = el.renderObject! as RenderBox;
            span(box.localToGlobal(Offset.zero).dx, box.size.width);
          }
          for (final el in find.descendant(of: grid, matching: find.byType(Container)).evaluate()) {
            final box = el.renderObject! as RenderBox;
            span(box.localToGlobal(Offset.zero).dx, box.size.width);
          }
          expect(left.isFinite, isTrue, reason: '$period rendered no cells at all');
          final column = (width - 28 * 2 - (perRow - 1) * 6) / perRow;
          final painted = right - left;
          expect(painted, lessThanOrEqualTo(column + 0.5),
              reason: '$period overflows its column at ${width.toInt()}px');
          // the only shortfall allowed is whole-pixel rounding of one cell per
          // column (a few px), never a cap leaving the column half empty
          expect(painted, greaterThan(column * 0.92),
              reason: '$period fills only ${(painted / column * 100).round()}% '
                  'of its column at ${width.toInt()}px');
        });
      }
    }
  });
}
