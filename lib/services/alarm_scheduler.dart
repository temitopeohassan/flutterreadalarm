import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/reading_alarm.dart';

/// What a ringing alarm needs to know, carried in the notification payload
/// so it also works after the app was killed or the phone rebooted.
class AlarmPayload {
  const AlarmPayload({
    required this.alarmId,
    required this.bookId,
    required this.durationMin,
    required this.title,
    required this.body,
    this.hour,
    this.minute,
  });

  factory AlarmPayload.forAlarm(ReadingAlarm alarm) => AlarmPayload(
        alarmId: alarm.id,
        bookId: alarm.book.id,
        durationMin: alarm.durationMin,
        hour: alarm.time.hour,
        minute: alarm.time.minute,
        title: 'Time to read',
        body: '${alarm.book.title} · Read ${alarm.durationMin} min',
      );

  final String alarmId;
  final String bookId;
  final int durationMin;
  final String title;
  final String body;
  final int? hour;
  final int? minute;

  TimeOfDay? get time => hour == null || minute == null
      ? null
      : TimeOfDay(hour: hour!, minute: minute!);

  String encode() => jsonEncode({
        'alarmId': alarmId,
        'bookId': bookId,
        'durationMin': durationMin,
        'title': title,
        'body': body,
        'hour': hour,
        'minute': minute,
      });

  static AlarmPayload? decode(String? payload) {
    if (payload == null) return null;
    try {
      final json = jsonDecode(payload) as Map<String, Object?>;
      return AlarmPayload(
        alarmId: json['alarmId'] as String,
        bookId: json['bookId'] as String,
        durationMin: json['durationMin'] as int,
        title: json['title'] as String? ?? 'Time to read',
        body: json['body'] as String? ?? '',
        hour: json['hour'] as int?,
        minute: json['minute'] as int?,
      );
    } catch (_) {
      return null;
    }
  }
}

/// How the user reacted to a ringing alarm.
enum AlarmAction { open, start, snooze }

class AlarmLaunch {
  const AlarmLaunch(this.payload, this.action);
  final AlarmPayload payload;
  final AlarmAction action;
}

const snoozeDuration = Duration(minutes: 10);

/// Schedules reading alarms with the OS so they ring on time, over the lock
/// screen, even when the app isn't running.
abstract class AlarmScheduler {
  /// [onLaunch] is called when the user opens or acts on a ringing alarm
  /// while the app is running.
  Future<void> init(void Function(AlarmLaunch launch) onLaunch);

  /// The alarm that launched the app, if any.
  Future<AlarmLaunch?> takeLaunch();

  /// (Re)schedules [alarm], or cancels it if it's disabled.
  Future<void> schedule(ReadingAlarm alarm);

  Future<void> cancel(String alarmId);

  /// Rings once at [at] (test alarms and snoozes).
  Future<void> scheduleOnce(AlarmPayload payload, DateTime at);

  /// Silences and removes a ringing alarm's notification.
  Future<void> dismiss(String alarmId);

  /// Ids of alarms that still have a future ring scheduled.
  Future<Set<String>> pendingAlarmIds();
}

// Notification ids: each alarm gets a block of 10.
// Slots 0–6 = weekly ring on Monday–Sunday, 7 = one-off, 8 = snooze/test.
const _onceSlot = 7;
const _snoozeSlot = 8;

int _notificationId(String alarmId, int slot) {
  var hash = 0x811c9dc5; // FNV-1a
  for (final unit in alarmId.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
  }
  return (hash % 200000000) * 10 + slot;
}

const _channelId = 'reading_alarms';
const _actionStart = 'start';
const _actionSnooze = 'snooze';
const _initSettings = InitializationSettings(
  android: AndroidInitializationSettings('ic_stat_readalarm'),
);

NotificationDetails _alarmDetails() => NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        'Reading alarms',
        channelDescription: 'Rings when it is time to read',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.alarm,
        fullScreenIntent: true,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        visibility: NotificationVisibility.public,
        autoCancel: false,
        ongoing: true,
        timeoutAfter: const Duration(minutes: 10).inMilliseconds,
        // FLAG_INSISTENT: keep ringing until the user responds.
        additionalFlags: Int32List.fromList([4]),
        actions: const [
          AndroidNotificationAction(_actionStart, 'Start reading',
              showsUserInterface: true),
          AndroidNotificationAction(_actionSnooze, 'Snooze 10 min'),
        ],
      ),
    );

/// Runs in a background isolate when "Snooze" is tapped on the notification.
@pragma('vm:entry-point')
Future<void> onBackgroundAlarmAction(NotificationResponse response) async {
  if (response.actionId != _actionSnooze) return;
  final payload = AlarmPayload.decode(response.payload);
  if (payload == null) return;
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(settings: _initSettings);
  await _initTimeZones();
  await _silence(plugin, payload.alarmId);
  await _snooze(plugin, payload);
}

Future<void> _initTimeZones() async {
  tzdata.initializeTimeZones();
  try {
    final zone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(zone.identifier));
  } catch (_) {
    // Unknown zone: tz.local stays UTC.
  }
}

