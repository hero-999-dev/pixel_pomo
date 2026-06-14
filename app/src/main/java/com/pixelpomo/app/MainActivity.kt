package com.pixelpomo.app

import android.content.SharedPreferences
import android.os.Bundle
import android.os.CountDownTimer
import android.util.TypedValue
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.widget.AppCompatButton
import androidx.core.content.res.ResourcesCompat

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

        const val DEFAULT_WORK = 25
        const val DEFAULT_BREAK = 5
        const val DEFAULT_SESSIONS = 4

        const val WORK_MIN = 5;     const val WORK_MAX = 90;     const val WORK_STEP = 5
        const val BREAK_MIN = 1;    const val BREAK_MAX = 30;    const val BREAK_STEP = 1
        const val SESSIONS_MIN = 1; const val SESSIONS_MAX = 12; const val SESSIONS_STEP = 1
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

    // Views
    private lateinit var root: View
    private lateinit var modeLabel: TextView
    private lateinit var timerText: TextView
    private lateinit var progress: ProgressBar
    private lateinit var startPauseBtn: AppCompatButton
    private lateinit var resetBtn: AppCompatButton
    private lateinit var switchModeBtn: AppCompatButton
    private lateinit var sessionLabel: TextView
    private lateinit var themeBtn: ImageView
    private lateinit var settingsBtn: ImageView

    private lateinit var settingsPanel: View
    private lateinit var themePanel: View
    private lateinit var settingsTitle: TextView
    private lateinit var themeTitle: TextView
    private lateinit var saveBtn: AppCompatButton
    private lateinit var settingsCloseBtn: AppCompatButton
    private lateinit var themeCloseBtn: AppCompatButton
    private lateinit var themeListContainer: LinearLayout

    private lateinit var rowWork: View
    private lateinit var rowBreak: View
    private lateinit var rowSessions: View

    private val themeButtons = mutableListOf<Pair<PixelTheme, AppCompatButton>>()

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

        applyTheme()   // applies colors, styles buttons, and renders
    }

    // ---- config persistence -------------------------------------------------

    private fun loadConfig() {
        workMin = prefs.getInt(KEY_WORK, DEFAULT_WORK)
        breakMin = prefs.getInt(KEY_BREAK, DEFAULT_BREAK)
        sessions = prefs.getInt(KEY_SESSIONS, DEFAULT_SESSIONS)
        pixelTheme = Themes.byId(prefs.getString(KEY_THEME, Themes.DEFAULT.id))
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
        themeBtn = findViewById(R.id.themeBtn)
        settingsBtn = findViewById(R.id.settingsBtn)

        settingsPanel = findViewById(R.id.settingsPanel)
        themePanel = findViewById(R.id.themePanel)
        settingsTitle = findViewById(R.id.settingsTitle)
        themeTitle = findViewById(R.id.themeTitle)
        saveBtn = findViewById(R.id.saveBtn)
        settingsCloseBtn = findViewById(R.id.settingsCloseBtn)
        themeCloseBtn = findViewById(R.id.themeCloseBtn)
        themeListContainer = findViewById(R.id.themeList)

        rowWork = findViewById(R.id.rowWork)
        rowBreak = findViewById(R.id.rowBreak)
        rowSessions = findViewById(R.id.rowSessions)
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
        saveBtn.setOnClickListener { saveSettings() }
        settingsCloseBtn.setOnClickListener { settingsPanel.visibility = View.GONE }
        themeCloseBtn.setOnClickListener { themePanel.visibility = View.GONE }
    }

    private fun openSettings() {
        draftWork = workMin
        draftBreak = breakMin
        draftSessions = sessions
        refreshStepperValues()
        themePanel.visibility = View.GONE
        settingsPanel.visibility = View.VISIBLE
    }

    private fun openThemes() {
        settingsPanel.visibility = View.GONE
        themePanel.visibility = View.VISIBLE
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
        when {
            settingsPanel.visibility == View.VISIBLE -> settingsPanel.visibility = View.GONE
            themePanel.visibility == View.VISIBLE -> themePanel.visibility = View.GONE
            else -> super.onBackPressed()
        }
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

    // ---- theming ------------------------------------------------------------

    /** Applies [pixelTheme] to every view + drawable, then re-renders. */
    private fun applyTheme() {
        root.setBackgroundColor(pixelTheme.bg)
        settingsPanel.setBackgroundColor(pixelTheme.bg)
        themePanel.setBackgroundColor(pixelTheme.bg)

        timerText.setTextColor(pixelTheme.onSurface)
        sessionLabel.setTextColor(pixelTheme.onSurfaceDim)
        switchModeBtn.setTextColor(pixelTheme.onSurfaceDim)
        settingsTitle.setTextColor(pixelTheme.onSurface)
        themeTitle.setTextColor(pixelTheme.onSurface)

        themeBtn.setColorFilter(pixelTheme.onSurface)
        settingsBtn.setColorFilter(pixelTheme.onSurface)

        stylePrimary(startPauseBtn)
        stylePrimary(saveBtn)
        styleSecondary(resetBtn)
        styleSecondary(settingsCloseBtn)
        styleSecondary(themeCloseBtn)

        styleStepper(rowWork)
        styleStepper(rowBreak)
        styleStepper(rowSessions)

        styleThemeButtons()

        renderedMode = null   // force the progress drawable to rebuild with new colors
        render()
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
