package com.pixelpomo.app

import android.content.Context
import android.content.SharedPreferences
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.os.CountDownTimer
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.widget.AppCompatButton
import androidx.core.content.res.ResourcesCompat
import java.time.LocalDate
import java.time.YearMonth
import java.time.format.TextStyle
import java.util.Locale

/**
 * The single screen. All timer *state* lives in [PomodoroEngine]; this class drives the
 * platform [CountDownTimer], renders engine state, and owns the user-facing extras: settings
 * (durations + **language**), themes, focus **labels** (with a per-label **color**), session
 * **stats** (with month navigation + bar/line/pie **charts**), a coin **shop** of pixel flowers,
 * and a **garden** where bought flowers are planted on an upgradable square grid. Everything is
 * persisted in [SharedPreferences] and applied programmatically so theme/locale changes are live.
 */
class MainActivity : AppCompatActivity() {

    private companion object {
        const val PREFS = "pixel_pomo_prefs"
        const val KEY_WORK = "work_min"
        const val KEY_BREAK = "break_min"
        const val KEY_SESSIONS = "sessions"
        const val KEY_THEME = "theme_id"
        const val KEY_LABELS = "labels"
        const val KEY_CURRENT_LABEL = "current_label"
        const val KEY_LABEL_COLORS = "label_colors"
        const val KEY_STATS = "stats"
        const val KEY_COINS = "coins"
        const val KEY_OWNED = "owned_flowers"
        const val KEY_GARDEN = "garden"
        const val KEY_LANG = "language"
        const val KEY_TEST_SEEDED = "test_seeded_v5"

        const val DEFAULT_WORK = 25
        const val DEFAULT_BREAK = 5
        const val DEFAULT_SESSIONS = 4

        const val WORK_MIN = 5;     const val WORK_MAX = 300;    const val WORK_STEP = 5
        const val BREAK_MIN = 1;    const val BREAK_MAX = 120;   const val BREAK_STEP = 1
        const val SESSIONS_MIN = 1; const val SESSIONS_MAX = 24; const val SESSIONS_STEP = 1

        /** Cap garden growth so tiles stay tappable on a phone. */
        const val GARDEN_MAX_SIZE = 8
    }

    private lateinit var prefs: SharedPreferences
    private var pixelTheme: PixelTheme = Themes.DEFAULT
    private var lang = LocaleManager.DEFAULT
    private var pixelFont: Typeface? = null

    private var engine = PomodoroEngine()
    private var countDownTimer: CountDownTimer? = null
    private var renderedMode: Mode? = null

    private var workMin = DEFAULT_WORK
    private var breakMin = DEFAULT_BREAK
    private var sessions = DEFAULT_SESSIONS
    private var draftWork = DEFAULT_WORK
    private var draftBreak = DEFAULT_BREAK
    private var draftSessions = DEFAULT_SESSIONS

    private var labels = Labels.SEED.toMutableList()
    private var currentLabel = Labels.DEFAULT
    private val labelColors = LinkedHashMap<String, Int>()
    private val records = mutableListOf<SessionRecord>()

    private var coins = 0
    private val owned = LinkedHashMap<String, Int>()
    private var garden = Garden()

    // Stats view state.
    private var viewYearMonth: YearMonth = YearMonth.now()
    private var chartMode = ChartView.Mode.BAR

    // Garden edit state.
    private var customizing = false

    // Views
    private lateinit var root: View
    private lateinit var modeLabel: TextView
    private lateinit var timerText: TextView
    private lateinit var progress: ProgressBar
    private lateinit var startPauseBtn: AppCompatButton
    private lateinit var resetBtn: AppCompatButton
    private lateinit var switchModeBtn: AppCompatButton
    private lateinit var sessionLabel: TextView
    private lateinit var labelBtn: AppCompatButton
    private lateinit var themeBtn: ImageView
    private lateinit var gardenBtn: ImageView
    private lateinit var statsBtn: ImageView
    private lateinit var settingsBtn: ImageView

    private lateinit var settingsPanel: View
    private lateinit var themePanel: View
    private lateinit var labelPanel: View
    private lateinit var statsPanel: View
    private lateinit var settingsTitle: TextView
    private lateinit var themeTitle: TextView
    private lateinit var saveBtn: AppCompatButton
    private lateinit var settingsCloseBtn: AppCompatButton
    private lateinit var themeCloseBtn: AppCompatButton
    private lateinit var themeListContainer: LinearLayout
    private lateinit var languageTitle: TextView
    private lateinit var languageListContainer: LinearLayout

    private lateinit var rowWork: View
    private lateinit var rowBreak: View
    private lateinit var rowSessions: View

    private lateinit var labelTitle: TextView
    private lateinit var labelHelp: TextView
    private lateinit var labelListContainer: LinearLayout
    private lateinit var labelInput: EditText
    private lateinit var addLabelBtn: AppCompatButton
    private lateinit var labelCloseBtn: AppCompatButton

    private lateinit var statsTitle: TextView
    private lateinit var statsBody: LinearLayout
    private lateinit var statToday: TextView
    private lateinit var statWeek: TextView
    private lateinit var statMonth: TextView
    private lateinit var statYear: TextView
    private lateinit var statAll: TextView
    private lateinit var statsByLabelTitle: TextView
    private lateinit var statsLabelList: LinearLayout
    private lateinit var statsCloseBtn: AppCompatButton
    private lateinit var monthPrevBtn: AppCompatButton
    private lateinit var monthNextBtn: AppCompatButton
    private lateinit var monthLabel: TextView
    private lateinit var chartBarBtn: AppCompatButton
    private lateinit var chartLineBtn: AppCompatButton
    private lateinit var chartPieBtn: AppCompatButton
    private lateinit var chart: ChartView

