import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pixel_pomo/logic.dart';
import 'package:pixel_pomo/main.dart';
import 'package:pixel_pomo/pixel.dart';
import 'package:pixel_pomo/store.dart';

/// #v39 — payment types, separate income types, expenses shown with a minus,
/// rates every 10 minutes from a live source, and every entry priced at the
/// rate of the moment it was added (back-dated ones at their own day's rate).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('rate sources', () {
    test('Coinbase: string rates, crypto dropped, USD present', () {
      final r = Fx.parseCoinbase({
        'data': {
          'currency': 'USD',
          'rates': {'EUR': '0.92', 'TRY': '41.5', 'BTC': '0.00001', '1INCH': '10', 'PLN': 'x'}
        }
      })!;
      expect(r, {'EUR': 0.92, 'TRY': 41.5, 'USD': 1.0});
    });

    test('currency-api: lowercase codes', () {
      final r = Fx.parseCurrencyApi({
        'date': '2026-10-01',
        'usd': {'eur': 0.9, 'try': 40.0, 'eth': 0.0003}
      })!;
      expect(r, {'EUR': 0.9, 'TRY': 40.0, 'USD': 1.0});
    });

    test('open.er-api, and garbage from any source is null', () {
      expect(Fx.parseErApi({'result': 'success', 'rates': {'EUR': 0.9}}), {'EUR': 0.9, 'USD': 1.0});
      expect(Fx.parseErApi({'result': 'error'}), isNull);
      expect(Fx.parseCoinbase('nope'), isNull);
      expect(Fx.parseCurrencyApi({'usd': {}}), isNull);
    });

    test('rates refresh every 10 minutes', () {
      expect(Fx.ttlMs, 10 * 60 * 1000);
      expect(Fx.needsRefresh(11 * 60 * 1000, 0), isTrue);
      expect(Fx.needsRefresh(9 * 60 * 1000, 0), isFalse);
    });
  });

  group('rate snapshot', () {
    const then = {'USD': 1.0, 'PLN': 4.0, 'TRY': 40.0};
    const now = {'USD': 1.0, 'PLN': 3.0, 'TRY': 50.0};
    const tx = MoneyTx(100, 0, 15000, 'PLN', 'catFood', true);

    test('a pinned entry keeps its value when rates move', () {
      final pinned = tx.snapshotAt(then, 'TRY');
      expect(MoneyBook.toMain(pinned, then, 'TRY'), closeTo(1500, 1e-6)); // 150 PLN = 37.5 USD = 1500 TRY
      expect(MoneyBook.toMain(pinned, now, 'TRY'), closeTo(1500, 1e-6), reason: 'priced as when it was added');
      expect(MoneyBook.toMain(tx, now, 'TRY'), closeTo(2500, 1e-6), reason: 'unpinned floats');
    });

    test('a pinned entry converts to a new main currency via its pinned USD value', () {
      final pinned = tx.snapshotAt(then, 'TRY');
      expect(MoneyBook.toMain(pinned, now, 'USD'), closeTo(37.5, 1e-6));
      final rebased = pinned.rebasedTo({'EUR': 0.8}, 'EUR');
      expect(rebased.refCur, 'EUR');
      expect(MoneyBook.toMain(rebased, now, 'EUR'), closeTo(30, 1e-6));
    });

    test('method + snapshot survive encode/decode; old 7-field lines still read', () {
      final t = const MoneyTx(100, 5, 15000, 'PLN', 'catFood', true, 'lunch', 'payCard').snapshotAt(then, 'TRY');
      final back = MoneyBook.decode(MoneyBook.encode([t])).single;
      expect(back.method, 'payCard');
      expect(back.note, 'lunch');
      expect(back.usdMicro, t.usdMicro);
      expect(back.refCur, 'TRY');
      expect(back.refMinor, 150000);

      const us = '\u001F';
      final legacy = MoneyBook.decode(['100', '5', '15000', 'PLN', '1', 'catFood', 'old note'].join(us)).single;
      expect(legacy.note, 'old note');
      expect(legacy.method, '');
      expect(legacy.hasSnapshot, isFalse);
    });

    test('a currency with a pinned value is not flagged as unconverted', () {
      final pinned = tx.snapshotAt(then, 'TRY');
      expect(MoneyBook.hasUnconverted([pinned], const {}, 'TRY'), isFalse);
      expect(MoneyBook.hasUnconverted([tx], const {}, 'TRY'), isTrue);
    });

    test('byMethod splits expenses per payment type', () {
      final txs = [
        const MoneyTx(1, 0, 1000, 'USD', 'catFood', true, '', 'payCard'),
        const MoneyTx(1, 0, 300, 'USD', 'catFood', true, '', 'payCash'),
        const MoneyTx(1, 0, 200, 'USD', 'catFood', true, '', 'payCard'),
        const MoneyTx(1, 0, 9900, 'USD', 'catSalary', false, '', 'payTransfer'),
      ];
      final m = MoneyBook.byMethod(txs, const {'USD': 1.0}, 'USD');
      expect(m.map((e) => (e.key, e.value)).toList(), [('payCard', 12.0), ('payCash', 3.0)]);
    });
  });

  group('AppStore', () {
    Future<AppStore> boot({Map<String, Object> prefs = const {}}) async {
      // money tracker hidden while loading so load() starts no real fetch,
      // then switched on with fake rate sources
      SharedPreferences.setMockInitialValues({'flutter.show_money_tracker': false, ...prefs});
      final s = AppStore();
      await s.load();
      s.showMoneyTracker = true;
      s.money = [];
      s.mainCurrency = 'TRY';
      return s;
    }

    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('an entry added with fresh rates is pinned at that moment', () async {
      final s = await boot();
      s.fxRates = {'USD': 1.0, 'PLN': 4.0, 'TRY': 40.0};
      s.fxFetchedAt = DateTime.now().millisecondsSinceEpoch;
      s.addMoneyTx(15000, 'PLN', 'catFood', true, '');
      s.fxRates = {'USD': 1.0, 'PLN': 3.0, 'TRY': 50.0}; // rates move afterwards
      expect(s.moneyToMain(s.money.single), closeTo(1500, 1e-6));
    });

    test('stale cache: not pinned until fresh rates arrive', () async {
      final s = await boot();
      s.fxRates = {'USD': 1.0, 'PLN': 4.0, 'TRY': 40.0};
      s.fxFetchedAt = 0; // ancient
      s.fxLatest = () async => {'USD': 1.0, 'PLN': 3.0, 'TRY': 45.0};
      s.fxHistory = (_) async => null;
      s.addMoneyTx(15000, 'PLN', 'catFood', true, '');
      expect(s.money.single.hasSnapshot, isFalse);
      await s.refreshFx(force: true);
      await settle();
      expect(s.money.single.hasSnapshot, isTrue);
      expect(s.moneyToMain(s.money.single), closeTo(2250, 1e-6)); // 50 USD × 45
    });

    test('a back-dated entry is priced at its own day\'s rate', () async {
      final s = await boot();
      final today = epochDayOf(DateTime.now());
      final asked = <DateTime>[];
      s.fxRates = {'USD': 1.0, 'PLN': 3.0, 'TRY': 50.0};
      s.fxFetchedAt = DateTime.now().millisecondsSinceEpoch;
      s.fxHistory = (d) async {
        asked.add(d);
        return {'USD': 1.0, 'PLN': 5.0, 'TRY': 30.0};
      };
      s.addMoneyTx(15000, 'PLN', 'catFood', true, '', epochDay: today - 3);
      await settle();
      expect(asked.single, dateOfEpochDay(today - 3));
      expect(s.moneyToMain(s.money.single), closeTo(900, 1e-6)); // 30 USD × 30
    });

    test('changing the main currency re-expresses pinned entries at their day\'s rate', () async {
      final s = await boot();
      final today = epochDayOf(DateTime.now());
      s.fxRates = {'USD': 1.0, 'PLN': 3.0, 'TRY': 50.0, 'EUR': 0.95};
      s.fxFetchedAt = DateTime.now().millisecondsSinceEpoch;
      s.fxHistory = (d) async => {'USD': 1.0, 'PLN': 5.0, 'TRY': 30.0, 'EUR': 0.8};
      s.addMoneyTx(15000, 'PLN', 'catFood', true, '', epochDay: today - 3);
      await settle();
      s.setMainCurrency('EUR');
      await settle();
      expect(s.money.single.refCur, 'EUR');
      expect(s.moneyToMain(s.money.single), closeTo(24, 1e-6)); // 30 USD × 0.8, not × 0.95
    });

    test('expense categories and income types are separate lists', () async {
      final s = await boot();
      s.addCustomCategory('rent');
      s.addCustomCategory('freelance', income: true);
      expect(s.customCategories, ['RENT']);
      expect(s.customIncomeCategories, ['FREELANCE']);
      s.removeCustomCategory('FREELANCE'); // wrong list → no-op
      expect(s.customIncomeCategories, ['FREELANCE']);
      s.removeCustomCategory('FREELANCE', income: true);
      expect(s.customIncomeCategories, isEmpty);
    });

    test('a legacy shared custom category used on income moves to income types', () async {
      const us = '\u001F';
      SharedPreferences.setMockInitialValues({
        'flutter.show_money_tracker': false,
        'flutter.custom_categories': 'RENT\nTIPS',
        'flutter.money_txs': ['100', '0', '500', 'USD', '0', 'TIPS', ''].join(us),
      });
      final s = AppStore();
      await s.load();
      expect(s.customCategories, ['RENT', 'TIPS']);
      expect(s.customIncomeCategories, ['TIPS']);
    });

    test('payment types: add, remember the last used, remove', () async {
      final s = await boot();
      s.addPayMethod('paypal');
      expect(s.customPayMethods, ['PAYPAL']);
      s.addMoneyTx(500, 'TRY', 'catFood', true, '', method: 'PAYPAL');
      expect(s.money.single.method, 'PAYPAL');
      expect(s.lastPayMethod, 'PAYPAL');
      s.removePayMethod('PAYPAL');
      expect(s.customPayMethods, isEmpty);
      expect(s.lastPayMethod, '');
      expect(s.money.single.method, 'PAYPAL', reason: 'entries keep their type');
    });
  });

  group('Money screen', () {
    setUp(() => PixelButton.animate = false);
    tearDown(() => PixelButton.animate = true);

    Future<AppStore> boot(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({'flutter.main_currency': 'USD', 'flutter.show_money_tracker': false});
      final s = AppStore();
      await s.load();
      s.showMoneyTracker = true;
      s.money = [];
      s.fxRates = {'USD': 1.0, 'EUR': 0.9, 'PLN': 4.0};
      s.fxFetchedAt = DateTime.now().millisecondsSinceEpoch;
      s.fxLatest = () async => null;
      s.fxHistory = (_) async => null;
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.6;
      addTearDown(tester.view.reset);
      return s;
    }

    Future<void> open(WidgetTester tester, AppStore s) async {
      await tester.pumpWidget(MaterialApp(
        scaffoldMessengerKey: messengerKey,
        home: AnimatedBuilder(animation: s, builder: (_, __) => MoneyScreen(s)),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('expenses read with a minus everywhere', (tester) async {
      final s = await boot(tester);
      s.addMoneyTx(2000, 'USD', 'catFood', true, '');
      await open(tester, s);
      // the EXPENSE total and the category bar, besides the row itself
      expect(find.text('-USD 20.00'), findsAtLeastNWidgets(3));
      expect(find.text('USD 20.00'), findsNothing);
    });

    testWidgets('pick a payment type; it shows on the row and gets its own breakdown', (tester) async {
      final s = await boot(tester);
      await open(tester, s);
      await tester.tap(find.byKey(const Key('addExpense')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('txAmount')), '12');
      await tester.tap(find.byKey(const Key('txPay_payCard')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('txSave')));
      await tester.tap(find.byKey(const Key('txSave')));
      await tester.pumpAndSettle();
      expect(s.money.single.method, 'payCard');
      expect(find.text('CARD'), findsWidgets); // row line + breakdown bar
      expect(find.text('SPENDING BY PAYMENT TYPE'), findsOneWidget);
      expect(find.byKey(const Key('moneyPay_payCard')), findsOneWidget);
    });

    testWidgets('a custom type added in income mode lands in the income list', (tester) async {
      final s = await boot(tester);
      await open(tester, s);
      await tester.tap(find.byKey(const Key('addIncome')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('txAddCategory')));
      await tester.tap(find.byKey(const Key('txAddCategory')));
      await tester.pumpAndSettle();
      expect(find.text('ADD INCOME TYPE'), findsWidgets);
      await tester.enterText(find.byType(TextField).last, 'freelance');
      await tester.tap(find.text('ADD').last);
      await tester.pumpAndSettle();
      expect(s.customIncomeCategories, ['FREELANCE']);
      expect(s.customCategories, isEmpty);
    });

    testWidgets('a foreign-currency entry shows the rate it is priced at', (tester) async {
      final s = await boot(tester);
      s.addMoneyTx(1000, 'PLN', 'catFood', true, '');
      await open(tester, s);
      await tester.tap(find.text('-PLN 10.00').last);
      await tester.pumpAndSettle();
      expect(find.text('1 PLN = USD 0.25  (AT ENTRY)'), findsOneWidget);
    });
  });
}
