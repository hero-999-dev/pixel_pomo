package com.pixelpomo.app

import android.content.SharedPreferences
import android.os.Bundle
import android.os.CountDownTimer
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
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

/**
 * The single screen. All timer *state* lives in [PomodoroEngine]; this class drives the
 * platform [CountDownTimer], renders engine state, and owns the user-facing extras:
 * a **settings** overlay (study / break minutes + session count) and a **theme** overlay
 * (six pixel themes mirroring the ClaWus widget). Durations, session count and theme are
 * persisted in [SharedPreferences] and applied across all views programmatically so a
 * theme switch takes effect instantly.
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
        const val KEY_STATS = "stats"
        const val KEY_COINS = "coins"
        const val KEY_OWNED = "owned_flowers"

        const val DEFAULT_WORK = 25
        const val DEFAULT_BREAK = 5
        const val DEFAULT_SESSIONS = 4

        // v3: raised the ceilings (study 300, break 120, sessions 24).
        const val WORK_MIN = 5;     const val WORK_MAX = 300;    const val WORK_STEP = 5
        const val BREAK_MIN = 1;    const val BREAK_MAX = 120;   const val BREAK_STEP = 1
        const val SESSIONS_MIN = 1; const val SESSIONS_MAX = 24; const val SESSIONS_STEP = 1
    }

    private lateinit var prefs: SharedPreferences
    private var pixelTheme: PixelTheme = Themes.DEFAULT

    private var engine = PomodoroEngine()
    private var countDownTimer: CountDownTimer? = null
    private var renderedMode: Mode? = null

    // Config currently applied to the engine.
    private var workMin = DEFAULT_WORK
    private var breakMin = DEFAULT_BREAK
    private var sessions = DEFAULT_SESSIONS

    // Draft values being edited in the settings panel (committed on SAVE).
    private var draftWork = DEFAULT_WORK
    private var draftBreak = DEFAULT_BREAK
    private var draftSessions = DEFAULT_SESSIONS

    // Focus labels (the subject tagged onto each completed WORK block) + recorded sessions.
    private var labels = Labels.SEED.toMutableList()
    private var currentLabel = Labels.DEFAULT
    private val records = mutableListOf<SessionRecord>()

    // Coin wallet + owned flowers (flowerId -> count) for the shop/garden.
    private var coins = 0
    private val owned = LinkedHashMap<String, Int>()

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

    private lateinit var rowWork: View
    private lateinit var rowBreak: View
    private lateinit var rowSessions: View

    // Label overlay
    private lateinit var labelTitle: TextView
    private lateinit var labelHelp: TextView
    private lateinit var labelListContainer: LinearLayout
    private lateinit var labelInput: EditText
    private lateinit var addLabelBtn: AppCompatButton
    private lateinit var labelCloseBtn: AppCompatButton

    // Stats overlay
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

    // Coins + shop
    private lateinit var coinBtn: View
    private lateinit var coinLabel: TextView
    private lateinit var shopPanel: View
    private lateinit var shopTitle: TextView
    private lateinit var shopHelp: TextView
    private lateinit var shopListContainer: LinearLayout
    private lateinit var shopCloseBtn: AppCompatButton

    private val themeButtons = mutableListOf<Pair<PixelTheme, AppCompatButton>>()
    private val labelButtons = mutableListOf<Pair<String, AppCompatButton>>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        loadConfig()

        bindViews()
        engine = buildEngine()

        wireTimerControls()
        wireOverlays()
        setupSteppers()
        buildThemeButtons()
        refreshLabelButtons()
        labelBtn.text = currentLabel
        updateCoinLabel()

        applyTheme()   // applies colors, styles buttons, and renders
    }

    // ---- config persistence -------------------------------------------------

    private fun loadConfig() {
        workMin = prefs.getInt(KEY_WORK, DEFAULT_WORK)
        breakMin = prefs.getInt(KEY_BREAK, DEFAULT_BREAK)
        sessions = prefs.getInt(KEY_SESSIONS, DEFAULT_SESSIONS)
        pixelTheme = Themes.byId(prefs.getString(KEY_THEME, Themes.DEFAULT.id))

        labels = loadLabels()
        currentLabel = prefs.getString(KEY_CURRENT_LABEL, Labels.DEFAULT) ?: Labels.DEFAULT
        if (labels.none { it.equals(currentLabel, ignoreCase = true) }) currentLabel = labels.first()

        records.clear()
        records.addAll(StatsCodec.decode(prefs.getString(KEY_STATS, "")))

        coins = prefs.getInt(KEY_COINS, 0)
        owned.clear()
        owned.putAll(Inventory.decode(prefs.getString(KEY_OWNED, "")))
    }

    /** Stored labels (one per line), falling back to the seed set on first launch. */
    private fun loadLabels(): MutableList<String> {
        val stored = prefs.getString(KEY_LABELS, null)
            ?.split("\n")
            ?.map { it.trim() }
            ?.filter { it.isNotEmpty() }
            ?.toMutableList()
        return if (stored.isNullOrEmpty()) Labels.SEED.toMutableList() else stored
    }

    private fun saveLabels() {
        prefs.edit()
            .putString(KEY_LABELS, labels.joinToString("\n"))
            .putString(KEY_CURRENT_LABEL, currentLabel)
            .apply()
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

    private fun updateCoinLabel() {
        coinLabel.text = coins.toString()
    }

    private fun buildEngine() = PomodoroEngine(
        workMillis = workMin * 60_000L,
        breakMillis = breakMin * 60_000L,
        totalSessions = sessions
    )

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

        coinBtn = findViewById(R.id.coinBtn)
        coinLabel = findViewById(R.id.coinLabel)
        shopPanel = findViewById(R.id.shopPanel)
        shopTitle = findViewById(R.id.shopTitle)
        shopHelp = findViewById(R.id.shopHelp)
        shopListContainer = findViewById(R.id.shopList)
        shopCloseBtn = findViewById(R.id.shopCloseBtn)
    }

    // ---- timer controls -----------------------------------------------------

    private fun wireTimerControls() {
        startPauseBtn.setOnClickListener { if (engine.isRunning) pause() else start() }
        resetBtn.setOnClickListener { reset() }
        switchModeBtn.setOnClickListener { switchMode() }
    }

    private fun start() {
        if (engine.isFinished) {
            engine.reset()                       // START after ALL DONE restarts the run
            renderedMode = null                  // force progress fill back to the phase color
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
                if (finished == Mode.WORK) recordWorkSession()   // a focus block just completed
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
        renderedMode = null   // leaving a finished run: rebuild progress fill for the phase color
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
    }

    /** Only one overlay is visible at a time. */
    private fun hideAllPanels() {
        settingsPanel.visibility = View.GONE
        themePanel.visibility = View.GONE
        labelPanel.visibility = View.GONE
        statsPanel.visibility = View.GONE
        shopPanel.visibility = View.GONE
    }

    private fun openSettings() {
        draftWork = workMin
        draftBreak = breakMin
        draftSessions = sessions
        refreshStepperValues()
        hideAllPanels()
        settingsPanel.visibility = View.VISIBLE
    }

    private fun openThemes() {
        hideAllPanels()
        themePanel.visibility = View.VISIBLE
    }

    private fun openLabels() {
        labelInput.setText("")
        refreshLabelButtons()
        hideAllPanels()
        labelPanel.visibility = View.VISIBLE
    }

    private fun openStats() {
        refreshStats()
        hideAllPanels()
        statsPanel.visibility = View.VISIBLE
    }

    private fun openShop() {
        refreshShop()
        hideAllPanels()
        shopPanel.visibility = View.VISIBLE
    }

    private fun saveSettings() {
        workMin = draftWork
        breakMin = draftBreak
        sessions = draftSessions
        prefs.edit()
            .putInt(KEY_WORK, workMin)
            .putInt(KEY_BREAK, breakMin)
            .putInt(KEY_SESSIONS, sessions)
            .apply()

        countDownTimer?.cancel()
        engine = buildEngine()   // fresh run with the new durations / session count
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
            shopPanel.visibility == View.VISIBLE
        if (anyOpen) hideAllPanels() else super.onBackPressed()
    }

    // ---- steppers -----------------------------------------------------------

    private fun setupSteppers() {
        bindStepper(
            rowWork, R.string.label_study, WORK_MIN, WORK_MAX, WORK_STEP,
            get = { draftWork }, set = { draftWork = it }
        )
        bindStepper(
            rowBreak, R.string.label_break, BREAK_MIN, BREAK_MAX, BREAK_STEP,
            get = { draftBreak }, set = { draftBreak = it }
        )
        bindStepper(
            rowSessions, R.string.label_sessions, SESSIONS_MIN, SESSIONS_MAX, SESSIONS_STEP,
            get = { draftSessions }, set = { draftSessions = it }
        )
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

    // ---- theme picker -------------------------------------------------------

    private fun buildThemeButtons() {
        val font = ResourcesCompat.getFont(this, R.font.press_start_2p)
        val pad = dp(16)
        Themes.ALL.forEach { theme ->
            val btn = AppCompatButton(this).apply {
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT
                ).apply { bottomMargin = dp(14) }
                typeface = font
                isAllCaps = false
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                setPadding(pad, pad, pad, pad)
                stateListAnimator = null
                setOnClickListener { selectTheme(theme) }
            }
            themeListContainer.addView(btn)
            themeButtons += theme to btn
        }
    }

    private fun selectTheme(theme: PixelTheme) {
        pixelTheme = theme
        prefs.edit().putString(KEY_THEME, theme.id).apply()
        applyTheme()   // re-themes everything live, including the open panel
    }

    // ---- label picker -------------------------------------------------------

    /** Rebuilds the label list: each row is [name button | 🗑 bin], and styles it. */
    private fun refreshLabelButtons() {
        labelListContainer.removeAllViews()
        labelButtons.clear()
        val font = ResourcesCompat.getFont(this, R.font.press_start_2p)
        val pad = dp(14)
        labels.forEach { label ->
            val row = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT
                ).apply { bottomMargin = dp(12) }
            }
            val name = AppCompatButton(this).apply {
                layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
                typeface = font
                isAllCaps = false
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                setPadding(pad, pad, pad, pad)
                stateListAnimator = null
                setOnClickListener { selectLabel(label) }
            }
            val bin = TextView(this).apply {
                text = getString(R.string.bin_emoji)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
                setPadding(dp(16), dp(12), dp(8), dp(12))
                setTextColor(pixelTheme.onSurfaceDim)
                isClickable = true
                isFocusable = true
                contentDescription = getString(R.string.label_remove_title)
                setOnClickListener { confirmDeleteLabel(label) }
            }
            row.addView(name)
            row.addView(bin)
            labelListContainer.addView(row)
            labelButtons += label to name
        }
        styleLabelButtons()
    }

    private fun styleLabelButtons() {
        labelButtons.forEach { (label, btn) ->
            if (label.equals(currentLabel, ignoreCase = true)) {
                stylePrimary(btn)
                btn.text = "> $label"
            } else {
                styleSecondary(btn)
                btn.text = label
            }
        }
    }

    /** Select a label as current but **stay on the label page** (v0.4.0). */
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
        refreshLabelButtons()   // stays on the label page
    }

    /** Ask for confirmation before deleting a label (triggered by the 🗑 button). */
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
        if (updated.size == labels.size) return   // refused to empty the list
        labels = updated.toMutableList()
        if (labels.none { it.equals(currentLabel, ignoreCase = true) }) {
            currentLabel = labels.first()
            labelBtn.text = currentLabel
        }
        saveLabels()
        refreshLabelButtons()
        Toast.makeText(this, getString(R.string.label_deleted), Toast.LENGTH_SHORT).show()
    }

    // ---- stats --------------------------------------------------------------

    /** A focus block just completed: record it for stats and award coins. */
    private fun recordWorkSession() {
        records.add(SessionRecord(LocalDate.now().toEpochDay(), workMin, currentLabel))
        saveStats()
        coins += Economy.coinsFor(workMin)
        saveWallet()
        updateCoinLabel()
    }

    /** Recomputes the totals + per-label breakdown shown in the stats overlay. */
    private fun refreshStats() {
        val totals = StatsAggregator.aggregate(records, LocalDate.now())
        statToday.text = StatsAggregator.formatMinutes(totals.today)
        statWeek.text = StatsAggregator.formatMinutes(totals.week)
        statMonth.text = StatsAggregator.formatMinutes(totals.month)
        statYear.text = StatsAggregator.formatMinutes(totals.year)
        statAll.text = StatsAggregator.formatMinutes(totals.all)

        statsLabelList.removeAllViews()
        val font = ResourcesCompat.getFont(this, R.font.press_start_2p)
        val breakdown = StatsAggregator.byLabel(records)
        if (breakdown.isEmpty()) {
            statsLabelList.addView(TextView(this).apply {
                text = getString(R.string.no_stats)
                typeface = font
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 9f)
                setLineSpacing(dp(4).toFloat(), 1f)
                setTextColor(pixelTheme.onSurfaceDim)
            })
        } else {
            breakdown.forEach { (label, minutes) ->
                val row = LinearLayout(this).apply {
                    orientation = LinearLayout.HORIZONTAL
                    layoutParams = LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.WRAP_CONTENT
                    )
                    setPadding(0, dp(6), 0, dp(6))
                }
                row.addView(TextView(this).apply {
                    text = label
                    typeface = font
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
                    setTextColor(pixelTheme.onSurface)
                })
                row.addView(View(this).apply {
                    layoutParams = LinearLayout.LayoutParams(0, dp(1), 1f)
                })
                row.addView(TextView(this).apply {
                    text = StatsAggregator.formatMinutes(minutes)
                    typeface = font
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
                    setTextColor(pixelTheme.onSurfaceDim)
                })
                statsLabelList.addView(row)
            }
        }
    }

    // ---- shop ---------------------------------------------------------------

    /** Rebuilds the shop: one row per flower (pixel icon · name · owned · cost · BUY). */
    private fun refreshShop() {
        shopListContainer.removeAllViews()
        val font = ResourcesCompat.getFont(this, R.font.press_start_2p)
        val cell = dp(4)
        Flowers.ALL.forEach { flower ->
            val row = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT
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
                text = flower.nameTr
                typeface = font
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                setTextColor(pixelTheme.onSurface)
            })
            info.addView(TextView(this).apply {
                text = getString(R.string.owned_count, owned[flower.id] ?: 0)
                typeface = font
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 8f)
                setPadding(0, dp(6), 0, 0)
                setTextColor(pixelTheme.onSurfaceDim)
            })
            row.addView(info)
            row.addView(AppCompatButton(this).apply {
                typeface = font
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

    // ---- theming ------------------------------------------------------------

    /** Applies [pixelTheme] to every view + drawable, then re-renders. */
    private fun applyTheme() {
        root.setBackgroundColor(pixelTheme.bg)
        settingsPanel.setBackgroundColor(pixelTheme.bg)
        themePanel.setBackgroundColor(pixelTheme.bg)
        labelPanel.setBackgroundColor(pixelTheme.bg)
        statsPanel.setBackgroundColor(pixelTheme.bg)
        shopPanel.setBackgroundColor(pixelTheme.bg)

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

        themeBtn.setColorFilter(pixelTheme.onSurface)
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

        styleStepper(rowWork)
        styleStepper(rowBreak)
        styleStepper(rowSessions)

        styleThemeButtons()
        styleLabelButtons()
        styleStatsView()

        labelInput.setBackgroundColor(pixelTheme.panel)
        labelInput.setTextColor(pixelTheme.onSurface)
        labelInput.setHintTextColor(pixelTheme.onSurfaceDim)

        renderedMode = null   // force the progress drawable to rebuild with new colors
        render()
    }

    /** Colors the stat caption/value rows (captions dim, values bright). */
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
            if (theme.id == pixelTheme.id) {
                stylePrimary(btn)
                btn.text = "> ${theme.displayName}"
            } else {
                styleSecondary(btn)
                btn.text = theme.displayName
            }
        }
    }

    // ---- rendering ----------------------------------------------------------

    /** Full render: called on every structural change (start/pause/reset/switch/save/theme). */
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

    /** Lightweight per-second update: just the time text + progress value. */
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
