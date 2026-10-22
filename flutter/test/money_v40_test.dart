import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pixel_pomo/logic.dart';
import 'package:pixel_pomo/main.dart';
import 'package:pixel_pomo/pixel.dart';
import 'package:pixel_pomo/store.dart';

/// #v40 — money charts for expenses AND income over daily / weekly / monthly /
/// yearly / all time, with averages and per-category averages.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const rates = {'USD': 1.0};
  // Wed 15 Oct 2025 as "now"
  final now = DateTime(2025, 10, 15, 12);
  final today = epochDayOf(now);
  MoneyTx ex(int day, int cents, String cat) => MoneyTx(day, 0, cents, 'USD', cat, true);
  MoneyTx inc(int day, int cents, String cat) => MoneyTx(day, 0, cents, 'USD', cat, false);

  group('MoneyStats.of', () {
    final txs = [
      ex(today, 1000, 'catFood'), // 10
      ex(today - 1, 3000, 'catFun'), // 30 (Tue, same week)
      ex(today - 10, 2000, 'catFood'), // 20 (5 Oct, earlier week, same month)
      ex(epochDayOf(DateTime(2025, 9, 1)), 5000, 'catFood'), // 50, September
      inc(today - 2, 100000, 'catSalary'), // 1000
    ];

    test('monthly: totals, averages over the days so far, categories', () {
      final st = MoneyStats.of(txs, now, StatPeriod.monthly, 0, rates, 'USD', expense: true);
      expect(st.total, 60);
      expect(st.count, 3);
      expect(st.days, 15, reason: '1–15 Oct: the month so far, not all 31 days');
      expect(st.perDay, closeTo(4, 1e-9));
      expect(st.perEntry, closeTo(20, 1e-9));
      expect(st.largest, 30);
      expect(st.cats.map((c) => (c.category, c.total, c.count)).toList(),
          [('catFood', 30.0, 2), ('catFun', 30.0, 1)]);
      expect(st.previous, 50, reason: 'September');
      expect(st.change, closeTo(0.2, 1e-9));
    });

    test('no "vs previous" against a window the history only partly covers', () {
      final late = [ex(epochDayOf(DateTime(2025, 9, 20)), 5000, 'catFood'), ex(today, 1000, 'catFood')];
      final st = MoneyStats.of(late, now, StatPeriod.monthly, 0, rates, 'USD', expense: true);
      expect(st.previous, isNull, reason: 'September began before the first entry');
      expect(st.change, isNull);
    });

    test('income is counted on its own', () {
      final st = MoneyStats.of(txs, now, StatPeriod.monthly, 0, rates, 'USD', expense: false);
      expect(st.total, 1000);
      expect(st.cats.single.category, 'catSalary');
    });

    test('weekly and daily windows', () {
      expect(MoneyStats.of(txs, now, StatPeriod.weekly, 0, rates, 'USD', expense: true).total, 40);
      expect(MoneyStats.of(txs, now, StatPeriod.daily, 0, rates, 'USD', expense: true).total, 10);
      expect(MoneyStats.of(txs, now, StatPeriod.daily, 1, rates, 'USD', expense: true).total, 30);
    });

    test('yearly counts months so far; all time starts at the first entry and has no "previous"', () {
      final y = MoneyStats.of(txs, now, StatPeriod.yearly, 0, rates, 'USD', expense: true);
      expect(y.total, 110);
      expect(y.months, 10);
      expect(y.perMonth, closeTo(11, 1e-9));
      final all = MoneyStats.of(txs, now, StatPeriod.allTime, 0, rates, 'USD', expense: true);
      expect(all.total, 110);
      expect(all.days, today - epochDayOf(DateTime(2025, 9, 1)) + 1);
      expect(all.months, 2);
      expect(all.previous, isNull);
      expect(all.change, isNull);
    });

    test('an empty window divides by at least one day', () {
      final st = MoneyStats.of(const [], now, StatPeriod.monthly, 0, rates, 'USD', expense: true);
      expect(st.total, 0);
      expect(st.perDay, 0);
      expect(st.perEntry, 0);
      expect(st.change, isNull);
    });
  });

  group('MoneyStats.series', () {
    final txs = [
      ex(today, 1050, 'catFood'),
      ex(today, 2000, 'catFun'),
      ex(epochDayOf(DateTime(2025, 2, 3)), 7000, 'catFood'),
      ex(epochDayOf(DateTime(2023, 6, 1)), 4000, 'catFood'),
      inc(today, 99900, 'catSalary'),
    ];

    test('yearly buckets by month, with a per-category breakdown', () {
      final s = MoneyStats.series(txs, now, StatPeriod.yearly, 0, rates, 'USD', expense: true);
      expect(s.totals.length, 12);
      expect(s.totals[9], 31); // 10.50 + 20 → 30.50 rounds to 31
      expect(s.totals[1], 70);
      expect(s.byLabel[9].map((e) => e.key), ['catFun', 'catFood']);
    });

    test('all time buckets by year from the first entry', () {
      final s = MoneyStats.series(txs, now, StatPeriod.allTime, 0, rates, 'USD', expense: true);
      expect(s.tickLabels, ['2023', '2024', '2025']);
      expect(s.totals, [40, 0, 101]);
    });

    test('monthly has one bucket per day; income stays out of expenses', () {
      final s = MoneyStats.series(txs, now, StatPeriod.monthly, 0, rates, 'USD', expense: true);
      expect(s.totals.length, 31);
      expect(s.totals[14], 31);
      final i = MoneyStats.series(txs, now, StatPeriod.monthly, 0, rates, 'USD', expense: false);
      expect(i.totals[14], 999);
    });
  });

  test('compact chart labels', () {
    expect(MoneyAmount.compact(950), '950');
    expect(MoneyAmount.compact(12500), '12.5K');
    expect(MoneyAmount.compact(12500, lang: 'tr'), '12,5K');
    expect(MoneyAmount.compact(1300000), '1.3M');
    expect(MoneyAmount.compact(250000), '250K');
  });

  group('Money screen charts', () {
    setUp(() => PixelButton.animate = false);
    tearDown(() => PixelButton.animate = true);

    Future<AppStore> open(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({'flutter.main_currency': 'USD', 'flutter.show_money_tracker': false});
      final s = AppStore();
      await s.load();
      s.showMoneyTracker = true;
      s.money = [];
      s.fxRates = {'USD': 1.0};
      s.fxFetchedAt = DateTime.now().millisecondsSinceEpoch;
      s.fxLatest = () async => null;
      s.fxHistory = (_) async => null;
      s.addMoneyTx(4000, 'USD', 'catFood', true, '');
      s.addMoneyTx(100000, 'USD', 'catSalary', false, '');
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 2.6;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        scaffoldMessengerKey: messengerKey,
        home: AnimatedBuilder(animation: s, builder: (_, __) => MoneyScreen(s)),
      ));
      await tester.pumpAndSettle();
      return s;
    }

    Future<void> tap(WidgetTester tester, String key) async {
      await tester.ensureVisible(find.byKey(Key(key)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }

    testWidgets('all five periods, and yearly adds AVG / MONTH', (tester) async {
      await open(tester);
      for (final p in StatPeriod.values) {
        expect(find.byKey(Key('moneyPeriod_${p.name}')), findsOneWidget);
      }
      expect(find.text('AVG / MONTH'), findsNothing);
      await tap(tester, 'moneyPeriod_yearly');
      expect(find.text('AVG / MONTH'), findsOneWidget);
      await tap(tester, 'moneyPeriod_allTime');
      expect(find.byKey(const Key('moneyChartPrev')), findsNothing, reason: 'nothing before all time');
    });

    testWidgets('expenses show their category averages; income has its own', (tester) async {
      await open(tester);
      expect(find.text('EXPENSES BY CATEGORY'), findsOneWidget);
      expect(find.byKey(const Key('moneyCatStat_catFood')), findsOneWidget);
      await tap(tester, 'moneyKind_1');
      expect(find.text('INCOME BY TYPE'), findsOneWidget);
      expect(find.byKey(const Key('moneyCatStat_catSalary')), findsOneWidget);
      expect(find.byKey(const Key('moneyCatStat_catFood')), findsNothing);
    });

    testWidgets('compare shows net and how much of the income was kept', (tester) async {
      await open(tester);
      await tap(tester, 'moneyKind_2');
      expect(find.text('KEPT'), findsOneWidget);
      expect(find.text('96%'), findsOneWidget); // (1000 - 40) / 1000
      expect(find.byKey(const Key('moneyMode_line')), findsNothing, reason: 'compare is a single bar pair');
    });

    testWidgets('trend and pie render for both kinds without errors', (tester) async {
      await open(tester);
      for (final kind in ['moneyKind_0', 'moneyKind_1']) {
        await tap(tester, kind);
        for (final m in ['moneyMode_line', 'moneyMode_pie', 'moneyMode_bar']) {
          await tap(tester, m);
          expect(tester.takeException(), isNull);
        }
      }
    });
  });
}
