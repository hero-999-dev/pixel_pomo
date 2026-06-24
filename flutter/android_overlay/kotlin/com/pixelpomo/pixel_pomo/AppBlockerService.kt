package com.pixelpomo.pixel_pomo

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
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
        // Ignore our own windows (incl. the overlay). A focusable overlay fires a
        // WINDOW_STATE_CHANGED for our package, which used to hit `else hide()` and
        // tear the overlay down; the blocked app then returned to front and we
        // re-showed — looping forever, i.e. the constant flicker (#v23 fb).
        if (pkg == packageName) return
        if (BlockerData.shouldBlock(this, pkg, packageName, launcherPkg())) show() else hide()
    }

    override fun onInterrupt() {}

    private fun launcherPkg(): String? {
        val i = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        return packageManager.resolveActivity(i, 0)?.activityInfo?.packageName
    }

    // Press Start 2P (the app's pixel font) loaded straight from Flutter's bundled
    // assets so overlay text matches the rest of the UI (#v23 fb). Null (e.g. asset
    // moved) falls back to the system font instead of crashing.
    private val pixelFont: Typeface? by lazy {
        try {
            Typeface.createFromAsset(assets, "flutter_assets/assets/fonts/PressStart2P-Regular.ttf")
        } catch (e: Exception) {
            null
        }
    }

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

    private fun show() {
        if (overlay != null) return
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val ink = BlockerData.ink(this)
        val accent = BlockerData.accent(this)
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(BlockerData.bg(this@AppBlockerService))
            setPadding(dp(32), dp(32), dp(32), dp(32))
            addView(TextView(context).apply {
                text = BlockerData.title(this@AppBlockerService)
                setTextColor(ink)
                typeface = pixelFont
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
                letterSpacing = 0.05f
                gravity = Gravity.CENTER
                setPadding(0, 0, 0, dp(28))
            })
            // A clickable TextView, not a Material Button: flat hard-edged fill +
            // border, no rounded corners / elevation / ALL-CAPS — i.e. PixelButton.
            addView(TextView(context).apply {
                text = BlockerData.button(this@AppBlockerService)
                setTextColor(BlockerData.onAccent(this@AppBlockerService))
                typeface = pixelFont
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
                letterSpacing = 0.05f
                gravity = Gravity.CENTER
                background = GradientDrawable().apply {
                    setColor(accent)
                    setStroke(dp(2), ink)
                }
                setPadding(dp(20), dp(12), dp(20), dp(12))
                isClickable = true
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
