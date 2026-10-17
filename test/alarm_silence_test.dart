import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readalarm/models/reading_alarm.dart';
import 'package:readalarm/services/alarm_scheduler.dart';
import 'package:timezone/data/latest.dart' as tzdata;

/// Stands in for flutter_local_notifications' Android side. Like Android, a
/// showing notification is reported without its payload; scheduled ones
/// keep theirs.
class FakeAndroidNotifications {
  FakeAndroidNotifications(this.binding) {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, _handle);
  }

  static const _channel =
      MethodChannel('dexterous.com/flutter/local_notifications');
  final TestWidgetsFlutterBinding binding;

  /// Scheduled rings: id → payload.
  final scheduled = <int, String?>{};

  /// Notifications showing (ringing) now.
  final showing = <int>{};

  /// Makes the scheduled ring [id] fire.
  void ring(int id) => showing.add(id);

  void dispose() =>
      binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null);

  Future<Object?> _handle(MethodCall call) async {
    switch (call.method) {
      case 'zonedSchedule':
        final args = (call.arguments as Map).cast<String, Object?>();
        scheduled[args['id'] as int] = args['payload'] as String?;
        return null;
      case 'cancel':
        final args = call.arguments;
        final id = args is Map ? args['id'] as int : args as int;
        scheduled.remove(id);
        showing.remove(id);
        return null;
      case 'getActiveNotifications':
        return [
          for (final id in showing)
            {'id': id, 'channelId': 'reading_alarms', 'tag': null},
        ];
      case 'pendingNotificationRequests':
        return [
          for (final e in scheduled.entries)
            {'id': e.key, 'title': '', 'body': '', 'payload': e.value},
        ];
    }
    return null;
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late FakeAndroidNotifications android;

  setUpAll(tzdata.initializeTimeZones);
  setUp(() {
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    android = FakeAndroidNotifications(binding);
  });
  tearDown(() => android.dispose());

  ReadingAlarm alarm({Set<int> days = const {0, 2, 4}}) => ReadingAlarm(
        id: 'a1',
        time: const TimeOfDay(hour: 7, minute: 0),
        book: SampleData.books.first,
        durationMin: 15,
        repeatDays: days,
      );

  test('dismissing stops a ringing weekly alarm and keeps its next rings',
      () async {
    final scheduler = NotificationAlarmScheduler();
    await scheduler.schedule(alarm());
    final rings = Set.of(android.scheduled.keys);
    expect(rings, hasLength(3));

    // Monday's ring goes off; Android reports it without a payload.
    final monday = rings.firstWhere((id) => id % 10 == 0);
    android.ring(monday);

    await scheduler.dismiss('a1');
    expect(android.showing, isEmpty, reason: 'the ringing stops');
    expect(android.scheduled.keys.toSet(), rings,
        reason: 'Monday still rings next week');
  });

  test('dismissing stops a ringing one-off alarm, snooze and test alarm',
      () async {
    final scheduler = NotificationAlarmScheduler();
    await scheduler.schedule(alarm(days: const {}));
    final once = android.scheduled.keys.single;
    android.ring(once);
    await scheduler.dismiss('a1');
    expect(android.showing, isEmpty);

    await scheduler.scheduleOnce(
      const AlarmPayload(
          alarmId: 'test',
          bookId: 'b1',
          durationMin: 1,
          title: 'Test alarm',
          body: ''),
      DateTime.now().add(const Duration(minutes: 1)),
    );
    final test = android.scheduled.keys.single;
    android.ring(test);
    await scheduler.dismiss('test');
    expect(android.showing, isEmpty);
  });

  test('dismissing leaves other alarms ringing', () async {
    final scheduler = NotificationAlarmScheduler();
    await scheduler.schedule(alarm(days: const {}));
    final other = android.scheduled.keys.single;
    android.ring(other);
    await scheduler.dismiss('someone-else');
    expect(android.showing, {other});
  });
}
