import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readalarm/main.dart';
import 'package:readalarm/models/reading_alarm.dart';
import 'package:readalarm/services/alarm_scheduler.dart';
import 'package:readalarm/services/speech.dart';
import 'package:readalarm/state/app_state.dart';

import 'support/android_tts.dart';
import 'support/fakes.dart';
import 'support/finders.dart';

/// Alarms on the same book pick up where the last session stopped.
void main() {
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1080, 2400);
    view.devicePixelRatio = 3;
  });
  tearDown(() => TestWidgetsFlutterBinding
      .instance.platformDispatcher.views.first
      .reset());

  /// Rings [alarmId], starts reading, and ends the session: by time for a
  /// 1-minute alarm, otherwise with "Stop and save" after 20 seconds.
  Future<(int startedAt, int stoppedAt)> ring(
      WidgetTester tester, AppState state, FakeServices fakes, String alarmId,
      {AlarmPayload? payload}) async {
    final alarm = state.alarms.firstWhere((a) => a.id == alarmId);
    fakes.alarms.onLaunch!(
        AlarmLaunch(payload ?? AlarmPayload.forAlarm(alarm), AlarmAction.open));
    await tester.pumpAndSettle();
    await tapText(tester, 'Start reading');
    final startedAt = state.reader.index;
    if (alarm.durationMin == 1) {
      await tester.pump(const Duration(minutes: 1, seconds: 1));
      await tester.pumpAndSettle();
    } else {
      await tester.pump(const Duration(seconds: 20));
      await tapText(tester, 'Stop and save');
    }
    final stoppedAt = state.bookById(alarm.book.id).position;
    await tapText(tester, 'Done');
    return (startedAt, stoppedAt);
  }

  testWidgets('with the real speech engine on (simulated) Android',
      (tester) async {
    final tts = FakeAndroidTts(tester.binding);
    final (state, fakes) =
        await demoState(premium: true, speech: TtsSpeechEngine());
    // A second alarm on a1's book; 1 minute, so it ends on its timer.
    await state.saveAlarm(ReadingAlarm(
      id: 'a3',
      time: const TimeOfDay(hour: 21, minute: 0),
      book: state.bookById('b1'),
      durationMin: 1,
      repeatDays: const {6},
    ));
    await tester.pumpWidget(ReadAlarmApp(state: state));
    await tester.pumpAndSettle();

    var (start, stop) = await ring(tester, state, fakes, 'a1');
    expect(start, 420);
    expect(stop, greaterThan(start));
    for (final id in ['a3', 'a1', 'a3']) {
      final previous = stop;
      (start, stop) = await ring(tester, state, fakes, id);
      expect(start, previous, reason: '$id continues where the last stopped');
      expect(stop, greaterThan(start));
    }
    expect(tts.spoken, isNotEmpty);

    await tester.pumpWidget(const SizedBox());
    state.dispose();
    tts.dispose();
  });

  testWidgets('an alarm reaching an out-of-date copy of the app',
      (tester) async {
    // Two copies of the app sharing saved data (an alarm can start one).
    final (stale, fakes) = await demoState(premium: true);
    final current = await AppState.load(fakes.services);

    // The other copy read on, to sentence 500.
    current.updatePosition('b1', 500);
    await tester.pump();

    // The out-of-date copy, still at 420, handles the alarm.
    expect(stale.bookById('b1').position, 420);
    await tester.pumpWidget(ReadAlarmApp(state: stale));
    await tester.pumpAndSettle();
    fakes.alarms.onLaunch = stale.openAlarm;
    final (start, _) = await ring(tester, stale, fakes, 'a1');
    expect(start, 500, reason: 'reads on from the saved position');

    await tester.pumpWidget(const SizedBox());
    stale.dispose();
    current.dispose();
  });
}
