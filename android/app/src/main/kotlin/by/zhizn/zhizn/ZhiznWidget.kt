package by.zhizn.zhizn

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/** Виджет «Жизнь»: дела на сегодня и кнопка «Записать». Данные пишет приложение. */
class ZhiznWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.zhizn_widget).apply {
                setTextViewText(R.id.widget_summary, widgetData.getString("summary", "Откройте приложение"))
                setTextViewText(R.id.widget_tasks, widgetData.getString("tasks", ""))
                setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("zhizn://today")),
                )
                setOnClickPendingIntent(
                    R.id.widget_capture,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("zhizn://capture")),
                )
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
