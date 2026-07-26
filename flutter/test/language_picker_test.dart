import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pixel_pomo/main.dart';
import 'package:pixel_pomo/store.dart';
import 'package:pixel_pomo/strings.dart';

/// #v34.3 — the language control is one button that drops open, not six
/// buttons stacked permanently down the Settings page.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppStore> boot([String lang = 'en']) async {
    SharedPreferences.setMockInitialValues(
        {'flutter.tutorial_done': true, 'flutter.language': lang});
    final s = AppStore();
    await s.load();
    return s;
  }

  Widget host(AppStore s) => MaterialApp(
      home: Scaffold(body: AnimatedBuilder(animation: s, builder: (_, __) => SettingsScreen(s))));

  /// The autonym of every language except the one in use.
  Iterable<String> others(String lang) =>
      languageOptions.where((o) => o[0] != lang).map((o) => o[1]);

  testWidgets('collapsed, it shows only the language in use', (tester) async {
    final s = await boot('en');
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('languageButton')), findsOneWidget);
    expect(find.textContaining('English'), findsOneWidget);
    for (final name in others('en')) {
      expect(find.text(name), findsNothing, reason: '$name is on screen while collapsed');
    }

    s.dispose();
  });

  testWidgets('tapping it reveals the other five, and it closes again', (tester) async {
    final s = await boot('en');
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('languageButton')));
    await tester.pumpAndSettle();
    for (final name in others('en')) {
      expect(find.text(name), findsOneWidget, reason: '$name missing from the open list');
    }

    await tester.tap(find.byKey(const Key('languageButton')));
    await tester.pumpAndSettle();
    expect(find.text('Türkçe'), findsNothing);

    s.dispose();
  });

  testWidgets('picking one switches the language, closes the list, and moves it to the top',
      (tester) async {
    final s = await boot('en');
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('languageButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Türkçe'));
    await tester.pumpAndSettle();

    expect(s.lang, 'tr');
    // the button now carries the new language...
    expect(find.textContaining('Türkçe'), findsOneWidget);
    // ...the list is closed...
    expect(find.text('English'), findsNothing);
    // ...and the screen really is in Turkish now
    expect(find.text(t('tr', 'settings')), findsWidgets);

    s.dispose();
  });

  testWidgets('the choice survives a restart', (tester) async {
    final s = await boot('en');
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('languageButton')));
    await tester.pumpAndSettle();
    // Deutsch sits three rows down the open list, below the fold in the test
    // viewport — tapping it blind silently misses.
    await tester.ensureVisible(find.text('Deutsch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deutsch'));
    await tester.pumpAndSettle();

    final reopened = AppStore();
    await reopened.load();
    expect(reopened.lang, 'de');

    s.dispose();
    reopened.dispose();
  });

  testWidgets('it opens on whatever language is already in use', (tester) async {
    final s = await boot('it');
    await tester.pumpWidget(host(s));
    await tester.pumpAndSettle();

    expect(find.textContaining('Italiano'), findsOneWidget);
    await tester.tap(find.byKey(const Key('languageButton')));
    await tester.pumpAndSettle();
    // the one in use is the button, so it must not repeat inside the list
    expect(find.textContaining('Italiano'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);

    s.dispose();
  });
}
