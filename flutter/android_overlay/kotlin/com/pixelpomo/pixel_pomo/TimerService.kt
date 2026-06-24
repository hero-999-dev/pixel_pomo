package com.pixelpomo.pixel_pomo

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper

/// Foreground service behind the focus-timer notification (#v23 fb). A plain
/// ongoing notification is user-dismissible on Android 14+, so to make it
/// **un-swipeable until the session ends** we run it as a foreground service.
///
/// It also drives the whole phase chain itself: the MM:SS is a system-ticked
/// chronometer, but the focus→break / focus→done TRANSITION needs to happen at the
/// deadline even though our Dart isolate is frozen in the background — so the show
/// call hands us the next phase up front. At a phase deadline we either roll into
/// the auto-break ([nextMs] > 0) with a fresh countdown, or settle on a static
/// [doneTitle] ("FOCUS DONE!" / "BREAK OVER!") that no longer ticks — then DETACH
/// (it lingers, now swipeable) and stop. Cancelling in-app removes it outright.
class TimerService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private val pending = ArrayList<Runnable>()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_SHOW -> {
                val deadline = intent.getLongExtra(EXTRA_DEADLINE, 0L)
                val title = intent.getStringExtra(EXTRA_TITLE) ?: "FOCUS"
                val nextMs = intent.getLongExtra(EXTRA_NEXT_MS, 0L)
                val nextTitle = intent.getStringExtra(EXTRA_NEXT_TITLE) ?: ""
                val doneTitle = intent.getStringExtra(EXTRA_DONE_TITLE) ?: title
                ensureChannel()
                try {
                    startForeground(NOTIF_ID, build(deadline, title, ongoing = true, chronometer = true))
                } catch (e: Exception) {
                    stopSelf(); return START_NOT_STICKY
                }
                clearPending()
                schedule(deadline) {
                    if (nextMs > 0L) {
                        val next = deadline + nextMs
                        nm().notify(NOTIF_ID, build(next, nextTitle, ongoing = true, chronometer = true))
                        schedule(next) { showDone(doneTitle) }
                    } else {
                        showDone(doneTitle)
                    }
                }
            }
            else -> { // ACTION_CANCEL (or anything) → remove and stop
                clearPending()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        clearPending()
        super.onDestroy()
    }

    /// Time's up and nothing follows: a static, now-swipeable card; step down.
    private fun showDone(title: String) {
        nm().notify(NOTIF_ID, build(0L, title, ongoing = false, chronometer = false))
        stopForeground(STOP_FOREGROUND_DETACH)
        stopSelf()
    }

    private fun schedule(atMs: Long, action: () -> Unit) {
        val r = Runnable { action() }
        pending.add(r)
        handler.postDelayed(r, (atMs - System.currentTimeMillis()).coerceAtLeast(0L))
    }

    private fun clearPending() {
        pending.forEach { handler.removeCallbacks(it) }
        pending.clear()
    }

    private fun nm() = getSystemService(NOTIFICATION_SERVICE) as NotificationManager

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm().createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Focus timer", NotificationManager.IMPORTANCE_LOW)
                    .apply { setShowBadge(false) })
        }
    }

    @Suppress("DEPRECATION") // pre-O has no channel constructor
    private fun build(deadlineMs: Long, title: String, ongoing: Boolean, chronometer: Boolean): Notification {
        val tap = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE)
        val b = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            Notification.Builder(this, CHANNEL_ID) else Notification.Builder(this)
        b.setSmallIcon(applicationInfo.icon)           // the app's icon, in the small/left slot (#v23 fb)
            .setContentTitle(title)
            .setOngoing(ongoing)
            .setVisibility(Notification.VISIBILITY_PUBLIC) // on the lock screen
            .setContentIntent(tap)
        if (chronometer) {
            b.setShowWhen(true).setWhen(deadlineMs).setUsesChronometer(true) // live MM:SS, system-ticked
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) b.setChronometerCountDown(true)
        } else {
            b.setShowWhen(false) // a finished phase: no clock, no ticking past zero
        }
        return b.build()
    }

    companion object {
        const val CHANNEL_ID = "pixel_pomo_timer"
        const val NOTIF_ID = 4123
        const val ACTION_SHOW = "com.pixelpomo.pixel_pomo.SHOW_TIMER"
        const val ACTION_CANCEL = "com.pixelpomo.pixel_pomo.CANCEL_TIMER"
        const val EXTRA_DEADLINE = "deadline"
        const val EXTRA_TITLE = "title"
        const val EXTRA_NEXT_MS = "nextMs"
        const val EXTRA_NEXT_TITLE = "nextTitle"
        const val EXTRA_DONE_TITLE = "doneTitle"

        fun show(ctx: Context, deadlineMs: Long, title: String, nextMs: Long, nextTitle: String, doneTitle: String) {
            val i = Intent(ctx, TimerService::class.java).apply {
                action = ACTION_SHOW
                putExtra(EXTRA_DEADLINE, deadlineMs)
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_NEXT_MS, nextMs)
                putExtra(EXTRA_NEXT_TITLE, nextTitle)
                putExtra(EXTRA_DONE_TITLE, doneTitle)
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) ctx.startForegroundService(i)
                else ctx.startService(i)
            } catch (e: Exception) {
                // ForegroundServiceStartNotAllowedException on some Android 12+ paths —
                // the in-app timer stays the source of truth; the badge just won't show.
            }
        }

        fun cancel(ctx: Context) {
            try {
                ctx.startService(Intent(ctx, TimerService::class.java).apply { action = ACTION_CANCEL })
            } catch (e: Exception) {
            }
        }
    }
}
