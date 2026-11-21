import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readalarm/models/reading_alarm.dart';
import 'package:readalarm/services/alarm_scheduler.dart';
import 'package:readalarm/services/backend_service.dart';
import 'package:readalarm/state/app_state.dart';

import 'support/fakes.dart';

void main() {
  ReadingAlarm alarm({Set<int> days = const {4, 0, 2}}) => ReadingAlarm(
        id: 'new',
        time: const TimeOfDay(hour: 21, minute: 15),
        book: SampleData.books.first,
        durationMin: 15,
        repeatDays: days,
      );

  test('an alarm goes to the server with its days, time and payload', () {
    final now = DateTime(2026, 11, 20, 18);
    final weekly = alarmForServer(alarm(), now);
    expect(weekly['id'], 'new');
    expect(weekly['enabled'], isTrue);
    expect(weekly['hour'], 21);
    expect(weekly['minute'], 15);
    expect(weekly['days'], [0, 2, 4], reason: 'Monday = 0, sorted');
    expect(weekly['once_at'], isNull);
    final payload = AlarmPayload.decode(weekly['payload'] as String)!;
    expect(payload.alarmId, 'new');
    expect(payload.durationMin, 15);

    final once = alarmForServer(alarm(days: const {}), now);
    expect(once['days'], isEmpty);
    expect(
        once['once_at'], DateTime(2026, 11, 20, 21, 15).millisecondsSinceEpoch);
  });

  test('creating, switching off and deleting alarms reach the server',
      () async {
    final (state, fakes) = await demoState(premium: true);
    expect((await state.saveAlarm(alarm())).status, AlarmSaveStatus.saved);
    await pumpEventQueue();
    expect(fakes.backend.saved.single.id, 'new');

    await state.toggleAlarm(
        state.alarms.firstWhere((a) => a.id == 'new'), false);
    await pumpEventQueue();
    expect(fakes.backend.saved.last.enabled, isFalse);

    await state.deleteAlarm(state.alarms.firstWhere((a) => a.id == 'new'));
    await pumpEventQueue();
    expect(fakes.backend.deleted, ['new']);

    // Coming back to the app sends them all, catching up on offline changes.
    fakes.backend.synced.clear();
    await state.resyncAlarms();
    await pumpEventQueue();
    expect(fakes.backend.synced.single, [for (final a in state.alarms) a.id]);
    state.dispose();
  });

  test('opening an alarm stops its push from ringing it again', () async {
    final (state, fakes) = await demoState();
    state.openAlarm(AlarmLaunch(
        AlarmPayload.forAlarm(state.alarms.first), AlarmAction.open));
    await pumpEventQueue();
    expect(fakes.alarms.handled, [state.alarms.first.id]);
    state.dispose();
  });
}
