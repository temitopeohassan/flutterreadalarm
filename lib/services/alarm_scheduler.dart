import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/reading_alarm.dart';
import 'event_log.dart';

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

  /// A push from ReadAlarm's server says an alarm is due (data from
  /// server/src/Fcm.php). Rings it unless it already rang or was handled.
  /// Returns whether it rang.
  Future<bool> ringFromPush(Map<String, dynamic> data);

  /// The user opened, silenced or snoozed [alarmId]'s ring: a push for
  /// it arriving soon after mustn't ring it again.
  Future<void> markHandled(String alarmId);

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

const _channelId = 'reading_alarms';
const _actionStart = 'start';
const _actionSnooze = 'snooze';
const _iosCategory = 'readalarm_alarm';

/// iPhone: the alarm's sound (in the app bundle, up to 30 seconds: iOS's
/// limit for notification sounds).
const _iosSound = 'readalarm_alarm.wav';

final _initSettings = InitializationSettings(
  android: const AndroidInitializationSettings('ic_stat_readalarm'),
  // Permission is asked for in onboarding, not at start-up.
  iOS: DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
    notificationCategories: [
      DarwinNotificationCategory(_iosCategory, actions: [
        DarwinNotificationAction.plain(_actionStart, 'Start reading',
            options: {DarwinNotificationActionOption.foreground}),
        DarwinNotificationAction.plain(_actionSnooze, 'Snooze 10 min'),
      ]),
    ],
  ),
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
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBanner: true,
        presentList: true,
        presentSound: true,
        sound: _iosSound,
        categoryIdentifier: _iosCategory,
        interruptionLevel: InterruptionLevel.timeSensitive,
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
  await _silence(plugin, payload.alarmId, payload: payload);
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

// ---- Pushes from the server ----------------------------------------------

Future<File> _handledFile() async => File(
    '${(await getApplicationSupportDirectory()).path}/alarms_handled.json');

/// When each alarm's ring was last opened, silenced or snoozed.
Future<Map<String, int>> _handled() async {
  try {
    final file = await _handledFile();
    if (!file.existsSync()) return {};
    return (jsonDecode(await file.readAsString()) as Map).cast<String, int>();
  } catch (_) {
    return {};
  }
}

Future<void> _markHandled(String alarmId) async {
  try {
    final handled = await _handled();
    final now = DateTime.now().millisecondsSinceEpoch;
    handled[alarmId] = now;
    // A day is plenty: pushes older than 15 minutes aren't sent.
    handled.removeWhere(
        (_, at) => now - at > const Duration(days: 1).inMilliseconds);
    await (await _handledFile()).writeAsString(jsonEncode(handled));
  } catch (e) {
    debugPrint('Recording a handled alarm failed: $e');
  }
}

/// Rings the alarm a push names, with the same notification id as the
/// phone's own ring: if that showed already, or the user already dealt
/// with it, nothing happens; if it shows later, it replaces this one.
Future<bool> _ringFromPush(
    FlutterLocalNotificationsPlugin plugin, Map<String, dynamic> data) async {
  if (data['type'] != 'alarm') return false;
  final payload = AlarmPayload.decode(data['payload'] as String?);
  if (payload == null) return false;
  final slot = int.tryParse('${data['slot']}') ?? _onceSlot;
  final due = int.tryParse('${data['due']}') ?? 0;
  final id = _notificationId(payload.alarmId, slot);
  final late = DateTime.now()
      .difference(DateTime.fromMillisecondsSinceEpoch(due))
      .inSeconds;
  try {
    final active = await plugin.getActiveNotifications();
    if (active.any((n) => n.id == id)) {
      logEvent('Push for alarm ${payload.alarmId}: it is ringing already');
      return false;
    }
  } catch (_) {
    // Can't tell (older Android): the handled check below still applies.
  }
  final handledAt = (await _handled())[payload.alarmId];
  if (handledAt != null &&
      handledAt >= due - const Duration(minutes: 5).inMilliseconds) {
    logEvent('Push for alarm ${payload.alarmId}: already dealt with');
    return false;
  }
  await plugin.show(
    id: id,
    title: payload.title,
    body: payload.body,
    notificationDetails: _alarmDetails(),
    payload: payload.encode(),
  );
  logEvent('Push for alarm ${payload.alarmId}: the phone had not rung it, '
      'ringing now (${late}s after its time)');
  return true;
}

