import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pixel_pomo/main.dart';
import 'package:pixel_pomo/store.dart';

/// #v33.7 — "scrolling down any page — app block, app list, pixel logs,
/// sessions in pixels — goes down in fits, nothing like scrolling a website or
/// a feed." Three separate things were fighting the drag, and each one has an
/// assertion here:
///
///  1. the fling curve — Android's clamping physics stops a fling dead
///  2. the frame budget — a `SingleChildScrollView` paints its child into its
///     own layer, so every frame of a drag re-recorded the entire page
///  3. the thread — the countdown rebuilt the app five times a second, and the
///     home screen kept doing it while it was covered by the page being read
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppStore> boot() async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore();
    await s.load();
    return s;
  }

  testWidgets('every scrollable in the app carries momentum physics and no glow', (tester) async {
    final s = await boot();
    await tester.pumpWidget(PixelPomoApp(s));
    await tester.pumpAndSettle();

    // read the app's own ScrollConfiguration from inside it
    final ctx = tester.element(find.byType(Navigator).first);
    final behavior = ScrollConfiguration.of(ctx);
    final physics = behavior.getScrollPhysics(ctx);

    expect(physics, isA<BouncingScrollPhysics>(),
        reason: 'clamping physics stops a fling dead — that is the "it does not flow" half');
    expect(physics.parent, isA<AlwaysScrollableScrollPhysics>(),
        reason: 'a short page should still rubber-band, the way a feed does');

    // the bounce IS the edge feedback; the Material glow on top of it is not
    const marker = SizedBox.shrink();
    expect(
      behavior.buildOverscrollIndicator(ctx, marker, const ScrollableDetails(direction: AxisDirection.down)),
      same(marker),
    );

    // desktop/web: the page can be dragged, not only wheel-scrolled
    expect(behavior.dragDevices, contains(PointerDeviceKind.mouse));
    expect(behavior.dragDevices, contains(PointerDeviceKind.touch));

    s.dispose();
  });

  testWidgets('scrolling a page does not repaint the sections it is scrolling', (tester) async {
    final s = await boot();
    final hits = <int>[];

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => overlayScaffold(ctx, s, 'TEST', [
          SizedBox(height: 200, child: CustomPaint(painter: _PaintCounter(hits))),
          // enough page under it to have somewhere to scroll to
          for (var i = 0; i < 20; i++) const SizedBox(height: 100),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    expect(hits, isNotEmpty, reason: 'the section should paint at least once when it first appears');
    final atRest = hits.length;

    // drag the page up, staying small enough that the section is still on screen
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -120));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(hits.length, atRest,
        reason: 'a section behind a RepaintBoundary is a layer the compositor moves — '
            'scrolling must not re-record it. Remove the boundary and this climbs with every frame.');

    s.dispose();
  });

  test('the running clock does not fire the store notifier', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore();
    await s.load();
    s.setPomodoroMode(false); // stopwatch — same 200ms tick, no phase to end mid-test
    s.start();

    // subscribe AFTER start(), which legitimately notifies once
    var storeNotifications = 0;
    s.addListener(() => storeNotifications++);
    final before = s.ticks.value;

    // real time, not fake-async: the store reads DateTime.now() directly
    await Future.delayed(const Duration(milliseconds: 450));

    expect(s.ticks.value, greaterThan(before), reason: 'the clock still has to move');
    expect(storeNotifications, 0,
        reason: 'the app root listens to the store — a tick going out on it rebuilt every route, '
            'five times a second, under whatever was being scrolled');

    s.dispose();
  });

  testWidgets('a covered home screen stops listening to the clock', (tester) async {
    final s = await boot();
    s.setPomodoroMode(false);
    await tester.pumpWidget(MaterialApp(home: HomeScreen(s)));
    await tester.pumpAndSettle();
    expect(find.text('00:00'), findsOneWidget);

    // on screen: a tick moves the clock
    s.stopwatch.setElapsed(5000);
    s.ticks.value++;
    await tester.pump();
    expect(find.text('00:05'), findsOneWidget);

    // open a page over it, the way every panel in the app does
    final nav = Navigator.of(tester.element(find.byType(HomeScreen)));
    nav.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('PANEL'))));
    await tester.pumpAndSettle();

    s.stopwatch.setElapsed(9000);
    s.ticks.value++;
    await tester.pump();

    // still mounted underneath, still showing the old time: the tick never
    // reached it, so it was not competing with the page on top
    expect(find.text('00:05', skipOffstage: false), findsOneWidget);
    expect(find.text('00:09', skipOffstage: false), findsNothing);

    // and it catches up the moment it is visible again
    nav.pop();
    await tester.pumpAndSettle();
    expect(find.text('00:09'), findsOneWidget);

    s.dispose();
  });
}

/// Records one entry per paint. `shouldRepaint` is false on purpose: this
/// counts times the SECTION was painted by its parent, not times the delegate
/// changed.
class _PaintCounter extends CustomPainter {
  const _PaintCounter(this.hits);
  final List<int> hits;

  @override
  void paint(Canvas canvas, Size size) => hits.add(1);

  @override
  bool shouldRepaint(_PaintCounter old) => false;
}
