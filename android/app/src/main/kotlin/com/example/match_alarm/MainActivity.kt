
package com.example.match_alarm

import android.util.Log
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "com.example.match_alarm/native_alarm"
    private val testAlarmRequestCode = 3001

    private lateinit var alarmChannel: MethodChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        alarmChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        )

        alarmChannel.setMethodCallHandler { call, result ->

            when (call.method) {

                // Existing test alarm
                "scheduleAlarm" -> {
                    val triggerAtMillis =
                        call.argument<Number>("triggerAtMillis")?.toLong()

                    if (triggerAtMillis == null) {
                        result.error(
                            "INVALID_TIME",
                            "Alarm time is missing",
                            null
                        )
                    } else {
                        try {
                            scheduleTestAlarm(triggerAtMillis)
                            result.success(true)
                        } catch (error: Exception) {
                            result.error(
                                "SCHEDULE_FAILED",
                                error.message,
                                null
                            )
                        }
                    }
                }

                // Schedule an individual football match alarm
                "scheduleMatchAlarm" -> {
                    val triggerAtMillis =
                        call.argument<Number>("triggerAtMillis")?.toLong()

                    val gameId = call.argument<String>("gameId")
                    val homeTeam = call.argument<String>("homeTeam")
                    val awayTeam = call.argument<String>("awayTeam")
                    val kickoffTime = call.argument<String>("kickoffTime")
                    val alarmTime = call.argument<String>("alarmTime")

                    if (
                        triggerAtMillis == null ||
                        gameId.isNullOrBlank() ||
                        homeTeam.isNullOrBlank() ||
                        awayTeam.isNullOrBlank()
                    ) {
                        result.error(
                            "INVALID_MATCH",
                            "Required match information is missing",
                            null
                        )
                    } else {
                        try {
                            scheduleMatchAlarm(
                                triggerAtMillis,
                                gameId,
                                homeTeam,
                                awayTeam,
                                kickoffTime ?: "",
                                alarmTime ?: ""
                            )
                            result.success(true)
                        } catch (error: Exception) {
                            result.error(
                                "SCHEDULE_FAILED",
                                error.message,
                                null
                            )
                        }
                    }
                }

                // Cancel the test alarm only
                "cancelAlarm" -> {
                    cancelTestAlarm()
                    result.success(true)
                }

                // Cancel one particular match alarm
                "cancelMatchAlarm" -> {
                    val gameId = call.argument<String>("gameId")

                    if (gameId.isNullOrBlank()) {
                        result.error(
                            "INVALID_MATCH",
                            "Match ID is missing",
                            null
                        )
                    } else {
                        cancelMatchAlarm(gameId)
                        result.success(true)
                    }
                }

                "stopAlarmSound" -> {
                    stopNativeAlarmSound()
                    result.success(true)
                }

                // Existing Dart launch handling
                "consumeAlarmLaunch" -> {
                    val shouldOpen =
                        intent?.getBooleanExtra("open_match_alarm", false) == true

                    intent?.removeExtra("open_match_alarm")

                    result.success(shouldOpen)
                }

                // Read the match details when the alarm screen opens
                "consumeAlarmPayload" -> {
                    val currentIntent = intent

                    val payload = if (
                        currentIntent?.getBooleanExtra(
                            "open_match_alarm",
                            false
                        ) == true
                    ) {
                        mapOf(
                            "gameId" to currentIntent.getStringExtra("gameId"),
                            "homeTeam" to currentIntent.getStringExtra("homeTeam"),
                            "awayTeam" to currentIntent.getStringExtra("awayTeam"),
                            "kickoffTime" to currentIntent.getStringExtra("kickoffTime"),
                            "alarmTime" to currentIntent.getStringExtra("alarmTime")
                        )
                    } else {
                        null
                    }

                    result.success(payload)
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)

        if (intent.getBooleanExtra("open_match_alarm", false)) {
            if (::alarmChannel.isInitialized) {
                alarmChannel.invokeMethod("openAlarmScreen", null)
            }
        }
    }

    private fun checkExactAlarmPermission() {
        val alarmManager =
            getSystemService(Context.ALARM_SERVICE) as AlarmManager

        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            !alarmManager.canScheduleExactAlarms()
        ) {
            throw IllegalStateException(
                "Exact alarm permission is not granted"
            )
        }
    }

    // Existing test alarm
    private fun scheduleTestAlarm(triggerAtMillis: Long) {
        checkExactAlarmPermission()

        val alarmManager =
            getSystemService(Context.ALARM_SERVICE) as AlarmManager

        alarmManager.setExactAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP,
            triggerAtMillis,
            getTestAlarmPendingIntent()
        )

    }

    private fun getTestAlarmPendingIntent(): PendingIntent {
        val alarmIntent = Intent(this, AlarmReceiver::class.java).apply {
            action = "com.example.match_alarm.TEST_ALARM"
            data = Uri.parse("match-alarm://test")
        }

        return PendingIntent.getBroadcast(
            this,
            testAlarmRequestCode,
            alarmIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or
                    PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun cancelTestAlarm() {
        val alarmManager =
            getSystemService(Context.ALARM_SERVICE) as AlarmManager

        alarmManager.cancel(getTestAlarmPendingIntent())
    }

    // Schedule a unique alarm for each match
    private fun scheduleMatchAlarm(
        triggerAtMillis: Long,
        gameId: String,
        homeTeam: String,
        awayTeam: String,
        kickoffTime: String,
        alarmTime: String
    ) {
        checkExactAlarmPermission()

        val alarmManager =
            getSystemService(Context.ALARM_SERVICE) as AlarmManager

        val requestCode = gameId.hashCode() and 0x7fffffff

        val alarmIntent = Intent(this, AlarmReceiver::class.java).apply {
            action = "com.example.match_alarm.MATCH_ALARM"
            data = Uri.parse("match-alarm://match/${Uri.encode(gameId)}")

            putExtra("gameId", gameId)
            putExtra("homeTeam", homeTeam)
            putExtra("awayTeam", awayTeam)
            putExtra("kickoffTime", kickoffTime)
            putExtra("alarmTime", alarmTime)
        }

        val pendingIntent = PendingIntent.getBroadcast(
            this,
            requestCode,
            alarmIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or
                    PendingIntent.FLAG_IMMUTABLE
        )

        alarmManager.setExactAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP,
            triggerAtMillis,
            pendingIntent
        )

        // Save match details for restoration after phone restart
        val preferences = getSharedPreferences(
            "match_alarm_storage",
            Context.MODE_PRIVATE
        )

        val gameIds = preferences.getStringSet(
            "scheduled_game_ids",
            emptySet()
        )?.toMutableSet() ?: mutableSetOf()

        gameIds.add(gameId)

        preferences.edit()
            .putStringSet("scheduled_game_ids", gameIds)
            .putLong("${gameId}_trigger", triggerAtMillis)
            .putString("${gameId}_home", homeTeam)
            .putString("${gameId}_away", awayTeam)
            .putString("${gameId}_kickoff", kickoffTime)
            .putString("${gameId}_alarm", alarmTime)
            .apply()
    }

    private fun cancelMatchAlarm(gameId: String) {
        
        // Remove this match from saved alarm records
        val preferences = getSharedPreferences(
            "match_alarm_storage",
            Context.MODE_PRIVATE
        )

        val gameIds = preferences.getStringSet(
            "scheduled_game_ids",
            emptySet()
        )?.toMutableSet() ?: mutableSetOf()

        gameIds.remove(gameId)

        preferences.edit()
            .putStringSet("scheduled_game_ids", gameIds)
            .remove("${gameId}_trigger")
            .remove("${gameId}_home")
            .remove("${gameId}_away")
            .remove("${gameId}_kickoff")
            .remove("${gameId}_alarm")
            .apply()

        Log.e("MATCH_ALARM_DEBUG", "CANCEL CALLED for gameId: $gameId")
        val alarmManager =
            getSystemService(Context.ALARM_SERVICE) as AlarmManager

        val requestCode = gameId.hashCode() and 0x7fffffff

        val alarmIntent = Intent(this, AlarmReceiver::class.java).apply {
            action = "com.example.match_alarm.MATCH_ALARM"
            data = Uri.parse("match-alarm://match/${Uri.encode(gameId)}")
        }

        val pendingIntent = PendingIntent.getBroadcast(
            this,
            requestCode,
            alarmIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or
                    PendingIntent.FLAG_IMMUTABLE
        )

        alarmManager.cancel(pendingIntent)
        pendingIntent.cancel()
    }

    private fun stopNativeAlarmSound() {
        val stopIntent = Intent(
            this,
            AlarmAudioService::class.java
        ).apply {
            action = AlarmAudioService.ACTION_STOP
        }

        startService(stopIntent)
    }
}
