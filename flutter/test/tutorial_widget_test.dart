import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pixel_pomo/main.dart';
import 'package:pixel_pomo/store.dart';
import 'package:pixel_pomo/tutorial.dart';

/// #v34 — the first-run tour: pops itself on a fresh install, walks the screen
/// one highlighted box at a time, and can be skipped.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppStore> boot([Map<String, Object> prefs = const {}]) async {
    SharedPreferences.setMockInitialValues({...prefs});
    final s = AppStore();
    await s.load();
    return s;
  }

  Widget host(AppStore s) => MaterialApp(home: HomeScreen(s));

  /// The hole the scrim is cut around right now, if any.
  Rect? spotlight(WidgetTester tester) {
    final paints = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .where((p) => p.painter is SpotlightPainter);
    return paints.isEmpty ? null : (paints.first.painter as SpotlightPainter).hole;
  }

  testWidgets('a fresh install opens on the tour, not on a bare timer', (tester) async {
    final s = await boot();
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();

    expect(find.text('A QUICK TOUR'), findsOneWidget);
    expect(find.byKey(const Key('tutorialSkip')), findsOneWidget);
    expect(find.byKey(const Key('tutorialNext')), findsOneWidget);
    // step 1 introduces the app itself, so nothing is singled out yet
    expect(spotlight(tester), isNull);

    s.dispose();
  });

  testWidgets('a second launch does not replay it', (tester) async {
    final s = await boot({'flutter.tutorial_done': true});
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();

    expect(find.text('A QUICK TOUR'), findsNothing);
    expect(find.byKey(const Key('tutorialSkip')), findsNothing);

    s.dispose();
  });

  testWidgets('NEXT walks the steps and each one highlights a real widget', (tester) async {
    final s = await boot();
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();

    // both trackers are hidden by default (#v34), so their steps drop out:
    // welcome, timer, label, stats, garden, theme, settings, store, coin, end.
    expect(find.text('1/10'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tutorialNext')));
    await tester.pumpAndSettle();
    expect(find.text('THE TIMER'), findsOneWidget);
    final timerHole = spotlight(tester);
    expect(timerHole, isNotNull, reason: 'the timer step must cut a hole around the real timer');
    expect(timerHole!.width, greaterThan(0));

    // ...and the next step moves the hole somewhere else — the tour follows the
    // widgets, it does not draw one fixed box.
    await tester.tap(find.byKey(const Key('tutorialNext')));
    await tester.pumpAndSettle();
    expect(find.text('LABEL'), findsWidgets);
    expect(spotlight(tester), isNot(timerHole));

    s.dispose();
  });

  testWidgets('showing a tracker puts its step back in the tour', (tester) async {
    final s = await boot({'flutter.show_habit_tracker': true, 'flutter.show_money_tracker': true});
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();
    expect(find.text('1/12'), findsOneWidget);

    s.dispose();
  });

  testWidgets('SKIP closes the tour and it stays closed after a restart', (tester) async {
    final s = await boot();
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('tutorialSkip')));
    await tester.pumpAndSettle();

    expect(find.text('A QUICK TOUR'), findsNothing);
    expect(find.text('START'), findsOneWidget); // the app underneath is usable again
    expect(s.tutorialDone, true);

    final reopened = AppStore();
    await reopened.load();
    expect(reopened.tutorialDone, true);

    s.dispose();
    reopened.dispose();
  });

  testWidgets('walking to the end finishes it the same way SKIP does', (tester) async {
    final s = await boot();
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();

    for (var i = 0; i < 9; i++) {
      // 10 steps, so 9 taps to stand on the last one
      await tester.tap(find.byKey(const Key('tutorialNext')));
      await tester.pumpAndSettle();
    }
    expect(find.text('READY'), findsOneWidget); // last step
    expect(find.text('DONE'), findsOneWidget); // NEXT became DONE

    await tester.tap(find.byKey(const Key('tutorialNext')));
    await tester.pumpAndSettle();
    expect(find.text('READY'), findsNothing);
    expect(s.tutorialDone, true);

    s.dispose();
  });

  testWidgets('the card stays on screen even beside a tall centred target', (tester) async {
    // CLEAN home centres the whole timer block, leaving thin gaps above and
    // below it. Anchoring the card to that box pushed SKIP/NEXT off the top.
    // a SHORT phone, not the 800x600 test default: with the timer block centred
    // here, neither gap above nor below it fits the card — the case that broke.
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(360 * 3, 560 * 3);
    addTearDown(tester.view.reset);

    final s = await boot({'flutter.home_backdrop': 'clean'});
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tutorialNext'))); // the timer step
    await tester.pumpAndSettle();

    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    // the whole card, not just the buttons: a card hanging off the edge is the
    // symptom, and its title is as much a part of the tour as SKIP is.
    for (final key in [
      const Key('tutorialCard'),
      const Key('tutorialSkip'),
      const Key('tutorialNext'),
    ]) {
      final r = tester.getRect(find.byKey(key));
      expect(r.top, greaterThanOrEqualTo(0.0), reason: '$key ran off the top');
      expect(r.bottom, lessThanOrEqualTo(screen.height), reason: '$key ran off the bottom');
    }

    s.dispose();
  });

  testWidgets('the tour blocks the screen underneath while it is up', (tester) async {
    final s = await boot();
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();

    // START is on screen but covered — tapping where it sits must not run it.
    await tester.tap(find.text('START'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(s.engine.isRunning, false);

    s.dispose();
  });
}