    private lateinit var coinBtn: View
    private lateinit var coinLabel: TextView
    private lateinit var shopPanel: View
    private lateinit var shopTitle: TextView
    private lateinit var shopHelp: TextView
    private lateinit var shopListContainer: LinearLayout
    private lateinit var shopCloseBtn: AppCompatButton

    private lateinit var gardenPanel: View
    private lateinit var gardenTitle: TextView
    private lateinit var gardenSizeLabel: TextView
    private lateinit var gardenHelp: TextView
    private lateinit var gardenUpgradeBtn: AppCompatButton
    private lateinit var gardenCustomizeBtn: AppCompatButton
    private lateinit var gardenCloseBtn: AppCompatButton
    private lateinit var gardenGrid: LinearLayout

    private val themeButtons = mutableListOf<Pair<PixelTheme, AppCompatButton>>()
    private val languageButtons = mutableListOf<Pair<String, AppCompatButton>>()
    private val labelButtons = mutableListOf<Pair<String, AppCompatButton>>()
    private val chartButtons = mutableListOf<Pair<ChartView.Mode, AppCompatButton>>()

    /** Apply the saved UI language to every resource lookup in this Activity. */
    override fun attachBaseContext(newBase: Context) {
        val saved = newBase.getSharedPreferences(PREFS, MODE_PRIVATE)
            .getString(KEY_LANG, LocaleManager.DEFAULT) ?: LocaleManager.DEFAULT
        super.attachBaseContext(LocaleManager.wrap(newBase, saved))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        loadConfig()
        pixelFont = ResourcesCompat.getFont(this, R.font.press_start_2p)

        bindViews()
        engine = buildEngine()

        // Press Start 2P has no Hangul glyphs — fall back to the system font for Korean.
        if (lang == "ko") retypeface(root)

        wireTimerControls()
        wireOverlays()
        setupSteppers()
        buildThemeButtons()
        buildLanguageButtons()
        buildChartButtons()
        refreshLabelButtons()
        labelBtn.text = currentLabel
        updateCoinLabel()

        applyTheme()
    }

    // ---- config persistence -------------------------------------------------

    private fun loadConfig() {
        workMin = prefs.getInt(KEY_WORK, DEFAULT_WORK)
        breakMin = prefs.getInt(KEY_BREAK, DEFAULT_BREAK)
        sessions = prefs.getInt(KEY_SESSIONS, DEFAULT_SESSIONS)
        pixelTheme = Themes.byId(prefs.getString(KEY_THEME, Themes.DEFAULT.id))
        lang = prefs.getString(KEY_LANG, LocaleManager.DEFAULT) ?: LocaleManager.DEFAULT
        if (!LocaleManager.isSupported(lang)) lang = LocaleManager.DEFAULT

        labels = loadLabels()
        currentLabel = prefs.getString(KEY_CURRENT_LABEL, Labels.DEFAULT) ?: Labels.DEFAULT
        if (labels.none { it.equals(currentLabel, ignoreCase = true) }) currentLabel = labels.first()

        labelColors.clear()
        labelColors.putAll(LabelColors.decode(prefs.getString(KEY_LABEL_COLORS, "")))

        records.clear()
        records.addAll(StatsCodec.decode(prefs.getString(KEY_STATS, "")))

        coins = prefs.getInt(KEY_COINS, 0)
        owned.clear()
        owned.putAll(Inventory.decode(prefs.getString(KEY_OWNED, "")))
        garden = GardenCodec.decode(prefs.getString(KEY_GARDEN, ""))

        seedTestDataOnce()
    }

    /** Once per install (v0.5.0): seed example stats + 1000 coins so the new screens have data. */
    private fun seedTestDataOnce() {
        if (prefs.getBoolean(KEY_TEST_SEEDED, false)) return
        records.addAll(TestData.records(LocalDate.now()))
        coins += TestData.SEED_COINS
        for (l in TestData.LABELS) labels = Labels.add(labels, l).toMutableList()
        prefs.edit()
            .putString(KEY_STATS, StatsCodec.encode(records))
            .putInt(KEY_COINS, coins)
            .putString(KEY_LABELS, labels.joinToString("\n"))
            .putBoolean(KEY_TEST_SEEDED, true)
            .apply()
    }

    private fun loadLabels(): MutableList<String> {
        val stored = prefs.getString(KEY_LABELS, null)
            ?.split("\n")?.map { it.trim() }?.filter { it.isNotEmpty() }?.toMutableList()
        return if (stored.isNullOrEmpty()) Labels.SEED.toMutableList() else stored
    }

    private fun saveLabels() {
        prefs.edit()
            .putString(KEY_LABELS, labels.joinToString("\n"))
            .putString(KEY_CURRENT_LABEL, currentLabel)
            .apply()
    }

    private fun saveLabelColors() {
        prefs.edit().putString(KEY_LABEL_COLORS, LabelColors.encode(labelColors)).apply()
    }

    private fun saveStats() {
        prefs.edit().putString(KEY_STATS, StatsCodec.encode(records)).apply()
    }

    private fun saveWallet() {
        prefs.edit()
            .putInt(KEY_COINS, coins)
            .putString(KEY_OWNED, Inventory.encode(owned))
            .apply()
    }

    private fun saveGarden() {
        prefs.edit().putString(KEY_GARDEN, GardenCodec.encode(garden)).apply()
    }

    private fun updateCoinLabel() { coinLabel.text = coins.toString() }

    private fun buildEngine() = PomodoroEngine(
        workMillis = workMin * 60_000L,
        breakMillis = breakMin * 60_000L,
        totalSessions = sessions
    )

