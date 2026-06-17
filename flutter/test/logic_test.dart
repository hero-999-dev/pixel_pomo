import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_pomo/logic.dart';

void main() {
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
    test('coinsFor / upgradeCost', () {
      expect(Economy.coinsFor(4), 0);
      expect(Economy.coinsFor(25), 5);
      expect(Economy.coinsFor(-3), 0);
      expect(Economy.upgradeCost(4), 9);
      expect(Economy.upgradeCost(5), 11);
    });

    test('garden grows as a centred ring; codec round-trips', () {
      // (1,1) on a 4×4 → after a +2 ring it sits at (2,2) on a 6×6.
      final g = const Garden().plant(5, 'lale').grow();
      expect(g.size, 6);
      expect(g.flowerAt(2 * 6 + 2), 'lale');
      final decoded = Garden.decode(g.encode());
      expect(decoded.size, g.size);
      expect(decoded.tiles, g.tiles);
    });

    test('garden decode drops oversized tiles and clamps size up', () {
      final d = Garden.decode('size:1\n99:gul\n0:lale');
      expect(d.size, 4);
      expect(d.flowerAt(0), 'lale');
      expect(d.tiles.containsKey(99), false);
    });

    test('garden grows with no cap; stays centred', () {
      var g = const Garden().plant(0, 'gul');
      for (var i = 0; i < 10; i++) {
        g = g.grow();
      }
      expect(g.size, Economy.baseGardenSize + 20); // +2 ring × 10, past the old 8 cap
      expect(g.countPlanted('gul'), 1); // nothing lost
      expect(g.flowerAt(10 * g.size + 10), 'gul'); // (0,0) drifted to (10,10), centred
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
