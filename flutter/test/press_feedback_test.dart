import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_pomo/logic.dart';
import 'package:pixel_pomo/pixel.dart';

/// #v34.5 — "pressing a key only changes colour, the user could not tell they
/// had pressed it". A button now sinks onto its own shadow for ~90ms.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final th = Themes.fallback;

  Widget host({VoidCallback? onTap}) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: PixelButton(
              text: 'START',
              fill: th.accent,
              border: th.onSurface,
              textColor: th.onAccent,
              shadow: th.shadow,
              lang: 'en',
              onTap: onTap ?? () {},
            ),
          ),
        ),
      );

  /// Where the button's face currently sits, and how big its shadow is.
  (Offset, Offset) faceAndShadow(WidgetTester tester) {
    final box = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
    final t = box.transform!;
    final deco = box.decoration! as BoxDecoration;
    return (Offset(t.storage[12], t.storage[13]), deco.boxShadow!.first.offset);
  }

  setUp(() => PixelButton.animate = true);
  tearDown(() => PixelButton.animate = true);

  testWidgets('at rest the face is unmoved and the shadow is full', (tester) async {
    await tester.pumpWidget(host());
    final (face, shadow) = faceAndShadow(tester);
    expect(face, Offset.zero);
    expect(shadow, const Offset(kPixelShadowOffset, kPixelShadowOffset));
  });

  testWidgets('holding it down sinks the face onto its shadow', (tester) async {
    await tester.pumpWidget(host());
    final gesture = await tester.startGesture(tester.getCenter(find.byType(PixelButton)));
    await tester.pump(const Duration(milliseconds: 120)); // past the 90ms curve

    final (face, shadow) = faceAndShadow(tester);
    expect(face, const Offset(kPixelShadowOffset, kPixelShadowOffset),
        reason: 'the face did not move toward the shadow');
    expect(shadow, Offset.zero,
        reason: 'the shadow must close up by what the face moved, or it slides sideways');

    await gesture.up();
    await tester.pumpAndSettle();
    expect(faceAndShadow(tester).$1, Offset.zero, reason: 'it never came back up');
  });

  testWidgets('releasing still fires the tap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(onTap: () => taps++));
    await tester.tap(find.byType(PixelButton));
    await tester.pumpAndSettle();
    expect(taps, 1, reason: 'the animation swallowed the tap');
  });

  testWidgets('dragging off cancels the press and the button comes back up', (tester) async {
    await tester.pumpWidget(host());
    final gesture = await tester.startGesture(tester.getCenter(find.byType(PixelButton)));
    await tester.pump(const Duration(milliseconds: 120));
    expect(faceAndShadow(tester).$1, isNot(Offset.zero));

    await gesture.moveTo(const Offset(5, 5)); // off the button
    await gesture.up();
    await tester.pumpAndSettle();
    expect(faceAndShadow(tester).$1, Offset.zero, reason: 'left stuck in the pressed state');
  });

  testWidgets('a disabled button does not pretend to respond', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: PixelButton(
            text: 'BUY 10',
            fill: th.panel,
            border: th.onSurfaceDim,
            textColor: th.onSurface,
            shadow: th.shadow,
            lang: 'en',
            onTap: null, // nothing wired up
          ),
        ),
      ),
    ));
    final gesture = await tester.startGesture(tester.getCenter(find.byType(PixelButton)));
    await tester.pump(const Duration(milliseconds: 120));
    expect(faceAndShadow(tester).$1, Offset.zero,
        reason: 'a dead button animated as if it did something');
    await gesture.up();
  });

  testWidgets('PixelButton.animate = false holds it still, for tests that must settle',
      (tester) async {
    PixelButton.animate = false;
    await tester.pumpWidget(host());
    final gesture = await tester.startGesture(tester.getCenter(find.byType(PixelButton)));
    await tester.pump(const Duration(milliseconds: 120));
    expect(faceAndShadow(tester).$1, Offset.zero);
    await gesture.up();
  });
}
