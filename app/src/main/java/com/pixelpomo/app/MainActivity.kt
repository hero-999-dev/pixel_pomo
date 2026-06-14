package com.pixelpomo.app

import android.os.Bundle
import android.os.CountDownTimer
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.widget.AppCompatButton
import androidx.core.content.ContextCompat
import java.util.Locale

class MainActivity : AppCompatActivity() {

    /** A Pomodoro phase and how long it lasts. */
    private enum class Mode(val label: String, val durationMillis: Long) {
        WORK("WORK", 25 * 60 * 1000L),
        BREAK("BREAK", 5 * 60 * 1000L)
    }

    private lateinit var modeLabel: TextView
    private lateinit var timerText: TextView
    private lateinit var progress: ProgressBar
    private lateinit var startPauseBtn: AppCompatButton
    private lateinit var resetBtn: AppCompatButton
    private lateinit var switchModeBtn: AppCompatButton
    private lateinit var roundLabel: TextView

    private var mode: Mode = Mode.WORK
    private var timeLeftMillis: Long = Mode.WORK.durationMillis
    private var isRunning: Boolean = false
    private var round: Int = 1
    private var countDownTimer: CountDownTimer? = null

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

        startPauseBtn.setOnClickListener { if (isRunning) pauseTimer() else startTimer() }
        resetBtn.setOnClickListener { resetTimer() }
        switchModeBtn.setOnClickListener { switchMode() }

        updateUi()
    }

    private fun startTimer() {
        countDownTimer = object : CountDownTimer(timeLeftMillis, 1000) {
            override fun onTick(millisUntilFinished: Long) {
                timeLeftMillis = millisUntilFinished
                updateUi()
            }

            override fun onFinish() {
                timeLeftMillis = 0
                isRunning = false
                onSessionFinished()
            }
        }.start()
        isRunning = true
        updateButtons()
    }

    private fun pauseTimer() {
        countDownTimer?.cancel()
        isRunning = false
        updateButtons()
    }

    private fun resetTimer() {
        countDownTimer?.cancel()
        isRunning = false
        timeLeftMillis = mode.durationMillis
        updateUi()
    }

    private fun switchMode() {
        countDownTimer?.cancel()
        isRunning = false
        mode = if (mode == Mode.WORK) Mode.BREAK else Mode.WORK
        timeLeftMillis = mode.durationMillis
        updateUi()
    }

    /** Called when a phase reaches 00:00: notify, flip to the other phase, count rounds. */
    private fun onSessionFinished() {
        val message = if (mode == Mode.WORK) R.string.work_done else R.string.break_done
        Toast.makeText(this, getString(message), Toast.LENGTH_SHORT).show()

        if (mode == Mode.WORK) {
            mode = Mode.BREAK
        } else {
            mode = Mode.WORK
            round += 1
        }
        timeLeftMillis = mode.durationMillis
        updateUi()
    }

    private fun updateUi() {
        // Round up so a full duration reads e.g. 25:00 rather than 24:59.
        val totalSeconds = (timeLeftMillis + 999) / 1000
        val minutes = totalSeconds / 60
        val seconds = totalSeconds % 60
        timerText.text = String.format(Locale.US, "%02d:%02d", minutes, seconds)

        modeLabel.text = mode.label
        val accentRes = if (mode == Mode.WORK) R.color.work_green else R.color.break_blue
        modeLabel.setTextColor(ContextCompat.getColor(this, accentRes))

        val pct = if (mode.durationMillis > 0)
            (timeLeftMillis * 100 / mode.durationMillis).toInt() else 0
        progress.progress = pct

        roundLabel.text = getString(R.string.round, round)
        updateButtons()
    }

    private fun updateButtons() {
        startPauseBtn.text = getString(if (isRunning) R.string.pause else R.string.start)
    }

    override fun onDestroy() {
        super.onDestroy()
        countDownTimer?.cancel()
    }
}