/// For a push that arrived while ReadAlarm was closed (push_service.dart).
Future<bool> ringFromPushInBackground(Map<String, dynamic> data) async {
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(settings: _initSettings);
  return _ringFromPush(plugin, data);
}

/// Removes the ringing notification(s) of [alarmId], stopping the sound.
///
/// Matched by notification id: Android doesn't return a showing
/// notification's payload, so [payload] (or the scheduled ring's) supplies
/// the alarm's time. Cancelling a repeating notification also drops its
/// future repeats, so weekly rings are put back afterwards.
Future<void> _silence(FlutterLocalNotificationsPlugin plugin, String alarmId,
    {AlarmPayload? payload}) async {
  await _markHandled(alarmId);
  final ids = {
    for (var slot = 0; slot <= _snoozeSlot; slot++)
      _notificationId(alarmId, slot),
  };
  final active = await plugin.getActiveNotifications();
  final ringing = [
    for (final n in active)
      if (n.id != null && ids.contains(n.id)) n,
  ];
  if (ringing.isEmpty) return;
  var known = payload;
  if (known?.time == null) {
    try {
      for (final r in await plugin.pendingNotificationRequests()) {
        final p = AlarmPayload.decode(r.payload);
        if (ids.contains(r.id) && p?.time != null) known = p;
      }
    } catch (_) {
      // No scheduled rings to read: weekly rings are put back by the app.
    }
  }
  for (final n in ringing) {
    final id = n.id!;
    await plugin.cancel(id: id, tag: n.tag);
    final day = id % 10;
    final time = known?.time;
    if (day < _onceSlot && known != null && time != null) {
      final weekly = ReadingAlarm(
        id: alarmId,
        time: time,
        book: BookInfo(id: known.bookId, title: '', coverColors: const []),
        durationMin: known.durationMin,
        repeatDays: {day},
      );
      await _ringWeekly(
          plugin, known, day, weekly.nextOccurrence(DateTime.now()));
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
          await _silence(_plugin, launch.payload.alarmId,
              payload: launch.payload);
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
    if (!alarm.enabled) return cancel(alarm.id);
    final payload = AlarmPayload.forAlarm(alarm);
    final now = DateTime.now();

    // Scheduling an id again replaces it (without touching a ring that's
    // showing), so only the slots this alarm no longer uses are cancelled.
    final slots = alarm.repeatDays.isEmpty ? {_onceSlot} : alarm.repeatDays;
    for (var slot = 0; slot < _snoozeSlot; slot++) {
      if (!slots.contains(slot)) {
        await _plugin.cancel(id: _notificationId(alarm.id, slot));
      }
    }

    if (alarm.repeatDays.isEmpty) {
      final at = alarm.nextOccurrence(now);
      if (!at.isAfter(now)) return; // A dated one-off whose day has passed.
      await _plugin.zonedSchedule(
        id: _notificationId(alarm.id, _onceSlot),
        scheduledDate: tz.TZDateTime.from(at, tz.local),
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
  Future<bool> ringFromPush(Map<String, dynamic> data) =>
      _ringFromPush(_plugin, data);

  @override
  Future<void> markHandled(String alarmId) => _markHandled(alarmId);

  static const _diagnostics = MethodChannel('readalarm/diagnostics');

  @override
  Future<Map<String, bool>?> heldByAndroid(ReadingAlarm alarm) async {
    final ids = alarmNotificationIds(alarm)..remove('Snooze');
    try {
      final held = await _diagnostics.invokeMethod<List<Object?>>(
          'registered', {'ids': ids.values.toList()});
      if (held == null || held.length != ids.length) return null;
      final labels = ids.keys.toList();
      return {
        for (var i = 0; i < labels.length; i++) labels[i]: held[i] == true,
      };
    } catch (e) {
      return null;
    }
  }

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
