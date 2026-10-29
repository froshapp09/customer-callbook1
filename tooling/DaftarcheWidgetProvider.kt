package ir.apadanasleep.customer_callbook

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.widget.RemoteViews

class DaftarcheWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (id in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, id)
        }
    }

    companion object {
        private const val PREFS = "HomeWidgetPreferences"
        // home_widget package uses flutter.group or HomeWidgetPreferences depending on version
        private const val PREFS_ALT = "HomeWidgetPreferences"

        fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val views = RemoteViews(context.packageName, R.layout.daftarche_widget)
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val count = prefs.getString("widget_count", "0") ?: "0"
            val line1 = prefs.getString("widget_line1", "تماسی ثبت نشده") ?: "تماسی ثبت نشده"
            val line2 = prefs.getString("widget_line2", "") ?: ""
            val line3 = prefs.getString("widget_line3", "") ?: ""

            views.setTextViewText(R.id.widget_count, count)
            views.setTextViewText(R.id.widget_line1, line1)
            views.setTextViewText(R.id.widget_line2, line2)
            views.setTextViewText(R.id.widget_line3, line3)

            val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (intent != null) {
                val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                val pi = PendingIntent.getActivity(context, 0, intent, flags)
                views.setOnClickPendingIntent(R.id.widget_root, pi)
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
