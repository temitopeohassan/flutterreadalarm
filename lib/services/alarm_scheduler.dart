import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
  const AlarmLaunch(this.payload, this.action, {this.cold = false});
  final AlarmPayload payload;
  final AlarmAction action;

  /// The alarm started the app from closed (proof alarms work on this
  /// phone even when the app isn't running).
  final bool cold;
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

  /// (Re)schedules [alarm], or cancels it if it's disabled. Safe to repeat:
  /// it doesn't stop a ring that's going off or drop a snooze.
  Future<void> schedule(ReadingAlarm alarm);

  Future<void> cancel(String alarmId);

  /// Rings once at [at] (test alarms and snoozes).
  Future<void> scheduleOnce(AlarmPayload payload, DateTime at);

  /// Silences and removes a ringing alarm's notification.
  Future<void> dismiss(String alarmId);

  /// Ids of alarms that still have a future ring scheduled.
  Future<Set<String>> pendingAlarmIds();

  /// Closes the app completely, as a phone's power manager might (for the
  /// alarm test).
  Future<void> closeApp();

  /// Whether Android itself holds each of [alarm]'s rings, by day label
  /// ('Mon', 'Once'), or null if it can't be asked. The plugin's own list
  /// survives the phone removing the app's alarms; this asks Android.
  Future<Map<String, bool>?> heldByAndroid(ReadingAlarm alarm);
}

// Notification ids: each alarm gets a block of 10.
// Slots 0–6 = weekly ring on Monday–Sunday, 7 = one-off, 8 = snooze/test.
const _onceSlot = 7;
const _snoozeSlot = 8;

/// The notification ids [alarm] rings under, by label (e.g. 'Mon',
/// 'Once', 'Snooze'), for diagnostics.
Map<String, int> alarmNotificationIds(ReadingAlarm alarm) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final slots = alarm.repeatDays.isEmpty
      ? {'Once': _onceSlot}
      : {for (final d in alarm.repeatDays.toList()..sort()) days[d]: d};
  return {
    for (final e in slots.entries) e.key: _notificationId(alarm.id, e.value),
    'Snooze': _notificationId(alarm.id, _snoozeSlot),
  };
}

int _notificationId(String alarmId, int slot) {
  var hash = 0x811c9dc5; // FNV-1a
  for (final unit in alarmId.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
  }
  return (hash % 200000000) * 10 + slot;
}

/// Schedules alarms with Android's alarm clock (see AlarmEngine.kt): at
/// the alarm time Android opens ReadAlarm's screen directly, which works
/// even when the app was closed, and the app rings.
class NotificationAlarmScheduler implements AlarmScheduler {
  static const _channel = MethodChannel('readalarm/alarms');

  @override
  Future<void> init(void Function(AlarmLaunch launch) onLaunch) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'launch') return;
      final launch = _toLaunch(call.arguments);
      if (launch != null) onLaunch(launch);
    });
    // Earlier versions scheduled through the notification plugin: remove
    // those so nothing rings twice.
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_readalarm'),
        ),
      );
      await plugin.cancelAllPendingNotifications();
    } catch (e) {
      debugPrint('Removing old scheduled notifications failed: $e');
    }
  }

  AlarmLaunch? _toLaunch(Object? data) {
    if (data is! Map) return null;
    final payload = AlarmPayload.decode(data['payload'] as String?);
    if (payload == null) return null;
    final action = switch (data['action']) {
      'start' => AlarmAction.start,
      'snooze' => AlarmAction.snooze,
      _ => AlarmAction.open,
    };
    return AlarmLaunch(payload, action, cold: data['cold'] == true);
  }

  Future<T?> _call<T>(String method, [Object? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } catch (e) {
      debugPrint('Alarms $method failed: $e');
      return null;
    }
  }

  @override
  Future<AlarmLaunch?> takeLaunch() async =>
      _toLaunch(await _call<Object?>('takeLaunch'));

  Map<String, Object?> _entry(int id, AlarmPayload payload,
          {int weekday = 0, int hour = 0, int minute = 0, DateTime? at}) =>
      {
        'id': id,
        'weekday': weekday,
        'hour': hour,
        'minute': minute,
        'at': at?.millisecondsSinceEpoch ?? 0,
        'payload': payload.encode(),
        'title': payload.title,
        'body': payload.body,
      };

  @override
  Future<void> schedule(ReadingAlarm alarm) async {
    if (!alarm.enabled) return cancel(alarm.id);
    final payload = AlarmPayload.forAlarm(alarm);
    final now = DateTime.now();

    // Setting an id again replaces it (without stopping a ring that's
    // showing), so only the slots this alarm no longer uses are cancelled.
    final slots = alarm.repeatDays.isEmpty ? {_onceSlot} : alarm.repeatDays;
    await _call<void>('cancel', {
      'ids': [
        for (var slot = 0; slot < _snoozeSlot; slot++)
          if (!slots.contains(slot)) _notificationId(alarm.id, slot),
      ],
    });

    final entries = <Map<String, Object?>>[];
    if (alarm.repeatDays.isEmpty) {
      final at = alarm.nextOccurrence(now);
      if (!at.isAfter(now)) return; // A dated one-off whose day has passed.
      entries
          .add(_entry(_notificationId(alarm.id, _onceSlot), payload, at: at));
    } else {
      for (final day in alarm.repeatDays) {
        entries.add(_entry(_notificationId(alarm.id, day), payload,
            weekday: day + 1,
            hour: alarm.time.hour,
            minute: alarm.time.minute));
      }
    }
    await _call<void>('set', {'entries': entries});
  }

  @override
  Future<void> cancel(String alarmId) => _call<void>('cancel', {
        'ids': [
          for (var slot = 0; slot <= _snoozeSlot; slot++)
            _notificationId(alarmId, slot),
        ],
      });

  @override
  Future<void> scheduleOnce(AlarmPayload payload, DateTime at) =>
      _call<void>('set', {
        'entries': [
          _entry(_notificationId(payload.alarmId, _snoozeSlot), payload,
              at: at),
        ],
      });

  @override
  Future<void> dismiss(String alarmId) => _call<void>('dismiss', {
        'ids': [
          for (var slot = 0; slot <= _snoozeSlot; slot++)
            _notificationId(alarmId, slot),
        ],
      });

  @override
  Future<void> closeApp() => _call<void>('closeApp');

  @override
  Future<Map<String, bool>?> heldByAndroid(ReadingAlarm alarm) async {
    final ids = alarmNotificationIds(alarm)..remove('Snooze');
    final held =
        await _call<List<Object?>>('registered', {'ids': ids.values.toList()});
    if (held == null || held.length != ids.length) return null;
    final labels = ids.keys.toList();
    return {
      for (var i = 0; i < labels.length; i++) labels[i]: held[i] == true,
    };
  }

  @override
  Future<Set<String>> pendingAlarmIds() async {
    final pending = await _call<List<Object?>>('pending') ?? const [];
    return {
      for (final p in pending)
        if (AlarmPayload.decode(p as String?) case final payload?)
          payload.alarmId,
    };
  }
}
