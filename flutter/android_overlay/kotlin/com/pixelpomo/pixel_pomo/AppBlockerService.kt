package com.pixelpomo.pixel_pomo

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/// Detects the foreground app and, while a focus session is active, covers any
/// blocked app with a full-screen "stay focused" overlay (#v23). All state comes
/// from BlockerData (SharedPreferences written by the Flutter app).
class AppBlockerService : AccessibilityService() {
    private var overlay: View? = null
    private val handler = Handler(Looper.getMainLooper())

    // Drop the overlay when the session ends even if no new window event fires.
    private val tick = object : Runnable {
        override fun run() {
            if (!BlockerData.active(this@AppBlockerService)) hide()
            handler.postDelayed(this, 1000)
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        handler.postDelayed(tick, 1000)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = event.packageName?.toString() ?: return
        if (BlockerData.shouldBlock(this, pkg, packageName, launcherPkg())) show() else hide()
    }

    override fun onInterrupt() {}

    private fun launcherPkg(): String? {
        val i = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        return packageManager.resolveActivity(i, 0)?.activityInfo?.packageName
    }

    private fun show() {
        if (overlay != null) return
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#161616"))
            setPadding(64, 64, 64, 64)
            addView(TextView(context).apply {
                text = BlockerData.title(this@AppBlockerService)
                setTextColor(Color.WHITE)
                textSize = 24f
                gravity = Gravity.CENTER
                setPadding(0, 0, 0, 56)
            })
            addView(Button(context).apply {
                text = BlockerData.button(this@AppBlockerService)
                setTextColor(Color.WHITE)
                setBackgroundColor(Color.parseColor("#FF5A5F"))
                setOnClickListener { backToApp() }
            })
        }
        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            0, // focusable + touchable → fully covers the blocked app
            PixelFormat.OPAQUE,
        )
        try {
            wm.addView(root, lp)
            overlay = root
        } catch (e: Exception) {
        }
    }

    private fun backToApp() {
        val li = packageManager.getLaunchIntentForPackage(packageName)
            ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
        if (li != null) startActivity(li)
        hide()
    }

    private fun hide() {
        val o = overlay ?: return
        try {
            (getSystemService(WINDOW_SERVICE) as WindowManager).removeView(o)
        } catch (e: Exception) {
        }
        overlay = null
    }

    override fun onDestroy() {
        handler.removeCallbacks(tick)
        hide()
        super.onDestroy()
    }
}
