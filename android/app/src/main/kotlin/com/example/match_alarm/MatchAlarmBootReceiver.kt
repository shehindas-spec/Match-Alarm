
package com.example.match_alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.app.AlarmManager
import android.app.PendingIntent
import android.net.Uri
import android.os.Build

class MatchAlarmBootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent?) {

        if (intent?.action != Intent.ACTION_BOOT_COMPLETED &&
            intent?.action != Intent.ACTION_MY_PACKAGE_REPLACED &&
            intent?.action != "android.intent.action.QUICKBOOT_POWERON" &&
            intent?.action != "com.htc.intent.action.QUICKBOOT_POWERON"
        ) {
            return
        }

        val preferences = context.getSharedPreferences(
            "match_alarm_storage",
            Context.MODE_PRIVATE
        )

        val alarmManager = context.getSystemService(
            Context.ALARM_SERVICE
        ) as AlarmManager

        val gameIds = preferences.getStringSet(
            "scheduled_game_ids",
            emptySet()
        ) ?: emptySet()

        for (gameId in gameIds) {

            val triggerAtMillis = preferences.getLong(
                "${gameId}_trigger",
                0L
            )

            if (triggerAtMillis <= System.currentTimeMillis()) {
                continue
            }

            val homeTeam = preferences.getString(
                "${gameId}_home", ""
            ) ?: ""

            val awayTeam = preferences.getString(
                "${gameId}_away", ""
            ) ?: ""

            val kickoffTime = preferences.getString(
                "${gameId}_kickoff", ""
            ) ?: ""

            val alarmTime = preferences.getString(
                "${gameId}_alarm", ""
            ) ?: ""

            val requestCode = gameId.hashCode() and 0x7fffffff

            val alarmIntent = Intent(
                context,
                AlarmReceiver::class.java
            ).apply {
                action = "com.example.match_alarm.MATCH_ALARM"
                data = Uri.parse(
                    "match-alarm://match/${Uri.encode(gameId)}"
                )

                putExtra("gameId", gameId)
                putExtra("homeTeam", homeTeam)
                putExtra("awayTeam", awayTeam)
                putExtra("kickoffTime", kickoffTime)
                putExtra("alarmTime", alarmTime)
            }

            val pendingIntent = PendingIntent.getBroadcast(
                context,
                requestCode,
                alarmIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or
                    PendingIntent.FLAG_IMMUTABLE
            )

            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
                alarmManager.canScheduleExactAlarms()
            ) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerAtMillis,
                    pendingIntent
                )
            }
        }
    }
}
