// Pure, framework-free app logic — a direct Dart port of the Android app's Kotlin classes
// (PomodoroEngine, PixelTheme, Flowers, Economy, Garden, Labels, LabelColors, Stats). No
// Flutter imports here on purpose, so the same rules can be unit-tested and reused unchanged.

// ---- timer engine -----------------------------------------------------------

enum Mode { work, breakMode }

class PomodoroEngine {
  final int workMillis;
  final int breakMillis;
  final int totalSessions;
  Mode mode = Mode.work;
  int timeLeftMillis;
  bool isRunning = false;
  int session = 1;
  bool isFinished = false;

  PomodoroEngine({
    int workMillis = 25 * 60 * 1000,
    int breakMillis = 5 * 60 * 1000,
    this.totalSessions = 4,
  })  : workMillis = workMillis,
        breakMillis = breakMillis,
        timeLeftMillis = workMillis;

  int durationOf(Mode t) => t == Mode.work ? workMillis : breakMillis;

  void start() {
    if (!isFinished && timeLeftMillis > 0) isRunning = true;
  }

  void pause() => isRunning = false;

  void reset() {
    isRunning = false;
    isFinished = false;
    session = 1;
    mode = Mode.work;
    timeLeftMillis = workMillis;
  }

  void switchMode() {
    isRunning = false;
    isFinished = false;
    mode = mode == Mode.work ? Mode.breakMode : Mode.work;
    timeLeftMillis = durationOf(mode);
  }

  void setTimeLeft(int millis) {
    timeLeftMillis = millis.clamp(0, durationOf(mode)).toInt();
  }

  Mode finishPhase() {
    final finished = mode;
    isRunning = false;
    if (finished == Mode.work) {
      mode = Mode.breakMode;
      timeLeftMillis = breakMillis;
    } else if (session >= totalSessions) {
      isFinished = true;
      mode = Mode.work;
      timeLeftMillis = workMillis;
    } else {
      session++;
      mode = Mode.work;
      timeLeftMillis = workMillis;
    }
    return finished;
  }

  int progressPercent() {
    final total = durationOf(mode);
    if (total <= 0) return 0;
    return ((timeLeftMillis * 100) ~/ total).clamp(0, 100).toInt();
  }

