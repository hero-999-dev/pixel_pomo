import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_pomo/logic.dart';
import 'package:pixel_pomo/pixel.dart';

void main() {
  group('theme system-bar brightness', () {
    test('isLightColor splits light vs dark backgrounds', () {
      expect(isLightColor(0xFFF7EFDD), true); // latte cream
      expect(isLightColor(0xFFF2F2F4), true); // light
      expect(isLightColor(0xFF161616), false); // dark
      expect(isLightColor(0xFF1E1E2E), false); // mocha
    });

    test('systemOverlayFor colors bars to bg and picks icon brightness', () {
      final dark = systemOverlayFor(Themes.dark);
      expect(dark.systemNavigationBarColor, const Color(0xFF161616));
      expect(dark.statusBarIconBrightness, Brightness.light); // light icons on dark bg
      final light = systemOverlayFor(Themes.light);
      expect(light.statusBarIconBrightness, Brightness.dark);
    });
  });

  group('StatsAggregator periods (v12)', () {
    final now = DateTime(2026, 6, 17, 12); // Wed
    int day(int y, int m, int d) => epochDayOf(DateTime(y, m, d));
    final records = [
      SessionRecord(day(2026, 6, 17), 60, 'MATH'), // today
      SessionRecord(day(2026, 6, 17), 30, 'CODING'), // today
      SessionRecord(day(2026, 6, 15), 40, 'MATH'), // Mon this week
      SessionRecord(day(2026, 6, 10), 50, 'READING'), // earlier this month
      SessionRecord(day(2026, 3, 4), 90, 'MATH'), // earlier this year
      SessionRecord(day(2025, 12, 1), 25, 'MATH'), // last year
    ];

    test('byLabelInWindow daily = today only', () {
      final r = StatsAggregator.byLabelInWindow(records, now, StatPeriod.daily);
      expect(r.map((e) => e.key).toList(), ['MATH', 'CODING']);
      expect(r.first.value, 60);
    });

    test('byLabelInWindow weekly = Mon..Sun of this week', () {
      final total = StatsAggregator.byLabelInWindow(records, now, StatPeriod.weekly)
          .fold<int>(0, (a, e) => a + e.value);
      expect(total, 60 + 30 + 40);
    });

    test('byLabelInWindow monthly / yearly / allTime sum correctly', () {
      int sum(StatPeriod p) => StatsAggregator.byLabelInWindow(records, now, p)
          .fold<int>(0, (a, e) => a + e.value);
      expect(sum(StatPeriod.monthly), 60 + 30 + 40 + 50);
      expect(sum(StatPeriod.yearly), 60 + 30 + 40 + 50 + 90);
      expect(sum(StatPeriod.allTime), 60 + 30 + 40 + 50 + 90 + 25);
    });

    test('seriesFor monthly has one bucket per day with today populated', () {
      final s = StatsAggregator.seriesFor(records, now, StatPeriod.monthly);
      expect(s.totals.length, 30);
      expect(s.totals[16], 90); // day 17 → index 16 → 60+30
      expect(s.byLabel[16].length, 2);
    });

    test('seriesFor daily has 7 buckets ending today', () {
      final s = StatsAggregator.seriesFor(records, now, StatPeriod.daily);
      expect(s.totals.length, 7);
      expect(s.totals.last, 90);
    });

    test('seriesFor yearly has 12 month buckets; allTime per year', () {
      final y = StatsAggregator.seriesFor(records, now, StatPeriod.yearly);
      expect(y.totals.length, 12);
      expect(y.totals[5], 180); // June = 60+30+40+50
      final a = StatsAggregator.seriesFor(records, now, StatPeriod.allTime);
      expect(a.totals.length, 2);
      expect(a.totals.last, 60 + 30 + 40 + 50 + 90);
      expect(a.totals.first, 25);
    });

    test('labelSeriesFor daily gives one series per label over 7 days', () {
      final ls = StatsAggregator.labelSeriesFor(records, now, StatPeriod.daily);
      final math = ls.firstWhere((s) => s.label == 'MATH');
      expect(math.values.length, 7);
      expect(math.values.last, 60);
    });

    test('anchorFor shifts the window back by period units, never future', () {
      // monthly offset 1 → previous month window (no records in May 2026)
      final prevMonth = StatsAggregator.byLabelInWindow(records, now, StatPeriod.monthly, 1);
      expect(prevMonth, isEmpty);
      // daily offset 2 → 2026-06-15 (Mon), which has the 40-min MATH record
      final twoDaysAgo = StatsAggregator.byLabelInWindow(records, now, StatPeriod.daily, 2);
      expect(twoDaysAgo.fold<int>(0, (a, e) => a + e.value), 40);
      // yearly offset 1 → 2025, which has the 25-min record
      final lastYear = StatsAggregator.byLabelInWindow(records, now, StatPeriod.yearly, 1);
      expect(lastYear.fold<int>(0, (a, e) => a + e.value), 25);
      // seriesFor honours offset too (prev month series is all-zero)
      final s = StatsAggregator.seriesFor(records, now, StatPeriod.monthly, 1);
      expect(s.totals.every((v) => v == 0), true);
    });
  });

  group('StatsAggregator trend (v14)', () {
    final now = DateTime(2026, 6, 17, 23); // late today so all of today's hours are past
    int day(int y, int m, int d) => epochDayOf(DateTime(y, m, d));
    final recs = [
      SessionRecord(day(2026, 6, 17), 25, 'MATH', minuteOfDay: 8 * 60), // 08:00
      SessionRecord(day(2026, 6, 17), 75, 'CODING', minuteOfDay: 12 * 60), // 12:00
      SessionRecord(day(2026, 6, 17), 40, 'MATH'), // legacy (ignored on curve)
      SessionRecord(day(2026, 6, 10), 60, 'MATH'), // earlier this month
      SessionRecord(day(2026, 6, 9), 120, 'MATH'), // prev week
    ];

    test('dailyCumulative is monotonic, hours bucketed, legacy ignored', () {
      final s = StatsAggregator.dailyCumulative(recs, now);
      expect(s.totals.length, 7); // [0,4,8,12,16,20,24]
      expect(s.totals[0], 0); // before 08:00
      expect(s.totals[2], 25); // by 08:00 → 25
      expect(s.totals[3], 100); // by 12:00 → 25+75
      expect(s.totals.last, 100); // legacy 40 not on the hourly curve
      for (var i = 1; i < s.totals.length; i++) {
        expect(s.totals[i] >= s.totals[i - 1], true); // monotonic
      }
    });

    test('periodStats current/average/best per period', () {
      final (cur, avg, best) = StatsAggregator.periodStats(recs, now, StatPeriod.weekly);
      expect(cur, 140); // this week = 25+75+40
      expect(best, 180); // prev week (6/9 120 + 6/10 60) beats this week's 140
      expect(avg, 160); // (140 + 180) / 2
      final (dCur, _, dBest) = StatsAggregator.periodStats(recs, now, StatPeriod.daily);
      expect(dCur, 140);
      expect(dBest, 140);
    });
  });

  group('SessionRecord timestamp codec (v14)', () {
    test('4-field round-trip + legacy 3-field decode', () {
      final recs = [
        const SessionRecord(100, 60, 'MATH', minuteOfDay: 480),
        const SessionRecord(100, 30, 'CODING'), // no time
      ];
      final decoded = StatsCodec.decode(StatsCodec.encode(recs));
      expect(decoded[0].minuteOfDay, 480);
      expect(decoded[0].label, 'MATH');
      expect(decoded[1].minuteOfDay, isNull);
      // legacy rows (3 fields) still parse, minuteOfDay null
      final legacy = StatsCodec.decode('100,60,MATH\n100,30,CODING');
      expect(legacy.length, 2);
      expect(legacy[0].minuteOfDay, isNull);
      expect(legacy[0].label, 'MATH');
    });
  });

  group('PomodoroEngine', () {
    test('initial state', () {
      final e = PomodoroEngine();
      expect(e.mode, Mode.work);
      expect(e.session, 1);
      expect(e.isFinished, false);
      expect(e.progressPercent(), 100);
      expect(e.formattedTime(), '25:00');
    });

    test('start no-op when time left is 0', () {
      final e = PomodoroEngine();
      e.setTimeLeft(0);
      e.start();
      expect(e.isRunning, false);
    });

    test('finish WORK then BREAK advances session', () {
      final e = PomodoroEngine(totalSessions: 2);
      expect(e.finishPhase(), Mode.work);
      expect(e.mode, Mode.breakMode);
      expect(e.session, 1);
      expect(e.finishPhase(), Mode.breakMode);
      expect(e.session, 2);
    });

    test('final break finishes the run, no overflow', () {
      final e = PomodoroEngine(totalSessions: 1);
      e.finishPhase(); // work -> break
      e.finishPhase(); // last break -> finished
      expect(e.isFinished, true);
      expect(e.session, 1);
    });

    test('setTimeLeft clamps; progress clamps 0..100; format rounds up', () {
      final e = PomodoroEngine(workMillis: 60000);
      e.setTimeLeft(-5);
      expect(e.timeLeftMillis, 0);
      e.setTimeLeft(999999);
      expect(e.timeLeftMillis, 60000);
      e.setTimeLeft(1);
      expect(e.formattedTime(), '00:01'); // rounds up
      expect(e.progressPercent(), 0); // 1ms of 60000ms floors to 0%
      e.setTimeLeft(30000);
      expect(e.progressPercent(), 50);
    });
  });

  group('Economy + Garden', () {
    test('elapsedFocusMinutes counts spent time on cancel', () {
      expect(Economy.elapsedFocusMinutes(25, 14 * 60 * 1000), 11); // 25-min, 14 left → 11
      expect(Economy.elapsedFocusMinutes(25, 25 * 60 * 1000), 0); // untouched → 0
      expect(Economy.elapsedFocusMinutes(25, 0), 25); // finished → 25
    });

    test('coinsFor / upgradeCost (rectangular)', () {
      expect(Economy.coinsFor(4), 0);
      expect(Economy.coinsFor(25), 5);
      expect(Economy.coinsFor(-3), 0);
      expect(Economy.upgradeCost(4, 6), 21); // 2*(4+6)+1
      expect(Economy.upgradeCost(6, 8), 29);
    });

    test('garden base is 10x16; atLeast migrates a smaller plot keeping plantings', () {
      expect(Economy.baseGardenCols, 10);
      expect(Economy.baseGardenRows, 16);
      const def = Garden();
      expect(def.cols, 10);
      expect(def.rows, 16);
      // a saved 4x6 with a flower migrates into >=10x16, centred, nothing lost
      final small = const Garden(cols: 4, rows: 6).plant(5, 'gul');
      final big = small.atLeast(10, 16);
      expect(big.cols >= 10 && big.rows >= 16, true);
      expect(big.countPlanted('gul'), 1);
      // already-big plots are returned unchanged
      final already = const Garden(cols: 12, rows: 18);
      expect(already.atLeast(10, 16).cols, 12);
    });

    test('garden grows as a centred ring', () {
      const g = Garden(cols: 4, rows: 6);
      expect(g.cols, 4);
      expect(g.rows, 6);
      expect(g.tileCount, 24);

      // plant at (col 1, row 2) = index 2*4+1 = 9
      final grown = g.plant(9, 'lale').grow();
      expect(grown.cols, 6);
      expect(grown.rows, 8);
      // (1,2) drifts to (2,3) = 3*6+2 = 20
      expect(grown.propAt(20), 'lale');
      final decoded = Garden.decode(grown.encode());
      expect(decoded.cols, 6);
      expect(decoded.rows, 8);
      expect(decoded.propAt(20), 'lale');
      expect(decoded.tiles, grown.tiles);
    });

    test('garden decode migrates a legacy square size: line', () {
      final d = Garden.decode('size:5\n0:gul');
      expect(d.cols, 5);
      expect(d.rows, 5);
      expect(d.propAt(0), 'gul');
    });

    test('garden decode drops out-of-range tiles', () {
      final d = Garden.decode('cols:4\nrows:6\n99:gul\n9:lale');
      expect(d.tiles.containsKey(99), false);
      expect(d.propAt(9), 'lale');
    });

    test('garden grows with no cap; stays centred', () {
      var g = const Garden(cols: 4, rows: 6).plant(0, 'gul'); // (0,0)
      for (var i = 0; i < 10; i++) {
        g = g.grow();
      }
      expect(g.cols, 4 + 20);
      expect(g.rows, 6 + 20);
      expect(g.countPlanted('gul'), 1); // nothing lost
      // (0,0) drifts +10/+10 → (10,10) = 10*g.cols + 10
      expect(g.propAt(10 * g.cols + 10), 'gul');
    });
  });

  group('Placeables (roads + fences)', () {
    test('catalogue: 4 roads + 3 fences, classified correctly', () {
      expect(Placeables.roadIds.length, 4);
      expect(Placeables.fenceIds.length, 3);
      expect(Placeables.objectIds.length, 7);
      expect(Placeables.isRoad('road_concrete'), true);
      expect(Placeables.isFence('road_concrete'), false);
      expect(Placeables.isFence('fence_stone'), true);
      expect(Placeables.isRoad('fence_stone'), false);
      expect(Placeables.isObject('gul'), false);
    });

    test('costOf: objects 5, flowers 10', () {
      for (final id in Placeables.objectIds) {
        expect(Economy.costOf(id), 5, reason: id);
      }
      expect(Economy.costOf('gul'), 10);
    });

    test('roads/fences round-trip through the codec', () {
      final g = const Garden()
          .plant(0, 'road_concrete')
          .plant(1, 'fence_stone')
          .plant(2, 'gul');
      final d = Garden.decode(g.encode());
      expect(d.flowerAt(0), 'road_concrete');
      expect(d.flowerAt(1), 'fence_stone');
      expect(d.flowerAt(2), 'gul');
    });

    test('a fence stands on a road; layers split + round-trip (#2)', () {
      final g = const Garden().plant(0, 'road_wood').plant(0, 'fence_stone');
      expect(g.groundAt(0), 'road_wood'); // road kept underneath
      expect(g.propAt(0), 'fence_stone'); // fence stands on top
      expect(g.countPlanted('road_wood'), 1);
      expect(g.countPlanted('fence_stone'), 1);
      final d = Garden.decode(g.encode());
      expect(d.groundAt(0), 'road_wood');
      expect(d.propAt(0), 'fence_stone');
    });

    test('a road slides under a fence but clears a flower (#2)', () {
      final withFlower = const Garden().plant(0, 'gul').plant(0, 'road_dirt');
      expect(withFlower.groundAt(0), 'road_dirt');
      expect(withFlower.propAt(0), isNull); // flower removed (no flowers on roads)
      final withFence = const Garden().plant(1, 'fence_wood').plant(1, 'road_dirt');
      expect(withFence.groundAt(1), 'road_dirt');
      expect(withFence.propAt(1), 'fence_wood'); // fence preserved
    });

    test('flowers refuse to grow on a road (#2)', () {
      final g = const Garden().plant(0, 'road_stone').plant(0, 'gul');
      expect(g.groundAt(0), 'road_stone');
      expect(g.propAt(0), isNull); // plant() rejected the flower
    });
  });

  group('Labels + colors', () {
    test('normalize strips disallowed chars and caps at 12', () {
      expect(Labels.normalize('  hi-there!  '), 'HI THERE');
      expect(Labels.normalize('abcdefghijklmnop'), 'ABCDEFGHIJKL');
      expect(Labels.normalize('  '), isNull);
    });

    test('add dedups; remove keeps at least one', () {
      var list = ['STUDY'];
      list = Labels.add(list, 'study');
      expect(list.length, 1);
      list = Labels.remove(list, 'STUDY');
      expect(list.length, 1);
    });

    test('rename replaces a label in place, rejects empty/dupe/missing', () {
      final list = ['STUDY', 'MATH', 'CODING'];
      expect(Labels.rename(list, 'MATH', 'algebra'), ['STUDY', 'ALGEBRA', 'CODING']);
      expect(Labels.rename(list, 'MATH', '   '), list); // empty → unchanged
      expect(Labels.rename(list, 'MATH', 'coding'), list); // dupe → unchanged
      expect(Labels.rename(list, 'NOPE', 'X'), list); // missing → unchanged
    });

    test('label color default is stable and codec round-trips', () {
      expect(LabelColors.defaultFor('MATH'), LabelColors.defaultFor(' math '));
      final colors = {'MATH': 0xFFE5484D, 'CODING': 0xFF2A7DE1};
      expect(LabelColors.decode(LabelColors.encode(colors)), colors);
    });
  });

  group('Stats', () {
    final recs = [
      SessionRecord(epochDayOf(DateTime(2026, 6, 1)), 100, 'MATH'),
      SessionRecord(epochDayOf(DateTime(2026, 6, 1)), 50, 'CODING'),
      SessionRecord(epochDayOf(DateTime(2026, 6, 15)), 60, 'MATH'),
      SessionRecord(epochDayOf(DateTime(2026, 5, 20)), 200, 'READING'),
    ];

    test('monthTotal + byLabelInMonth + dailySeries', () {
      expect(StatsAggregator.monthTotal(recs, 2026, 6), 210);
      final byLabel = StatsAggregator.byLabelInMonth(recs, 2026, 6);
      expect(byLabel.first.key, 'MATH');
      expect(byLabel.first.value, 160);
      final series = StatsAggregator.dailySeries(recs, 2026, 6);
      expect(series.length, 30);
      expect(series[0], 150);
      expect(series[14], 60);
    });

    test('format minutes', () {
      expect(StatsAggregator.formatMinutes(0), '0m');
      expect(StatsAggregator.formatMinutes(90), '1h 30m');
      expect(StatsAggregator.formatMinutes(-5), '0m');
    });
  });

  group('TestData fixture (mid-week today)', () {
    final today = DateTime(2026, 6, 17);
    final recs = TestData.records(today);
    test('buckets to 360 / 700 / 1000', () {
      final totals = StatsAggregator.aggregate(recs, today);
      expect(totals.today, 360);
      expect(totals.week, 700);
      expect(totals.month, 1000);
    });
    test('2025 seeded; 1000 coins', () {
      expect(recs.any((r) => dateOfEpochDay(r.epochDay).year == 2025), true);
      expect(TestData.seedCoins, 1000);
    });
  });
}
