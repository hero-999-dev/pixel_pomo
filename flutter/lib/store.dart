import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'logic.dart';

/// Chart styles for the stats screen.
enum ChartMode { bar, line, pie }

/// Holds every piece of app state + persistence, and drives the countdown. The UI rebuilds
/// from this single [ChangeNotifier] (mirrors the Android `MainActivity` state ownership).
class AppStore extends ChangeNotifier {
  static const _kWork = 'work_min';
  static const _kBreak = 'break_min';
  static const _kSessions = 'sessions';
  static const _kTheme = 'theme_id';
  static const _kLang = 'language';
  static const _kLabels = 'labels';
  static const _kCurrentLabel = 'current_label';
  static const _kLabelColors = 'label_colors';
  static const _kStats = 'stats';
  static const _kCoins = 'coins';
  static const _kOwned = 'owned_flowers';
  static const _kGarden = 'garden';
  static const _kHomeMode = 'home_garden_backdrop'; // live garden behind timer (#3)
  static const _kAutoBreak = 'auto_break'; // auto-start break after focus (#4)
  static const _kWallpaperCam = 'wallpaper_cam'; // live-wallpaper framing (v15)
  static const _kSeeded = 'test_seeded_v5';

  late SharedPreferences _prefs;

  int workMin = 25;
  int breakMin = 5;
  int sessions = 4;
  PixelTheme theme = Themes.dark;
  String lang = 'en';

  List<String> labels = List.of(Labels.seed);
  String currentLabel = Labels.defaultLabel;
  Map<String, int> labelColors = {};

  List<SessionRecord> records = [];
  int coins = 0;
  Map<String, int> owned = {};
  Garden garden = const Garden();

  /// Home-screen mode: false = clean pomodoro, true = live garden behind it (#3).
  bool homeGardenBackdrop = false;

  /// The camera framing the live wallpaper reproduces (set from camera mode, v15).
  WallpaperCam wallpaperCam = WallpaperCam.none;

  /// Auto-start the break when a focus session ends (#4). When off, the home
  /// screen asks first via [awaitingBreakPrompt].
  bool autoBreak = true;
  bool awaitingBreakPrompt = false;

  late PomodoroEngine engine;

  // Stats view state.
  ChartMode chartMode = ChartMode.bar;
  StatPeriod statPeriod = StatPeriod.monthly;
  int statOffset = 0; // periods back from now (history navigator, #1)
  int viewYear = DateTime.now().year;
  int viewMonth = DateTime.now().month;
  bool customizing = false;

  Timer? _timer;
  DateTime? _deadline;

  /// Wired by the UI to surface toasts (passes a localized message key).
  void Function(String messageKey)? messenger;

  AppStore() {
    engine = _buildEngine();
  }

  PomodoroEngine _buildEngine() => PomodoroEngine(
        workMillis: workMin * 60 * 1000,
        breakMillis: breakMin * 60 * 1000,
        totalSessions: sessions,
      );

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    workMin = _prefs.getInt(_kWork) ?? 25;
    breakMin = _prefs.getInt(_kBreak) ?? 5;
    sessions = _prefs.getInt(_kSessions) ?? 4;
    theme = Themes.byId(_prefs.getString(_kTheme));
    lang = _prefs.getString(_kLang) ?? 'en';

    final storedLabels = _prefs.getString(_kLabels);
    if (storedLabels != null && storedLabels.trim().isNotEmpty) {
      labels = storedLabels.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    }
    currentLabel = _prefs.getString(_kCurrentLabel) ?? Labels.defaultLabel;
    if (!labels.any((l) => l.toUpperCase() == currentLabel.toUpperCase())) {
      currentLabel = labels.first;
    }
    labelColors = LabelColors.decode(_prefs.getString(_kLabelColors));

    records = StatsCodec.decode(_prefs.getString(_kStats));
    coins = _prefs.getInt(_kCoins) ?? 0;
    owned = _decodeOwned(_prefs.getString(_kOwned));
    garden = Garden.decode(_prefs.getString(_kGarden))
        .atLeast(Economy.baseGardenCols, Economy.baseGardenRows); // migrate to the bigger base (#7)
    homeGardenBackdrop = _prefs.getBool(_kHomeMode) ?? false;
    autoBreak = _prefs.getBool(_kAutoBreak) ?? true;
    wallpaperCam = WallpaperCam.decode(_prefs.getString(_kWallpaperCam));

