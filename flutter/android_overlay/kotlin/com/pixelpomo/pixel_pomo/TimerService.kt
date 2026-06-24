package com.pixelpomo.pixel_pomo

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper

/// Foreground service behind the focus-timer notification (#v23 fb). A plain
/// ongoing notification is user-dismissible on Android 14+, so to make it
/// **un-swipeable until the session ends** we run it as a foreground service. The
/// MM:SS countdown is a system-ticked chronometer (so it keeps counting even if
/// Android suspends our Dart isolate in the background); at the deadline we DETACH
/// it — it lingers, now swipeable — and stop. Cancelling in-app removes it outright.
class TimerService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var atDeadline: Runnable? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_SHOW -> {
                val deadline = intent.getLongExtra(EXTRA_DEADLINE, 0L)
                val title = intent.getStringExtra(EXTRA_TITLE) ?: "FOCUS"
                ensureChannel()
                try {
                    startForeground(NOTIF_ID, build(deadline, title, ongoing = true))
                } catch (e: Exception) {
                    stopSelf(); return START_NOT_STICKY
                }
                atDeadline?.let { handler.removeCallbacks(it) }
                atDeadline = Runnable {
                    // Time's up: leave a now-dismissible copy and step down.
                    nm().notify(NOTIF_ID, build(deadline, title, ongoing = false))
                    stopForeground(STOP_FOREGROUND_DETACH)
                    stopSelf()
                }
                handler.postDelayed(atDeadline!!, (deadline - System.currentTimeMillis()).coerceAtLeast(0L))
            }
            else -> { // ACTION_CANCEL (or anything) → remove and stop
                atDeadline?.let { handler.removeCallbacks(it) }
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        atDeadline?.let { handler.removeCallbacks(it) }
        super.onDestroy()
    }

    private fun nm() = getSystemService(NOTIFICATION_SERVICE) as NotificationManager

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm().createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Focus timer", NotificationManager.IMPORTANCE_LOW)
                    .apply { setShowBadge(false) })
        }
    }

    private fun appIcon(): Bitmap? = try {
        val d = packageManager.getApplicationIcon(packageName)
        val bmp = Bitmap.createBitmap(
            d.intrinsicWidth.coerceIn(1, 192), d.intrinsicHeight.coerceIn(1, 192), Bitmap.Config.ARGB_8888)
        Canvas(bmp).also { d.setBounds(0, 0, it.width, it.height); d.draw(it) }
        bmp
    } catch (e: Exception) {
        null
    }

    @Suppress("DEPRECATION") // pre-O has no channel constructor
    private fun build(deadlineMs: Long, title: String, ongoing: Boolean): Notification {
        val tap = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE)
        val b = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            Notification.Builder(this, CHANNEL_ID) else Notification.Builder(this)
        b.setSmallIcon(applicationInfo.icon)          // the app's own logo (#v23 fb)
            .setLargeIcon(appIcon())
            .setContentTitle(title)
            .setOngoing(ongoing)
            .setShowWhen(true)
            .setWhen(deadlineMs)
            .setUsesChronometer(true)                 // live MM:SS, ticked by the system
            .setVisibility(Notification.VISIBILITY_PUBLIC) // on the lock screen
            .setContentIntent(tap)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) b.setChronometerCountDown(true)
        return b.build()
    }

    companion object {
        const val CHANNEL_ID = "pixel_pomo_timer"
        const val NOTIF_ID = 4123
        const val ACTION_SHOW = "com.pixelpomo.pixel_pomo.SHOW_TIMER"
        const val ACTION_CANCEL = "com.pixelpomo.pixel_pomo.CANCEL_TIMER"
        const val EXTRA_DEADLINE = "deadline"
        const val EXTRA_TITLE = "title"

        fun show(ctx: Context, deadlineMs: Long, title: String) {
            val i = Intent(ctx, TimerService::class.java).apply {
                action = ACTION_SHOW
                putExtra(EXTRA_DEADLINE, deadlineMs)
                putExtra(EXTRA_TITLE, title)
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
