import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readalarm/main.dart';
import 'package:readalarm/screens/main_shell.dart';
import 'package:readalarm/state/app_state.dart';

import 'support/finders.dart';

void main() {
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1080, 2400);
    view.devicePixelRatio = 3;
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('onboarding walks through every step into the main app',
      (tester) async {
    final state = AppState();
    await tester.pumpWidget(ReadAlarmApp(state: state));

    expect(find.text('Wake up to your book'), findsOneWidget);
    await tapText(tester, 'Get started');

    await tapText(tester, 'Allow notifications');
    expect(state.permissions['notifications'], isTrue);

    // Exact alarm, battery and OEM auto-start steps.
    for (var i = 0; i < 3; i++) {
      await tapText(tester, 'Skip for now');
    }

    expect(find.text('Add your first book'), findsOneWidget);
    await tapText(tester, 'I\'ll add a book later');

    expect(find.text('ReadAlarm Premium'), findsOneWidget);
    await tapText(tester, 'Continue with ads');

    expect(state.onboardingDone, isTrue);
    expect(find.byType(MainShell), findsOneWidget);
  });

  testWidgets('bottom tabs switch between the four main screens',
      (tester) async {
    final state = AppState()..onboardingDone = true;
    await tester.pumpWidget(ReadAlarmApp(state: state));
    await tester.pumpAndSettle();

    for (final tab in ['Library', 'Stats', 'Settings', 'Home']) {
      await tapText(tester, tab);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('reminder preview opens and starts a reading session',
      (tester) async {
    final state = AppState()..onboardingDone = true;
    await tester.pumpWidget(ReadAlarmApp(state: state));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Preview alarm screen'));
    await tester.pumpAndSettle();
    expect(find.text('Reading reminder'), findsOneWidget);

    await tapText(tester, 'Start reading');
    expect(find.text('Alarm session'), findsOneWidget);

    final sessions = state.sessions.length;
    await tester.pump(const Duration(seconds: 5));
    await tester.scrollUntilVisible(find.text('Stop and save'), 200,
        scrollable: find.byType(Scrollable).last);
    await tapText(tester, 'Stop and save');

    expect(find.text('Session complete'), findsOneWidget);
    expect(state.sessions.length, sessions + 1);
  });

  testWidgets('saving a new alarm adds it to the list', (tester) async {
    final state = AppState()
      ..onboardingDone = true
      ..isPremium = true;
    await tester.pumpWidget(ReadAlarmApp(state: state));
    await tester.pumpAndSettle();

    final count = state.alarms.length;
    await tester.tap(find.bySemanticsLabel('Add alarm'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Save alarm'));
    await tapText(tester, 'Save alarm');

    expect(state.alarms.length, count + 1);
  });
}
