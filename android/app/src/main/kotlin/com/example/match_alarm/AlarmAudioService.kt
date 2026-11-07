
package com.example.match_alarm

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.IBinder
import android.content.pm.ServiceInfo

class AlarmAudioService : Service() {

    private var mediaPlayer: MediaPlayer? = null

    companion object {
        const val ACTION_START =
            "com.example.match_alarm.START_ALARM"

        const val ACTION_STOP =
            "com.example.match_alarm.STOP_ALARM"

        private const val CHANNEL_ID = "match_alarm_audio"
        private const val NOTIFICATION_ID = 2001
    }

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int
    ): Int {

        when (intent?.action) {

            ACTION_STOP -> {
                stopAlarm()
                return START_NOT_STICKY
            }

            ACTION_START -> {
                startAlarm(intent)
            }
        }

        return START_STICKY
    }

    private fun startAlarm(intent: Intent) {

        createNotificationChannel()

        val gameId = intent.getStringExtra("gameId") ?: ""
        val homeTeam =
            intent.getStringExtra("homeTeam") ?: "Football Match"

        val awayTeam =
            intent.getStringExtra("awayTeam") ?: ""

        val kickoffTime =
            intent.getStringExtra("kickoffTime") ?: ""

        val alarmTime =
            intent.getStringExtra("alarmTime") ?: ""

        val openAppIntent = Intent(
            this,
            MainActivity::class.java
        ).apply {

            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP

            putExtra("open_match_alarm", true)
            putExtra("gameId", gameId)
            putExtra("homeTeam", homeTeam)
            putExtra("awayTeam", awayTeam)
            putExtra("kickoffTime", kickoffTime)
            putExtra("alarmTime", alarmTime)
        }

        val pendingIntent = PendingIntent.getActivity(
            this,
            NOTIFICATION_ID,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or
                    PendingIntent.FLAG_IMMUTABLE
        )

        val matchTitle = "$homeTeam vs $awayTeam"

        val notificationText = if (kickoffTime.isNotBlank()) {
            "Match starts in 5 minutes • $kickoffTime"
        } else {
            "Your football match starts in 5 minutes"
        }

        val notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }
            .setContentTitle(matchTitle)
            .setContentText(notificationText)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setCategory(Notification.CATEGORY_ALARM)
            .setPriority(Notification.PRIORITY_MAX)
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(pendingIntent)
            .setFullScreenIntent(pendingIntent, true)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        // Start ringtone only if it is not already playing
        if (mediaPlayer == null) {
            try {

                val alarmUri = RingtoneManager.getDefaultUri(
                    RingtoneManager.TYPE_ALARM
                ) ?: RingtoneManager.getDefaultUri(
                    RingtoneManager.TYPE_NOTIFICATION
                )

                mediaPlayer = MediaPlayer.create(this, alarmUri)

                mediaPlayer?.apply {
                    isLooping = true
                    setVolume(1.0f, 1.0f)
                    start()
                }

            } catch (error: Exception) {
                error.printStackTrace()
            }
        }
    }

    private fun createNotificationChannel() {

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {

            val channel = NotificationChannel(
                CHANNEL_ID,
                "Match Alarm Sound",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {

                description = "Football match alarm"
                setSound(null, null)
                lockscreenVisibility =
                    Notification.VISIBILITY_PUBLIC
            }

            val manager =
                getSystemService(NotificationManager::class.java)

            manager.createNotificationChannel(channel)
        }
    }

    private fun stopAlarm() {

        mediaPlayer?.stop()
        mediaPlayer?.release()
        mediaPlayer = null

        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {

        mediaPlayer?.release()
        mediaPlayer = null

        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