  String formattedTime() {
    final totalSeconds = (timeLeftMillis + 999) ~/ 1000;
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

// ---- themes -----------------------------------------------------------------

class PixelTheme {
  final String id;
  final String displayName;
  final int bg, panel, accent, work, breakColor, onSurface, onSurfaceDim, onAccent, shadow;
  const PixelTheme({
    required this.id,
    required this.displayName,
    required this.bg,
    required this.panel,
    required this.accent,
    required this.work,
    required this.breakColor,
    required this.onSurface,
    required this.onSurfaceDim,
    required this.onAccent,
    required this.shadow,
  });

  int phaseColor(Mode m) => m == Mode.work ? work : breakColor;
}

class Themes {
  static const dark = PixelTheme(
      id: 'dark', displayName: 'DARK',
      bg: 0xFF161616, panel: 0xFF262626, accent: 0xFFFF5A5F, work: 0xFF46E08A,
      breakColor: 0xFF58A6FF, onSurface: 0xFFF4F4F4, onSurfaceDim: 0xFF8E8E8E,
      onAccent: 0xFF1A1A1A, shadow: 0xFF000000);
  static const light = PixelTheme(
      id: 'light', displayName: 'LIGHT',
      bg: 0xFFF2F2F4, panel: 0xFFFFFFFF, accent: 0xFFE5484D, work: 0xFF1F9D55,
      breakColor: 0xFF2A7DE1, onSurface: 0xFF18181B, onSurfaceDim: 0xFF6E6E73,
      onAccent: 0xFFFFFFFF, shadow: 0xFFC7C7CC);
  static const mocha = PixelTheme(
      id: 'mocha', displayName: 'MOCHA',
      bg: 0xFF1E1E2E, panel: 0xFF313244, accent: 0xFFF38BA8, work: 0xFFA6E3A1,
      breakColor: 0xFF89B4FA, onSurface: 0xFFCDD6F4, onSurfaceDim: 0xFFA6ADC8,
      onAccent: 0xFF1E1E2E, shadow: 0xFF11111B);
  static const frappe = PixelTheme(
      id: 'frappe', displayName: 'FRAPPE',
      bg: 0xFF303446, panel: 0xFF414559, accent: 0xFFE78284, work: 0xFFA6D189,
      breakColor: 0xFF8CAAEE, onSurface: 0xFFC6D0F5, onSurfaceDim: 0xFFA5ADCE,
      onAccent: 0xFF303446, shadow: 0xFF232634);
  static const latte = PixelTheme(
      id: 'latte', displayName: 'LATTE',
      bg: 0xFFF7EFDD, panel: 0xFFFFFBF0, accent: 0xFFD20F39, work: 0xFF40A02B,
      breakColor: 0xFF1E66F5, onSurface: 0xFF4C4F69, onSurfaceDim: 0xFF8A7F6A,
      onAccent: 0xFFFFFFFF, shadow: 0xFFD9CBB0);

  static const all = [dark, light, mocha, frappe, latte];
  static const fallback = dark;

  static PixelTheme byId(String? id) {
    for (final t in all) {
      if (t.id == id) return t;
    }
    return fallback;
  }
}

// ---- flowers ----------------------------------------------------------------

const int flowerGreen = 0xFF46A03C;

class Flower {
  final String id;
  final Map<String, String> names;
  final int petal, center;
  final List<String> grid;
  const Flower(this.id, this.names, this.petal, this.center, this.grid);

  String get nameTr => names['tr'] ?? names['en'] ?? id;
  String nameIn(String lang) => names[lang] ?? names['en'] ?? nameTr;
}

const List<String> _bloom = [
  '..PPP...', '.PPPPP..', '.PPCPP..', '.PPPPP..',
  '..PPP...', '...S....', '..LSL...', '...S....',
];
const List<String> _tulip = [
  '.P.P.P..', '.PPPPP..', '.PPPPP..', '..PPP...',
  '...S....', '..LS....', '...SL...', '...S....',
];
const List<String> _cactus = [
  '...C....', '..PPP...', 'P.PPP...', 'PPPPP...',
  '..PPP...', '..PPP...', '..PPP...', '..PPP...',
];

Map<String, String> _loc(String en, String tr, String pl, String de, String ko, String it) =>
    {'en': en, 'tr': tr, 'pl': pl, 'de': de, 'ko': ko, 'it': it};

class Flowers {
  static const langs = ['en', 'tr', 'pl', 'de', 'ko', 'it'];

  static final all = <Flower>[
    Flower('gul', _loc('Rose', 'Gül', 'Róża', 'Rose', '장미', 'Rosa'), 0xFFE5484D, 0xFFB01030, _bloom),
    Flower('papatya', _loc('Daisy', 'Papatya', 'Stokrotka', 'Gänseblümchen', '데이지', 'Margherita'), 0xFFFFFFFF, 0xFFF2C94C, _bloom),
    Flower('lale', _loc('Tulip', 'Lale', 'Tulipan', 'Tulpe', '튤립', 'Tulipano'), 0xFFE0457B, 0xFFC02060, _tulip),
    Flower('kaktus', _loc('Cactus', 'Kaktüs', 'Kaktus', 'Kaktus', '선인장', 'Cactus'), 0xFF46A03C, 0xFFF2C94C, _cactus),
    Flower('kasimpati', _loc('Chrysanthemum', 'Kasımpatı', 'Chryzantema', 'Chrysantheme', '국화', 'Crisantemo'), 0xFFF2994A, 0xFFC9710B, _bloom),
    Flower('menekse', _loc('Violet', 'Menekşe', 'Fiołek', 'Veilchen', '제비꽃', 'Viola'), 0xFF8E4FE0, 0xFFF2C94C, _bloom),
    Flower('nilufer', _loc('Water Lily', 'Nilüfer', 'Lilia wodna', 'Seerose', '수련', 'Ninfea'), 0xFFF4A6C0, 0xFFF2C94C, _bloom),
    Flower('orkide', _loc('Orchid', 'Orkide', 'Orchidea', 'Orchidee', '난초', 'Orchidea'), 0xFFC24FE0, 0xFF7A2EA0, _bloom),
    Flower('begonya', _loc('Begonia', 'Begonya', 'Begonia', 'Begonie', '베고니아', 'Begonia'), 0xFFF2585B, 0xFFFFD9A0, _bloom),
    Flower('kamelya', _loc('Camellia', 'Kamelya', 'Kamelia', 'Kamelie', '동백', 'Camelia'), 0xFFE02C6D, 0xFFFFFFFF, _bloom),
  ];

  static Flower? byId(String? id) {
    for (final f in all) {
      if (f.id == id) return f;
    }
    return null;
  }
}

// ---- placeable objects (non-flower) -----------------------------------------

/// Garden objects that aren't flowers. They live in the same tile map (value =
/// the id). Roads lie flat on the ground; fences stand up. Adjacent same-kind
/// tiles abut, so they read as continuous paths/fences with no extra logic.
///
/// A tile can hold up to two things: a flat **ground** layer (a road) and a
/// standing **prop** (a flower or a fence). Fences may stand on top of a road,
/// so such a tile is stored as the composite `"<road>+<fence>"`. Flowers only
/// grow on bare grass. A plain id (no `+`) is a single occupant.
class Placeables {
  // 4 road surfaces + 3 fence materials.
  static const roadIds = ['road_concrete', 'road_wood', 'road_dirt', 'road_stone'];
  static const fenceIds = ['fence_wood', 'fence_dark', 'fence_stone'];
  static const objectIds = [...roadIds, ...fenceIds];

  static bool isObject(String id) => objectIds.contains(id);
  static bool isRoad(String id) => roadIds.contains(id);
  static bool isFence(String id) => fenceIds.contains(id);
  static bool isFlower(String id) => id.isNotEmpty && !isObject(id);

  /// Split a stored tile value into (road, prop). prop is the standing
  /// flower/fence; road is the flat ground beneath it (or null).
  static (String?, String?) split(String value) {
    String? road, prop;
    for (final p in value.split('+')) {
      if (p.isEmpty) continue;
      if (isRoad(p)) {
        road = p;
      } else {
        prop = p;
      }
    }
    return (road, prop);
  }

  static String? groundOf(String? value) => value == null ? null : split(value).$1;
  static String? propOf(String? value) => value == null ? null : split(value).$2;

  /// Re-join a (road, prop) pair into a stored value (road first).
  static String combine(String? road, String? prop) =>
      (road != null && prop != null) ? '$road+$prop' : (road ?? prop)!;
}

// ---- economy ----------------------------------------------------------------

class Economy {
  static const flowerCost = 10;
  static const objectCost = 5; // roads + fences
  static const baseGardenCols = 4;
  static const baseGardenRows = 6;
  static int coinsFor(int minutes) => minutes <= 0 ? 0 : minutes ~/ 5;

  /// EXPAND price — rises with the plot's perimeter so each ring costs more.
  static int upgradeCost(int cols, int rows) => 2 * (cols + rows) + 1;

  /// Buy price for any catalogue id (flower or object).
  static int costOf(String id) => Placeables.isObject(id) ? objectCost : flowerCost;
}

// ---- garden -----------------------------------------------------------------

class Garden {
  final int cols;
  final int rows;
  final Map<int, String> tiles;
  const Garden({
    this.cols = Economy.baseGardenCols,
    this.rows = Economy.baseGardenRows,
    this.tiles = const {},
  });

  int get tileCount => cols * rows;
  bool isValidIndex(int i) => i >= 0 && i < tileCount;

  /// Raw stored value for a tile (may be a `"road+fence"` composite).
  String? flowerAt(int i) => tiles[i];

  /// The flat ground layer (a road) on a tile, or null.
  String? groundAt(int i) => Placeables.groundOf(tiles[i]);

  /// The standing prop (flower or fence) on a tile, or null.
  String? propAt(int i) => Placeables.propOf(tiles[i]);

  /// Place [id] on [index], honouring the layering rules:
  /// • a flower only grows on bare grass (rejected if a road is there);
  /// • a fence stands on grass or on top of a road (keeps the road);
  /// • a road slides under an existing fence (keeps the fence) but clears a
  ///   flower, since flowers can't sit on roads.
  Garden plant(int index, String id) {
    if (!isValidIndex(index) || id.trim().isEmpty) return this;
    final current = tiles[index];
    final (road, prop) = current == null ? (null, null) : Placeables.split(current);

    final String value;
    if (Placeables.isRoad(id)) {
      final keepFence = prop != null && Placeables.isFence(prop) ? prop : null;
      value = Placeables.combine(id, keepFence);
    } else if (Placeables.isFence(id)) {
      value = Placeables.combine(road, id);
    } else {
      // flower — only on bare grass
      if (road != null) return this;
      value = id;
    }
    return Garden(cols: cols, rows: rows, tiles: {...tiles, index: value});
  }

  Garden clear(int index) {
    if (!tiles.containsKey(index)) return this;
    final next = {...tiles}..remove(index);
    return Garden(cols: cols, rows: rows, tiles: next);
  }

  /// Expand by one tile on every side (a ring), so the plot grows **centred** —
  /// existing tiles shift by (+1 col, +1 row) into the larger grid.
  Garden grow() {
    final nc = cols + 2;
    final nr = rows + 2;
    final remapped = <int, String>{};
    tiles.forEach((index, id) {
      final r = index ~/ cols;
      final c = index % cols;
      remapped[(r + 1) * nc + (c + 1)] = id;
    });
    return Garden(cols: nc, rows: nr, tiles: remapped);
  }

  int countPlanted(String flowerId) => tiles.values.where((v) {
        final (road, prop) = Placeables.split(v);
        return road == flowerId || prop == flowerId;
      }).length;

  String encode() {
    final b = StringBuffer('cols:$cols\nrows:$rows');
    final keys = tiles.keys.toList()..sort();
    for (final k in keys) {
      b.write('\n$k:${tiles[k]}');
    }
    return b.toString();
  }

  static Garden decode(String? text) {
    if (text == null || text.trim().isEmpty) return const Garden();
    var cols = Economy.baseGardenCols;
    var rows = Economy.baseGardenRows;
    final tiles = <int, String>{};
    for (final line in text.split('\n')) {
      if (line.trim().isEmpty) continue;
      final i = line.indexOf(':');
      if (i < 0) continue;
      final key = line.substring(0, i).trim();
      final value = line.substring(i + 1).trim();
      if (key == 'size') {
        final s = int.tryParse(value); // legacy square gardens
        if (s != null && s >= 1) {
          cols = s;
          rows = s;
        }
      } else if (key == 'cols') {
        final s = int.tryParse(value);
        if (s != null && s >= 1) cols = s;
      } else if (key == 'rows') {
        final s = int.tryParse(value);
        if (s != null && s >= 1) rows = s;
      } else {
        final idx = int.tryParse(key);
        if (idx != null && idx >= 0 && value.isNotEmpty) tiles[idx] = value;
      }
    }
    tiles.removeWhere((k, v) => k >= cols * rows);
    return Garden(cols: cols, rows: rows, tiles: tiles);
  }
}

// ---- focus labels + colors --------------------------------------------------

class Labels {
  static const defaultLabel = 'STUDY';
  static const maxLen = 12;
  static const seed = ['STUDY', 'MATH', 'CODING', 'READING'];

  static String? normalize(String raw) {
    final cleaned = raw
        .toUpperCase()
        .split('')
        .map((ch) => RegExp(r'[A-Z0-9 ]').hasMatch(ch) ? ch : ' ')
        .join()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return null;
    final capped = cleaned.length > maxLen ? cleaned.substring(0, maxLen) : cleaned;
    return capped.trim();
  }

  static List<String> add(List<String> list, String raw) {
    final label = normalize(raw);
    if (label == null) return list;
    if (list.any((l) => l.toUpperCase() == label.toUpperCase())) return list;
    return [...list, label];
  }

  static List<String> remove(List<String> list, String label) {
    if (list.length <= 1) return list;
    return list.where((l) => l.toUpperCase() != label.toUpperCase()).toList();
  }
}

class LabelColors {
  static const palette = [
    0xFFE5484D, 0xFFF2994A, 0xFFF2C94C, 0xFF46A03C, 0xFF2A9D8F,
    0xFF2A7DE1, 0xFF8E4FE0, 0xFFE0457B, 0xFF9C6B4A, 0xFF8E8E8E,
  ];

  static int _stableHash(String s) {
    var h = 0;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h;
  }

  static int defaultFor(String label) {
    final key = label.trim().toUpperCase();
    return palette[_stableHash(key) % palette.length];
  }

  static int colorFor(String label, Map<String, int> chosen) =>
      chosen[label.toUpperCase()] ?? defaultFor(label);

  static String encode(Map<String, int> colors) =>
      colors.entries.map((e) => '${e.key.toUpperCase()}:${e.value}').join('\n');

  static Map<String, int> decode(String? text) {
    final out = <String, int>{};
    if (text == null || text.trim().isEmpty) return out;
    for (final line in text.split('\n')) {
      if (line.trim().isEmpty) continue;
      final i = line.indexOf(':');
      if (i < 0) continue;
      final name = line.substring(0, i).trim().toUpperCase();
      final color = int.tryParse(line.substring(i + 1).trim());
      if (name.isNotEmpty && color != null) out[name] = color;
    }
    return out;
  }
}

// ---- stats ------------------------------------------------------------------

class SessionRecord {
  final int epochDay;
  final int minutes;
  final String label;
  const SessionRecord(this.epochDay, this.minutes, this.label);
}

class StatTotals {
  final int today, week, month, year, all;
  const StatTotals(this.today, this.week, this.month, this.year, this.all);
}

int epochDayOf(DateTime d) =>
    DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/ 86400000;

DateTime dateOfEpochDay(int e) =>
    DateTime.fromMillisecondsSinceEpoch(e * 86400000, isUtc: true);

class StatsAggregator {
  static StatTotals aggregate(List<SessionRecord> records, DateTime today) {
    final todayE = epochDayOf(today);
    final weekStart = todayE - (today.weekday - 1);
    var day = 0, week = 0, month = 0, year = 0, all = 0;
    for (final r in records) {
      final min = r.minutes < 0 ? 0 : r.minutes;
      all += min;
      final d = dateOfEpochDay(r.epochDay);
      if (d.year == today.year) {
        year += min;
        if (d.month == today.month) month += min;
      }
      if (r.epochDay >= weekStart && r.epochDay <= todayE) week += min;
      if (r.epochDay == todayE) day += min;
    }
    return StatTotals(day, week, month, year, all);
  }

  static bool _inMonth(int epochDay, int year, int month) {
    final d = dateOfEpochDay(epochDay);
    return d.year == year && d.month == month;
  }

  static int monthTotal(List<SessionRecord> records, int year, int month) {
    var sum = 0;
    for (final r in records) {
      if (_inMonth(r.epochDay, year, month)) sum += r.minutes < 0 ? 0 : r.minutes;
    }
    return sum;
  }

  static List<MapEntry<String, int>> byLabelInMonth(
      List<SessionRecord> records, int year, int month) {
    final map = <String, int>{};
    for (final r in records) {
      if (!_inMonth(r.epochDay, year, month)) continue;
      map[r.label] = (map[r.label] ?? 0) + (r.minutes < 0 ? 0 : r.minutes);
    }
    final list = map.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return list;
  }

  static List<MapEntry<String, int>> byLabelAll(List<SessionRecord> records) {
    final map = <String, int>{};
    for (final r in records) {
      map[r.label] = (map[r.label] ?? 0) + (r.minutes < 0 ? 0 : r.minutes);
    }
    return map.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  }

  static List<int> dailySeries(List<SessionRecord> records, int year, int month) {
    final days = DateTime(year, month + 1, 0).day;
    final out = List<int>.filled(days, 0);
    for (final r in records) {
      if (!_inMonth(r.epochDay, year, month)) continue;
      final dom = dateOfEpochDay(r.epochDay).day - 1;
      out[dom] += r.minutes < 0 ? 0 : r.minutes;
    }
    return out;
  }

  static String formatMinutes(int min) {
    final safe = min < 0 ? 0 : min;
    final h = safe ~/ 60;
    final m = safe % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }
}

class StatsCodec {
  static String encode(List<SessionRecord> records) =>
      records.map((r) => '${r.epochDay},${r.minutes},${r.label}').join('\n');

  static List<SessionRecord> decode(String? text) {
    final out = <SessionRecord>[];
    if (text == null || text.trim().isEmpty) return out;
    for (final line in text.split('\n')) {
      if (line.trim().isEmpty) continue;
      final parts = line.split(',');
      if (parts.length < 3) continue;
      final day = int.tryParse(parts[0].trim());
      final min = int.tryParse(parts[1].trim());
      final label = parts.sublist(2).join(',').trim();
      if (day == null || min == null || label.isEmpty) continue;
      out.add(SessionRecord(day, min, label));
    }
    return out;
  }
}

// ---- first-launch test fixture ----------------------------------------------

class TestData {
  static const seedCoins = 1000;
  static const labels = ['MATH', 'HISTORY', 'ENGLISH', 'CODING', 'SCIENCE', 'TURKISH', 'READING'];

  static List<SessionRecord> records(DateTime today) {
    final out = <SessionRecord>[];
    void add(DateTime date, int min, String label) =>
        out.add(SessionRecord(epochDayOf(date), min, label));

    add(today, 60, 'MATH');
    add(today, 100, 'HISTORY');
    add(today, 40, 'ENGLISH');
    add(today, 160, 'CODING');

    add(today.subtract(const Duration(days: 1)), 200, 'MATH');
    add(today.subtract(const Duration(days: 2)), 100, 'SCIENCE');
    add(today.subtract(const Duration(days: 2)), 40, 'ENGLISH');

    add(today.subtract(const Duration(days: 9)), 150, 'TURKISH');
    add(today.subtract(const Duration(days: 14)), 150, 'TURKISH');

    add(DateTime(today.year, today.month - 1, 10), 120, 'CODING');
    add(DateTime(today.year, today.month - 1, 18), 90, 'MATH');
    add(DateTime(today.year, today.month - 2, 6), 75, 'READING');
    add(DateTime(today.year, today.month - 2, 22), 130, 'HISTORY');
    add(DateTime(today.year, today.month - 3, 14), 60, 'ENGLISH');

    add(DateTime(2025, 11, 12), 200, 'CODING');
    add(DateTime(2025, 9, 5), 150, 'MATH');
    add(DateTime(2025, 6, 20), 90, 'READING');
    add(DateTime(2025, 3, 8), 110, 'HISTORY');

    return out;
  }
}
