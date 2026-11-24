import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readalarm/models/reading_alarm.dart';
import 'package:readalarm/services/alarm_scheduler.dart';

/// Stands in for AlarmEngine.kt on the 'readalarm/alarms' channel.
class FakeEngine {
  FakeEngine(this.binding) {
    final m = binding.defaultBinaryMessenger;
    m.setMockMethodCallHandler(_channel, _handle);
    m.setMockMethodCallHandler(
        const MethodChannel('dexterous.com/flutter/local_notifications'),
        (call) async => null);
  }

  static const _channel = MethodChannel('readalarm/alarms');
  final TestWidgetsFlutterBinding binding;
  final entries = <int, Map>{};
  final dismissed = <int>[];
  Map<String, Object?>? launch;

  Future<Object?> _handle(MethodCall call) async {
    final args = call.arguments as Map?;
    switch (call.method) {
      case 'set':
        for (final e in args!['entries'] as List) {
          entries[(e as Map)['id'] as int] = e;
        }
      case 'cancel':
        for (final id in args!['ids'] as List) {
          entries.remove(id);
        }
      case 'dismiss':
        dismissed.addAll((args!['ids'] as List).cast<int>());
      case 'pending':
        return [for (final e in entries.values) e['payload']];
      case 'registered':
        return [for (final id in args!['ids'] as List) entries.containsKey(id)];
      case 'takeLaunch':
        final l = launch;
        launch = null;
        return l;
    }
    return null;
  }

  /// The engine opening ReadAlarm for a ringing alarm while it runs.
  Future<void> ring(int id, String action) async {
    const codec = StandardMethodCodec();
    await binding.defaultBinaryMessenger.handlePlatformMessage(
      _channel.name,
      codec.encodeMethodCall(MethodCall(
          'launch', {'payload': entries[id]!['payload'], 'action': action})),
      (_) {},
    );
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late FakeEngine engine;
  setUp(() => engine = FakeEngine(binding));

  ReadingAlarm alarm({Set<int> days = const {0, 2, 4}}) => ReadingAlarm(
        id: 'a1',
        time: const TimeOfDay(hour: 19, minute: 0),
        book: SampleData.books.first,
        durationMin: 15,
        repeatDays: days,
      );

  test('a weekly alarm is one alarm clock per day, Monday = 1', () async {
    final scheduler = NativeAlarmScheduler();
    await scheduler.schedule(alarm());
    final days = [for (final e in engine.entries.values) e['weekday']]..sort();
    expect(days, [1, 3, 5]);
    for (final e in engine.entries.values) {
      expect((e['hour'], e['minute']), (19, 0));
      expect(AlarmPayload.decode(e['payload'] as String)!.alarmId, 'a1');
    }
    expect(await scheduler.pendingAlarmIds(), {'a1'});
    expect(await scheduler.heldByAndroid(alarm()),
        {'Mon': true, 'Wed': true, 'Fri': true});
  });

  test('ids match the push server\'s (alarm id and slot)', () async {
    final scheduler = NativeAlarmScheduler();
    await scheduler.schedule(alarm(days: {6}));
    // AlarmEngine.notificationId computes the same for a push's
    // alarm_id and slot (6 = Sunday).
    expect(engine.entries.keys.single,
        alarmNotificationIds(alarm(days: {6}))['Sun']);
  });

  test('dropping days cancels those; switching off cancels all', () async {
    final scheduler = NativeAlarmScheduler();
    await scheduler.schedule(alarm());
    await scheduler.schedule(alarm(days: {0}));
    expect(engine.entries.keys, [alarmNotificationIds(alarm())['Mon']]);
    await scheduler.schedule(alarm().copyWith(enabled: false));
    expect(engine.entries, isEmpty);
  });

  test('a one-off rings once at its time; snooze in its own slot', () async {
    final scheduler = NativeAlarmScheduler();
    final tomorrow =
        DateUtils.dateOnly(DateTime.now()).add(const Duration(days: 1));
    await scheduler.schedule(alarm(days: {}).copyWith(date: () => tomorrow));
    final e = engine.entries.values.single;
    expect(e['weekday'], 0);
    expect(e['at'],
        tomorrow.add(const Duration(hours: 19)).millisecondsSinceEpoch);
    await scheduler.scheduleOnce(
        AlarmPayload.forAlarm(alarm()), DateTime.now().add(snoozeDuration));
    expect(
        engine.entries.keys, contains(alarmNotificationIds(alarm())['Snooze']));
  });

  test('dismissing stops every ring of the alarm', () async {
    await NativeAlarmScheduler().dismiss('a1');
    expect(engine.dismissed.toSet(), {
      ...alarmNotificationIds(alarm(days: {0, 1, 2, 3, 4, 5, 6})).values,
      alarmNotificationIds(alarm(days: {}))['Once'],
    });
  });

  test('a ringing alarm reaches the app, opened or started', () async {
    final scheduler = NativeAlarmScheduler();
    final launches = <AlarmLaunch>[];
    await scheduler.init(launches.add);
    await scheduler.schedule(alarm());
    final id = alarmNotificationIds(alarm())['Mon']!;
    engine.launch = {
      'payload': engine.entries[id]!['payload'],
      'action': 'start'
    };
    final cold = await scheduler.takeLaunch();
    expect(cold!.action, AlarmAction.start);
    expect(await scheduler.takeLaunch(), isNull, reason: 'taken once');
    await engine.ring(id, 'open');
    expect(launches.single.payload.alarmId, 'a1');
    expect(launches.single.action, AlarmAction.open);
  });
}
