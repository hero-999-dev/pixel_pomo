package com.pixelpomo.app

import android.os.Bundle
import android.os.CountDownTimer
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.widget.AppCompatButton
import androidx.core.content.ContextCompat

/**
 * The single screen. All timer *state* lives in [PomodoroEngine]; this class only
 * drives the platform [CountDownTimer] and renders the engine's state into the views.
 */
class MainActivity : AppCompatActivity() {

    private val engine = PomodoroEngine()
    private var countDownTimer: CountDownTimer? = null

    private lateinit var modeLabel: TextView
    private lateinit var timerText: TextView
    private lateinit var progress: ProgressBar
    private lateinit var startPauseBtn: AppCompatButton
    private lateinit var resetBtn: AppCompatButton
    private lateinit var switchModeBtn: AppCompatButton
    private lateinit var roundLabel: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        modeLabel = findViewById(R.id.modeLabel)
        timerText = findViewById(R.id.timer)
        progress = findViewById(R.id.progress)
        startPauseBtn = findViewById(R.id.startPauseBtn)
        resetBtn = findViewById(R.id.resetBtn)
        switchModeBtn = findViewById(R.id.switchModeBtn)
        roundLabel = findViewById(R.id.roundLabel)

        startPauseBtn.setOnClickListener { if (engine.isRunning) pause() else start() }
        resetBtn.setOnClickListener { reset() }
        switchModeBtn.setOnClickListener { switchMode() }

        render()
    }

    private fun start() {
        engine.start()
        if (!engine.isRunning) return
        countDownTimer?.cancel()
        countDownTimer = object : CountDownTimer(engine.timeLeftMillis, 1000) {
            override fun onTick(millisUntilFinished: Long) {
                engine.setTimeLeft(millisUntilFinished)
                render()
            }

            override fun onFinish() {
                val finished = engine.finishPhase()
                val msg = if (finished == Mode.WORK) R.string.work_done else R.string.break_done
                Toast.makeText(this@MainActivity, getString(msg), Toast.LENGTH_SHORT).show()
                render()
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
        render()
    }

    private fun switchMode() {
        countDownTimer?.cancel()
        engine.switchMode()
        render()
    }

    /** Push the engine's current state into the views. */
    private fun render() {
        timerText.text = engine.formattedTime()
        modeLabel.text = getString(if (engine.mode == Mode.WORK) R.string.work else R.string.break_label)
        val accentRes = if (engine.mode == Mode.WORK) R.color.work_green else R.color.break_blue
        modeLabel.setTextColor(ContextCompat.getColor(this, accentRes))
        progress.progress = engine.progressPercent()
        roundLabel.text = getString(R.string.round, engine.round)
        startPauseBtn.text = getString(if (engine.isRunning) R.string.pause else R.string.start)
    }

    override fun onDestroy() {
        super.onDestroy()
        countDownTimer?.cancel()
    }
}
