package ir.apadanasleep.customer_callbook

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.CallLog
import android.telephony.TelephonyManager
import android.text.SpannableString
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import androidx.core.app.NotificationCompat
import org.json.JSONArray

class PhoneStateReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != TelephonyManager.ACTION_PHONE_STATE_CHANGED) return
        val state = intent.getStringExtra(TelephonyManager.EXTRA_STATE) ?: return

        var number = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER)
        if (!number.isNullOrBlank()) {
            lastNumber = number
            lastWasIncoming = (state == TelephonyManager.EXTRA_STATE_RINGING)
        }

        when (state) {
            TelephonyManager.EXTRA_STATE_RINGING -> {
                if (number.isNullOrBlank()) number = lastNumber
                if (number.isNullOrBlank()) {
                    postNotif(context, "تماس ورودی", "شماره در دسترس نیست", null, null, MODE_RING)
                    return
                }
                lastWasIncoming = true
                lastNumber = number
                savePending(context, number, MODE_RING)
                val c = findCustomer(context, number)
                if (c != null) {
                    openAlert(context, number, c.first, c.third, MODE_RING)
                    postNotif(context, "تماس: ${c.first}", ltr(formatPhone(number)), number, c.first, MODE_RING)
                } else {
                    openAlert(context, number, null, null, MODE_RING)
                    postNotif(context, "مشتری ناشناس", ltr(formatPhone(number)) + " · در دفترچه نیست", number, null, MODE_RING)
                }
            }
            TelephonyManager.EXTRA_STATE_OFFHOOK -> {
                // پاسخ داده شد یا تماس خروجی — فقط شماره را نگه دار
                if (!number.isNullOrBlank()) lastNumber = number
            }
            TelephonyManager.EXTRA_STATE_IDLE -> {
                val n = when {
                    !number.isNullOrBlank() -> number
                    !lastNumber.isNullOrBlank() -> lastNumber
                    else -> lastKnownNumber(context)
                } ?: return

                // فقط بعد از تماس ورودی ناشناس پیشنهاد ذخیره بده (نه تماس خروجی)
                if (!lastWasIncoming) {
                    lastNumber = null
                    return
                }
                lastWasIncoming = false
                lastNumber = null

                val c = findCustomer(context, n)
                if (c == null) {
                    savePending(context, n, MODE_SAVE)
                    openAlert(context, n, null, null, MODE_SAVE)
                    postNotif(
                        context,
                        "مشتری جدید",
                        ltr(formatPhone(n)) + " · ذخیره شود؟",
                        n,
                        null,
                        MODE_SAVE
                    )
                }
            }
        }
    }

    private fun savePending(context: Context, number: String, mode: String) {
        try {
            context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .edit()
                .putString("flutter.pending_add_phone", number)
                .putString("flutter.pending_add_mode", mode)
                .apply()
        } catch (_: Exception) {
        }
    }

    private fun openAlert(
        context: Context,
        number: String,
        name: String?,
        note: String?,
        mode: String
    ) {
        // پاپ‌آپ روی صفحه (نه فقط نوار اعلان)
        try {
            CallOverlayService.show(context, number, name, note, mode)
        } catch (_: Exception) {
            try {
                val i = Intent(context, CallAlertActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    putExtra(CallAlertActivity.EXTRA_NUMBER, number)
                    putExtra(CallAlertActivity.EXTRA_MODE, mode)
                    if (name != null) putExtra(CallAlertActivity.EXTRA_NAME, name)
                    if (note != null) putExtra(CallAlertActivity.EXTRA_NOTE, note)
                }
                context.startActivity(i)
            } catch (_: Exception) {
            }
        }
    }

    private fun postNotif(
        context: Context,
        title: String,
        body: String,
        number: String?,
        name: String?,
        mode: String
    ) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channelId = "incoming_calls_v2"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                channelId,
                "تماس‌های ورودی",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "پاپ‌آپ و ذخیره مشتری هنگام تماس"
                setShowBadge(true)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                enableVibration(true)
            }
            nm.createNotificationChannel(ch)
        }

        // باز کردن اپ برای ذخیره (قابل اطمینان‌تر از Activity شفاف)
        val mainIntent = Intent(context, MainActivity::class.java).apply {
            action = MainActivity.ACTION_ADD_CUSTOMER
            putExtra(MainActivity.EXTRA_NUMBER, number ?: "")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        val mainPi = PendingIntent.getActivity(
            context, 2010, mainIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val alertIntent = Intent(context, CallAlertActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra(CallAlertActivity.EXTRA_NUMBER, number ?: "")
            putExtra(CallAlertActivity.EXTRA_MODE, mode)
            if (name != null) putExtra(CallAlertActivity.EXTRA_NAME, name)
        }
        val fullPi = PendingIntent.getActivity(
            context, 2011, alertIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(android.R.drawable.sym_call_incoming)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(true)
            .setContentIntent(mainPi)
            .setFullScreenIntent(fullPi, true)

        if (number != null && name == null) {
            builder.addAction(
                android.R.drawable.ic_input_add,
                "ذخیره در دفترچه",
                mainPi
            )
        }

        nm.notify(2001, builder.build())
    }

    private fun ltr(s: String): String = "\u200E$s\u200E"

    private fun lastKnownNumber(context: Context): String? {
        return try {
            context.contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                arrayOf(CallLog.Calls.NUMBER, CallLog.Calls.TYPE),
                null, null,
                CallLog.Calls.DATE + " DESC"
            )?.use {
                if (it.moveToFirst()) it.getString(0) else null
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun findCustomer(context: Context, phone: String): Triple<String, String, String?>? {
        return try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val raw = prefs.getString("flutter.customers_v2", null) ?: return null
            val arr = JSONArray(raw)
            val norm = normalize(phone)
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                val p = normalize(o.optString("phone", ""))
                if (p.isNotEmpty() && (p == norm || p.endsWith(norm.takeLast(10)) || norm.endsWith(p.takeLast(10)))) {
                    return Triple(
                        o.optString("name", phone).ifBlank { phone },
                        o.optString("tag", ""),
                        o.optString("note", null)
                    )
                }
            }
            null
        } catch (_: Exception) {
            null
        }
    }

    private fun normalize(phone: String): String {
        var p = phone.replace(Regex("[\\s\\-()]"), "")
        if (p.startsWith("+98")) p = "0" + p.substring(3)
        if (p.startsWith("0098")) p = "0" + p.substring(4)
        if (p.startsWith("98") && p.length >= 12) p = "0" + p.substring(2)
        return p
    }

    private fun formatPhone(phone: String): String {
        val p = normalize(phone)
        return if (p.length == 11 && p.startsWith("09")) {
            p.substring(0, 4) + " " + p.substring(4, 7) + " " + p.substring(7)
        } else p
    }

    companion object {
        @Volatile private var lastNumber: String? = null
        @Volatile private var lastWasIncoming: Boolean = false
        const val MODE_RING = "ringing"
        const val MODE_SAVE = "save"
    }
}
