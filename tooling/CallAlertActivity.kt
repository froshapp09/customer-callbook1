package ir.apadanasleep.customer_callbook

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.ImageView
import android.graphics.Typeface
import android.util.TypedValue

/**
 * تمام‌صفحه پاپ‌آپ تماس — شبیه طرح «مشتری جدید»
 */
class CallAlertActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(
            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_FULLSCREEN
        )
        try {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } catch (_: Exception) {}

        val number = intent.getStringExtra(EXTRA_NUMBER) ?: ""
        val name = intent.getStringExtra(EXTRA_NAME)
        val note = intent.getStringExtra(EXTRA_NOTE)
        val mode = intent.getStringExtra(EXTRA_MODE) ?: MODE_RINGING
        val known = !name.isNullOrBlank()

        val density = resources.displayMetrics.density
        fun dp(v: Int) = (v * density).toInt()

        val root = FrameLayout(this).apply {
            setBackgroundColor(Color.parseColor("#CC0B0F1A"))
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            setOnClickListener { /* absorb */ }
        }

        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            val bg = GradientDrawable().apply {
                setColor(Color.parseColor("#1A1F2E"))
                cornerRadius = dp(28).toFloat()
                setStroke(dp(1), Color.parseColor("#33FFFFFF"))
            }
            background = bg
            setPadding(dp(28), dp(32), dp(28), dp(28))
            val lp = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                gravity = Gravity.CENTER
                marginStart = dp(24)
                marginEnd = dp(24)
            }
            layoutParams = lp
        }

        // icon circle
        val iconWrap = TextView(this).apply {
            text = if (known) "👤" else "＋"
            gravity = Gravity.CENTER
            textSize = 28f
            val g = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#2A2035"))
                setStroke(dp(2), Color.parseColor("#FF8C3A"))
            }
            background = g
            layoutParams = LinearLayout.LayoutParams(dp(64), dp(64)).apply {
                gravity = Gravity.CENTER_HORIZONTAL
                bottomMargin = dp(16)
            }
        }
        card.addView(iconWrap)

        val title = TextView(this).apply {
            text = when {
                mode == MODE_SAVE && !known -> "مشتری جدید"
                mode == MODE_RINGING && known -> name
                mode == MODE_RINGING && !known -> "مشتری ناشناس"
                else -> name ?: "تماس"
            }
            setTextColor(Color.parseColor("#FF8C3A"))
            textSize = 24f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { bottomMargin = dp(10) }
        }
        card.addView(title)

        val phoneTv = TextView(this).apply {
            text = formatPhone(number)
            setTextColor(Color.WHITE)
            textSize = 22f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { bottomMargin = dp(8) }
        }
        card.addView(phoneTv)

        val subtitle = TextView(this).apply {
            text = when {
                known && !note.isNullOrBlank() -> note
                known -> "در دفترچه شماست"
                mode == MODE_SAVE -> "این شماره در دفترچه شما ثبت نشده"
                else -> "در حال دریافت تماس..."
            }
            setTextColor(Color.parseColor("#99A0B0"))
            textSize = 14f
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { bottomMargin = dp(24) }
        }
        card.addView(subtitle)

        if (!known) {
            val addBtn = Button(this).apply {
                text = "افزودن به دفترچه"
                setTextColor(Color.WHITE)
                textSize = 16f
                isAllCaps = false
                val g = GradientDrawable().apply {
                    setColor(Color.parseColor("#00C2D8"))
                    cornerRadius = dp(16).toFloat()
                }
                background = g
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    dp(52)
                ).apply { bottomMargin = dp(12) }
                setOnClickListener {
                    val i = packageManager.getLaunchIntentForPackage(packageName)
                    if (i != null) {
                        i.action = ACTION_ADD_CUSTOMER
                        i.putExtra(EXTRA_NUMBER, number)
                        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                        startActivity(i)
                    }
                    finish()
                }
            }
            card.addView(addBtn)
        } else {
            val openBtn = Button(this).apply {
                text = "مشاهده مشتری"
                setTextColor(Color.WHITE)
                textSize = 16f
                isAllCaps = false
                val g = GradientDrawable().apply {
                    setColor(Color.parseColor("#6C63FF"))
                    cornerRadius = dp(16).toFloat()
                }
                background = g
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    dp(52)
                ).apply { bottomMargin = dp(12) }
                setOnClickListener {
                    val i = packageManager.getLaunchIntentForPackage(packageName)
                    if (i != null) {
                        i.action = ACTION_OPEN_CUSTOMER
                        i.putExtra(EXTRA_NUMBER, number)
                        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                        startActivity(i)
                    }
                    finish()
                }
            }
            card.addView(openBtn)
        }

        val ignoreBtn = Button(this).apply {
            text = "نادیده گرفتن"
            setTextColor(Color.parseColor("#B0B8C8"))
            textSize = 15f
            isAllCaps = false
            val g = GradientDrawable().apply {
                setColor(Color.parseColor("#2A3142"))
                cornerRadius = dp(16).toFloat()
            }
            background = g
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(52)
            )
            setOnClickListener { finish() }
        }
        card.addView(ignoreBtn)

        root.addView(card)
        setContentView(root)
    }

    private fun formatPhone(phone: String): String {
        var p = phone.replace(Regex("[\\s\\-()]"), "")
        if (p.startsWith("+98")) p = "0" + p.substring(3)
        if (p.startsWith("0098")) p = "0" + p.substring(4)
        if (p.startsWith("98") && p.length >= 12) p = "0" + p.substring(2)
        return if (p.length == 11 && p.startsWith("09")) {
            p.substring(0, 4) + " " + p.substring(4, 7) + " " + p.substring(7)
        } else {
            phone
        }
    }

    companion object {
        const val EXTRA_NUMBER = "number"
        const val EXTRA_NAME = "name"
        const val EXTRA_NOTE = "note"
        const val EXTRA_MODE = "mode"
        const val MODE_RINGING = "ringing"
        const val MODE_SAVE = "save"
        const val ACTION_ADD_CUSTOMER = "ir.apadanasleep.customer_callbook.ADD_CUSTOMER"
        const val ACTION_OPEN_CUSTOMER = "ir.apadanasleep.customer_callbook.OPEN_CUSTOMER"
    }
}
