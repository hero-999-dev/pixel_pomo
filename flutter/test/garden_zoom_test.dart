import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_pomo/engine/garden_engine.dart';
import 'package:pixel_pomo/engine/garden_view.dart';
import 'package:pixel_pomo/logic.dart';
import 'package:pixel_pomo/main.dart' show gardenSprites;

/// #v34.4 — "check the zoom in/out on the phone for garden editing, whether it
/// works properly". Pinch is a touch gesture, so the pure `wheelZoom` tests
/// (#v33.8) say nothing about it; this drives the real two-finger gesture
/// against the real widget, including while CUSTOMIZE is on, where the tap
/// handler that places tiles is also live and could swallow it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SpriteBank sprites;

  setUpAll(() async {
    // decoding PNGs is real async — fake-async pump() can't drive it
    sprites = await gardenSprites();
  });

  Future<GardenCamera> pump(WidgetTester tester, {required bool customizing}) async {
    final cam = GardenCamera();
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GardenView(
          garden: const Garden(cols: 4, rows: 6),
          sprites: sprites,
          customizing: customizing,
          onTapTile: (_) => taps++,
          groundColor: 0xFF57A636,
          soilColor: 0xFF6B4A2F,
          uiColor: 0xFFE8E9F0,
          panelColor: 0xFF1B1D27,
          lang: 'en',
          tr: (k) => k,
          camera: cam,
        ),
      ),
    ));
    await tester.pump();
    return cam;
  }

  /// Two fingers moving apart (or together) about the centre of the view.
  Future<void> pinch(WidgetTester tester, {required double from, required double to}) async {
    final c = tester.getCenter(find.byType(GardenView));
    final a = await tester.startGesture(c + Offset(-from, 0));
    final b = await tester.startGesture(c + Offset(from, 0));
    await tester.pump();
    // walk outward in steps, the way real fingers arrive
    const steps = 8;
    for (var i = 1; i <= steps; i++) {
      final d = from + (to - from) * i / steps;
      await a.moveTo(c + Offset(-d, 0));
      await b.moveTo(c + Offset(d, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await a.up();
    await b.up();
    await tester.pump();
  }

  testWidgets('pinching out zooms in', (tester) async {
    final cam = await pump(tester, customizing: false);
    final before = cam.zoom;
    await pinch(tester, from: 40, to: 120);
    expect(cam.zoom, greaterThan(before), reason: 'spreading two fingers did not zoom in');
  });

  testWidgets('pinching in zooms out', (tester) async {
    final cam = await pump(tester, customizing: false);
    cam.zoom = 2.0; // start zoomed so there is room to come back down
    await pinch(tester, from: 120, to: 40);
    expect(cam.zoom, lessThan(2.0), reason: 'bringing two fingers together did not zoom out');
  });

  testWidgets('zoom works with CUSTOMIZE on — the tile-placing tap does not swallow it',
      (tester) async {
    // This is the case actually asked about: editing the garden while zooming.
    final cam = await pump(tester, customizing: true);
    final before = cam.zoom;
    await pinch(tester, from: 40, to: 120);
    expect(cam.zoom, greaterThan(before), reason: 'CUSTOMIZE blocks pinch-zoom');
  });

  testWidgets('zoom stays inside its 0.5x-4x range', (tester) async {
    final cam = await pump(tester, customizing: true);
    await pinch(tester, from: 20, to: 380); // far past 4x
    expect(cam.zoom, lessThanOrEqualTo(4.0));

    cam.zoom = 4.0;
    await pinch(tester, from: 380, to: 8); // far past 0.5x
    expect(cam.zoom, greaterThanOrEqualTo(0.5));
  });

  testWidgets('RECENTER puts the zoom back', (tester) async {
    final cam = await pump(tester, customizing: false);
    await pinch(tester, from: 40, to: 160);
    expect(cam.zoom, isNot(1.0));
    cam.reset();
    expect(cam.zoom, 1.0);
    expect(cam.panX, 0.0);
    expect(cam.panY, 0.0);
  });
}
