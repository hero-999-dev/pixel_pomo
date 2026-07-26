import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pixel_pomo/main.dart';
import 'package:pixel_pomo/store.dart';

/// #v34.5 — tap the number in a Settings stepper to type a value, and show the
/// allowed range under each one. Getting from 25 to 180 minutes was 31 taps.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppStore> boot() async {
    SharedPreferences.setMockInitialValues({'flutter.tutorial_done': true});
    final s = AppStore();
    await s.load();
    return s;
  }

  Widget host(AppStore s) => MaterialApp(
      home: Scaffold(body: AnimatedBuilder(animation: s, builder: (_, __) => SettingsScreen(s))));

  Future<void> type(WidgetTester tester, String label, String value,
      {bool submitByEnter = true}) async {
    await tester.tap(find.byKey(Key('stepperValue_$label')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('stepperField')), value);
    if (submitByEnter) {
      await tester.testTextInput.receiveAction(TextInputAction.done);
    } else {
      await tester.tap(find.text('SAVE'));
    }
    await tester.pumpAndSettle();
  }

  testWidgets('each stepper says its range', (tester) async {
    final s = await boot();
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();
    // study 5-300, break 1-120, sessions 1-24
    expect(find.text('MIN 5 - MAX 300'), findsOneWidget);
    expect(find.text('MIN 1 - MAX 120'), findsOneWidget);
    expect(find.text('MIN 1 - MAX 24'), findsOneWidget);
    s.dispose();
  });

  testWidgets('tapping the number opens a keyboard field on it', (tester) async {
    final s = await boot();
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('stepperValue_STUDY (MIN)')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('stepperField')), findsOneWidget);
    // it opens on the current value, so a small correction is one edit
    expect(find.widgetWithText(TextField, '${s.workMin}'), findsOneWidget);
    s.dispose();
  });

  testWidgets('a typed value is applied and persisted', (tester) async {
    final s = await boot();
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();
    await type(tester, 'STUDY (MIN)', '180');
    expect(s.workMin, 180);

    final reopened = AppStore();
    await reopened.load();
    expect(reopened.workMin, 180);
    s.dispose();
    reopened.dispose();
  });

  testWidgets('over the maximum picks the maximum, it does not refuse', (tester) async {
    // the explicit ask: "if they try a higher number and press enter, take the max"
    final s = await boot();
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();
    await type(tester, 'STUDY (MIN)', '9999');
    expect(s.workMin, 300);

    await type(tester, 'SESSIONS', '50');
    expect(s.sessions, 24);
    s.dispose();
  });

  testWidgets('under the minimum picks the minimum', (tester) async {
    final s = await boot();
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();
    await type(tester, 'STUDY (MIN)', '0');
    expect(s.workMin, 5);
    s.dispose();
  });

  testWidgets('CANCEL leaves the value alone', (tester) async {
    final s = await boot();
    final before = s.workMin;
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('stepperValue_STUDY (MIN)')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('stepperField')), '99');
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();
    expect(s.workMin, before);
    s.dispose();
  });

  testWidgets('SAVE works as well as the enter key', (tester) async {
    final s = await boot();
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();
    await type(tester, 'BREAK (MIN)', '45', submitByEnter: false);
    expect(s.breakMin, 45);
    s.dispose();
  });
}