    _seedOnce();
    engine = _buildEngine();
    notifyListeners();
  }

  void _seedOnce() {
    if (_prefs.getBool(_kSeeded) ?? false) return;
    records.addAll(TestData.records(DateTime.now()));
    coins += TestData.seedCoins;
    for (final l in TestData.labels) {
      labels = Labels.add(labels, l);
    }
    _prefs.setString(_kStats, StatsCodec.encode(records));
    _prefs.setInt(_kCoins, coins);
    _prefs.setString(_kLabels, labels.join('\n'));
    _prefs.setBool(_kSeeded, true);
  }

  // ---- persistence helpers --------------------------------------------------

  Map<String, int> _decodeOwned(String? text) {
    final out = <String, int>{};
    if (text == null || text.trim().isEmpty) return out;
    for (final line in text.split('\n')) {
      if (line.trim().isEmpty) continue;
      final i = line.indexOf(':');
      if (i < 0) continue;
      final id = line.substring(0, i).trim();
      final n = int.tryParse(line.substring(i + 1).trim());
      if (id.isNotEmpty && n != null && n > 0) out[id] = n;
    }
    return out;
  }

  String _encodeOwned(Map<String, int> owned) => owned.entries
      .where((e) => e.value > 0)
      .map((e) => '${e.key}:${e.value}')
      .join('\n');

  void _saveLabels() {
    _prefs.setString(_kLabels, labels.join('\n'));
    _prefs.setString(_kCurrentLabel, currentLabel);
  }

  void _saveLabelColors() => _prefs.setString(_kLabelColors, LabelColors.encode(labelColors));
  void _saveStats() => _prefs.setString(_kStats, StatsCodec.encode(records));

  /// Persist the framing the live wallpaper should reproduce (v15).
  void setWallpaperCamera(double yaw, double zoom, double panXFrac, double panYFrac) {
    wallpaperCam = WallpaperCam(yaw, zoom, panXFrac, panYFrac);
    _prefs.setString(_kWallpaperCam, wallpaperCam.encode());
  }
  void _saveWallet() {
    _prefs.setInt(_kCoins, coins);
    _prefs.setString(_kOwned, _encodeOwned(owned));
  }

  void _saveGarden() => _prefs.setString(_kGarden, garden.encode());

  // ---- timer ----------------------------------------------------------------

  void start() {
    if (engine.isFinished) engine.reset();
    engine.start();
    if (!engine.isRunning) {
      notifyListeners();
      return;
    }
    _deadline = DateTime.now().add(Duration(milliseconds: engine.timeLeftMillis));
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) => _onTick());
    notifyListeners();
  }

  void _onTick() {
    final remaining = _deadline!.difference(DateTime.now()).inMilliseconds;
    if (remaining > 0) {
      engine.setTimeLeft(remaining);
      notifyListeners();
      return;
    }
    _timer?.cancel();
    engine.setTimeLeft(0);
    final finished = engine.finishPhase();
    if (finished == Mode.work) _recordWork();
    messenger?.call(finished == Mode.work ? 'workDone' : 'breakDone');
    if (engine.isFinished) {
      notifyListeners();
    } else if (finished == Mode.work && !autoBreak) {
      // pause before the break and ask the user first (#4)
      awaitingBreakPrompt = true;
      notifyListeners();
    } else {
      start();
    }
  }

  void setAutoBreak(bool v) {
    autoBreak = v;
    _prefs.setBool(_kAutoBreak, v);
    notifyListeners();
  }

  /// Resolve the "start the break?" prompt (auto-break off path).
  void confirmBreak(bool startNow) {
    awaitingBreakPrompt = false;
    if (startNow) {
      start();
    } else {
      notifyListeners();
    }
  }

  void pause() {
    _timer?.cancel();
    engine.pause();
    notifyListeners();
  }

  void reset() {
    _timer?.cancel();
    // cancelling a started focus session still pays out the time spent (#6)
    if (engine.mode == Mode.work && engine.timeLeftMillis < engine.workMillis) {
      final spent = Economy.elapsedFocusMinutes(workMin, engine.timeLeftMillis);
      if (spent > 0) {
        final now = DateTime.now();
        records.add(SessionRecord(epochDayOf(now), spent, currentLabel,
            minuteOfDay: now.hour * 60 + now.minute));
        _saveStats();
        coins += Economy.coinsFor(spent);
        _saveWallet();
      }
    }
    engine.reset();
    notifyListeners();
  }

  void switchMode() {
    _timer?.cancel();
    engine.switchMode();
    notifyListeners();
  }

  void toggleStartPause() => engine.isRunning ? pause() : start();

  void _recordWork() {
    final now = DateTime.now();
    records.add(SessionRecord(epochDayOf(now), workMin, currentLabel,
        minuteOfDay: now.hour * 60 + now.minute));
    _saveStats();
    coins += Economy.coinsFor(workMin);
    _saveWallet();
  }

  // ---- settings -------------------------------------------------------------

  void saveSettings(int work, int brk, int sess) {
    workMin = work;
    breakMin = brk;
    sessions = sess;
    _prefs.setInt(_kWork, work);
    _prefs.setInt(_kBreak, brk);
    _prefs.setInt(_kSessions, sess);
    _timer?.cancel();
    engine = _buildEngine();
    notifyListeners();
  }

  void selectTheme(PixelTheme t) {
    theme = t;
    _prefs.setString(_kTheme, t.id);
    notifyListeners();
  }

  void selectLanguage(String tag) {
    if (tag == lang) return;
    lang = tag;
    _prefs.setString(_kLang, tag);
    // reset the stats view to the current month under the new language
    viewYear = DateTime.now().year;
    viewMonth = DateTime.now().month;
    notifyListeners();
  }

  // ---- labels ---------------------------------------------------------------

  void selectLabel(String label) {
    currentLabel = label;
    _saveLabels();
    notifyListeners();
  }

  bool addLabel(String raw) {
    final updated = Labels.add(labels, raw);
    if (updated.length == labels.length) return false;
    labels = updated;
    _saveLabels();
    notifyListeners();
    return true;
  }

  void deleteLabel(String label) {
    final updated = Labels.remove(labels, label);
    if (updated.length == labels.length) return;
    labels = updated;
    if (!labels.any((l) => l.toUpperCase() == currentLabel.toUpperCase())) {
      currentLabel = labels.first;
    }
    _saveLabels();
    notifyListeners();
  }

  void renameLabel(String oldLabel, String raw) {
    final updated = Labels.rename(labels, oldLabel, raw);
    if (updated == labels) return;
    final newName = updated.firstWhere(
        (l) => !labels.any((o) => o.toUpperCase() == l.toUpperCase()),
        orElse: () => oldLabel);
    labels = updated;
    final oldU = oldLabel.toUpperCase();
    if (labelColors.containsKey(oldU)) {
      labelColors[newName.toUpperCase()] = labelColors.remove(oldU)!;
      _saveLabelColors();
    }
    if (currentLabel.toUpperCase() == oldU) currentLabel = newName;
    records = [
      for (final r in records)
        r.label.toUpperCase() == oldU ? SessionRecord(r.epochDay, r.minutes, newName) : r
    ];
    _saveStats();
    _saveLabels();
    notifyListeners();
  }

  void setLabelColor(String label, int color) {
    labelColors[label.toUpperCase()] = color;
    _saveLabelColors();
    notifyListeners();
  }

  int labelColorOf(String label) => LabelColors.colorFor(label, labelColors);

  // ---- shop -----------------------------------------------------------------

  /// Buy any catalogue id (flower or object). Adds one to inventory.
  bool buyItem(String id) {
    final cost = Economy.costOf(id);
    if (coins < cost) {
      messenger?.call('notEnough');
      return false;
    }
    coins -= cost;
    owned[id] = (owned[id] ?? 0) + 1;
    _saveWallet();
    messenger?.call('purchased');
    notifyListeners();
    return true;
  }

  bool buyFlower(Flower flower) => buyItem(flower.id);

  // ---- garden ---------------------------------------------------------------

  int availableOf(String flowerId) => (owned[flowerId] ?? 0) - garden.countPlanted(flowerId);

  void plantTile(int index, String flowerId) {
    garden = garden.plant(index, flowerId);
    _saveGarden();
    notifyListeners();
  }

  void clearTile(int index) {
    garden = garden.clear(index);
    _saveGarden();
    notifyListeners();
  }

  void toggleCustomizing() {
    customizing = !customizing;
    notifyListeners();
  }

  /// Toggle the home screen between clean pomodoro and a live garden backdrop.
  void setHomeGardenBackdrop(bool v) {
    homeGardenBackdrop = v;
    _prefs.setBool(_kHomeMode, v);
    notifyListeners();
  }

  void upgradeGarden() {
    // No size cap — the rising upgradeCost is the only limit.
    final cost = Economy.upgradeCost(garden.cols, garden.rows);
    if (coins < cost) {
      messenger?.call('notEnough');
      return;
    }
    coins -= cost;
    garden = garden.grow();
    _saveWallet();
    _saveGarden();
    messenger?.call('upgraded');
    notifyListeners();
  }

  // ---- stats view -----------------------------------------------------------

  void setChartMode(ChartMode m) {
    chartMode = m;
    notifyListeners();
  }

  void setStatPeriod(StatPeriod p) {
    statPeriod = p;
    statOffset = 0; // a fresh period starts at "now"
    notifyListeners();
  }

  void shiftStatOffset(int d) {
    final next = statOffset + d;
    if (next < 0) return; // can't browse the future
    statOffset = next;
    notifyListeners();
  }

  void shiftMonth(int delta) {
    final candidate = DateTime(viewYear, viewMonth + delta);
    final now = DateTime.now();
    if (candidate.year > now.year || (candidate.year == now.year && candidate.month > now.month)) {
      return; // don't browse the future
    }
    viewYear = candidate.year;
    viewMonth = candidate.month;
    notifyListeners();
  }

  bool get canGoNextMonth {
    final now = DateTime.now();
    return viewYear < now.year || (viewYear == now.year && viewMonth < now.month);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
