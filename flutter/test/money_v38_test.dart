import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pixel_pomo/logic.dart';
import 'package:pixel_pomo/main.dart';
import 'package:pixel_pomo/pixel.dart';
import 'package:pixel_pomo/store.dart';

/// #v38 — the money tracker rework: amounts typed the way people type them,
/// entries that can be edited and back-dated, delete with UNDO, a budget that
/// saves without pressing enter, and a "today vs budget" meter.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MoneyAmount.parse', () {
    test('plain and decimal amounts, either decimal mark', () {
      expect(MoneyAmount.parse('12'), 1200);
      expect(MoneyAmount.parse('12.5'), 1250);
      expect(MoneyAmount.parse('12,5'), 1250);
      expect(MoneyAmount.parse('0,99'), 99);
      expect(MoneyAmount.parse('12.'), 1200);
    });

    test('thousands grouping in both styles — these used to be dropped silently', () {
      expect(MoneyAmount.parse('1.250,50'), 125050);
      expect(MoneyAmount.parse('1,250.50'), 125050);
      expect(MoneyAmount.parse('1.250'), 125000);
      expect(MoneyAmount.parse('1,250'), 125000);
      expect(MoneyAmount.parse('1.250.000'), 125000000);
      expect(MoneyAmount.parse('1 250,50'), 125050);
      expect(MoneyAmount.parse("1'250.50"), 125050);
    });

    test('currency symbols and spaces are ignored', () {
      expect(MoneyAmount.parse(' ₺ 45 '), 4500);
      expect(MoneyAmount.parse('€12,30'), 1230);
    });

    test('nonsense, zero, negatives-as-text and absurd sizes are refused', () {
      for (final bad in ['', 'abc', '0', '0,00', '1,2,3', '12.345,6.7', '1.2345', '9999999999']) {
        expect(MoneyAmount.parse(bad), isNull, reason: bad);
      }
    });
  });

  group('MoneyAmount.format', () {
    test('groups thousands per language', () {
      expect(MoneyAmount.format(1250.5, 'USD'), 'USD 1,250.50');
      expect(MoneyAmount.format(1250.5, 'TRY', lang: 'tr'), 'TRY 1.250,50');
      expect(MoneyAmount.format(1250.5, 'PLN', lang: 'pl'), 'PLN 1 250,50');
      expect(MoneyAmount.format(-3, 'EUR', lang: 'de'), 'EUR 3,00'); // sign is the caller's
    });

    test('yen and won have no cents', () {
      expect(MoneyAmount.format(1500, 'JPY'), 'JPY 1,500');
      expect(MoneyAmount.format(1500.4, 'KRW', lang: 'tr'), 'KRW 1.500');
    });

    test('toInput round-trips through parse', () {
      for (final lang in ['en', 'tr']) {
        for (final minor in [1, 99, 100, 1250, 125050]) {
          expect(MoneyAmount.parse(MoneyAmount.toInput(minor, 'EUR', lang: lang)), minor);
        }
      }
    });
  });

  test('hasUnconverted spots a single currency without a rate', () {
    const rates = {'USD': 1.0, 'EUR': 0.9};
    final ok = [const MoneyTx(1, 0, 100, 'EUR', 'catFood', true)];
    final bad = [...ok, const MoneyTx(1, 0, 100, 'XYZ', 'catFood', true)];
    expect(MoneyBook.hasUnconverted(ok, rates, 'USD'), isFalse);
    expect(MoneyBook.hasUnconverted(bad, rates, 'USD'), isTrue);
  });

  group('AppStore money mutators', () {
    Future<AppStore> boot() async {
      SharedPreferences.setMockInitialValues({});
      final s = AppStore();
      await s.load();
      s.money = [];
      return s;
    }

    test('an entry can be back-dated, never future-dated', () async {
      final s = await boot();
      final today = epochDayOf(DateTime.now());
      s.addMoneyTx(500, 'USD', 'catFood', true, '', epochDay: today - 1);
      s.addMoneyTx(500, 'USD', 'catFood', true, '', epochDay: today + 5);
      expect(s.money.map((t) => t.epochDay), [today - 1, today]);
    });

    test('update replaces in place and persists', () async {
      final s = await boot();
      s.addMoneyTx(500, 'USD', 'catFood', true, 'lunch');
      final old = s.money.single;
      s.updateMoneyTx(old, old.copyWith(amountMinor: 750, category: 'catFun', note: 'cinema'));
      expect(s.money.single.amountMinor, 750);
      expect(s.money.single.category, 'catFun');

      final s2 = AppStore();
      await s2.load();
      expect(s2.money.where((t) => t.note == 'cinema').single.amountMinor, 750);
    });

    test('delete then restore puts the entry back where it was', () async {
      final s = await boot();
      s.addMoneyTx(100, 'USD', 'catFood', true, 'a');
      s.addMoneyTx(200, 'USD', 'catFood', true, 'b');
      s.addMoneyTx(300, 'USD', 'catFood', true, 'c');
      final b = s.money[1];
      final i = s.deleteMoneyTx(b);
      expect(i, 1);
      expect(s.money.map((t) => t.note), ['a', 'c']);
      s.restoreMoneyTx(b, i);
      expect(s.money.map((t) => t.note), ['a', 'b', 'c']);
      s.restoreMoneyTx(b, i); // twice is a no-op
      expect(s.money.length, 3);
    });

    test('spentToday counts only today\'s expenses', () async {
      final s = await boot();
      final today = epochDayOf(DateTime.now());
      s.addMoneyTx(1000, 'USD', 'catFood', true, '');
      s.addMoneyTx(9900, 'USD', 'catSalary', false, '');
      s.addMoneyTx(500, 'USD', 'catFood', true, '', epochDay: today - 1);
      expect(s.spentToday, closeTo(10, 1e-9));
    });
  });

  group('Money screen', () {
    setUp(() => PixelButton.animate = false);
    tearDown(() => PixelButton.animate = true);

    Future<AppStore> boot() async {
      SharedPreferences.setMockInitialValues({'flutter.main_currency': 'USD'});
      final s = AppStore();
      await s.load();
      s.money = [];
      s.fxRates = {'USD': 1.0, 'EUR': 0.9};
      return s;
    }

    Future<void> open(WidgetTester tester, AppStore s) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.6;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        scaffoldMessengerKey: messengerKey,
        home: AnimatedBuilder(animation: s, builder: (_, __) => MoneyScreen(s)),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('a grouped amount is added instead of vanishing', (tester) async {
      final s = await boot();
      await open(tester, s);
      await tester.tap(find.byKey(const Key('addExpense')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('txAmount')), '1.250,50');
      await tester.tap(find.byKey(const Key('txSave')));
      await tester.pumpAndSettle();
      expect(s.money.single.amountMinor, 125050);
      // the NET total reads the same, so look for the row as well as it
      expect(find.text('-USD 1,250.50'), findsWidgets); // row, expense total, NET, category bar
    });

    testWidgets('a bad amount keeps the dialog open with a message', (tester) async {
      final s = await boot();
      await open(tester, s);
      await tester.tap(find.byKey(const Key('addExpense')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('txAmount')), 'abc');
      await tester.tap(find.byKey(const Key('txSave')));
      await tester.pumpAndSettle();
      expect(s.money, isEmpty);
      expect(find.text('Enter an amount, e.g. 12.50'), findsOneWidget);
      expect(find.byKey(const Key('txAmount')), findsOneWidget);
    });

    testWidgets('yesterday can be picked for a new entry', (tester) async {
      final s = await boot();
      await open(tester, s);
      await tester.tap(find.byKey(const Key('addExpense')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('txAmount')), '4');
      await tester.tap(find.byKey(const Key('txDayPrev')));
      await tester.pumpAndSettle();
      expect(find.text('YESTERDAY'), findsOneWidget);
      await tester.tap(find.byKey(const Key('txSave')));
      await tester.pumpAndSettle();
      expect(s.money.single.epochDay, epochDayOf(DateTime.now()) - 1);
    });

    testWidgets('tapping an entry edits it — amount, type and note', (tester) async {
      final s = await boot();
      s.addMoneyTx(500, 'USD', 'catFood', true, 'lunch');
      await open(tester, s);
      expect(find.text('lunch'), findsOneWidget, reason: 'the note is shown on the row');
      await tester.ensureVisible(find.text('-USD 5.00').last); // .last is the row
      await tester.pumpAndSettle();
      await tester.tap(find.text('-USD 5.00').last);
      await tester.pumpAndSettle();
      expect(find.text('EDIT ENTRY'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('txAmount')), '8');
      await tester.tap(find.byKey(const Key('txTypeIncome')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('txSave')));
      await tester.pumpAndSettle();
      final tx = s.money.single;
      expect(tx.amountMinor, 800);
      expect(tx.isExpense, isFalse);
      expect(tx.category, 'catSalary', reason: 'an expense-only category falls back to an income one');
      expect(tx.note, 'lunch');
    });

    testWidgets('delete from the edit dialog, then UNDO', (tester) async {
      final s = await boot();
      s.addMoneyTx(500, 'USD', 'catFood', true, '');
      await open(tester, s);
      await tester.ensureVisible(find.text('-USD 5.00').last); // .last is the row
      await tester.pumpAndSettle();
      await tester.tap(find.text('-USD 5.00').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('txDelete')));
      await tester.pumpAndSettle();
      expect(s.money, isEmpty);
      await tester.tap(find.text('UNDO'));
      await tester.pumpAndSettle();
      expect(s.money.length, 1);
    });

    testWidgets('the daily budget saves while typing, and the meter shows what is left', (tester) async {
      final s = await boot();
      s.addMoneyTx(1500, 'USD', 'catFood', true, '');
      await open(tester, s);
      await tester.enterText(find.byKey(const Key('moneyBudget')), '40');
      await tester.pumpAndSettle();
      expect(s.dailyRateMinor, 4000, reason: 'no enter key pressed — it must still be saved');
      expect(find.text('USD 25.00 LEFT TODAY'), findsOneWidget);
    });

    testWidgets('tapping a category bar filters the entries to it', (tester) async {
      final s = await boot();
      s.addMoneyTx(500, 'USD', 'catFood', true, 'bread');
      s.addMoneyTx(900, 'USD', 'catFun', true, 'cinema');
      await open(tester, s);
      expect(find.text('bread'), findsOneWidget);
      expect(find.text('cinema'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('moneyCat_catFun')));
      await tester.tap(find.byKey(const Key('moneyCat_catFun')));
      await tester.pumpAndSettle();
      expect(find.text('bread'), findsNothing);
      expect(find.text('cinema'), findsOneWidget);
      await tester.tap(find.byKey(const Key('moneyClearFilter_catFun')));
      await tester.pumpAndSettle();
      expect(find.text('bread'), findsOneWidget);
    });

    testWidgets('a currency with no rate is flagged even when other rates loaded', (tester) async {
      final s = await boot();
      s.addMoneyTx(500, 'XYZ', 'catFood', true, '');
      await open(tester, s);
      expect(find.byKey(const Key('moneyNoRates')), findsOneWidget);
    });
  });
}
