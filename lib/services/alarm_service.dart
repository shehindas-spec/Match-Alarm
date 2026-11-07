import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'fixture_service.dart';

class AlarmService {
  AlarmService._();

  static final AlarmService instance = AlarmService._();

  final FlutterLocalNotificationsPlugin notifications =
      FlutterLocalNotificationsPlugin();

  static const MethodChannel _nativeAlarmChannel = MethodChannel(
    'com.example.match_alarm/native_alarm',
  );

  static const int testAlarmId = 1001;

  static const AndroidNotificationChannel alarmChannel =
      AndroidNotificationChannel(
        'match_alarm_channel',
        'Match Alarms',
        description: 'Notifications for upcoming football matches',
        importance: Importance.max,
        playSound: false,
        enableVibration: true,
      );

  Future<void> initialize({
    void Function(String? payload)? onAlarmOpened,
  }) async {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const initializationSettings = InitializationSettings(
      android: androidSettings,
    );

    await notifications.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (response) {
        onAlarmOpened?.call(response.payload);
      },
    );

    final androidPlugin = notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    await androidPlugin?.createNotificationChannel(alarmChannel);
  }

  Future<bool> requestPermissions() async {
    final androidPlugin = notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (androidPlugin == null) return false;

    final notificationPermission = await androidPlugin
        .requestNotificationsPermission();

    final exactAlarmPermission = await androidPlugin
        .requestExactAlarmsPermission();

    final fullScreenPermission = await androidPlugin
        .requestFullScreenIntentPermission();

    return notificationPermission == true &&
        exactAlarmPermission == true &&
        fullScreenPermission == true;
  }

  // --------------------------------------------------
  // TEST ALARM
  // --------------------------------------------------

  Future<void> scheduleTestAlarm() async {
    final scheduledTime = tz.TZDateTime.now(tz.local)
        .add(const Duration(minutes: 1));

    await _nativeAlarmChannel.invokeMethod<bool>('scheduleAlarm', {
      'triggerAtMillis': scheduledTime.millisecondsSinceEpoch,
    });
  }

  Future<void> cancelTestAlarm() async {
    await _nativeAlarmChannel.invokeMethod<bool>('cancelAlarm');
    await _nativeAlarmChannel.invokeMethod<bool>('stopAlarmSound');
    await notifications.cancel(id: testAlarmId);
  }

  // --------------------------------------------------
  // FOOTBALL MATCH ALARMS
  // --------------------------------------------------

  /// Schedule one match alarm exactly five minutes before kickoff.
  Future<void> scheduleMatchAlarm(MatchFixture fixture) async {
    final now = tz.TZDateTime.now(tz.local);
    final alarmTime = fixture.alarmTimeIst;

    if (!alarmTime.isAfter(now)) {
      return;
    }
    print(
      'SCHEDULING MATCH: ${fixture.homeTeam} vs ${fixture.awayTeam} | '
      'Kickoff: ${fixture.kickoffIst} | '
      'Alarm: $alarmTime | '
      'Millis: ${alarmTime.millisecondsSinceEpoch}',
    );
    await _nativeAlarmChannel.invokeMethod<bool>('scheduleMatchAlarm', {
      'triggerAtMillis': alarmTime.millisecondsSinceEpoch,
      'gameId': fixture.gameId,
      'homeTeam': fixture.homeTeam,
      'awayTeam': fixture.awayTeam,
      'kickoffTime': _formatDateTime(fixture.kickoffIst),
      'alarmTime': _formatDateTime(alarmTime),
    });
  }

  /// Schedule all upcoming fixtures.
  Future<int> scheduleMatchAlarms(List<MatchFixture> fixtures) async {
    int scheduledCount = 0;

    for (final fixture in fixtures) {
      await scheduleMatchAlarm(fixture);
      scheduledCount++;
    }

    return scheduledCount;
  }

  /// Cancel one particular match alarm.
  Future<void> cancelMatchAlarm(String gameId) async {
    await _nativeAlarmChannel.invokeMethod<bool>('cancelMatchAlarm', {
      'gameId': gameId,
    });
  }

  // --------------------------------------------------
  // GENERAL METHODS
  // --------------------------------------------------

  String _formatDateTime(DateTime dateTime) {
    final local = dateTime.toUtc().add(const Duration(hours: 5, minutes: 30));

    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();

    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');

    return '$day/$month/$year $hour:$minute IST';
  }

  Future<void> cancelAllAlarms() async {
    await cancelTestAlarm();
    await notifications.cancelAll();
  }

  Future<List<PendingNotificationRequest>> getPendingAlarms() async {
    return notifications.pendingNotificationRequests();
  }
}
