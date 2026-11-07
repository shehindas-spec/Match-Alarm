
package com.example.match_alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class AlarmReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent?) {

        val serviceIntent = Intent(
            context,
            AlarmAudioService::class.java
        ).apply {

            action = AlarmAudioService.ACTION_START

            // Forward match details
            putExtra(
                "gameId",
                intent?.getStringExtra("gameId")
            )

            putExtra(
                "homeTeam",
                intent?.getStringExtra("homeTeam")
            )

            putExtra(
                "awayTeam",
                intent?.getStringExtra("awayTeam")
            )

            putExtra(
                "kickoffTime",
                intent?.getStringExtra("kickoffTime")
            )

            putExtra(
                "alarmTime",
                intent?.getStringExtra("alarmTime")
            )
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
        } catch (error: Exception) {
            error.printStackTrace()
        }
    }
}
