package ir.apadanasleep.customer_callbook

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.CallLog
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import androidx.core.app.NotificationCompat
import org.json.JSONArray

/**
 * سرویس پیش‌زمینه — تنها راه قابل‌اعتماد شناسایی تماس وقتی اپ بسته است.
 */
class CallMonitorService : Service() {
    private var tm: TelephonyManager? = null
    private var lastState = TelephonyManager.CALL_STATE_IDLE
    private var lastNumber: String? = null
    private var wasRinging = false
    private val handler = Handler(Looper.getMainLooper())
    private var modernCallback: TelephonyCallback? = null
    private var legacyListener: PhoneStateListener? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        startAsForeground()
        startListen()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopListen()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        startAsForeground()
        if (tm == null) startListen()
        return START_STICKY
    }

    private fun startAsForeground() {
        val chId = "call_monitor_fg"
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                chId,
                "مانیتور تماس",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "سرویس شناسایی تماس فعال است"
                setShowBadge(false)
            }
            nm.createNotificationChannel(ch)
        }
        val open = packageManager.getLaunchIntentForPackage(packageName)
        val pi = if (open != null) {
            PendingIntent.getActivity(
                this, 0, open,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        } else null
        val n = NotificationCompat.Builder(this, chId)
            .setSmallIcon(android.R.drawable.sym_call_incoming)
            .setContentTitle("دفترچه مشتریان")
            .setContentText("شناسایی تماس فعال است")
            .setOngoing(true)
            .setContentIntent(pi)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(9001, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL)
        } else {
            startForeground(9001, n)
        }
    }

    private fun startListen() {
        tm = getSystemService(TELEPHONY_SERVICE) as TelephonyManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val cb = object : TelephonyCallback(), TelephonyCallback.CallStateListener {
                override fun onCallStateChanged(state: Int) {
                    handleState(state, null)
                }
            }
            modernCallback = cb
            try {
                tm?.registerTelephonyCallback(mainExecutor, cb)
            } catch (e: SecurityException) {
                startLegacy()
            }
        } else {
            startLegacy()
        }
    }

    @Suppress("DEPRECATION")
    private fun startLegacy() {
        legacyListener = object : PhoneStateListener() {
            @Deprecated("Deprecated in Java")
            override fun onCallStateChanged(state: Int, phoneNumber: String?) {
                handleState(state, phoneNumber)
            }
        }
        try {
            tm?.listen(legacyListener, PhoneStateListener.LISTEN_CALL_STATE)
        } catch (_: Exception) {
        }
    }

    private fun handleState(state: Int, phoneNumber: String?) {
        if (!phoneNumber.isNullOrBlank()) lastNumber = phoneNumber

        when (state) {
            TelephonyManager.CALL_STATE_RINGING -> {
                wasRinging = true
                if (!phoneNumber.isNullOrBlank()) lastNumber = phoneNumber
                // اگر شماره نبود کمی بعد از لاگ بخوان
                val num = lastNumber
                if (!num.isNullOrBlank()) {
                    onIncoming(num)
                } else {
                    handler.postDelayed({
                        val n = lastNumber ?: readLatestNumber()
                        if (!n.isNullOrBlank()) {
                            lastNumber = n
                            onIncoming(n)
                        }
                    }, 800)
                }
            }
            TelephonyManager.CALL_STATE_OFFHOOK -> {
                if (!phoneNumber.isNullOrBlank()) lastNumber = phoneNumber
            }
            TelephonyManager.CALL_STATE_IDLE -> {
                if (lastState == TelephonyManager.CALL_STATE_IDLE) return
                val incoming = wasRinging
                wasRinging = false
                val num = lastNumber ?: readLatestNumber()
                lastNumber = null
                if (incoming && !num.isNullOrBlank()) {
                    // بعد از قطع تماس ورودی
                    handler.postDelayed({ onCallEnded(num) }, 500)
                }
            }
        }
        lastState = state
    }

    private fun onIncoming(number: String) {
        val c = findCustomer(number)
        if (c != null) {
            CallOverlayService.show(this, number, c.first, c.third, CallOverlayService.MODE_RING)
        } else {
            CallOverlayService.show(this, number, null, null, CallOverlayService.MODE_RING)
        }
        savePending(number, "ringing")
    }

    private fun onCallEnded(number: String) {
        val c = findCustomer(number)
        if (c == null) {
            savePending(number, "save")
            CallOverlayService.show(this, number, null, null, CallOverlayService.MODE_SAVE)
        }
    }

    private fun savePending(number: String, mode: String) {
        try {
            getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
                .edit()
                .putString("flutter.pending_add_phone", number)
                .putString("flutter.pending_add_mode", mode)
                .apply()
        } catch (_: Exception) {
        }
    }

    private fun readLatestNumber(): String? {
        return try {
            contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                arrayOf(CallLog.Calls.NUMBER, CallLog.Calls.TYPE, CallLog.Calls.DATE),
                null, null,
                CallLog.Calls.DATE + " DESC"
            )?.use {
                if (it.moveToFirst()) it.getString(0) else null
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun findCustomer(phone: String): Triple<String, String, String?>? {
        return try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
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

    private fun stopListen() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                modernCallback?.let { tm?.unregisterTelephonyCallback(it) }
            } else {
                @Suppress("DEPRECATION")
                legacyListener?.let { tm?.listen(it, PhoneStateListener.LISTEN_NONE) }
            }
        } catch (_: Exception) {
        }
        modernCallback = null
        legacyListener = null
        tm = null
    }

    override fun onDestroy() {
        stopListen()
        super.onDestroy()
    }

    companion object {
        const val ACTION_STOP = "ir.apadanasleep.customer_callbook.STOP_MONITOR"

        fun start(context: Context) {
            val i = Intent(context, CallMonitorService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(i)
            } else {
                context.startService(i)
            }
        }

        fun stop(context: Context) {
            val i = Intent(context, CallMonitorService::class.java).apply { action = ACTION_STOP }
            context.startService(i)
        }
    }
}
