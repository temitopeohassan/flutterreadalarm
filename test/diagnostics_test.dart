import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readalarm/main.dart';
import 'package:readalarm/services/diagnostics.dart';
import 'package:readalarm/services/event_log.dart';

import 'support/fakes.dart';
import 'support/finders.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('readalarm/diagnostics');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    EventLog.instance = EventLog.memory();
  });

  test('the report flags alarms Android dropped and phone restrictions',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'phone':
          return 'PHONE\nModel: TECNO KI5q\n'
              'Background restricted by user: true\n'
              'WHY READALARM WAS LAST CLOSED (newest first)\n'
              '2026-10-25 23:01:00  USER_REQUESTED (force stop: alarms '
              'removed)  importance=400';
        case 'registered':
          // a1 rings Mon, Wed, Fri: Android lost Wednesday's.
          final ids = (call.arguments as Map)['ids'] as List;
          return [for (var i = 0; i < ids.length; i++) i != 1];
        case 'logcat':
          return 'logcat lines';
      }
      return null;
    });
    final (state, _) = await demoState();
    logEvent('App started');
    final report = await Diagnostics.buildReport(state);

    expect(report, contains('READALARM DIAGNOSTICS REPORT'));
    expect(report, contains('Model: TECNO KI5q'));
    expect(report, contains('Android no longer holds its ring for Wed'));
    expect(report, contains('restricted in the background'));
    expect(report, contains('force-stopped or closed by the system'));
    expect(report, contains('Wed ring held by Android: no'));
    expect(report, contains('App started'));
    expect(report, contains('logcat lines'));
    state.dispose();
  });

  test('without the native side the report still builds', () async {
    final (state, _) = await demoState();
    final report = await Diagnostics.buildReport(state);
    expect(report, contains('Phone details unavailable.'));
    expect(report, contains('ring held by Android: unknown'));
    state.dispose();
  });

  test('alarm times with no "opened" record are listed', () async {
    // a1 rings 7:00 Mon, Wed, Fri. Logging began Sun 18 Oct 2026; the app
    // was opened by the alarm on Monday only.
    await withClock(Clock.fixed(DateTime(2026, 10, 24, 12)), () async {
      final log = EventLog.memory();
      EventLog.instance = log;
      await withClock(Clock.fixed(DateTime(2026, 10, 18, 9)),
          () async => logEvent('App started'));
      await withClock(Clock.fixed(DateTime(2026, 10, 19, 7, 0, 5)),
          () async => logEvent('Alarm a1 opened (open)'));
      final (state, _) = await demoState();
      final report = await Diagnostics.buildReport(state);
      expect(report, contains('a1 at 2026-10-21 07:00'));
      expect(report, contains('a1 at 2026-10-23 07:00'));
      expect(report, isNot(contains('a1 at 2026-10-19 07:00')));
      state.dispose();
    });
  });

  testWidgets('Settings → Send a problem report shows and sends the report',
      (tester) async {
    final sent = <Map>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'email') sent.add(call.arguments as Map);
      if (call.method == 'phone') return 'PHONE\nModel: TECNO';
      return call.method == 'email' ? true : null;
    });
    final (state, _) = await demoState();
    await tester.pumpWidget(ReadAlarmApp(state: state));
    await tapText(tester, 'Settings');
    await tester.scrollUntilVisible(find.text('Send a problem report'), 200,
        scrollable: find.byType(Scrollable).first);
    await tapText(tester, 'Send a problem report');
    expect(find.textContaining('Model: TECNO'), findsOneWidget);

    await tapText(tester, 'Send report');
    expect(sent.single['to'], Diagnostics.reportEmail);
    expect(sent.single['body'], contains('READALARM DIAGNOSTICS REPORT'));
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
}