Future<void> _snooze(
    FlutterLocalNotificationsPlugin plugin, AlarmPayload payload) {
  return plugin.zonedSchedule(
    id: _notificationId(payload.alarmId, _snoozeSlot),
    scheduledDate: tz.TZDateTime.now(tz.UTC).add(snoozeDuration),
    notificationDetails: _alarmDetails(),
    androidScheduleMode: AndroidScheduleMode.alarmClock,
    title: payload.title,
    body: payload.body,
    payload: payload.encode(),
  );
}

Future<void> _ringWeekly(FlutterLocalNotificationsPlugin plugin,
    AlarmPayload payload, int day, DateTime at) {
  return plugin.zonedSchedule(
    id: _notificationId(payload.alarmId, day),
    scheduledDate: tz.TZDateTime.from(at, tz.local),
    notificationDetails: _alarmDetails(),
    androidScheduleMode: AndroidScheduleMode.alarmClock,
    title: payload.title,
    body: payload.body,
    payload: payload.encode(),
    matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
  );
}

/// Removes the ringing notification(s) of [alarmId].
///
/// On Android, cancelling a repeating notification also drops its future
/// repeats, so weekly rings are put back afterwards.
Future<void> _silence(
    FlutterLocalNotificationsPlugin plugin, String alarmId) async {
  final active = await plugin.getActiveNotifications();
  for (final n in active) {
    final payload = AlarmPayload.decode(n.payload);
    final id = n.id;
    if (payload?.alarmId != alarmId || id == null) continue;
    await plugin.cancel(id: id, tag: n.tag);
    final day = id % 10;
    final time = payload!.time;
    if (day < _onceSlot && time != null) {
      final weekly = ReadingAlarm(
        id: alarmId,
        time: time,
        book: BookInfo(id: payload.bookId, title: '', coverColors: const []),
        durationMin: payload.durationMin,
        repeatDays: {day},
      );
      await _ringWeekly(
          plugin, payload, day, weekly.nextOccurrence(DateTime.now()));
    }
  }
}

class NotificationAlarmScheduler implements AlarmScheduler {
  final _plugin = FlutterLocalNotificationsPlugin();

  @override
  Future<void> init(void Function(AlarmLaunch launch) onLaunch) async {
    await _initTimeZones();
    await _plugin.initialize(
      settings: _initSettings,
      onDidReceiveNotificationResponse: (response) async {
        final launch = _toLaunch(response);
        if (launch == null) return;
        if (launch.action == AlarmAction.snooze) {
          await _silence(_plugin, launch.payload.alarmId);
          await _snooze(_plugin, launch.payload);
        } else {
          onLaunch(launch);
        }
      },
      onDidReceiveBackgroundNotificationResponse: onBackgroundAlarmAction,
    );
  }

  AlarmLaunch? _toLaunch(NotificationResponse response) {
    final payload = AlarmPayload.decode(response.payload);
    if (payload == null) return null;
    final action = switch (response.actionId) {
      _actionStart => AlarmAction.start,
      _actionSnooze => AlarmAction.snooze,
      _ => AlarmAction.open,
    };
    return AlarmLaunch(payload, action);
  }

  @override
  Future<AlarmLaunch?> takeLaunch() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    final response = details?.notificationResponse;
    if (details?.didNotificationLaunchApp != true || response == null) {
      return null;
    }
    return _toLaunch(response);
  }

  @override
  Future<void> schedule(ReadingAlarm alarm) async {
    await cancel(alarm.id);
    if (!alarm.enabled) return;
    final payload = AlarmPayload.forAlarm(alarm);
    final now = DateTime.now();

    if (alarm.repeatDays.isEmpty) {
      await _plugin.zonedSchedule(
        id: _notificationId(alarm.id, _onceSlot),
        scheduledDate: tz.TZDateTime.from(alarm.nextOccurrence(now), tz.local),
        notificationDetails: _alarmDetails(),
        androidScheduleMode: AndroidScheduleMode.alarmClock,
        title: payload.title,
        body: payload.body,
        payload: payload.encode(),
      );
    } else {
      for (final day in alarm.repeatDays) {
        final onDay = alarm.copyWith(repeatDays: {day}).nextOccurrence(now);
        await _ringWeekly(_plugin, payload, day, onDay);
      }
    }
  }

  @override
  Future<void> cancel(String alarmId) async {
    for (var slot = 0; slot <= _snoozeSlot; slot++) {
      await _plugin.cancel(id: _notificationId(alarmId, slot));
    }
  }

  @override
  Future<void> scheduleOnce(AlarmPayload payload, DateTime at) =>
      _plugin.zonedSchedule(
        id: _notificationId(payload.alarmId, _snoozeSlot),
        scheduledDate: tz.TZDateTime.from(at, tz.UTC),
        notificationDetails: _alarmDetails(),
        androidScheduleMode: AndroidScheduleMode.alarmClock,
        title: payload.title,
        body: payload.body,
        payload: payload.encode(),
      );

  @override
  Future<void> dismiss(String alarmId) => _silence(_plugin, alarmId);

  @override
  Future<Set<String>> pendingAlarmIds() async {
    try {
      final pending = await _plugin.pendingNotificationRequests();
      return {
        for (final p in pending)
          if (AlarmPayload.decode(p.payload) case final payload?)
            payload.alarmId,
      };
    } catch (e) {
      debugPrint('pendingNotificationRequests failed: $e');
      return {};
    }
  }
}