    /** The active pixel font, or the system font for Korean (which the pixel font can't render). */
    private fun font(): Typeface? = if (lang == "ko") Typeface.DEFAULT else pixelFont

    private fun localeForLang(): Locale = Locale(lang)

    private fun labelColorOf(label: String): Int = LabelColors.colorFor(label, labelColors)

    /** Replace every TextView's typeface (used to swap to a glyph-complete font for Korean). */
    private fun retypeface(v: View) {
        when (v) {
            is ViewGroup -> for (i in 0 until v.childCount) retypeface(v.getChildAt(i))
            is TextView -> v.typeface = Typeface.DEFAULT
        }
    }

    // ---- view binding -------------------------------------------------------

    private fun bindViews() {
        root = findViewById(R.id.root)
        modeLabel = findViewById(R.id.modeLabel)
        timerText = findViewById(R.id.timer)
        progress = findViewById(R.id.progress)
        startPauseBtn = findViewById(R.id.startPauseBtn)
        resetBtn = findViewById(R.id.resetBtn)
        switchModeBtn = findViewById(R.id.switchModeBtn)
        sessionLabel = findViewById(R.id.sessionLabel)
        labelBtn = findViewById(R.id.labelBtn)
        themeBtn = findViewById(R.id.themeBtn)
        gardenBtn = findViewById(R.id.gardenBtn)
        statsBtn = findViewById(R.id.statsBtn)
        settingsBtn = findViewById(R.id.settingsBtn)

        settingsPanel = findViewById(R.id.settingsPanel)
        themePanel = findViewById(R.id.themePanel)
        labelPanel = findViewById(R.id.labelPanel)
        statsPanel = findViewById(R.id.statsPanel)
        settingsTitle = findViewById(R.id.settingsTitle)
        themeTitle = findViewById(R.id.themeTitle)
        saveBtn = findViewById(R.id.saveBtn)
        settingsCloseBtn = findViewById(R.id.settingsCloseBtn)
        themeCloseBtn = findViewById(R.id.themeCloseBtn)
        themeListContainer = findViewById(R.id.themeList)
        languageTitle = findViewById(R.id.languageTitle)
        languageListContainer = findViewById(R.id.languageList)

        rowWork = findViewById(R.id.rowWork)
        rowBreak = findViewById(R.id.rowBreak)
        rowSessions = findViewById(R.id.rowSessions)

        labelTitle = findViewById(R.id.labelTitle)
        labelHelp = findViewById(R.id.labelHelp)
        labelListContainer = findViewById(R.id.labelList)
        labelInput = findViewById(R.id.labelInput)
        addLabelBtn = findViewById(R.id.addLabelBtn)
        labelCloseBtn = findViewById(R.id.labelCloseBtn)

        statsTitle = findViewById(R.id.statsTitle)
        statsBody = findViewById(R.id.statsBody)
        statToday = findViewById(R.id.statToday)
        statWeek = findViewById(R.id.statWeek)
        statMonth = findViewById(R.id.statMonth)
        statYear = findViewById(R.id.statYear)
        statAll = findViewById(R.id.statAll)
        statsByLabelTitle = findViewById(R.id.statsByLabelTitle)
        statsLabelList = findViewById(R.id.statsLabelList)
        statsCloseBtn = findViewById(R.id.statsCloseBtn)
        monthPrevBtn = findViewById(R.id.monthPrevBtn)
        monthNextBtn = findViewById(R.id.monthNextBtn)
        monthLabel = findViewById(R.id.monthLabel)
        chartBarBtn = findViewById(R.id.chartBarBtn)
        chartLineBtn = findViewById(R.id.chartLineBtn)
        chartPieBtn = findViewById(R.id.chartPieBtn)
        chart = findViewById(R.id.chart)

        coinBtn = findViewById(R.id.coinBtn)
        coinLabel = findViewById(R.id.coinLabel)
        shopPanel = findViewById(R.id.shopPanel)
        shopTitle = findViewById(R.id.shopTitle)
        shopHelp = findViewById(R.id.shopHelp)
        shopListContainer = findViewById(R.id.shopList)
        shopCloseBtn = findViewById(R.id.shopCloseBtn)

        gardenPanel = findViewById(R.id.gardenPanel)
        gardenTitle = findViewById(R.id.gardenTitle)
        gardenSizeLabel = findViewById(R.id.gardenSizeLabel)
        gardenHelp = findViewById(R.id.gardenHelp)
        gardenUpgradeBtn = findViewById(R.id.gardenUpgradeBtn)
        gardenCustomizeBtn = findViewById(R.id.gardenCustomizeBtn)
        gardenCloseBtn = findViewById(R.id.gardenCloseBtn)
        gardenGrid = findViewById(R.id.gardenGrid)
    }

    // ---- timer controls -----------------------------------------------------

    private fun wireTimerControls() {
        startPauseBtn.setOnClickListener { if (engine.isRunning) pause() else start() }
        resetBtn.setOnClickListener { reset() }
        switchModeBtn.setOnClickListener { switchMode() }
    }

    private fun start() {
        if (engine.isFinished) {
            engine.reset()
            renderedMode = null
        }
        engine.start()
        if (!engine.isRunning) return
        countDownTimer?.cancel()
        countDownTimer = object : CountDownTimer(engine.timeLeftMillis, 1000) {
            override fun onTick(millisUntilFinished: Long) {
                engine.setTimeLeft(millisUntilFinished)
                tick()
            }

            override fun onFinish() {
                val finished = engine.finishPhase()
                if (finished == Mode.WORK) recordWorkSession()
                val msg = if (finished == Mode.WORK) R.string.work_done else R.string.break_done
                Toast.makeText(this@MainActivity, getString(msg), Toast.LENGTH_SHORT).show()
                if (!engine.isFinished) start() else render()
            }
        }.start()
        render()
    }

