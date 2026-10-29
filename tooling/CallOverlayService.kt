package ir.apadanasleep.customer_callbook

import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView

/**
 * پاپ‌آپ روی همه صفحات (روی صفحه تماس) — نیاز به مجوز SYSTEM_ALERT_WINDOW
 */
class CallOverlayService : Service() {
    private var wm: WindowManager? = null
    private var root: View? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (intent.action == ACTION_DISMISS) {
            remove()
            stopSelf()
            return START_NOT_STICKY
        }
        val number = intent.getStringExtra(EXTRA_NUMBER) ?: ""
        val name = intent.getStringExtra(EXTRA_NAME)
        val note = intent.getStringExtra(EXTRA_NOTE)
        val mode = intent.getStringExtra(EXTRA_MODE) ?: MODE_SAVE
        show(number, name, note, mode)
        return START_NOT_STICKY
    }

    private fun show(number: String, name: String?, note: String?, mode: String) {
        if (!Settings.canDrawOverlays(this)) {
            // بدون مجوز اورلی — Activity تمام‌صفحه
            try {
                val i = Intent(this, CallAlertActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    putExtra(CallAlertActivity.EXTRA_NUMBER, number)
                    putExtra(CallAlertActivity.EXTRA_MODE, mode)
                    if (name != null) putExtra(CallAlertActivity.EXTRA_NAME, name)
                    if (note != null) putExtra(CallAlertActivity.EXTRA_NOTE, note)
                }
                startActivity(i)
            } catch (_: Exception) {
            }
            stopSelf()
            return
        }
        remove()
        wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val density = resources.displayMetrics.density
        fun dp(v: Int) = (v * density).toInt()

        val known = !name.isNullOrBlank()
        val container = FrameLayout(this).apply {
            setBackgroundColor(Color.parseColor("#99000A12"))
            isClickable = true
            setOnClickListener { /* block behind */ }
        }

        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#1A1F2E"))
                cornerRadius = dp(28).toFloat()
                setStroke(dp(1), Color.parseColor("#33FFFFFF"))
            }
            setPadding(dp(28), dp(28), dp(28), dp(24))
            val lp = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                gravity = Gravity.CENTER
                marginStart = dp(20)
                marginEnd = dp(20)
            }
            layoutParams = lp
        }

        val icon = TextView(this).apply {
            text = if (known) "👤" else "＋"
            gravity = Gravity.CENTER
            textSize = 26f
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#2A2035"))
                setStroke(dp(2), Color.parseColor("#FF8C3A"))
            }
            layoutParams = LinearLayout.LayoutParams(dp(60), dp(60)).apply {
                gravity = Gravity.CENTER_HORIZONTAL
                bottomMargin = dp(14)
            }
        }
        card.addView(icon)

        val title = TextView(this).apply {
            text = when {
                mode == MODE_SAVE && !known -> "مشتری جدید"
                known -> name
                else -> "مشتری ناشناس"
            }
            setTextColor(Color.parseColor("#FF8C3A"))
            textSize = 22f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { bottomMargin = dp(8) }
        }
        card.addView(title)

        val phoneTv = TextView(this).apply {
            text = "\u200E" + formatPhone(number)
            setTextColor(Color.WHITE)
            textSize = 20f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { bottomMargin = dp(8) }
        }
        card.addView(phoneTv)

        val sub = TextView(this).apply {
            text = when {
                known && !note.isNullOrBlank() -> note
                known -> "در دفترچه شماست"
                mode == MODE_SAVE -> "این شماره در دفترچه شما ثبت نشده"
                else -> "در حال دریافت تماس..."
            }
            setTextColor(Color.parseColor("#99A0B0"))
            textSize = 13f
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { bottomMargin = dp(20) }
        }
        card.addView(sub)

        if (!known) {
            card.addView(makeBtn("افزودن به دفترچه", Color.parseColor("#00C2D8")) {
                val i = Intent(this, MainActivity::class.java).apply {
                    action = MainActivity.ACTION_ADD_CUSTOMER
                    putExtra(MainActivity.EXTRA_NUMBER, number)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                }
                startActivity(i)
                remove()
                stopSelf()
            })
        } else {
            card.addView(makeBtn("مشاهده مشتری", Color.parseColor("#6C63FF")) {
                val i = Intent(this, MainActivity::class.java).apply {
                    action = MainActivity.ACTION_OPEN_CUSTOMER
                    putExtra(MainActivity.EXTRA_NUMBER, number)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                }
                startActivity(i)
                remove()
                stopSelf()
            })
        }
        card.addView(makeBtn("نادیده گرفتن", Color.parseColor("#2A3142"), Color.parseColor("#B0B8C8")) {
            remove()
            stopSelf()
        })

        container.addView(card)
        root = container

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.CENTER
        }
        // need focus for buttons
        params.flags = WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
            WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON

        try {
            wm?.addView(container, params)
        } catch (_: Exception) {
            stopSelf()
        }
    }

    private fun makeBtn(
        label: String,
        bg: Int,
        fg: Int = Color.WHITE,
        onClick: () -> Unit
    ): Button {
        val density = resources.displayMetrics.density
        fun dp(v: Int) = (v * density).toInt()
        return Button(this).apply {
            text = label
            setTextColor(fg)
            textSize = 15f
            isAllCaps = false
            background = GradientDrawable().apply {
                setColor(bg)
                cornerRadius = dp(16).toFloat()
            }
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(50)
            ).apply { bottomMargin = dp(10) }
            setOnClickListener { onClick() }
        }
    }

    private fun formatPhone(phone: String): String {
        var p = phone.replace(Regex("[\\s\\-()]"), "")
        if (p.startsWith("+98")) p = "0" + p.substring(3)
        if (p.startsWith("0098")) p = "0" + p.substring(4)
        if (p.startsWith("98") && p.length >= 12) p = "0" + p.substring(2)
        return if (p.length == 11 && p.startsWith("09")) {
            "+98 " + p.substring(1, 4) + " " + p.substring(4, 7) + " " + p.substring(7)
        } else phone
    }

    private fun remove() {
        try {
            root?.let { wm?.removeView(it) }
        } catch (_: Exception) {
        }
        root = null
    }

    override fun onDestroy() {
        remove()
        super.onDestroy()
    }

    companion object {
        const val EXTRA_NUMBER = "number"
        const val EXTRA_NAME = "name"
        const val EXTRA_NOTE = "note"
        const val EXTRA_MODE = "mode"
        const val MODE_RING = "ringing"
        const val MODE_SAVE = "save"
        const val ACTION_DISMISS = "ir.apadanasleep.customer_callbook.DISMISS_OVERLAY"

        fun show(
            context: Context,
            number: String,
            name: String?,
            note: String?,
            mode: String
        ) {
            val i = Intent(context, CallOverlayService::class.java).apply {
                putExtra(EXTRA_NUMBER, number)
                putExtra(EXTRA_MODE, mode)
                if (name != null) putExtra(EXTRA_NAME, name)
                if (note != null) putExtra(EXTRA_NOTE, note)
            }
            context.startService(i)
        }
    }
}
