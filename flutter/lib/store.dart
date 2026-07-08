import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fx_fetch.dart';
import 'logic.dart';
import 'strings.dart';
import 'timer_notif.dart';

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
  static const _kDeleted = 'deleted_stats'; // Recycle Bin (#v31.16)
  static const _kCoins = 'coins';
  static const _kOwned = 'owned_flowers';
  static const _kGarden = 'garden';
  static const _kHomeMode = 'home_garden_backdrop'; // live garden behind timer (#3)
  static const _kTimerMode = 'timer_mode_pomodoro'; // stopwatch vs pomodoro settings (#v31.15)
  static const _kAutoBreak = 'auto_break'; // auto-start break after focus (#4)
  static const _kBlocker = 'app_blocker'; // app blocker on/off (#v23)
  static const _kBlocked = 'blocked_apps'; // csv of blocked package names (#v23)
  static const _kWallpaperCam = 'wallpaper_cam'; // live-wallpaper framing (v15)
  // habit tracker + money manager (#v29)
  static const _kHabits = 'habits';
  static const _kHabitLog = 'habit_log';
  static const _kMoods = 'moods';
  static const _kMoney = 'money_txs';
  static const _kFx = 'fx_rates';
  static const _kMainCur = 'main_currency';
  static const _kDailyRate = 'daily_rate_minor';
  static const _kMoneyRewardDay = 'money_last_reward_day';
  static const _kCustomCats = 'custom_categories'; // user-added money categories (#v30)
  static const _kSeeded = 'test_seeded_v5';

  late SharedPreferences _prefs;

  int workMin = 25;
  int breakMin = 5;
  int sessions = 4;
  PixelTheme theme = Themes.dark;
  String lang = 'en';
  bool appBlockerEnabled = false; // #v23
  Set<String> blockedApps = {}; // #v23 package names blocked during focus

  List<String> labels = List.of(Labels.seed);
  String currentLabel = Labels.defaultLabel;
  Map<String, int> labelColors = {};

  List<SessionRecord> records = [];
  // soft-deleted log entries — excluded from every stats aggregation just by
  // virtue of not being in [records] anymore; nothing else needs to know
  // about this list to "honor" the deletion (#v31.16).
  List<SessionRecord> deletedRecords = [];
  int coins = 0;
  Map<String, int> owned = {};
  Garden garden = const Garden();
  // Picks a random sprite variant when a multi-variant flower is planted (#v22).
  final Random _variantRng = Random();

  /// Home-screen mode: false = clean pomodoro, true = live garden behind it (#3).
  bool homeGardenBackdrop = false;

  /// Settings screen mode: true = show the pomodoro work/break/session
  /// steppers, false = hide them (stopwatch mode, no fixed durations to
  /// configure) (#v31.15).
  bool isPomodoroMode = true;

  /// The camera framing the live wallpaper reproduces (set from camera mode, v15).
  WallpaperCam wallpaperCam = WallpaperCam.none;

  /// Auto-start the break when a focus session ends (#4). When off, the home
  /// screen asks first via [awaitingBreakPrompt].
  bool autoBreak = false; // off on a fresh install (#v23 fb)
  bool awaitingBreakPrompt = false;

  // ---- habit tracker + money manager (#v29) ---------------------------------
  List<Habit> habits = [];
  Map<String, Map<int, int>> habitLog = {}; // manual habit -> day -> count
  Map<int, int> moods = {}; // epochDay -> 1..5
  List<MoneyTx> money = [];
  Map<String, double> fxRates = {}; // per-USD
  int fxFetchedAt = 0;
  String mainCurrency = 'USD';
  int dailyRateMinor = 0; // 0 = daily-budget coin off
  int _moneyRewardDay = 0; // last day evaluated for the budget coin
  List<String> customCategories = []; // user-added money categories (#v30)
  bool _fxFetching = false;

  late PomodoroEngine engine;
  final StopwatchTimer stopwatch = StopwatchTimer(); // #v31.16

  // Stats view state.
  ChartMode chartMode = ChartMode.bar;
  StatPeriod statPeriod = StatPeriod.monthly;
  int statOffset = 0; // periods back from now (history navigator, #1)
  int viewYear = DateTime.now().year;
  int viewMonth = DateTime.now().month;
  bool customizing = false;

  Timer? _timer;
  DateTime? _deadline; // pomodoro: counts DOWN toward this
  DateTime? _stopwatchStartedAt; // stopwatch: counts UP from this (#v31.16)

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
    // a previously-selected language that no longer exists (e.g. 'ko', removed in
    // #v22) falls back to English so the UI isn't left half-translated.
    if (!languageOptions.any((o) => o[0] == lang)) lang = 'en';
    appBlockerEnabled = _prefs.getBool(_kBlocker) ?? false;
    blockedApps = AppBlocker.decode(_prefs.getString(_kBlocked));

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
    deletedRecords = StatsCodec.decode(_prefs.getString(_kDeleted));
    coins = _prefs.getInt(_kCoins) ?? 0;
    final rawOwned = _decodeOwned(_prefs.getString(_kOwned));
    final rawGarden = Garden.decode(_prefs.getString(_kGarden))
        .atLeast(Economy.baseGardenCols, Economy.baseGardenRows); // migrate to the bigger base (#7)
    owned = Flowers.migrateOwned(rawOwned);
    garden = Flowers.migrateGarden(rawGarden);
    if (!identical(owned, rawOwned) || !identical(garden, rawGarden)) {
      // one-time legacy-species rewrite (#v27) — persist immediately so the
      // native wallpaper/services read the migrated ids too.
      _saveWallet();
      _saveGarden();
    }
    homeGardenBackdrop = _prefs.getBool(_kHomeMode) ?? false;
    isPomodoroMode = _prefs.getBool(_kTimerMode) ?? true;
    autoBreak = _prefs.getBool(_kAutoBreak) ?? false;
    wallpaperCam = WallpaperCam.decode(_prefs.getString(_kWallpaperCam));

    // habit tracker + money manager (#v29)
    habits = Habits.decode(_prefs.getString(_kHabits));
    habitLog = HabitLog.decode(_prefs.getString(_kHabitLog));
    moods = Moods.decode(_prefs.getString(_kMoods));
    money = MoneyBook.decode(_prefs.getString(_kMoney));
    final (fr, fat) = Fx.decode(_prefs.getString(_kFx));
    fxRates = fr;
    fxFetchedAt = fat;
    mainCurrency = _prefs.getString(_kMainCur) ?? 'USD';
    dailyRateMinor = _prefs.getInt(_kDailyRate) ?? 0;
    _moneyRewardDay = _prefs.getInt(_kMoneyRewardDay) ?? (epochDayOf(DateTime.now()) - 1);
    customCategories = (_prefs.getString(_kCustomCats) ?? '')
        .split('\n')
        .where((s) => s.trim().isNotEmpty)
        .toList();

    _seedOnce();
    _accrueMoneyReward();
    engine = _buildEngine();
    notifyListeners();
    unawaited(refreshFx()); // best-effort; updates silently when it lands
  }

  /// Award +1 coin per completed day (yesterday-and-earlier) that stayed under
  /// the daily rate (#v29). Idempotent via the [_kMoneyRewardDay] cursor.
  void _accrueMoneyReward() {
    final today = epochDayOf(DateTime.now());
    final (earned, cursor) = MoneyReward.accrue(
      txs: money,
      rateMinor: dailyRateMinor,
      lastDoneDay: _moneyRewardDay,
      today: today,
      rates: fxRates,
      main: mainCurrency,
    );
    if (cursor != _moneyRewardDay) {
      _moneyRewardDay = cursor;
      _prefs.setInt(_kMoneyRewardDay, cursor);
    }
    if (earned > 0) {
      coins += earned;
      _saveWallet();
    }
  }

  // Set only by the separately-published "Test Pixel Pomo" APK (a different
  // applicationId, installable side by side with the real app) via
  // `flutter build apk --dart-define=TEST_BUILD=true` — a *release* build
  // that still wants the debug-only demo seed, so it can be checked visually
  // on a real device instead of only via `flutter run`/`flutter test` (#v31.12).
  static const _kTestBuild = bool.fromEnvironment('TEST_BUILD');

  void _seedOnce() {
    if (_prefs.getBool(_kSeeded) ?? false) return;
    // kDebugMode (incl. `flutter test`, which also runs with asserts on) gets
    // a full pretend history for dev/demo use; a real release build gets a
    // clean slate — see Economy.firstLaunchSeed (#v31.11).
    final (seedRecords, seedCoins, seedLabels) =
        Economy.firstLaunchSeed(kDebugMode || _kTestBuild, DateTime.now());
    records.addAll(seedRecords);
    coins += seedCoins;
    for (final l in seedLabels) {
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
  void _saveDeleted() => _prefs.setString(_kDeleted, StatsCodec.encode(deletedRecords));

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

  // ---- habit tracker (#v29) -------------------------------------------------

  /// All habits shown on the tracker: manual habits + focus-session labels as
  /// automatic habits (derived from records). Manual first, then labels not
  /// already used as a manual habit name.
  Map<String, Map<int, int>> get labelHabitCounts => LabelHabits.fromRecords(records);

  void addHabit(String name, int color) {
    final next = Habits.add(habits, name, color);
    if (identical(next, habits)) return;
    habits = next;
    _prefs.setString(_kHabits, Habits.encode(habits));
    notifyListeners();
  }

  void removeHabit(String name) {
    habits = Habits.remove(habits, name);
    habitLog.remove(name);
    _prefs.setString(_kHabits, Habits.encode(habits));
    _prefs.setString(_kHabitLog, HabitLog.encode(habitLog));
    notifyListeners();
  }

  /// Manual habit completion for today, [delta] +1/-1. Label habits are
  /// automatic (driven by sessions) and are not bumped here.
  void bumpHabit(String name, [int delta = 1]) {
    habitLog = HabitLog.bump(habitLog, name, epochDayOf(DateTime.now()), delta);
    _prefs.setString(_kHabitLog, HabitLog.encode(habitLog));
    notifyListeners();
  }

  void setMood(int mood) => setMoodOn(epochDayOf(DateTime.now()), mood);

  /// Set/overwrite the mood for any past-or-today [day] — tapping a mood
  /// heatmap cell edits history (#v30.9).
  void setMoodOn(int day, int mood) {
    if (mood < 1 || mood > 5) return;
    moods[day] = mood;
    _prefs.setString(_kMoods, Moods.encode(moods));
    notifyListeners();
  }

  int? get todayMood => moods[epochDayOf(DateTime.now())];

  // ---- money manager (#v29) -------------------------------------------------

  void addMoneyTx(int amountMinor, String currency, String category,
      bool isExpense, String note) {
    if (amountMinor <= 0) return;
    final now = DateTime.now();
    money.add(MoneyTx(epochDayOf(now), now.hour * 60 + now.minute, amountMinor,
        currency, category, isExpense, note));
    _prefs.setString(_kMoney, MoneyBook.encode(money));
    notifyListeners();
  }

  void deleteMoneyTx(MoneyTx tx) {
    money.remove(tx);
    _prefs.setString(_kMoney, MoneyBook.encode(money));
    notifyListeners();
  }

  void setMainCurrency(String cur) {
    mainCurrency = cur;
    _prefs.setString(_kMainCur, cur);
    notifyListeners();
    // switching main currency is exactly when conversion rates are needed —
    // if the cache is empty (fetch never landed) this is what let 150 PLN
    // display as "EUR 150.00" (#v30.9). TTL-gated, so it's a no-op when the
    // cache is fresh.
    unawaited(refreshFx());
  }

  void setDailyRate(int minor) {
    dailyRateMinor = minor < 0 ? 0 : minor;
    _prefs.setInt(_kDailyRate, dailyRateMinor);
    notifyListeners();
  }

  /// Adds a user-defined money category (#v30 item 10). No-op for an empty
  /// or already-known name (case-insensitive).
  void addCustomCategory(String name) {
    final n = name.trim().toUpperCase();
    if (n.isEmpty || customCategories.contains(n)) return;
    customCategories = [...customCategories, n];
    _prefs.setString(_kCustomCats, customCategories.join('\n'));
    notifyListeners();
  }

  /// Removes a user-defined category (#v30.9, long-press its chip). Existing
  /// entries keep the name — display falls back to the raw string.
  void removeCustomCategory(String name) {
    if (!customCategories.contains(name)) return;
    customCategories = [for (final c in customCategories) if (c != name) c];
    _prefs.setString(_kCustomCats, customCategories.join('\n'));
    notifyListeners();
  }

  /// Currencies offered in the picker: the fetched set if we have one, else the
  /// seed list (always includes the current main currency).
  List<String> get currencyOptions {
    final set = {...Fx.seedCurrencies, ...fxRates.keys, mainCurrency};
    final list = set.toList()..sort();
    return list;
  }

  double moneyToMain(MoneyTx t) => MoneyBook.toMain(t, fxRates, mainCurrency);

  /// Fetch USD-based rates from open.er-api.com when online + stale (>1h). Uses
  /// dart:io directly (no new dep); silent on any failure so it never blocks.
  Future<void> refreshFx({bool force = false}) async {
    if (_fxFetching) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (!force && fxRates.isNotEmpty && !Fx.needsRefresh(nowMs, fxFetchedAt)) {
      return;
    }
    _fxFetching = true;
    try {
      final rates = await fetchFxRates();
      if (rates != null && rates.isNotEmpty) {
        fxRates = rates;
        fxFetchedAt = DateTime.now().millisecondsSinceEpoch;
        _prefs.setString(_kFx, Fx.encode(fxRates, fxFetchedAt));
        _accrueMoneyReward(); // fresh rates may complete a pending under-budget day
        notifyListeners();
      }
    } catch (_) {
      // offline / transient — keep the cache, try again next time.
    } finally {
      _fxFetching = false;
    }
  }

  // ---- timer ----------------------------------------------------------------

  void start() {
    if (isPomodoroMode) {
      // rebuild (not engine.reset()) so a settings change made mid-cycle
      // finally takes effect once that cycle is actually done (#v31.15).
      if (engine.isFinished) engine = _buildEngine();
      engine.start();
      if (!engine.isRunning) {
        notifyListeners();
        return;
      }
      _deadline = DateTime.now().add(Duration(milliseconds: engine.timeLeftMillis));
    } else {
      // counts UP from "now minus whatever's already elapsed", so pausing
      // and resuming keeps accumulating instead of restarting from 0 (#v31.16)
      stopwatch.start();
      _stopwatchStartedAt = DateTime.now().subtract(Duration(milliseconds: stopwatch.elapsedMillis));
    }
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) => _onTick());
    _publishBlocker();
    notifyListeners();
  }

  void _onTick() {
    if (!isPomodoroMode) {
      stopwatch.setElapsed(DateTime.now().difference(_stopwatchStartedAt!).inMilliseconds);
      notifyListeners();
      return;
    }
    final remaining = _deadline!.difference(DateTime.now()).inMilliseconds;
    if (remaining > 0) {
      engine.setTimeLeft(remaining);
      notifyListeners();
      return;
    }
    _timer?.cancel();
    cancelTimerNotification(); // phase done in-app (the native one self-clears at its deadline too)
    engine.setTimeLeft(0);
    final finished = engine.finishPhase();
    if (finished == Mode.work) _recordWork();
    messenger?.call(finished == Mode.work ? 'workDone' : 'breakDone');
    _publishBlocker();
    switch (phaseEndAction(isFinished: engine.isFinished, autoBreak: autoBreak)) {
      case PhaseEnd.done:
        notifyListeners();
        break;
      case PhaseEnd.prompt:
        // auto-start off → ask before the NEXT phase: the break after a focus
        // session, OR the next focus session after a break (#v25 item1 — was
        // focus→break only; break→work used to auto-start unconditionally)
        awaitingBreakPrompt = true;
        notifyListeners();
        break;
      case PhaseEnd.autoStart:
        start();
        break;
    }
  }

  void setAutoBreak(bool v) {
    autoBreak = v;
    _prefs.setBool(_kAutoBreak, v);
    notifyListeners();
  }

  // ---- app blocker (#v23) ---------------------------------------------------

  // stopwatch (#v31.16) has no work/break split and never "finishes" a fixed
  // session count — it's blockable the whole time it's actually running.
  bool get blockerActive => AppBlocker.active(
        enabled: appBlockerEnabled,
        isRunning: isPomodoroMode ? engine.isRunning : stopwatch.isRunning,
        isWork: isPomodoroMode ? engine.mode == Mode.work : true,
        isFinished: isPomodoroMode ? engine.isFinished : false,
      );

  void setAppBlocker(bool on) {
    appBlockerEnabled = on;
    _prefs.setBool(_kBlocker, on);
    _publishBlocker();
    notifyListeners();
  }

  void setBlocked(String pkg, bool on) {
    on ? blockedApps.add(pkg) : blockedApps.remove(pkg);
    _prefs.setString(_kBlocked, AppBlocker.encode(blockedApps));
    _publishBlocker();
    notifyListeners();
  }

  /// The AccessibilityService runs in a SEPARATE PROCESS and reads these from
  /// SharedPreferences (native sees them under the `flutter.` prefix), so writing
  /// the prefs IS the IPC — there is no channel push for blocker state.
  void _publishBlocker() {
    final active = blockerActive;
    // wall-clock end of the running WORK session (safety so a killed app
    // can't block forever) — stopwatch has no natural end, so cap it at the
    // same 300-minute ceiling Settings' own STUDY stepper allows (#v31.16).
    final safetyMillis = isPomodoroMode ? engine.timeLeftMillis : 300 * 60 * 1000;
    final until = active ? DateTime.now().millisecondsSinceEpoch + safetyMillis : 0;
    _prefs.setBool('blocker_active', active);
    _prefs.setInt('block_until', until);
    _prefs.setString('blocker_title', t(lang, 'stayFocused'));
    _prefs.setString('blocker_button', t(lang, 'backToPomo'));
    // The AccessibilityService draws the overlay in native views and can't read
    // PixelTheme, so hand it the active palette to match our font/theme (#v23 fb).
    _prefs.setInt('blocker_bg', theme.bg);
    _prefs.setInt('blocker_ink', theme.onSurface);
    _prefs.setInt('blocker_accent', theme.accent);
    _prefs.setInt('blocker_on_accent', theme.onAccent);
    _prefs.setInt('blocker_shadow', theme.shadow);
  }

  /// Resolve the "start the break?" prompt (auto-break off path).
  void confirmBreak(bool startNow) {
    awaitingBreakPrompt = false;
    if (startNow) {
      start();
    } else {
      _publishBlocker();
      notifyListeners();
    }
  }

  void pause() {
    _timer?.cancel();
    isPomodoroMode ? engine.pause() : stopwatch.pause();
    cancelTimerNotification(); // not running → drop the countdown notification
    _publishBlocker();
    notifyListeners();
  }

  /// App backgrounded mid-session → raise the ongoing countdown notification
  /// (#v23 fb). Only while actually running; cancelled by the stop paths below.
  /// Stopwatch mode (#v31.16) skips this: the native notification is a
  /// deadline-based countdown, and stopwatch has no deadline to count down
  /// to — it stays a Flutter-only display for now.
  void onBackgrounded() {
    if (!isPomodoroMode) return;
    if (!engine.isRunning || _deadline == null) return;
    final deadline = _deadline!.millisecondsSinceEpoch;
    if (engine.mode == Mode.work) {
      // Focus: roll into the break if auto-break is on, otherwise announce it's
      // done — so the badge can't sit there ticking past zero with the old label.
      if (autoBreak) {
        showTimerNotification(deadline, currentLabel,
            nextMs: breakMin * 60 * 1000, nextTitle: t(lang, 'break'), doneTitle: t(lang, 'breakDone'));
      } else {
        showTimerNotification(deadline, currentLabel, doneTitle: t(lang, 'workDone'));
      }
    } else {
      showTimerNotification(deadline, t(lang, 'break'), doneTitle: t(lang, 'breakDone'));
    }
  }

  void reset() {
    _timer?.cancel();
    if (isPomodoroMode) {
      // cancelling a started focus session still pays out the time spent (#6)
      if (engine.mode == Mode.work && engine.timeLeftMillis < engine.workMillis) {
        final spent = Economy.elapsedFocusMinutes(workMin, engine.timeLeftMillis);
        if (spent > 0) {
          final now = DateTime.now();
          records.add(SessionRecord(epochDayOf(now), spent, currentLabel,
              minuteOfDay: now.hour * 60 + now.minute));
          _saveStats();
          _prefs.setString(_kCurrentLabel, currentLabel); // #v25 item2 hardening
          coins += Economy.coinsFor(spent);
          _saveWallet();
        }
      }
      // rebuild (not engine.reset()) so a settings change made mid-session
      // finally takes effect on this explicit cancel/restart (#v31.15).
      engine = _buildEngine();
    } else {
      // stopwatch: log the elapsed time to stats — no coins, ever (#v31.16)
      final spent = stopwatch.elapsedMillis ~/ 60000;
      if (spent > 0) {
        final now = DateTime.now();
        records.add(SessionRecord(epochDayOf(now), spent, currentLabel,
            minuteOfDay: now.hour * 60 + now.minute));
        _saveStats();
        _prefs.setString(_kCurrentLabel, currentLabel);
      }
      stopwatch.reset();
    }
    cancelTimerNotification(); // session cancelled in-app → drop the notification
    _publishBlocker();
    notifyListeners();
  }

  void switchMode() {
    _timer?.cancel();
    engine.switchMode();
    cancelTimerNotification();
    notifyListeners();
  }

  void toggleStartPause() =>
      (isPomodoroMode ? engine.isRunning : stopwatch.isRunning) ? pause() : start();

  void _recordWork() {
    final now = DateTime.now();
    records.add(SessionRecord(epochDayOf(now), workMin, currentLabel,
        minuteOfDay: now.hour * 60 + now.minute));
    _saveStats();
    // re-affirm the active label on this durable write so it can't be lost
    // between sessions (#v25 item2 hardening)
    _prefs.setString(_kCurrentLabel, currentLabel);
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
    // a pomodoro already in progress keeps running on its OLD durations
    // uninterrupted — rebuilding here would reset live progress out from
    // under the user (#v31.15 bug); the new values apply starting the next
    // fresh run instead, via start()/reset() rebuilding from current
    // workMin/breakMin/sessions rather than reusing the frozen engine.
    if (!engine.inProgress) {
      _timer?.cancel();
      engine = _buildEngine();
    }
    notifyListeners();
  }

  void selectTheme(PixelTheme t) {
    theme = t;
    _prefs.setString(_kTheme, t.id);
    _publishBlocker(); // keep the native overlay's palette in sync (#v23 fb)
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
        r.label.toUpperCase() == oldU ? r.copyWith(label: newName) : r
    ];
    _saveStats();
    _saveLabels();
    notifyListeners();
  }

  /// Reassign one past session's label (from the log-history screen, #v25 item3).
  /// [index] indexes into [records].
  void relabelRecord(int index, String newLabel) {
    if (index < 0 || index >= records.length) return;
    records[index] = records[index].copyWith(label: newLabel);
    _saveStats();
    notifyListeners();
  }

  // ---- recycle bin ------------------------------------------------------------
  // Soft-delete: a log moves out of [records] (so every existing stats
  // aggregation stops seeing it automatically) into [deletedRecords], where
  // it sits until permanently purged — one at a time or all at once (#v31.16).

  /// [index] indexes into [records].
  void removeRecord(int index) {
    if (index < 0 || index >= records.length) return;
    deletedRecords.add(records.removeAt(index));
    _saveStats();
    _saveDeleted();
    notifyListeners();
  }

  /// [index] indexes into [deletedRecords] — permanent, no further recovery.
  void purgeRecord(int index) {
    if (index < 0 || index >= deletedRecords.length) return;
    deletedRecords.removeAt(index);
    _saveDeleted();
    notifyListeners();
  }

  void cleanRecycleBin() {
    deletedRecords.clear();
    _saveDeleted();
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
    // A flower with multiple sprite variants gets a random one (e.g. "gul~2");
    // roads, fences and single-variant flowers are placed as-is (#v22).
    var toPlant = flowerId;
    if (Placeables.isFlower(flowerId)) {
      final n = Flowers.variantsFor(flowerId);
      if (n > 1) toPlant = '$flowerId~${_variantRng.nextInt(n)}';
    }
    garden = garden.plant(index, toPlant);
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

  /// Settings screen only, for now (#v31.15) — hides the work/break/session
  /// steppers in stopwatch mode. Doesn't yet change home-screen timer
  /// behaviour.
  void setPomodoroMode(bool v) {
    isPomodoroMode = v;
    _prefs.setBool(_kTimerMode, v);
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