    private fun pause() {
        countDownTimer?.cancel()
        engine.pause()
        render()
    }

    private fun reset() {
        countDownTimer?.cancel()
        engine.reset()
        renderedMode = null
        render()
    }

    private fun switchMode() {
        countDownTimer?.cancel()
        engine.switchMode()
        render()
    }

    // ---- overlays -----------------------------------------------------------

    private fun wireOverlays() {
        settingsBtn.setOnClickListener { openSettings() }
        themeBtn.setOnClickListener { openThemes() }
        gardenBtn.setOnClickListener { openGarden() }
        statsBtn.setOnClickListener { openStats() }
        labelBtn.setOnClickListener { openLabels() }
        coinBtn.setOnClickListener { openShop() }
        saveBtn.setOnClickListener { saveSettings() }
        addLabelBtn.setOnClickListener { addLabel() }
        settingsCloseBtn.setOnClickListener { settingsPanel.visibility = View.GONE }
        themeCloseBtn.setOnClickListener { themePanel.visibility = View.GONE }
        labelCloseBtn.setOnClickListener { labelPanel.visibility = View.GONE }
        statsCloseBtn.setOnClickListener { statsPanel.visibility = View.GONE }
        shopCloseBtn.setOnClickListener { shopPanel.visibility = View.GONE }
        gardenCloseBtn.setOnClickListener { gardenPanel.visibility = View.GONE }

        monthPrevBtn.setOnClickListener { shiftMonth(-1) }
        monthNextBtn.setOnClickListener { shiftMonth(1) }
        gardenUpgradeBtn.setOnClickListener { upgradeGarden() }
        gardenCustomizeBtn.setOnClickListener { customizing = !customizing; refreshGarden() }
    }

    private fun hideAllPanels() {
        settingsPanel.visibility = View.GONE
        themePanel.visibility = View.GONE
        labelPanel.visibility = View.GONE
        statsPanel.visibility = View.GONE
        shopPanel.visibility = View.GONE
        gardenPanel.visibility = View.GONE
    }

    private fun openSettings() {
        draftWork = workMin; draftBreak = breakMin; draftSessions = sessions
        refreshStepperValues()
        hideAllPanels()
        settingsPanel.visibility = View.VISIBLE
    }

    private fun openThemes() { hideAllPanels(); themePanel.visibility = View.VISIBLE }

    private fun openLabels() {
        labelInput.setText("")
        refreshLabelButtons()
        hideAllPanels()
        labelPanel.visibility = View.VISIBLE
    }

    private fun openStats() {
        viewYearMonth = YearMonth.now()
        refreshStats()
        hideAllPanels()
        statsPanel.visibility = View.VISIBLE
    }

    private fun openShop() {
        refreshShop()
        hideAllPanels()
        shopPanel.visibility = View.VISIBLE
    }

    private fun openGarden() {
        customizing = false
        refreshGarden()
        hideAllPanels()
        gardenPanel.visibility = View.VISIBLE
    }

    private fun saveSettings() {
        workMin = draftWork; breakMin = draftBreak; sessions = draftSessions
        prefs.edit()
            .putInt(KEY_WORK, workMin)
            .putInt(KEY_BREAK, breakMin)
            .putInt(KEY_SESSIONS, sessions)
            .apply()
        countDownTimer?.cancel()
        engine = buildEngine()
        renderedMode = null
        render()
        settingsPanel.visibility = View.GONE
        Toast.makeText(this, getString(R.string.settings_saved), Toast.LENGTH_SHORT).show()
    }

    override fun onBackPressed() {
        val anyOpen = settingsPanel.visibility == View.VISIBLE ||
            themePanel.visibility == View.VISIBLE ||
            labelPanel.visibility == View.VISIBLE ||
            statsPanel.visibility == View.VISIBLE ||
            shopPanel.visibility == View.VISIBLE ||
            gardenPanel.visibility == View.VISIBLE
        if (anyOpen) hideAllPanels() else super.onBackPressed()
    }

    // ---- steppers -----------------------------------------------------------

    private fun setupSteppers() {
        bindStepper(rowWork, R.string.label_study, WORK_MIN, WORK_MAX, WORK_STEP,
            get = { draftWork }, set = { draftWork = it })
        bindStepper(rowBreak, R.string.label_break, BREAK_MIN, BREAK_MAX, BREAK_STEP,
            get = { draftBreak }, set = { draftBreak = it })
        bindStepper(rowSessions, R.string.label_sessions, SESSIONS_MIN, SESSIONS_MAX, SESSIONS_STEP,
            get = { draftSessions }, set = { draftSessions = it })
    }

    private fun bindStepper(
        row: View, labelRes: Int, min: Int, max: Int, step: Int,
        get: () -> Int, set: (Int) -> Unit
    ) {
        row.findViewById<TextView>(R.id.stepperLabel).setText(labelRes)
        val value = row.findViewById<TextView>(R.id.stepperValue)
        value.text = get().toString()
        row.findViewById<View>(R.id.stepperMinus).setOnClickListener {
            val v = (get() - step).coerceAtLeast(min); set(v); value.text = v.toString()
        }
        row.findViewById<View>(R.id.stepperPlus).setOnClickListener {
            val v = (get() + step).coerceAtMost(max); set(v); value.text = v.toString()
        }
    }

    private fun refreshStepperValues() {
        rowWork.findViewById<TextView>(R.id.stepperValue).text = draftWork.toString()
        rowBreak.findViewById<TextView>(R.id.stepperValue).text = draftBreak.toString()
        rowSessions.findViewById<TextView>(R.id.stepperValue).text = draftSessions.toString()
    }

