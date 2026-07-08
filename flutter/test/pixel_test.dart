import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_pomo/pixel.dart';

/// #v31.14 — Swatch gained an opt-in `plain` style (sharp corners, no
/// border) for the Labels screen and Stats' BY LABEL list specifically; the
/// default (rounded + bordered, #v31.5) stays everywhere else.
void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('default Swatch is rounded with a border', (tester) async {
    await tester.pumpWidget(host(const Swatch(color: 0xFFFF0000, border: 0xFF888888)));
    final deco = tester.widget<Container>(find.byType(Container)).decoration as BoxDecoration;
    expect(deco.borderRadius, isNotNull);
    expect(deco.border, isNotNull);
  });

  testWidgets('plain Swatch has sharp corners and no border', (tester) async {
    await tester.pumpWidget(host(const Swatch(color: 0xFFFF0000, border: 0xFF888888, plain: true)));
    final deco = tester.widget<Container>(find.byType(Container)).decoration as BoxDecoration;
    expect(deco.borderRadius, isNull);
    expect(deco.border, isNull);
    expect(deco.color, const Color(0xFFFF0000)); // the label's own colour still shows
  });
}
