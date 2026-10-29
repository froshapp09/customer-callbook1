package ir.apadanasleep.customer_callbook

import android.widget.RemoteViews

import android.appwidget.AppWidgetProvider

import android.appwidget.AppWidgetManager

import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.database.Cursor
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.CallLog
import android.provider.ContactsContract
import android.provider.MediaStore
import android.provider.Settings
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import android.text.SpannableString
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import org.json.JSONArray

class MainActivity : FlutterActivity() {
    private val methodChannelName = "ir.apadanasleep.customer_callbook/call_log"
    private val eventChannelName = "ir.apadanasleep.customer_callbook/phone_state"

    private var eventSink: EventChannel.EventSink? = null
    private var receiver: BroadcastReceiver? = null
    private var lastState = TelephonyManager.CALL_STATE_IDLE
    private var lastNumber: String? = null
    private var pendingAddNumber: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureAddIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureAddIntent(intent)
    }

    private fun captureAddIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action ?: return
        if (action == ACTION_ADD_CUSTOMER || action == ACTION_OPEN_CUSTOMER) {
            pendingAddNumber = intent.getStringExtra(EXTRA_NUMBER)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ir.apadanasleep.customer_callbook/bazaar_billing")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "purchase", "restore" -> {
                        // اسکلت: بعد از افزودن Poolakey اینجا وصل شود
                        result.success(false)
                    }
                    else -> result.notImplemented()
                }
            }


        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openOverlayPermission" -> {
                        try {
                            val uri = Uri.parse("package:$packageName")
                            val i = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, uri)
                            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(i)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    "canDrawOverlays" -> {
                        result.success(Settings.canDrawOverlays(this))
                    }
                    "clearPendingAddPhone" -> {
                        pendingAddNumber = null
                        try {
                            getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
                                .edit()
                                .remove("flutter.pending_add_phone")
                                .remove("flutter.pending_add_mode")
                                .apply()
                        } catch (_: Exception) {}
                        result.success(true)
                    }
                    "getPendingAddPhone" -> {
                        var n = pendingAddNumber
                        pendingAddNumber = null
                        if (n.isNullOrBlank()) {
                            try {
                                val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
                                n = prefs.getString("flutter.pending_add_phone", null)
                                if (!n.isNullOrBlank()) {
                                    prefs.edit()
                                        .remove("flutter.pending_add_phone")
                                        .remove("flutter.pending_add_mode")
                                        .apply()
                                }
                            } catch (_: Exception) {
                            }
                        }
                        result.success(n)
                    }
                    "getRecentCalls" -> {
                        try {
                            val days = call.argument<Int>("days") ?: 2
                            result.success(getRecentCalls(days))
                        } catch (e: SecurityException) {
                            result.error("PERMISSION", "need call log permission", null)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    "startCallMonitor" -> {
                        try {
                            val i = Intent(this, CallMonitorService::class.java)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(i)
                            } else {
                                startService(i)
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    "stopCallMonitor" -> {
                        try {
                            val i = Intent(this, CallMonitorService::class.java)
                            i.action = CallMonitorService.ACTION_STOP
                            startService(i)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    "startPhoneListen" -> {
                        try {
                            startReceiver()
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    "stopPhoneListen" -> {
                        try {
                            stopReceiver()
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    "saveBackupFile", "saveToDownloads" -> {
                        try {
                            val name = call.argument<String>("name")
                                ?: call.argument<String>("fileName")
                                ?: "daftarche_backup.json"
                            val content = call.argument<String>("content") ?: ""
                            val path = saveBackup(name, content)
                            result.success(path)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                                        "updateWidget" -> {
                        try {
                            val mgr = android.appwidget.AppWidgetManager.getInstance(this)
                            val cn = android.content.ComponentName(this, DaftarcheWidgetProvider::class.java)
                            val ids = mgr.getAppWidgetIds(cn)
                            for (id in ids) {
                                DaftarcheWidgetProvider.updateOne(this, mgr, id)
                            }
                            result.success(ids.size)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
    }

    private fun startReceiver() {
        if (receiver != null) return
        receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action != TelephonyManager.ACTION_PHONE_STATE_CHANGED) return
                val stateStr = intent.getStringExtra(TelephonyManager.EXTRA_STATE) ?: return
                val number = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER)

                val state = when (stateStr) {
                    TelephonyManager.EXTRA_STATE_RINGING -> TelephonyManager.CALL_STATE_RINGING
                    TelephonyManager.EXTRA_STATE_OFFHOOK -> TelephonyManager.CALL_STATE_OFFHOOK
                    TelephonyManager.EXTRA_STATE_IDLE -> TelephonyManager.CALL_STATE_IDLE
                    else -> return
                }

                if (state == TelephonyManager.CALL_STATE_RINGING) {
                    lastNumber = number
                    val map = hashMapOf<String, Any?>(
                        "status" to "incoming",
                        "number" to (number ?: lastNumber ?: "")
                    )
                    runOnUiThread { eventSink?.success(map) }
                } else if (state == TelephonyManager.CALL_STATE_IDLE && lastState != TelephonyManager.CALL_STATE_IDLE) {
                    val map = hashMapOf<String, Any?>(
                        "status" to "idle",
                        "number" to (lastNumber ?: "")
                    )
                    runOnUiThread { eventSink?.success(map) }
                    lastNumber = null
                }
                lastState = state
            }
        }
        val filter = IntentFilter(TelephonyManager.ACTION_PHONE_STATE_CHANGED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(receiver, filter)
        }
    }

    private fun stopReceiver() {
        try {
            receiver?.let { unregisterReceiver(it) }
        } catch (_: Exception) {
        }
        receiver = null
    }

    override fun onDestroy() {
        stopReceiver()
        super.onDestroy()
    }

    private fun getRecentCalls(days: Int): List<Map<String, Any?>> {
        val out = mutableListOf<Map<String, Any?>>()
        val from = System.currentTimeMillis() - days.toLong() * 24L * 60L * 60L * 1000L
        val projection = arrayOf(
            CallLog.Calls.NUMBER,
            CallLog.Calls.CACHED_NAME,
            CallLog.Calls.TYPE,
            CallLog.Calls.DATE,
            CallLog.Calls.DURATION
        )
        val cursor: Cursor? = contentResolver.query(
            CallLog.Calls.CONTENT_URI,
            projection,
            "${CallLog.Calls.DATE} >= ?",
            arrayOf(from.toString()),
            "${CallLog.Calls.DATE} DESC"
        )
        cursor?.use {
            val idxNum = it.getColumnIndex(CallLog.Calls.NUMBER)
            val idxName = it.getColumnIndex(CallLog.Calls.CACHED_NAME)
            val idxType = it.getColumnIndex(CallLog.Calls.TYPE)
            val idxDate = it.getColumnIndex(CallLog.Calls.DATE)
            var count = 0
            while (it.moveToNext() && count < 200) {
                val number = if (idxNum >= 0) it.getString(idxNum) else null
                val name = if (idxName >= 0) it.getString(idxName) else null
                val typeInt = if (idxType >= 0) it.getInt(idxType) else 0
                val date = if (idxDate >= 0) it.getLong(idxDate) else 0L
                val type = when (typeInt) {
                    CallLog.Calls.INCOMING_TYPE -> "incoming"
                    CallLog.Calls.OUTGOING_TYPE -> "outgoing"
                    CallLog.Calls.MISSED_TYPE -> "missed"
                    CallLog.Calls.REJECTED_TYPE -> "rejected"
                    else -> "other"
                }
                out.add(
                    mapOf(
                        "number" to (number ?: ""),
                        "name" to (name ?: ""),
                        "type" to type,
                        "timestamp" to date
                    )
                )
                count++
            }
        }
        return out
    }

    private fun saveBackup(fileName: String, content: String): String {
        val safeName = fileName.replace(Regex("[\\/]+"), "_")
        val bytes = content.toByteArray(Charsets.UTF_8)
        val mime = when {
            safeName.endsWith(".csv", true) -> "text/csv"
            safeName.endsWith(".txt", true) -> "text/plain"
            else -> "application/json"
        }
        val relative = Environment.DIRECTORY_DOWNLOADS + "/Daftarche"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // حذف نسخه قبلی هم‌نام در MediaStore (اختیاری)
            try {
                contentResolver.delete(
                    MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                    MediaStore.MediaColumns.DISPLAY_NAME + "=?",
                    arrayOf(safeName)
                )
            } catch (_: Exception) {}
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, safeName)
                put(MediaStore.MediaColumns.MIME_TYPE, mime)
                put(MediaStore.MediaColumns.RELATIVE_PATH, relative)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw Exception("ساخت فایل در دانلود ممکن نشد")
            contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: throw Exception("نوشتن فایل ممکن نشد")
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            contentResolver.update(uri, values, null, null)
            return "Download/Daftarche/$safeName"
        }
        val base = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        val dir = File(base, "Daftarche")
        if (!dir.exists()) dir.mkdirs()
        val file = File(dir, safeName)
        FileOutputStream(file).use { it.write(bytes) }
        return file.absolutePath
    }

    companion object {
        const val ACTION_ADD_CUSTOMER = "ir.apadanasleep.customer_callbook.ADD_CUSTOMER"
        const val ACTION_OPEN_CUSTOMER = "ir.apadanasleep.customer_callbook.OPEN_CUSTOMER"
        const val EXTRA_NUMBER = "number"
    }
}

class CallMonitorService : Service() {
    private var tm: TelephonyManager? = null
    private var lastState = TelephonyManager.CALL_STATE_IDLE
    private var lastNumber: String? = null
    private var wasRinging = false
    private var lastWasIncoming = false
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
            .setContentTitle("فروشیار")
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
                lastWasIncoming = true
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
                if (!wasRinging) lastWasIncoming = false
                if (!phoneNumber.isNullOrBlank()) lastNumber = phoneNumber
                // تماس پاسخ داده شد — بنر زنگ را بردار
                try {
                    val d = Intent(this, CallOverlayService::class.java).apply { action = CallOverlayService.ACTION_DISMISS }
                    startService(d)
                } catch (_: Exception) {}
            }
            TelephonyManager.CALL_STATE_IDLE -> {
                if (lastState == TelephonyManager.CALL_STATE_IDLE) return
                wasRinging = false
                // ورودی یا خروجی — اگر شماره در دفترچه نبود پیشنهاد ذخیره
                var num = lastNumber
                if (num.isNullOrBlank()) {
                    // کمی صبر تا لاگ تماس گوشی به‌روز شود
                    handler.postDelayed({
                        val n = lastNumber ?: readLatestNumber()
                        lastNumber = null
                        if (!n.isNullOrBlank()) onCallEnded(n)
                    }, 800)
                } else {
                    lastNumber = null
                    handler.postDelayed({ onCallEnded(num!!) }, 500)
                }
            }
        }
        lastState = state
    }

    private fun onIncoming(number: String) {
        val c = findCustomer(number)
        if (c != null) {
            CallOverlayService.show(this, number, c.first, c.third, CallOverlayService.MODE_RING)
            // شماره در دفترچه — pending ذخیره نگذار
        } else {
            val contactName = lookupContactName(number)
            if (contactName != null) {
                // مخاطب گوشی — فقط نام نشان بده، بعداً پیشنهاد ذخیره نده
                CallOverlayService.show(this, number, contactName, "مخاطب گوشی", CallOverlayService.MODE_RING)
            } else {
                CallOverlayService.show(this, number, null, null, CallOverlayService.MODE_RING)
                savePending(number, "ringing")
            }
        }
    }

    private fun lookupContactName(phone: String): String? {
        return try {
            val key = matchKey(phone)
            if (key.isEmpty()) return null
            val uri = android.provider.ContactsContract.CommonDataKinds.Phone.CONTENT_URI
            contentResolver.query(
                uri,
                arrayOf(
                    android.provider.ContactsContract.CommonDataKinds.Phone.NUMBER,
                    android.provider.ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME
                ),
                null, null, null
            )?.use { cursor ->
                val idxN = cursor.getColumnIndex(android.provider.ContactsContract.CommonDataKinds.Phone.NUMBER)
                val idxName = cursor.getColumnIndex(android.provider.ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)
                if (idxN < 0) return null
                while (cursor.moveToNext()) {
                    val n = cursor.getString(idxN) ?: continue
                    if (matchKey(n) == key) {
                        val name = if (idxName >= 0) cursor.getString(idxName) else null
                        if (!name.isNullOrBlank()) return name
                    }
                }
            }
            null
        } catch (_: Exception) {
            null
        }
    }

    private fun onCallEnded(number: String) {
        // اعلان‌های موقت تماس را پاک کن
        try {
            val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            nm.cancel(2010)
            nm.cancel(2011)
            nm.cancel(42)
            for (id in 2000..2020) nm.cancel(id)
        } catch (_: Exception) {}

        // ۱) مشتری دفترچه اپ؟
        val c = findCustomer(number)
        if (c != null) {
            if (isResultPopupEnabled()) {
                CallOverlayService.show(this, number, c.first, c.third, CallOverlayService.MODE_RESULT)
            }
            return
        }
        // ۲) فقط مخاطب گوشی → هیچ پاپ‌آپ نتیجه/ذخیره
        if (isInDeviceContacts(number)) return
        // ۳) کاملاً ناشناس → پیشنهاد ذخیره
        savePending(number, "save", if (lastWasIncoming) "1" else "2")
        CallOverlayService.show(this, number, null, null, CallOverlayService.MODE_SAVE)
    }

    private fun isResultPopupEnabled(): Boolean {
        return try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
            // پیش‌فرض روشن؛ اگر کاربر خاموش کرده false
            if (prefs.contains("flutter.show_result_popup")) {
                prefs.getBoolean("flutter.show_result_popup", true)
            } else {
                true
            }
        } catch (_: Exception) {
            true
        }
    }

    private fun isInDeviceContacts(phone: String): Boolean {
        return try {
            val key = matchKey(phone)
            if (key.isEmpty()) return false
            val uri = android.provider.ContactsContract.CommonDataKinds.Phone.CONTENT_URI
            contentResolver.query(
                uri,
                arrayOf(android.provider.ContactsContract.CommonDataKinds.Phone.NUMBER),
                null, null, null
            )?.use { cursor ->
                val idx = cursor.getColumnIndex(android.provider.ContactsContract.CommonDataKinds.Phone.NUMBER)
                if (idx < 0) return false
                while (cursor.moveToNext()) {
                    val n = cursor.getString(idx) ?: continue
                    if (matchKey(n) == key) return true
                }
            }
            false
        } catch (_: Exception) {
            false
        }
    }

    private fun savePending(number: String, mode: String, callType: String = "1") {
        try {
            getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
                .edit()
                .putString("flutter.pending_add_phone", number)
                .putString("flutter.pending_add_mode", mode)
                .putString("flutter.pending_add_call_type", callType)
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
        // ۱) دفترچه اپ
        try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
            val raw = prefs.getString("flutter.customers_v2", null)
            if (raw != null) {
                val arr = JSONArray(raw)
                val key = matchKey(phone)
                for (i in 0 until arr.length()) {
                    val o = arr.getJSONObject(i)
                    val p = matchKey(o.optString("phone", ""))
                    if (p.isNotEmpty() && p == key) {
                        return Triple(
                            o.optString("name", phone).ifBlank { phone },
                            o.optString("tag", ""),
                            o.optString("note", null)
                        )
                    }
                }
            }
        } catch (_: Exception) {
        }
        // فقط دفترچه اپ — مخاطب گوشی مشتری اپ نیست
        return null
    }

    private fun findDeviceContactName(context: Context, phone: String): String? {
        return try {
            val uri = android.net.Uri.withAppendedPath(
                ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
                android.net.Uri.encode(phone)
            )
            context.contentResolver.query(
                uri,
                arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME),
                null, null, null
            )?.use {
                if (it.moveToFirst()) {
                    val n = it.getString(0)
                    if (!n.isNullOrBlank()) return n
                }
            }
            // fallback: ۱۰ رقم آخر
            val key = matchKey(phone)
            if (key.length < 8) return null
            context.contentResolver.query(
                ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                arrayOf(
                    ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                    ContactsContract.CommonDataKinds.Phone.NUMBER
                ),
                null, null, null
            )?.use {
                while (it.moveToNext()) {
                    val num = it.getString(1) ?: continue
                    if (matchKey(num) == key) {
                        val n = it.getString(0)
                        if (!n.isNullOrBlank()) return n
                    }
                }
            }
            null
        } catch (_: Exception) {
            null
        }
    }

    private fun normalize(phone: String): String {
        var p = phone
        val fa = "۰۱۲۳۴۵۶۷۸۹"
        val ar = "٠١٢٣٤٥٦٧٨٩"
        for (i in 0..9) {
            p = p.replace(fa[i].toString(), i.toString()).replace(ar[i].toString(), i.toString())
        }
        p = p.replace(Regex("[^\\d+]"), "")
        if (p.startsWith("+98")) p = "0" + p.substring(3)
        if (p.startsWith("0098")) p = "0" + p.substring(4)
        if (p.startsWith("98") && p.length >= 12) p = "0" + p.substring(2)
        if (p.startsWith("9") && p.length == 10) p = "0" + p
        return p
    }

    private fun matchKey(phone: String): String {
        val p = normalize(phone)
        return if (p.length >= 10) p.takeLast(10) else p
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
        remove() // پاک کردن هر overlay قبلی
        when {
            mode == MODE_RING || mode == "ringing" -> showTopBanner(number, name, note)
            mode == MODE_RESULT || mode == "result" -> showResultDialog(number, name, note)
            else -> showCenterDialog(number, name, note, mode)
        }
        return START_NOT_STICKY
    }

    private fun showTopBanner(number: String, name: String?, note: String?) {
        if (!Settings.canDrawOverlays(this)) {
            stopSelf()
            return
        }
        remove()
        wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val density = resources.displayMetrics.density
        fun dp(v: Int) = (v * density).toInt()
        val known = !name.isNullOrBlank()

        // بنر فشرده مثل اعلان سیستم — فقط اطلاعات، بدون دکمه‌های بزرگ
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#F21A1F2E"))
                cornerRadius = dp(16).toFloat()
                setStroke(dp(1), Color.parseColor("#40FFFFFF"))
            }
            setPadding(dp(14), dp(10), dp(14), dp(10))
        }

        val texts = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        }
        texts.addView(TextView(this).apply {
            text = if (known) name else "مشتری ناشناس"
            setTextColor(Color.parseColor("#FF8C3A"))
            textSize = 14f
            typeface = Typeface.DEFAULT_BOLD
            maxLines = 1
        })
        texts.addView(TextView(this).apply {
            text = "\u200E" + formatPhone(number) + if (known) " · مخاطب" else ""
            setTextColor(Color.WHITE)
            textSize = 12f
            maxLines = 1
        })
        card.addView(texts)

        // فقط X کوچک
        card.addView(TextView(this).apply {
            text = "✕"
            setTextColor(Color.parseColor("#B0B8C8"))
            textSize = 16f
            setPadding(dp(12), dp(4), dp(4), dp(4))
            setOnClickListener {
                remove()
                stopSelf()
            }
        })
        root = card

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            y = dp(12)
            width = resources.displayMetrics.widthPixels - dp(20)
        }
        try {
            wm?.addView(card, params)
            // خودکار بعد از ۸ ثانیه بسته شود تا مزاحم نباشد
            Handler(Looper.getMainLooper()).postDelayed({
                try {
                    remove()
                    stopSelf()
                } catch (_: Exception) {
                }
            }, 8000)
        } catch (_: Exception) {
            stopSelf()
        }
    }


    private fun showResultDialog(number: String, name: String?, note: String?) {
        if (!Settings.canDrawOverlays(this)) {
            stopSelf()
            return
        }
        remove()
        wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val density = resources.displayMetrics.density
        fun dp(v: Int) = (v * density).toInt()

        val container = FrameLayout(this).apply {
            setBackgroundColor(Color.parseColor("#44000A12"))
            isClickable = true
        }
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#1A1F2E"))
                cornerRadius = dp(24).toFloat()
            }
            setPadding(dp(20), dp(20), dp(20), dp(16))
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                gravity = Gravity.CENTER
                marginStart = dp(20)
                marginEnd = dp(20)
            }
        }
        card.addView(TextView(this).apply {
            text = name ?: "مشتری"
            setTextColor(Color.parseColor("#FF8C3A"))
            textSize = 18f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
        })
        card.addView(TextView(this).apply {
            text = "نتیجه این تماس؟"
            setTextColor(Color.parseColor("#99A0B0"))
            textSize = 13f
            gravity = Gravity.CENTER
            setPadding(0, dp(6), 0, dp(14))
        })
        fun statusBtn(label: String, status: String, color: Int) {
            card.addView(makeBtn(label, color) {
                try {
                    getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE).edit()
                        .putString("flutter.pending_status_phone", number)
                        .putString("flutter.pending_status_value", status)
                        .apply()
                } catch (_: Exception) {}
                val i = Intent(this, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                }
                startActivity(i)
                remove()
                stopSelf()
            })
        }
        statusBtn("در حال پیگیری", "در حال پیگیری", Color.parseColor("#F59E0B"))
        statusBtn("در حال مذاکره", "در حال مذاکره", Color.parseColor("#8B5CF6"))
        statusBtn("موفق", "موفق", Color.parseColor("#22C55E"))
        statusBtn("از دست رفته", "از دست رفته", Color.parseColor("#EF4444"))
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
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED,
            PixelFormat.TRANSLUCENT
        )
        try {
            wm?.addView(container, params)
        } catch (_: Exception) {
            stopSelf()
        }
    }

    private fun showCenterDialog(number: String, name: String?, note: String?, mode: String) {
        // فقط بعد از قطع تماس — هرگز وسط زنگ
        if (mode == MODE_RING || mode == "ringing") {
            showTopBanner(number, name, note)
            return
        }
        if (!Settings.canDrawOverlays(this)) {
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
            // نیمه‌شفاف ولی لمس بیرون روی دکمه‌های سیستم را نگیرد زیاد — بعد از تماس اوکی است
            setBackgroundColor(Color.parseColor("#66000A12"))
            isClickable = true
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
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                gravity = Gravity.CENTER
                marginStart = dp(20)
                marginEnd = dp(20)
            }
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
        }
        card.addView(title)

        val phoneTv = TextView(this).apply {
            text = "\u200E" + formatPhone(number)
            setTextColor(Color.WHITE)
            textSize = 20f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding(0, dp(8), 0, dp(8))
        }
        card.addView(phoneTv)

        val sub = TextView(this).apply {
            text = when {
                known && !note.isNullOrBlank() -> note
                known -> "در دفترچه شماست"
                else -> "این شماره در دفترچه شما ثبت نشده"
            }
            setTextColor(Color.parseColor("#99A0B0"))
            textSize = 13f
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, dp(20))
        }
        card.addView(sub)

        if (!known) {
            card.addView(makeBtn("ثبت مشتری", Color.parseColor("#00C2D8")) {
                val i = Intent(this, MainActivity::class.java).apply {
                    action = MainActivity.ACTION_ADD_CUSTOMER
                    putExtra(MainActivity.EXTRA_NUMBER, number)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                }
                startActivity(i)
                remove()
                stopSelf()
            })
        } else if (note == "از مخاطبین گوشی") {
            // فقط مخاطب گوشی است — نیازی به ذخیره در اپ نیست
            card.addView(makeBtn("متوجه شدم", Color.parseColor("#2A3142"), Color.parseColor("#B0B8C8")) {
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
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            PixelFormat.TRANSLUCENT
        )
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
        const val MODE_RESULT = "result"
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
                text = "ثبت مشتری"
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
                    return
                }
                lastWasIncoming = true
                lastNumber = number
                val c = findCustomer(context, number)
                if (c != null) {
                    openAlert(context, number, c.first, c.third, MODE_RING)
                } else {
                    val contactName = lookupContactName(context, number)
                    if (contactName != null) {
                        openAlert(context, number, contactName, "مخاطب گوشی", MODE_RING)
                    } else {
                        openAlert(context, number, null, null, MODE_RING)
                        savePending(context, number, MODE_RING)
                    }
                }
            }
            TelephonyManager.EXTRA_STATE_OFFHOOK -> {
                // پاسخ یا خروجی
                if (!number.isNullOrBlank()) {
                    lastNumber = number
                } else if (lastNumber.isNullOrBlank()) {
                    // تماس خروجی — شماره را از آخرین لاگ بگیر
                    val latest = lastKnownNumber(context)
                    if (!latest.isNullOrBlank()) lastNumber = latest
                }
            }
            TelephonyManager.EXTRA_STATE_IDLE -> {
                val n = when {
                    !number.isNullOrBlank() -> number
                    !lastNumber.isNullOrBlank() -> lastNumber
                    else -> lastKnownNumber(context)
                } ?: return

                lastWasIncoming = false
                lastNumber = null

                // پاک کردن اعلان‌های تماس
                try {
                    val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    for (id in 2000..2020) nm.cancel(id)
                } catch (_: Exception) {}
                // ورودی یا خروجی: مشتری دفترچه → نتیجه؛ ناشناس → ذخیره
                val c = findCustomer(context, n)
                if (c != null) {
                    val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    val enabled = if (prefs.contains("flutter.show_result_popup"))
                        prefs.getBoolean("flutter.show_result_popup", true) else true
                    if (enabled) openAlert(context, n, c.first, c.third, "result")
                } else if (isInDeviceContacts(context, n)) {
                    // مخاطب گوشی — پیشنهاد ذخیره نه
                } else {
                    savePending(context, n, MODE_SAVE, "1")
                    openAlert(context, n, null, null, MODE_SAVE)
                }
            }
        }
    }

    private fun savePending(context: Context, number: String, mode: String, callType: String = "1") {
        try {
            context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .edit()
                .putString("flutter.pending_add_phone", number)
                .putString("flutter.pending_add_mode", mode)
                .putString("flutter.pending_add_call_type", callType)
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
        try {
            CallOverlayService.show(context, number, name, note, mode)
        } catch (_: Exception) {
            // هنگام زنگ Activity تمام‌صفحه باز نکن — پاسخ تماس قطع می‌شود
            if (mode == MODE_RING || mode == "ringing") return
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
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "اطلاع تماس و ذخیره مشتری"
                setShowBadge(false)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                enableVibration(false)
                setSound(null, null)
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
            // no fullScreenIntent — blocks answering the call
            // // fullScreen disabled

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
        try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val raw = prefs.getString("flutter.customers_v2", null)
            if (raw != null) {
                val arr = JSONArray(raw)
                val key = matchKey(phone)
                for (i in 0 until arr.length()) {
                    val o = arr.getJSONObject(i)
                    val p = matchKey(o.optString("phone", ""))
                    if (p.isNotEmpty() && p == key) {
                        return Triple(
                            o.optString("name", phone).ifBlank { phone },
                            o.optString("tag", ""),
                            o.optString("note", null)
                        )
                    }
                }
            }
        } catch (_: Exception) {
        }
        // فقط دفترچه اپ
        return null
    }

    private fun findDeviceContactName(context: Context, phone: String): String? {
        return try {
            val uri = android.net.Uri.withAppendedPath(
                ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
                android.net.Uri.encode(phone)
            )
            context.contentResolver.query(
                uri,
                arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME),
                null, null, null
            )?.use {
                if (it.moveToFirst()) {
                    val n = it.getString(0)
                    if (!n.isNullOrBlank()) return n
                }
            }
            val key = matchKey(phone)
            if (key.length < 8) return null
            context.contentResolver.query(
                ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                arrayOf(
                    ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                    ContactsContract.CommonDataKinds.Phone.NUMBER
                ),
                null, null, null
            )?.use {
                while (it.moveToNext()) {
                    val num = it.getString(1) ?: continue
                    if (matchKey(num) == key) {
                        val n = it.getString(0)
                        if (!n.isNullOrBlank()) return n
                    }
                }
            }
            null
        } catch (_: Exception) {
            null
        }
    }

    private fun normalize(phone: String): String {
        var p = phone
        val fa = "۰۱۲۳۴۵۶۷۸۹"
        val ar = "٠١٢٣٤٥٦٧٨٩"
        for (i in 0..9) {
            p = p.replace(fa[i].toString(), i.toString()).replace(ar[i].toString(), i.toString())
        }
        p = p.replace(Regex("[^\\d+]"), "")
        if (p.startsWith("+98")) p = "0" + p.substring(3)
        if (p.startsWith("0098")) p = "0" + p.substring(4)
        if (p.startsWith("98") && p.length >= 12) p = "0" + p.substring(2)
        if (p.startsWith("9") && p.length == 10) p = "0" + p
        return p
    }

    private fun matchKey(phone: String): String {
        val p = normalize(phone)
        return if (p.length >= 10) p.takeLast(10) else p
    }

    private fun formatPhone(phone: String): String {
        val p = normalize(phone)
        return if (p.length == 11 && p.startsWith("09")) {
            p.substring(0, 4) + " " + p.substring(4, 7) + " " + p.substring(7)
        } else p
    }

    private fun lookupContactName(context: Context, phone: String): String? {
        return try {
            val key = matchKey(phone)
            if (key.isEmpty()) return null
            val uri = android.provider.ContactsContract.CommonDataKinds.Phone.CONTENT_URI
            context.contentResolver.query(
                uri,
                arrayOf(
                    android.provider.ContactsContract.CommonDataKinds.Phone.NUMBER,
                    android.provider.ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME
                ),
                null, null, null
            )?.use { cursor ->
                val idxN = cursor.getColumnIndex(android.provider.ContactsContract.CommonDataKinds.Phone.NUMBER)
                val idxName = cursor.getColumnIndex(android.provider.ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)
                if (idxN < 0) return null
                while (cursor.moveToNext()) {
                    val n = cursor.getString(idxN) ?: continue
                    if (matchKey(n) == key) {
                        val name = if (idxName >= 0) cursor.getString(idxName) else null
                        if (!name.isNullOrBlank()) return name
                    }
                }
            }
            null
        } catch (_: Exception) {
            null
        }
    }

    private fun isInDeviceContacts(context: Context, phone: String): Boolean {
        return try {
            val key = matchKey(phone)
            if (key.isEmpty()) return false
            val uri = android.provider.ContactsContract.CommonDataKinds.Phone.CONTENT_URI
            context.contentResolver.query(
                uri,
                arrayOf(android.provider.ContactsContract.CommonDataKinds.Phone.NUMBER),
                null, null, null
            )?.use { cursor ->
                val idx = cursor.getColumnIndex(android.provider.ContactsContract.CommonDataKinds.Phone.NUMBER)
                if (idx < 0) return false
                while (cursor.moveToNext()) {
                    val n = cursor.getString(idx) ?: continue
                    if (matchKey(n) == key) return true
                }
            }
            false
        } catch (_: Exception) {
            false
        }
    }

    companion object {
        @Volatile private var lastNumber: String? = null
        @Volatile private var lastWasIncoming: Boolean = false
        const val MODE_RING = "ringing"
        const val MODE_SAVE = "save"
    }
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        // Manifest PHONE_STATE receiver is enough; boot just ensures app data is warm.
    }
}


class DaftarcheWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (id in appWidgetIds) {
            updateOne(context, appWidgetManager, id)
        }
    }

    companion object {
        private fun rid(context: Context, name: String, type: String): Int {
            return context.resources.getIdentifier(name, type, context.packageName)
        }

        fun updateOne(context: Context, manager: AppWidgetManager, widgetId: Int) {
            val layoutId = rid(context, "daftarche_widget", "layout")
            if (layoutId == 0) return
            val views = RemoteViews(context.packageName, layoutId)

            val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
            val flutterPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            fun data(key: String, fallback: String): String {
                return prefs.getString(key, null)
                    ?: flutterPrefs.getString("flutter.$key", null)
                    ?: fallback
            }

            val count = data("widget_count", "0")
            val line1 = data("widget_line1", "تماس امروزی ثبت نشده")
            val line2 = data("widget_line2", "")
            val line3 = data("widget_line3", "")

            val idCount = rid(context, "widget_count", "id")
            val id1 = rid(context, "widget_line1", "id")
            val id2 = rid(context, "widget_line2", "id")
            val id3 = rid(context, "widget_line3", "id")
            val idRoot = rid(context, "widget_root", "id")

            if (idCount != 0) views.setTextViewText(idCount, count)
            if (id1 != 0) views.setTextViewText(id1, line1)
            if (id2 != 0) views.setTextViewText(id2, line2)
            if (id3 != 0) views.setTextViewText(id3, line3)

            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (launch != null && idRoot != 0) {
                val pi = PendingIntent.getActivity(
                    context, 0, launch,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(idRoot, pi)
            }
            manager.updateAppWidget(widgetId, views)
        }
    }
}
