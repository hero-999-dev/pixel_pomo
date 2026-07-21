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

    test('inProgress: false when fresh or fully finished, true anywhere in between (#v31.15)', () {
      final e = PomodoroEngine(totalSessions: 1);
      expect(e.inProgress, false); // never started

      e.start();
      expect(e.inProgress, true); // isRunning alone is enough

      e.setTimeLeft(e.workMillis - 1000); // a tick passed
      e.pause();
      expect(e.inProgress, true); // paused mid-phase, real progress made

      e.finishPhase(); // work -> break
      expect(e.inProgress, true);
      e.finishPhase(); // last break -> finished (totalSessions: 1)
      expect(e.isFinished, true);
      expect(e.inProgress, false); // fully done — safe to rebuild again
    });
  });

  group('StopwatchTimer', () {
    test('starts at 00:00, counts up, formats HH:MM:SS only past an hour (#v31.16)', () {
      final w = StopwatchTimer();
      expect(w.isRunning, false);
      expect(w.elapsedMillis, 0);
      expect(w.formattedTime(), '00:00');

      w.start();
      expect(w.isRunning, true);
      w.setElapsed(65 * 1000); // 1:05
      expect(w.formattedTime(), '01:05');

      w.setElapsed(3661 * 1000); // 1h 01m 01s
      expect(w.formattedTime(), '01:01:01');

      w.pause();
      expect(w.isRunning, false);
      expect(w.elapsedMillis, 3661 * 1000); // pausing doesn't reset the clock

      w.reset();
      expect(w.isRunning, false);
      expect(w.elapsedMillis, 0);
      expect(w.formattedTime(), '00:00');
    });

    test('setElapsed clamps negative values to 0', () {
      final w = StopwatchTimer();
      w.setElapsed(-500);
      expect(w.elapsedMillis, 0);
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

    test('firstLaunchSeed: debug gets full TestData, a real release build gets a clean 50-gold slate (#v31.11)', () {
      final now = DateTime(2026, 7, 7);
      final (debugRecords, debugCoins, debugLabels) = Economy.firstLaunchSeed(true, now);
      // SessionRecord has no value equality, so compare the deterministic
      // LCG fill's length (TestData's own exact-total tests already cover
      // its content elsewhere) rather than deep-equal the two instance lists.
      expect(debugRecords.length, TestData.records(now).length);
      expect(debugRecords, isNotEmpty);
      expect(debugCoins, TestData.seedCoins);
      expect(debugLabels, TestData.labels);

      final (realRecords, realCoins, realLabels) = Economy.firstLaunchSeed(false, now);
      expect(realRecords, isEmpty, reason: 'a real user must not get fake pre-filled sessions');
      expect(realCoins, Economy.startingGold);
      expect(realLabels, isEmpty, reason: 'a real user must not get auto-added demo labels');
    });

    test('garden base is 4x8 (portrait); atLeast pads each axis keeping plantings', () {
      expect(Economy.baseGardenCols, 4);
      expect(Economy.baseGardenRows, 8);
      const def = Garden();
      expect(def.cols, 4);
      expect(def.rows, 8);
      // a saved 4x6 with a flower pads into >=10x20, centred, nothing lost
      final small = const Garden(cols: 4, rows: 6).plant(5, 'gul');
      final big = small.atLeast(10, 20);
      expect(big.cols >= 10 && big.rows >= 20, true);
      expect(big.countPlanted('gul'), 1);
      // a legacy WIDE plot gains rows (portrait) without widening (#v18)
      final tall = const Garden(cols: 10, rows: 16).atLeast(10, 20);
      expect(tall.cols, 10); // not widened
      expect(tall.rows, 20); // padded up to portrait
      // already-big plots are returned unchanged
      final already = const Garden(cols: 12, rows: 22);
      expect(already.atLeast(10, 20).cols, 12);
      expect(already.atLeast(10, 20).rows, 22);
    });

    test('garden grows centred, taller faster than wider (+2 cols / +4 rows, #v19)', () {
      const g = Garden(cols: 4, rows: 6);
      expect(g.cols, 4);
      expect(g.rows, 6);
      expect(g.tileCount, 24);

      // plant at (col 1, row 2) = index 2*4+1 = 9
      final grown = g.plant(9, 'lale').grow();
      expect(grown.cols, 6); // +2 wide
      expect(grown.rows, 10); // +4 tall
      // (1,2) drifts to (2,4) = 4*6+2 = 26
      expect(grown.propAt(26), 'lale');
      final decoded = Garden.decode(grown.encode());
      expect(decoded.cols, 6);
      expect(decoded.rows, 10);
      expect(decoded.propAt(26), 'lale');
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

    test('garden grows with no cap; stays centred (taller, #v19)', () {
      var g = const Garden(cols: 4, rows: 6).plant(0, 'gul'); // (0,0)
      for (var i = 0; i < 10; i++) {
        g = g.grow();
      }
      expect(g.cols, 4 + 20); // 10 × +2 cols
      expect(g.rows, 6 + 40); // 10 × +4 rows
      expect(g.countPlanted('gul'), 1); // nothing lost
      // (0,0) drifts +10 cols / +20 rows → (10,20) = 20*g.cols + 10
      expect(g.propAt(20 * g.cols + 10), 'gul');
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

    test('sellPrice: half the buy price floored (flowers 5, decor 2)', () {
      expect(Economy.sellPrice('gul'), 5);
      for (final id in Placeables.objectIds) {
        expect(Economy.sellPrice(id), 2, reason: id);
      }
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

    test('palette grew to 14 but hash defaults stay in the original 10 (#v27.1)', () {
      expect(LabelColors.palette.length, 14);
      for (final l in ['STUDY', 'MATH', 'CODING', 'READING', 'ANYTHING', 'Q']) {
        final i = LabelColors.palette.indexOf(LabelColors.defaultFor(l));
        expect(i, isNonNegative);
        expect(i, lessThan(10)); // growing the palette must never recolor old labels
      }
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
    test('daily trend curve is non-empty — timestamps seeded (v18)', () {
      final s = StatsAggregator.dailyCumulative(recs, today);
      expect(s.totals.any((v) => v > 0), true); // was all-zero before timestamps
      expect(s.totals.last, 360); // cumulative end-of-day == today's total
    });
  });

  group('WallpaperCam framing codec (v15)', () {
    test('encodes 4 fields and round-trips', () {
      const w = WallpaperCam(0.5, 1.5, -0.25, 0.1);
      expect(w.encode(), '0.5,1.5,-0.25,0.1');
      final back = WallpaperCam.decode(w.encode());
      expect(back.yaw, closeTo(0.5, 1e-9));
      expect(back.zoom, closeTo(1.5, 1e-9));
      expect(back.panXFrac, closeTo(-0.25, 1e-9));
      expect(back.panYFrac, closeTo(0.1, 1e-9));
    });

    test('decode tolerates null/garbage with a sane default', () {
      expect(WallpaperCam.decode(null).zoom, 1.0);
      expect(WallpaperCam.decode('').yaw, 0.0);
      expect(WallpaperCam.decode('x,y').zoom, 1.0); // malformed -> default
    });
  });

  group('flower variants (#v22)', () {
    test('flowerBase strips the ~N suffix; plain ids unchanged', () {
      expect(Placeables.flowerBase('gul~2'), 'gul');
      expect(Placeables.flowerBase('gul'), 'gul');
      expect(Placeables.flowerBase('papatya'), 'papatya');
    });

    test('variantsFor: every species has 2 models; unknown defaults to 1', () {
      for (final f in Flowers.all) {
        expect(Flowers.variantsFor(f.id), 2, reason: '${f.id} should have 2 models');
      }
      expect(Flowers.variantsFor('unknown'), 1);
    });

    test('a variant-suffixed prop is still a flower, not an object', () {
      expect(Placeables.isFlower('gul~2'), true);
      expect(Placeables.isObject('gul~2'), false);
      expect(Placeables.isRoad('gul~2'), false);
      final (road, prop) = Placeables.split('gul~2');
      expect(road, isNull);
      expect(prop, 'gul~2');
    });

    test('planting a variant prop stores it, counts by base, round-trips', () {
      final g = const Garden().plant(0, 'gul~2');
      expect(g.propAt(0), 'gul~2');
      expect(g.countPlanted('gul'), 1); // counted despite the ~2 suffix
      expect(g.countPlanted('papatya'), 0);
      expect(Garden.decode(g.encode()).propAt(0), 'gul~2'); // survives save/load
    });

    test('a variant flower still refuses to sit on a road', () {
      var g = const Garden().plant(0, 'road_dirt');
      g = g.plant(0, 'gul~1'); // flowers only grow on bare grass
      expect(g.propAt(0), isNull);
      expect(g.groundAt(0), 'road_dirt');
    });
  });

  group('legacy species migration (#v27)', () {
    test('kaktus is gone from the catalogue', () {
      expect(Flowers.byId('kaktus'), isNull);
      expect(Flowers.byId('kaktusd'), isNotNull);
    });

    test('migrateId maps the base id and keeps variant + composite parts', () {
      expect(Flowers.migrateId('kaktus'), 'kaktusd');
      expect(Flowers.migrateId('kaktus~1'), 'kaktusd~1');
      expect(Flowers.migrateId('gul~1'), 'gul~1');
      expect(Flowers.migrateId('road_dirt+fence_wood'), 'road_dirt+fence_wood');
    });

    test('migrateGarden rewrites planted legacy tiles, else returns same', () {
      final g = Garden(cols: 4, rows: 4, tiles: const {0: 'kaktus~1', 1: 'gul', 2: 'road_dirt'});
      final m = Flowers.migrateGarden(g);
      expect(m.tiles[0], 'kaktusd~1');
      expect(m.tiles[1], 'gul');
      expect(m.tiles[2], 'road_dirt');
      final clean = Garden(cols: 4, rows: 4, tiles: const {0: 'gul'});
      expect(identical(Flowers.migrateGarden(clean), clean), true);
    });

    test('migrateOwned merges legacy counts into the replacement', () {
      expect(Flowers.migrateOwned({'kaktus': 2, 'kaktusd': 1, 'gul': 3}),
          {'kaktusd': 3, 'gul': 3});
      final clean = {'gul': 1};
      expect(identical(Flowers.migrateOwned(clean), clean), true);
    });
  });

  group('phase-end action (#v25 item1)', () {
    test('a finished run is always done, regardless of auto-start', () {
      expect(phaseEndAction(isFinished: true, autoBreak: true), PhaseEnd.done);
      expect(phaseEndAction(isFinished: true, autoBreak: false), PhaseEnd.done);
    });
    test('auto-start on rolls into the next phase; off asks first (both ways)', () {
      expect(phaseEndAction(isFinished: false, autoBreak: true), PhaseEnd.autoStart);
      expect(phaseEndAction(isFinished: false, autoBreak: false), PhaseEnd.prompt);
    });
  });

  group('Paging (#v25 item3)', () {
    test('pageCount rounds up; empty still has one page', () {
      expect(Paging.pageCount(0, 50), 1);
      expect(Paging.pageCount(1, 50), 1);
      expect(Paging.pageCount(50, 50), 1);
      expect(Paging.pageCount(51, 50), 2);
      expect(Paging.pageCount(100, 50), 2);
      expect(Paging.pageCount(101, 50), 3);
    });
    test('page slices the right window and clamps the partial/over-end pages', () {
      final items = [for (var i = 0; i < 120; i++) i];
      expect(Paging.page(items, 0, 50).first, 0);
      expect(Paging.page(items, 0, 50).length, 50);
      expect(Paging.page(items, 1, 50).first, 50);
      expect(Paging.page(items, 2, 50), [for (var i = 100; i < 120; i++) i]); // partial
      expect(Paging.page(items, 3, 50), isEmpty); // past the end
    });
  });

  group('SessionRecord.copyWith (#v25)', () {
    test('relabel keeps day/minutes/timestamp', () {
      const r = SessionRecord(100, 60, 'MATH', minuteOfDay: 540);
      final r2 = r.copyWith(label: 'CODING');
      expect(r2.label, 'CODING');
      expect(r2.epochDay, 100);
      expect(r2.minutes, 60);
      expect(r2.minuteOfDay, 540); // timestamp preserved → trend keeps its shape
    });
  });

  group('habits (#v29)', () {
    test('add rejects empty + case-insensitive dupes; codec round-trips', () {
      var hs = <Habit>[];
      hs = Habits.add(hs, ' water ', 0xFF2A7DE1);
      hs = Habits.add(hs, 'WATER', 0xFFE5484D); // dupe
      hs = Habits.add(hs, '   ', 0xFF46A03C); // empty
      expect(hs.length, 1);
      expect(hs.first.name, 'WATER'); // cleaned + uppercased
      hs = Habits.add(hs, 'Read', 0xFF8E4FE0);
      final rt = Habits.decode(Habits.encode(hs));
      expect(rt.map((h) => h.name), ['WATER', 'READ']);
      expect(rt[1].color, 0xFF8E4FE0);
    });

    test('remove drops by name', () {
      final hs = [const Habit('WATER', 1), const Habit('READ', 2)];
      expect(Habits.remove(hs, 'WATER').map((h) => h.name), ['READ']);
    });

    test('log bump adds/clamps and codec round-trips', () {
      var log = <String, Map<int, int>>{};
      log = HabitLog.bump(log, 'WATER', 100);
      log = HabitLog.bump(log, 'WATER', 100); // 2nd time same day
      log = HabitLog.bump(log, 'WATER', 101);
      expect(HabitLog.daysDone(log['WATER']!), 2);
      expect(HabitLog.totalTimes(log['WATER']!), 3);
      log = HabitLog.bump(log, 'WATER', 101, -1); // undo → day removed
      expect(log['WATER']!.containsKey(101), false);
      log = HabitLog.bump(log, 'WATER', 100, -5); // over-undo clamps + drops
      expect(log.containsKey('WATER'), false);
      final rt = HabitLog.decode(HabitLog.encode(HabitLog.bump({}, 'X', 5, 3)));
      expect(rt['X']![5], 3);
    });

    test('streak counts back from today or yesterday, stops at a gap', () {
      final days = {10: 1, 9: 1, 8: 2, 5: 1};
      expect(HabitLog.streak(days, 10), 3); // 10,9,8
      expect(HabitLog.streak(days, 11), 3); // counts from yesterday
      expect(HabitLog.streak(days, 12), 0); // 2-day gap
      expect(HabitLog.streak(days, 5), 1);
    });

    test('label habits derive counts straight from records', () {
      final recs = [
        const SessionRecord(100, 60, 'TURKISH'),
        const SessionRecord(100, 30, 'TURKISH'),
        const SessionRecord(101, 45, 'TURKISH'),
        const SessionRecord(101, 20, 'MATH'),
      ];
      final byLabel = LabelHabits.fromRecords(recs);
      expect(HabitLog.daysDone(byLabel['TURKISH']!), 2);
      expect(HabitLog.totalTimes(byLabel['TURKISH']!), 3); // "2 days · 3 times"
      expect(byLabel['MATH']![101], 1);

      // same shape, but summing minutes instead of session count — feeds the
      // heatmap tap-for-details tooltip (#v30 follow-up)
      final minsByLabel = LabelHabits.minutesFromRecords(recs);
      expect(minsByLabel['TURKISH'], {100: 90, 101: 45});
      expect(minsByLabel['MATH'], {101: 20});
    });

    test('moods codec keeps only 1..5', () {
      expect(Moods.decode(Moods.encode({100: 5, 101: 3})), {100: 5, 101: 3});
      expect(Moods.decode('100:0\n101:6\n102:4'), {102: 4}); // out-of-range dropped
    });
  });

  group('money manager (#v29)', () {
    final rates = {'USD': 1.0, 'EUR': 0.5, 'TRY': 40.0};

    test('tx codec round-trips incl. note with spaces', () {
      final txs = [
        const MoneyTx(100, 540, 12345, 'TRY', 'FOOD', true, 'lunch out'),
        const MoneyTx(100, 600, 500000, 'TRY', 'SALARY', false),
      ];
      final rt = MoneyBook.decode(MoneyBook.encode(txs));
      expect(rt.length, 2);
      expect(rt[0].amountMinor, 12345);
      expect(rt[0].note, 'lunch out');
      expect(rt[1].isExpense, false);
    });

    test('toMain converts via USD cross-rate', () {
      // 40 TRY at USD-rate 40 = 1 USD = 0.5 EUR
      const t = MoneyTx(100, 0, 4000, 'TRY', 'FOOD', true);
      expect(MoneyBook.toMain(t, rates, 'USD'), closeTo(1.0, 1e-9));
      expect(MoneyBook.toMain(t, rates, 'EUR'), closeTo(0.5, 1e-9));
      expect(MoneyBook.toMain(t, rates, 'TRY'), closeTo(40.0, 1e-9)); // same cur
    });

    test('unknown currency falls back to raw amount', () {
      const t = MoneyTx(100, 0, 1000, 'XYZ', 'FOOD', true);
      expect(MoneyBook.toMain(t, rates, 'USD'), closeTo(10.0, 1e-9));
    });

    test('month totals + category split in the main currency', () {
      final d = dateOfEpochDay(epochDayOf(DateTime(2026, 7, 3)));
      final day = epochDayOf(DateTime(d.year, d.month, 3));
      final txs = [
        MoneyTx(day, 0, 4000, 'TRY', 'FOOD', true), // 1 USD
        MoneyTx(day, 0, 8000, 'TRY', 'HOME', true), // 2 USD
        MoneyTx(day, 0, 400000, 'TRY', 'SALARY', false), // 100 USD income
      ];
      final (inc, exp) = MoneyBook.monthTotals(txs, d.year, d.month, rates, 'USD');
      expect(inc, closeTo(100.0, 1e-9));
      expect(exp, closeTo(3.0, 1e-9));
      final cats = MoneyBook.byCategory(txs, d.year, d.month, rates, 'USD');
      expect(cats.first.key, 'HOME'); // 2 > 1, sorted
      expect(cats.first.value, closeTo(2.0, 1e-9));
    });

    test('window totals + category split for the daily/weekly/monthly chart (#v30)', () {
      final day = epochDayOf(DateTime(2026, 7, 3));
      final txs = [
        MoneyTx(day, 0, 4000, 'TRY', 'FOOD', true), // 1 USD
        MoneyTx(day, 0, 8000, 'TRY', 'HOME', true), // 2 USD
        MoneyTx(day, 0, 400000, 'TRY', 'SALARY', false), // 100 USD income
        MoneyTx(day - 10, 0, 100000, 'TRY', 'FOOD', true), // 25 USD, outside a 1-day window
      ];
      final (inc, exp) = MoneyBook.totalsInWindow(txs, day, day, rates, 'USD');
      expect(inc, closeTo(100.0, 1e-9));
      expect(exp, closeTo(3.0, 1e-9)); // day-10 entry excluded
      final cats = MoneyBook.byCategoryInWindow(txs, day, day, rates, 'USD');
      expect(cats.first.key, 'HOME'); // 2 > 1, sorted, income excluded
      expect(cats.first.value, closeTo(2.0, 1e-9));
      // widen the window to include the older entry
      final (inc2, exp2) = MoneyBook.totalsInWindow(txs, day - 10, day, rates, 'USD');
      expect(inc2, closeTo(100.0, 1e-9));
      expect(exp2, closeTo(28.0, 1e-9)); // + 25 USD
    });

    test('fx cache codec + 1h TTL', () {
      final enc = Fx.encode({'USD': 1.0, 'TRY': 40.0}, 1000);
      final (r, at) = Fx.decode(enc);
      expect(r['TRY'], 40.0);
      expect(at, 1000);
      expect(Fx.needsRefresh(1000 + Fx.ttlMs + 1, 1000), true);
      expect(Fx.needsRefresh(1000 + Fx.ttlMs - 1, 1000), false);
    });

    test('reward: +1 per completed under-budget day, cursor advances', () {
      final rates1 = {'USD': 1.0};
      // rate = \$20/day. day 10 spent \$10 (under), day 11 spent \$30 (over),
      // day 12 no spend (under). today = 13 → evaluates days 11..12 (10 already done).
      final txs = [
        const MoneyTx(11, 0, 3000, 'USD', 'FOOD', true),
        const MoneyTx(10, 0, 1000, 'USD', 'FOOD', true),
      ];
      final (coins, cursor) = MoneyReward.accrue(
          txs: txs, rateMinor: 2000, lastDoneDay: 10, today: 13,
          rates: rates1, main: 'USD');
      expect(coins, 1); // only day 12
      expect(cursor, 12);
    });

    test('reward off (rate 0) awards nothing but still advances the cursor', () {
      final (coins, cursor) = MoneyReward.accrue(
          txs: const [], rateMinor: 0, lastDoneDay: 5, today: 10,
          rates: const {'USD': 1.0}, main: 'USD');
      expect(coins, 0);
      expect(cursor, 9); // so enabling later never back-pays
    });

    test('reward is a no-op when already caught up to yesterday', () {
      final (coins, cursor) = MoneyReward.accrue(
          txs: const [], rateMinor: 2000, lastDoneDay: 9, today: 10,
          rates: const {'USD': 1.0}, main: 'USD');
      expect(coins, 0);
      expect(cursor, 9);
    });
  });
}
