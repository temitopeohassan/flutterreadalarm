import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readalarm/models/reading_alarm.dart';
import 'package:readalarm/services/alarm_scheduler.dart';

/// Stands in for AlarmEngine.kt on the 'readalarm/alarms' channel.
class FakeAlarmEngine {
  FakeAlarmEngine(this.binding) {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, _handle);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('dexterous.com/flutter/local_notifications'),
        (call) async => null);
  }

  static const _channel = MethodChannel('readalarm/alarms');
  final TestWidgetsFlutterBinding binding;

  /// Alarms set, by id.
  final entries = <int, Map>{};
  final dismissed = <int>[];

  /// Ids Android lost (as when a phone force-stops the app).
  final lost = <int>{};
  Map<String, Object?>? launch;

  void dispose() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null);
  }

  /// Android opening the app for alarm [id] while it's running.
  Future<void> ring(int id, {String action = 'open'}) async {
    const codec = StandardMethodCodec();
    await binding.defaultBinaryMessenger.handlePlatformMessage(
      _channel.name,
      codec.encodeMethodCall(MethodCall('launch', {
        'payload': entries[id]!['payload'],
        'action': action,
        'cold': false,
      })),
      (_) {},
    );
  }

  Future<Object?> _handle(MethodCall call) async {
    final args = call.arguments as Map?;
    switch (call.method) {
      case 'set':
        for (final e in args!['entries'] as List) {
          entries[(e as Map)['id'] as int] = e;
          lost.remove(e['id']);
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
        return [
          for (final id in args!['ids'] as List)
            entries.containsKey(id) && !lost.contains(id),
        ];
      case 'takeLaunch':
        final l = launch;
        launch = null;
        return l;
    }
    return null;
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late FakeAlarmEngine engine;

  setUp(() => engine = FakeAlarmEngine(binding));
  tearDown(() => engine.dispose());

  ReadingAlarm alarm({Set<int> days = const {0, 2, 4}}) => ReadingAlarm(
        id: 'a1',
        time: const TimeOfDay(hour: 19, minute: 0),
        book: SampleData.books.first,
        durationMin: 15,
        repeatDays: days,
      );

  test('a weekly alarm is set as one alarm-clock ring per day', () async {
    final scheduler = NotificationAlarmScheduler();
    await scheduler.schedule(alarm());
    expect(engine.entries, hasLength(3));
    final days = [for (final e in engine.entries.values) e['weekday']]..sort();
    expect(days, [1, 3, 5], reason: 'Mon, Wed, Fri (Monday = 1)');
    for (final e in engine.entries.values) {
      expect(e['hour'], 19);
      expect(e['minute'], 0);
      final payload = AlarmPayload.decode(e['payload'] as String)!;
      expect(payload.alarmId, 'a1');
      expect(payload.durationMin, 15);
    }
    expect(await scheduler.pendingAlarmIds(), {'a1'});
  });

  test('dropping days cancels only those; disabling cancels all', () async {
    final scheduler = NotificationAlarmScheduler();
    final a = alarm();
    await scheduler.schedule(a);
    final monday = alarmNotificationIds(a)['Mon']!;
    await scheduler.schedule(a.copyWith(repeatDays: {0}));
    expect(engine.entries.keys, [monday]);
    await scheduler.schedule(a.copyWith(enabled: false));
    expect(engine.entries, isEmpty);
  });

  test('a one-off alarm rings once at its date and time', () async {
    final scheduler = NotificationAlarmScheduler();
    final tomorrow =
        DateUtils.dateOnly(DateTime.now()).add(const Duration(days: 1));
    await scheduler
        .schedule(alarm(days: const {}).copyWith(date: () => tomorrow));
    final e = engine.entries.values.single;
    expect(e['weekday'], 0);
    expect(DateTime.fromMillisecondsSinceEpoch(e['at'] as int),
        tomorrow.add(const Duration(hours: 19)));
  });

  test('dismissing silences every ring of the alarm', () async {
    final scheduler = NotificationAlarmScheduler();
    await scheduler.dismiss('a1');
    expect(
        engine.dismissed.toSet(),
        alarmNotificationIds(alarm(days: const {0, 1, 2, 3, 4, 5, 6}))
            .values
            .toSet()
          ..add(alarmNotificationIds(alarm(days: const {}))['Once']!));
  });

  test('Android asked directly whether it still holds each ring', () async {
    final scheduler = NotificationAlarmScheduler();
    final a = alarm();
    await scheduler.schedule(a);
    engine.lost.add(alarmNotificationIds(a)['Wed']!);
    expect(await scheduler.heldByAndroid(a),
        {'Mon': true, 'Wed': false, 'Fri': true});
  });

  test('alarm launches reach the app, cold or while running', () async {
    final scheduler = NotificationAlarmScheduler();
    final launches = <AlarmLaunch>[];
    await scheduler.init(launches.add);
    await scheduler.schedule(alarm());

    final id = alarmNotificationIds(alarm())['Mon']!;
    engine.launch = {
      'payload': engine.entries[id]!['payload'],
      'action': 'start',
      'cold': true,
    };
    final cold = await scheduler.takeLaunch();
    expect(cold!.payload.alarmId, 'a1');
    expect(cold.action, AlarmAction.start);
    expect(cold.cold, isTrue);
    expect(await scheduler.takeLaunch(), isNull, reason: 'taken once');

    await engine.ring(id);
    expect(launches.single.action, AlarmAction.open);
    expect(launches.single.cold, isFalse);
  });
}
