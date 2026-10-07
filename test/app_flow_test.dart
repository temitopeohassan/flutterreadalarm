import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readalarm/main.dart';
import 'package:readalarm/screens/main_shell.dart';
import 'package:readalarm/services/alarm_scheduler.dart';
import 'package:readalarm/services/book_importer.dart';
import 'package:readalarm/state/app_state.dart';

import 'support/fakes.dart';
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

  Future<void> close(WidgetTester tester, AppState state) async {
    await state.reader.finish('stop');
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  }

  testWidgets('onboarding: permissions, first book, test alarm, paywall',
      (tester) async {
    final (state, fakes) =
        await demoState(onboardingDone: false, emptyLibrary: true);
    await tester.pumpWidget(ReadAlarmApp(state: state));

    expect(find.text('Wake up to your book'), findsOneWidget);
    await tapText(tester, 'Get started');
    await tapText(tester, 'Allow notifications');
    await tapText(tester, 'Open alarm settings');
    await tapText(tester, 'Skip for now'); // battery
    expect(fakes.permissions.requested, ['notifications', 'exactAlarm']);
    expect(state.permissions['battery'], isFalse);

    // The phone's brand guide is preselected (fakes report a Tecno).
    expect(find.text('Open Phone Master (or Settings → Battery).'),
        findsOneWidget);
    await tapText(tester, 'I\'ve done this');
    expect(state.autoStartConfirmed, isTrue);

    expect(find.text('Add your first book'), findsOneWidget);
    await tapText(tester, 'Choose a PDF or EPUB');
    await tapText(tester, 'Choose EPUB');
    expect(find.text('Ready to read'), findsOneWidget);
    expect(find.text('The Quiet Morning'), findsOneWidget);
    await tapText(tester, 'Done');
    expect(state.books.single.title, 'The Quiet Morning');

    await tapText(tester, 'Run 1-minute test alarm');
    expect(fakes.alarms.once.single.$1.bookId, state.books.single.id);
    expect(find.text('Test alarm scheduled'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5)); // Let the snackbar go.

    await tapText(tester, 'Finish setup');
    expect(find.text('ReadAlarm Premium'), findsOneWidget);
    await tapText(tester, 'Continue with ads');

    expect(state.onboardingDone, isTrue);
    expect(find.byType(MainShell), findsOneWidget);
    await close(tester, state);
  });

  testWidgets('an unreadable file shows why it failed', (tester) async {
    final (state, fakes) = await demoState(emptyLibrary: true);
    fakes.importer.file = null;
    await tester.pumpWidget(ReadAlarmApp(state: state));
    await tapText(tester, 'Library');

    fakes.importer.file = null;
    await tester.tap(find.byTooltip('Add book'));
    await tester.pumpAndSettle();
    // A text-less PDF.
    fakes.importer.file = await _blankPdf();
    await tapText(tester, 'Choose PDF');
    expect(find.text('Can\'t read this file'), findsOneWidget);
    expect(find.textContaining('Scanned PDFs'), findsWidgets);
    expect(state.books, isEmpty);
    await tapText(tester, 'Cancel');
    await close(tester, state);
  });

  testWidgets('bottom tabs switch between the four main screens',
      (tester) async {
    final (state, _) = await demoState();
    await tester.pumpWidget(ReadAlarmApp(state: state));
    await tester.pumpAndSettle();

    for (final tab in ['Library', 'Stats', 'Settings', 'Home']) {
      await tapText(tester, tab);
      expect(tester.takeException(), isNull);
    }
    await close(tester, state);
  });

  testWidgets('reading from the library, minimising and stopping',
      (tester) async {
    final (state, fakes) = await demoState();
    await tester.pumpWidget(ReadAlarmApp(state: state));
    await tapText(tester, 'Library');
    await tapText(tester, 'Atomic Habits');

    expect(find.text('Reading now'), findsOneWidget);
    expect(fakes.speech.spoken, isNotEmpty);
    await tester.pump(const Duration(seconds: 3));

    // Minimise: reading continues and the mini player appears.
    await tester.tap(find.byTooltip('Minimise'));
    await tester.pumpAndSettle();
    expect(state.reader.active, isTrue);
    expect(find.text('Reading aloud'), findsOneWidget);

    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    expect(state.reader.playing, isFalse);

    await tapText(tester, 'Atomic Habits');
    await tapText(tester, 'Stop and save');
    expect(find.text('Session complete'), findsOneWidget);
    expect(state.sessions.first.bookTitle, 'Atomic Habits');
    await tapText(tester, 'Done');
    expect(find.byType(MainShell), findsOneWidget);
    await close(tester, state);
  });

  testWidgets('a ringing alarm opens the reminder; Start reads the book',
      (tester) async {
    final (state, fakes) = await demoState();
    await tester.pumpWidget(ReadAlarmApp(state: state));
    await tester.pumpAndSettle();

    // A 1-minute alarm, like the test alarm.
    final alarm = state.alarms.first.copyWith(durationMin: 1);
    await state.upsertAlarm(alarm);
    fakes.alarms
        .onLaunch!(AlarmLaunch(AlarmPayload.forAlarm(alarm), AlarmAction.open));
    await tester.pumpAndSettle();
    expect(find.text('Reading reminder'), findsOneWidget);
    expect(find.text('7:00 AM — Read 1 min'), findsOneWidget);

    await tapText(tester, 'Start reading');
    expect(fakes.alarms.dismissed, [alarm.id]);
    expect(find.text('Alarm session'), findsOneWidget);
    expect(state.reader.durationMin, alarm.durationMin);

    // The session ends by itself and shows the summary.
    await tester.pump(const Duration(minutes: 1, seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Session complete'), findsOneWidget);
    expect(find.text('You listened for 1 min'), findsOneWidget);
    await close(tester, state);
  });

  testWidgets('snoozing a ringing alarm rings again in 10 minutes',
      (tester) async {
    final (state, fakes) = await demoState();
    await tester.pumpWidget(ReadAlarmApp(state: state));
    await tester.pumpAndSettle();

    final alarm = state.alarms.first;
    fakes.alarms
        .onLaunch!(AlarmLaunch(AlarmPayload.forAlarm(alarm), AlarmAction.open));
    await tester.pumpAndSettle();
    await tapText(tester, 'Snooze 10 min');

    final (payload, at) = fakes.alarms.once.single;
    expect(payload.alarmId, alarm.id);
    expect(at.difference(DateTime.now()).inMinutes, closeTo(10, 1));
    expect(find.text('Reading reminder'), findsNothing);
    await close(tester, state);
  });

  testWidgets('saving a new alarm schedules it', (tester) async {
    final (state, fakes) = await demoState(premium: true);
    await tester.pumpWidget(ReadAlarmApp(state: state));
    await tester.pumpAndSettle();

    final count = state.alarms.length;
    await tester.tap(find.bySemanticsLabel('Add alarm'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Save alarm');

    expect(state.alarms.length, count + 1);
    expect(fakes.alarms.scheduled.containsKey(state.alarms.last.id), isTrue);
    await close(tester, state);
  });

  testWidgets('paywall shows the monthly plan without scrolling',
      (tester) async {
    final (state, _) = await demoState();
    await tester.pumpWidget(ReadAlarmApp(state: state));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Go ad-free').first);
    await tester.pumpAndSettle();

    for (final plan in ['Yearly', 'Monthly', 'Lifetime']) {
      final rect = tester.getRect(find.text(plan));
      expect(rect.bottom, lessThan(tester.view.physicalSize.height / 3),
          reason: '$plan should be on screen');
    }
    expect(find.text('₦1,500 / month'), findsOneWidget);

    await tester.tap(find.text('Monthly'));
    await tester.pumpAndSettle();
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Start 7-day free trial'), findsNothing);
    await close(tester, state);
  });

  testWidgets('settings: voice preview and test alarm', (tester) async {
    final (state, fakes) = await demoState(premium: true);
    await tester.pumpWidget(ReadAlarmApp(state: state));
    await tapText(tester, 'Settings');

    await tapText(tester, 'Preview voice');
    expect(fakes.speech.spoken.single, contains('ReadAlarm'));
    await tester.pump(const Duration(seconds: 3));

    await tapText(tester, 'Run 1-minute test alarm');
    expect(fakes.alarms.once, hasLength(1));
    await close(tester, state);
  });
}

Future<PickedBook> _blankPdf() async =>
    pickedFile('scan.pdf', buildPdfBytesWithoutText());
