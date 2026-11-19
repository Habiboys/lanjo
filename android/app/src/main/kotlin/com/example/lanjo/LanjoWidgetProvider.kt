package com.example.lanjo

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.widget.RemoteViews

class LanjoWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId)
        }
    }

    companion object {
        const val PREFS_NAME = "lanjo_native_prefs"

        fun updateAllWidgets(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, LanjoWidgetProvider::class.java)
            )
            if (ids != null && ids.isNotEmpty()) {
                for (id in ids) {
                    updateWidget(context, manager, id)
                }
            }
        }

        private fun buildRoutePendingIntent(
            context: Context,
            route: String,
            requestCode: Int
        ): PendingIntent {
            val intent = Intent(
                Intent.ACTION_VIEW,
                Uri.parse("lanjo://route$route"),
                context,
                MainActivity::class.java
            ).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            return PendingIntent.getActivity(context, requestCode, intent, flags)
        }

        fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val title = prefs.getString("widget_title", "AMAN DIBELANJAKAN / HARI")
                ?: "AMAN DIBELANJAKAN / HARI"
            val safeToSpend = prefs.getString("widget_safe_to_spend", "Rp0") ?: "Rp0"
            val todaySpent = prefs.getString(
                "widget_subtitle",
                "Hari ini: Rp0 • Ketuk untuk buka Lanjo"
            ) ?: "Hari ini: Rp0"
            val remainingDays = prefs.getString("widget_badge", "Periode aktif")
                ?: "Periode aktif"

            val views = RemoteViews(context.packageName, R.layout.lanjo_widget)
            views.setTextViewText(R.id.tv_widget_title, title)
            views.setTextViewText(R.id.tv_safe_to_spend, safeToSpend)
            views.setTextViewText(R.id.tv_today_spent, todaySpent)
            views.setTextViewText(R.id.tv_remaining_days, remainingDays)

            views.setOnClickPendingIntent(
                R.id.widget_root,
                buildRoutePendingIntent(context, "/home", 100)
            )
            views.setOnClickPendingIntent(
                R.id.btn_widget_expense,
                buildRoutePendingIntent(context, "/transactions/new?type=expense", 101)
            )
            views.setOnClickPendingIntent(
                R.id.btn_widget_ai,
                buildRoutePendingIntent(context, "/ai/quick-expense", 102)
            )
            views.setOnClickPendingIntent(
                R.id.btn_widget_scan,
                buildRoutePendingIntent(context, "/ai/receipt-scanner", 103)
            )
            views.setOnClickPendingIntent(
                R.id.btn_widget_voice,
                buildRoutePendingIntent(context, "/ai/quick-expense?voice=1", 104)
            )

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