    // ---- theme + language pickers -------------------------------------------

    private fun buildThemeButtons() {
        val pad = dp(16)
        Themes.ALL.forEach { theme ->
            val btn = listButton(pad).apply { setOnClickListener { selectTheme(theme) } }
            themeListContainer.addView(btn)
            themeButtons += theme to btn
        }
    }

    private fun buildLanguageButtons() {
        val pad = dp(14)
        LocaleManager.LANGUAGES.forEach { (tag, name) ->
            val btn = listButton(pad).apply {
                // Autonyms (한국어 etc.) need a glyph-complete font regardless of current UI lang.
                typeface = Typeface.DEFAULT
                text = name
                setOnClickListener { selectLanguage(tag) }
            }
            languageListContainer.addView(btn)
            languageButtons += tag to btn
        }
    }

    /** A full-width pixel list button used by the theme/language pickers. */
    private fun listButton(pad: Int) = AppCompatButton(this).apply {
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { bottomMargin = dp(12) }
        typeface = font()
        isAllCaps = false
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
        setPadding(pad, pad, pad, pad)
        stateListAnimator = null
    }

    private fun selectTheme(theme: PixelTheme) {
        pixelTheme = theme
        prefs.edit().putString(KEY_THEME, theme.id).apply()
        applyTheme()
    }

    private fun selectLanguage(tag: String) {
        if (tag == lang) return
        prefs.edit().putString(KEY_LANG, tag).apply()
        recreate()   // re-inflate with the new locale (and font fallback)
    }

    // ---- label picker -------------------------------------------------------

