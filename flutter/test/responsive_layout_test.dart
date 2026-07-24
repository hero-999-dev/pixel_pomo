import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pixel_pomo/logic.dart';
import 'package:pixel_pomo/main.dart';
import 'package:pixel_pomo/pixel.dart';
import 'package:pixel_pomo/store.dart';

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

  testWidgets('the custom editor shows 26 swatches, 13 per row, spanning the panel', (tester) async {
    sizeTo(tester, 390, 1400);
    final s = await boot();
    await tester.pumpWidget(MaterialApp(home: CustomThemeScreen(s)));
    await tester.pumpAndSettle();

    // slot 0 = BACKGROUND; every slot draws the same palette
    final swatches = [for (final c in kSwatches) find.byKey(ValueKey('swatch_0_$c'))];
    expect(kSwatches.length, 26, reason: 'the two added colours (#v33)');
    for (final f in swatches) {
      expect(f, findsOneWidget);
    }

    // exactly two rows: the first 13 share a top, the next 13 share a lower one
    final tops = [for (final f in swatches) tester.getRect(f).top];
    expect(tops.take(kSwatchesPerRow).toSet().length, 1, reason: 'row 1 is not one row');
    expect(tops.skip(kSwatchesPerRow).toSet().length, 1, reason: 'row 2 is not one row');
    expect(tops.first, lessThan(tops.last), reason: 'the second row must sit below the first');

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

  group('a label heatmap fills the column it is given', () {
    // MONTHLY packs 3 per row, 18 WEEKS is full width — both must stretch.
    for (final (period, perRow) in [('MONTHLY', 3), ('18 WEEKS', 1)]) {
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
          // Measure the PAINTED cells, not the grid widget: the label block
          // stretches its children, so the widget's own box is the column
          // width whatever size the cells inside it came out — which is
          // exactly how a capped grid hid in a half-empty column.
          var left = double.infinity, right = 0.0;
          for (final el in find
              .descendant(of: grid, matching: find.byType(Container))
              .evaluate()) {
            final box = el.renderObject! as RenderBox;
            final x = box.localToGlobal(Offset.zero).dx;
            left = math.min(left, x);
            right = math.max(right, x + box.size.width);
          }
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