    /** Rebuilds the label list: each row is [color swatch | name | 🗑]. */
    private fun refreshLabelButtons() {
        labelListContainer.removeAllViews()
        labelButtons.clear()
        val pad = dp(14)
        labels.forEach { label ->
            val row = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
                ).apply { bottomMargin = dp(12) }
            }
            val swatch = swatchView(labelColorOf(label), 24).apply {
                setOnClickListener { openColorPicker(label) }
            }
            val name = AppCompatButton(this).apply {
                layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
                typeface = font()
                isAllCaps = false
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                setPadding(pad, pad, pad, pad)
                stateListAnimator = null
                setOnClickListener { selectLabel(label) }
            }
            val bin = TextView(this).apply {
                text = getString(R.string.bin_emoji)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
                setPadding(dp(14), dp(12), dp(6), dp(12))
                setTextColor(pixelTheme.onSurfaceDim)
                isClickable = true; isFocusable = true
                contentDescription = getString(R.string.label_remove_title)
                setOnClickListener { confirmDeleteLabel(label) }
            }
            row.addView(swatch); row.addView(name); row.addView(bin)
            labelListContainer.addView(row)
            labelButtons += label to name
        }
        styleLabelButtons()
    }

    private fun styleLabelButtons() {
        labelButtons.forEach { (label, btn) ->
            if (label.equals(currentLabel, ignoreCase = true)) {
                stylePrimary(btn); btn.text = "> $label"
            } else {
                styleSecondary(btn); btn.text = label
            }
        }
    }

    private fun selectLabel(label: String) {
        currentLabel = label
        saveLabels()
        labelBtn.text = currentLabel
        styleLabelButtons()
    }

    private fun addLabel() {
        val updated = Labels.add(labels, labelInput.text?.toString().orEmpty())
        if (updated.size == labels.size) {
            Toast.makeText(this, getString(R.string.label_invalid), Toast.LENGTH_SHORT).show()
            return
        }
        labels = updated.toMutableList()
        labelInput.setText("")
        saveLabels()
        refreshLabelButtons()
    }

    private fun confirmDeleteLabel(label: String) {
        AlertDialog.Builder(this)
            .setTitle(getString(R.string.label_remove_title))
            .setMessage(getString(R.string.label_remove_msg, label))
            .setPositiveButton(getString(R.string.yes)) { _, _ -> deleteLabel(label) }
            .setNegativeButton(getString(R.string.no), null)
            .show()
    }

    private fun deleteLabel(label: String) {
        val updated = Labels.remove(labels, label)
        if (updated.size == labels.size) return
        labels = updated.toMutableList()
        if (labels.none { it.equals(currentLabel, ignoreCase = true) }) {
            currentLabel = labels.first()
            labelBtn.text = currentLabel
        }
        saveLabels()
        refreshLabelButtons()
        Toast.makeText(this, getString(R.string.label_deleted), Toast.LENGTH_SHORT).show()
    }

    /** Palette dialog: tap a swatch to set this label's color (used everywhere incl. charts). */
    private fun openColorPicker(label: String) {
        val perRow = 5
        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(16), dp(20), dp(8))
        }
        val dialog = AlertDialog.Builder(this)
            .setTitle(getString(R.string.label_pick_color))
            .setView(container)
            .create()
        var row: LinearLayout? = null
        LabelColors.PALETTE.forEachIndexed { i, color ->
            if (i % perRow == 0) {
                row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
                container.addView(row)
            }
            val sw = swatchView(color, 40).apply {
                (layoutParams as LinearLayout.LayoutParams).apply { rightMargin = dp(8); bottomMargin = dp(8) }
                setOnClickListener {
                    labelColors[label.uppercase()] = color
                    saveLabelColors()
                    dialog.dismiss()
                    refreshLabelButtons()
                }
            }
            row?.addView(sw)
        }
        dialog.show()
    }

    // ---- stats --------------------------------------------------------------

    private fun recordWorkSession() {
        records.add(SessionRecord(LocalDate.now().toEpochDay(), workMin, currentLabel))
        saveStats()
        coins += Economy.coinsFor(workMin)
        saveWallet()
        updateCoinLabel()
    }

    private fun buildChartButtons() {
        chartButtons.clear()
        chartButtons += ChartView.Mode.BAR to chartBarBtn
        chartButtons += ChartView.Mode.LINE to chartLineBtn
        chartButtons += ChartView.Mode.PIE to chartPieBtn
        chartBarBtn.setOnClickListener { chartMode = ChartView.Mode.BAR; refreshStats() }
        chartLineBtn.setOnClickListener { chartMode = ChartView.Mode.LINE; refreshStats() }
        chartPieBtn.setOnClickListener { chartMode = ChartView.Mode.PIE; refreshStats() }
    }

    private fun shiftMonth(delta: Int) {
        val candidate = viewYearMonth.plusMonths(delta.toLong())
        if (candidate.isAfter(YearMonth.now())) return   // don't browse the future
        viewYearMonth = candidate
        refreshStats()
    }

    private fun formatMonth(ym: YearMonth): String {
        val locale = localeForLang()
        val name = ym.month.getDisplayName(TextStyle.FULL, locale)
        return "${name.uppercase(locale)} ${ym.year}"
    }

    /** Recomputes the headline totals, the month chart, and the per-month per-label breakdown. */
    private fun refreshStats() {
        val today = LocalDate.now()
        val totals = StatsAggregator.aggregate(records, today)
        statToday.text = StatsAggregator.formatMinutes(totals.today)
        statWeek.text = StatsAggregator.formatMinutes(totals.week)
        statMonth.text = StatsAggregator.formatMinutes(totals.month)
        statYear.text = StatsAggregator.formatMinutes(totals.year)
        statAll.text = StatsAggregator.formatMinutes(totals.all)

        monthLabel.text = formatMonth(viewYearMonth)
        monthNextBtn.alpha = if (viewYearMonth.isBefore(YearMonth.now())) 1f else 0.35f
        statsByLabelTitle.text = getString(R.string.by_label_month, formatMonth(viewYearMonth))

        val byLabel = StatsAggregator.byLabelInMonth(records, viewYearMonth)
        val series = StatsAggregator.dailySeries(records, viewYearMonth)
        chart.axisColor = pixelTheme.onSurfaceDim
        chart.textColor = pixelTheme.onSurface
        chart.lineColor = pixelTheme.accent
        chart.pixelTypeface = font()
        chart.setData(byLabel.map { ChartView.Entry(it.first, it.second, labelColorOf(it.first)) },
            series, chartMode)
        styleChartButtons()

        statsLabelList.removeAllViews()
        if (byLabel.isEmpty()) {
            statsLabelList.addView(TextView(this).apply {
                text = getString(R.string.no_stats)
                typeface = font()
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 9f)
                setLineSpacing(dp(4).toFloat(), 1f)
                setTextColor(pixelTheme.onSurfaceDim)
            })
        } else {
            byLabel.forEach { (label, minutes) ->
                val row = LinearLayout(this).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                    layoutParams = LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
                    )
                    setPadding(0, dp(6), 0, dp(6))
                }
                row.addView(swatchView(labelColorOf(label), 16))
                row.addView(TextView(this).apply {
                    text = label
                    typeface = font()
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
                    setPadding(dp(10), 0, 0, 0)
                    setTextColor(pixelTheme.onSurface)
                })
                row.addView(View(this).apply {
                    layoutParams = LinearLayout.LayoutParams(0, dp(1), 1f)
                })
                row.addView(TextView(this).apply {
                    text = StatsAggregator.formatMinutes(minutes)
                    typeface = font()
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
                    setTextColor(pixelTheme.onSurfaceDim)
                })
                statsLabelList.addView(row)
            }
        }
    }

    private fun styleChartButtons() {
        chartButtons.forEach { (mode, btn) ->
            if (mode == chartMode) stylePrimary(btn) else styleSecondary(btn)
        }
    }

    // ---- shop ---------------------------------------------------------------

    private fun refreshShop() {
        shopListContainer.removeAllViews()
        val cell = dp(4)
        Flowers.ALL.forEach { flower ->
            val row = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
                ).apply { bottomMargin = dp(14) }
            }
            row.addView(ImageView(this).apply {
                layoutParams = LinearLayout.LayoutParams(dp(40), dp(40))
                setImageDrawable(PixelArt.flower(resources, flower, cell))
            })
            val info = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
                setPadding(dp(12), 0, dp(8), 0)
            }
            info.addView(TextView(this).apply {
                text = flower.nameIn(lang)
                typeface = font()
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                setTextColor(pixelTheme.onSurface)
            })
            info.addView(TextView(this).apply {
                text = getString(R.string.owned_count, owned[flower.id] ?: 0)
                typeface = font()
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 8f)
                setPadding(0, dp(6), 0, 0)
                setTextColor(pixelTheme.onSurfaceDim)
            })
            row.addView(info)
            row.addView(AppCompatButton(this).apply {
                typeface = font()
                isAllCaps = false
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
                setPadding(dp(12), dp(12), dp(12), dp(12))
                stateListAnimator = null
                text = "${getString(R.string.buy)} ${Economy.FLOWER_COST}"
                background = PixelStyle.button(resources, pixelTheme.accent, pixelTheme.onSurface, pixelTheme.shadow)
                setTextColor(pixelTheme.onAccent)
                alpha = if (coins >= Economy.FLOWER_COST) 1f else 0.45f
                setOnClickListener { buyFlower(flower) }
            })
            shopListContainer.addView(row)
        }
    }

    private fun buyFlower(flower: Flower) {
        if (coins < Economy.FLOWER_COST) {
            Toast.makeText(this, getString(R.string.not_enough_coins), Toast.LENGTH_SHORT).show()
            return
        }
        coins -= Economy.FLOWER_COST
        owned[flower.id] = (owned[flower.id] ?: 0) + 1
        saveWallet()
        updateCoinLabel()
        refreshShop()
        Toast.makeText(this, getString(R.string.purchased), Toast.LENGTH_SHORT).show()
    }

    // ---- garden -------------------------------------------------------------

    private fun refreshGarden() {
        gardenSizeLabel.text = getString(R.string.garden_size, garden.size, garden.size)
        if (garden.size >= GARDEN_MAX_SIZE) {
            gardenUpgradeBtn.text = getString(R.string.garden_max)
            gardenUpgradeBtn.alpha = 0.45f
        } else {
            val cost = Economy.upgradeCost(garden.size)
            gardenUpgradeBtn.text = getString(R.string.garden_upgrade, cost)
            gardenUpgradeBtn.alpha = if (coins >= cost) 1f else 0.45f
        }
        gardenCustomizeBtn.text = getString(if (customizing) R.string.garden_done else R.string.garden_customize)
        buildGardenGrid()
    }

    private fun buildGardenGrid() {
        gardenGrid.removeAllViews()
        val gap = dp(4)
        val avail = resources.displayMetrics.widthPixels - dp(56)   // screen minus panel padding
        val tile = ((avail - gap * (garden.size - 1)) / garden.size).coerceIn(dp(28), dp(72))
        val cell = (tile / 8).coerceAtLeast(1)
        for (r in 0 until garden.size) {
            val rowView = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
            for (c in 0 until garden.size) {
                val index = r * garden.size + c
                val tileView = FrameLayout(this).apply {
                    layoutParams = LinearLayout.LayoutParams(tile, tile).apply {
                        if (c < garden.size - 1) rightMargin = gap
                        bottomMargin = gap
                    }
                    background = tileBackground()
                    isClickable = true
                    setOnClickListener { onTileTap(index) }
                }
                garden.flowerAt(index)?.let { id ->
                    Flowers.byId(id)?.let { flower ->
                        tileView.addView(ImageView(this).apply {
                            layoutParams = FrameLayout.LayoutParams(cell * 8, cell * 8, Gravity.CENTER)
                            setImageDrawable(PixelArt.flower(resources, flower, cell))
                        })
                    }
                }
                rowView.addView(tileView)
            }
            gardenGrid.addView(rowView)
        }
    }

    /** A garden tile: a soft "soil" fill with a hard border so the grid reads as a map. */
    private fun tileBackground() = GradientDrawable().apply {
        shape = GradientDrawable.RECTANGLE
        setColor(pixelTheme.panel)
        setStroke(dp(2), pixelTheme.onSurfaceDim)
    }

    private fun onTileTap(index: Int) {
        if (!customizing) return
        val current = garden.flowerAt(index)
        val plantable = Flowers.ALL.filter { (owned[it.id] ?: 0) - garden.countPlanted(it.id) > 0 }
        if (current == null && plantable.isEmpty()) {
            val msg = if (owned.isEmpty()) R.string.garden_need_flowers else R.string.garden_none_left
            Toast.makeText(this, getString(msg), Toast.LENGTH_SHORT).show()
            return
        }
        val options = ArrayList<String>()
        val actions = ArrayList<() -> Unit>()
        if (current != null) {
            options += getString(R.string.garden_clear_tile)
            actions += { garden = garden.clear(index) }
        }
        plantable.forEach { flower ->
            val left = (owned[flower.id] ?: 0) - garden.countPlanted(flower.id)
            options += "${flower.nameIn(lang)}  ×$left"
            actions += { garden = garden.plant(index, flower.id) }
        }
        AlertDialog.Builder(this)
            .setTitle(getString(if (current == null) R.string.garden_pick else R.string.garden_title))
            .setItems(options.toTypedArray()) { _, which ->
                actions[which].invoke()
                saveGarden()
                refreshGarden()
            }
            .show()
    }

    private fun upgradeGarden() {
        if (garden.size >= GARDEN_MAX_SIZE) return
        val cost = Economy.upgradeCost(garden.size)
        if (coins < cost) {
            Toast.makeText(this, getString(R.string.not_enough_coins), Toast.LENGTH_SHORT).show()
            return
        }
        coins -= cost
        garden = garden.grow()
        saveWallet(); saveGarden(); updateCoinLabel(); refreshGarden()
        Toast.makeText(this, getString(R.string.garden_upgraded), Toast.LENGTH_SHORT).show()
    }

    // ---- theming ------------------------------------------------------------

    private fun applyTheme() {
        root.setBackgroundColor(pixelTheme.bg)
        settingsPanel.setBackgroundColor(pixelTheme.bg)
        themePanel.setBackgroundColor(pixelTheme.bg)
        labelPanel.setBackgroundColor(pixelTheme.bg)
        statsPanel.setBackgroundColor(pixelTheme.bg)
        shopPanel.setBackgroundColor(pixelTheme.bg)
        gardenPanel.setBackgroundColor(pixelTheme.bg)

        coinLabel.setTextColor(pixelTheme.onSurface)
        shopTitle.setTextColor(pixelTheme.onSurface)
        shopHelp.setTextColor(pixelTheme.onSurfaceDim)

        timerText.setTextColor(pixelTheme.onSurface)
        sessionLabel.setTextColor(pixelTheme.onSurfaceDim)
        switchModeBtn.setTextColor(pixelTheme.onSurfaceDim)
        settingsTitle.setTextColor(pixelTheme.onSurface)
        themeTitle.setTextColor(pixelTheme.onSurface)
        labelTitle.setTextColor(pixelTheme.onSurface)
        labelHelp.setTextColor(pixelTheme.onSurfaceDim)
        statsTitle.setTextColor(pixelTheme.onSurface)
        statsByLabelTitle.setTextColor(pixelTheme.onSurfaceDim)
        languageTitle.setTextColor(pixelTheme.onSurfaceDim)
        monthLabel.setTextColor(pixelTheme.onSurface)
        gardenTitle.setTextColor(pixelTheme.onSurface)
        gardenHelp.setTextColor(pixelTheme.onSurfaceDim)
        gardenSizeLabel.setTextColor(pixelTheme.onSurface)

        themeBtn.setColorFilter(pixelTheme.onSurface)
        gardenBtn.setColorFilter(pixelTheme.onSurface)
        statsBtn.setColorFilter(pixelTheme.onSurface)
        settingsBtn.setColorFilter(pixelTheme.onSurface)

        stylePrimary(startPauseBtn)
        stylePrimary(saveBtn)
        stylePrimary(addLabelBtn)
        styleSecondary(resetBtn)
        styleSecondary(labelBtn)
        styleSecondary(settingsCloseBtn)
        styleSecondary(themeCloseBtn)
        styleSecondary(labelCloseBtn)
        styleSecondary(statsCloseBtn)
        styleSecondary(shopCloseBtn)
        styleSecondary(gardenCloseBtn)
        styleSecondary(monthPrevBtn)
        styleSecondary(monthNextBtn)
        stylePrimary(gardenUpgradeBtn)
        stylePrimary(gardenCustomizeBtn)

        styleStepper(rowWork)
        styleStepper(rowBreak)
        styleStepper(rowSessions)

        styleThemeButtons()
        styleLanguageButtons()
        styleLabelButtons()
        styleChartButtons()
        styleStatsView()

        labelInput.setBackgroundColor(pixelTheme.panel)
        labelInput.setTextColor(pixelTheme.onSurface)
        labelInput.setHintTextColor(pixelTheme.onSurfaceDim)

        renderedMode = null
        render()
    }

    private fun styleStatsView() {
        for (i in 0 until statsBody.childCount) {
            val row = statsBody.getChildAt(i) as? ViewGroup ?: continue
            (row.getChildAt(0) as? TextView)?.setTextColor(pixelTheme.onSurfaceDim)
            (row.getChildAt(row.childCount - 1) as? TextView)?.setTextColor(pixelTheme.onSurface)
        }
    }

    private fun stylePrimary(btn: AppCompatButton) {
        btn.background = PixelStyle.button(resources, pixelTheme.accent, pixelTheme.onSurface, pixelTheme.shadow)
        btn.setTextColor(pixelTheme.onAccent)
    }

    private fun styleSecondary(btn: AppCompatButton) {
        btn.background = PixelStyle.button(resources, pixelTheme.panel, pixelTheme.onSurfaceDim, pixelTheme.shadow)
        btn.setTextColor(pixelTheme.onSurface)
    }

    private fun styleStepper(row: View) {
        row.findViewById<TextView>(R.id.stepperLabel).setTextColor(pixelTheme.onSurfaceDim)
        row.findViewById<TextView>(R.id.stepperValue).setTextColor(pixelTheme.onSurface)
        styleSecondary(row.findViewById(R.id.stepperMinus))
        styleSecondary(row.findViewById(R.id.stepperPlus))
    }

    private fun styleThemeButtons() {
        themeButtons.forEach { (theme, btn) ->
            if (theme.id == pixelTheme.id) { stylePrimary(btn); btn.text = "> ${theme.displayName}" }
            else { styleSecondary(btn); btn.text = theme.displayName }
        }
    }

    private fun styleLanguageButtons() {
        languageButtons.forEach { (tag, btn) ->
            val name = LocaleManager.autonym(tag)
            if (tag == lang) { stylePrimary(btn); btn.text = "> $name" }
            else { styleSecondary(btn); btn.text = name }
        }
    }

    // ---- shared little builders ---------------------------------------------

    /** A solid color square with a hard border, used for label swatches + the palette dialog. */
    private fun swatchView(color: Int, sizeDp: Int): View = View(this).apply {
        layoutParams = LinearLayout.LayoutParams(dp(sizeDp), dp(sizeDp))
        background = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            setColor(color)
            setStroke(dp(2), pixelTheme.onSurfaceDim)
        }
    }

    // ---- rendering ----------------------------------------------------------

    private fun render() {
        if (engine.isFinished) {
            modeLabel.text = getString(R.string.all_done)
            modeLabel.setTextColor(pixelTheme.accent)
        } else {
            modeLabel.text = getString(if (engine.mode == Mode.WORK) R.string.work else R.string.break_label)
            modeLabel.setTextColor(pixelTheme.phaseColor(engine.mode))
        }
        if (engine.mode != renderedMode) {
            refreshProgressDrawable()
            renderedMode = engine.mode
        }
        sessionLabel.text = getString(R.string.session, engine.session, engine.totalSessions)
        startPauseBtn.text = getString(if (engine.isRunning) R.string.pause else R.string.start)
        tick()
    }

    private fun tick() {
        timerText.text = engine.formattedTime()
        progress.progress = engine.progressPercent()
    }

    private fun refreshProgressDrawable() {
        val fill = if (engine.isFinished) pixelTheme.accent else pixelTheme.phaseColor(engine.mode)
        progress.progressDrawable =
            PixelStyle.progress(resources, pixelTheme.panel, pixelTheme.onSurfaceDim, fill)
        progress.progress = engine.progressPercent()
    }

    private fun dp(value: Int): Int = TypedValue.applyDimension(
        TypedValue.COMPLEX_UNIT_DIP, value.toFloat(), resources.displayMetrics
    ).toInt()

    override fun onDestroy() {
        super.onDestroy()
        countDownTimer?.cancel()
    }
}
