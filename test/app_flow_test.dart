import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readalarm/main.dart';
import 'package:readalarm/models/reading_alarm.dart';
import 'package:readalarm/screens/main_shell.dart';
import 'package:readalarm/services/alarm_scheduler.dart';
import 'package:readalarm/services/billing_service.dart';
import 'package:readalarm/services/permission_service.dart';
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

    // The phone's brand guide is preselected (fakes report a Tecno), and
    // the button opens the maker's auto-start page, not Android's app info.
    expect(
        find.textContaining('Phone Master\'s Auto-start list'), findsOneWidget);
    await tapText(tester, 'Open auto-start settings');
    expect(fakes.permissions.autoStartOpened, 1);
    expect(find.byType(SnackBar), findsNothing);

    // Only Phone Master's home screen found: say where to look.
    fakes.permissions.autoStartPage = AutoStartPage.phoneManager;
    await tapText(tester, 'Open auto-start settings');
    expect(
        find.textContaining('Look for Auto-start management'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5)); // Let the message go.
    await tester.pumpAndSettle();
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

    // The paywall offers Premium (no free trial) or the free version.
    await tapText(tester, 'Finish setup');
    expect(find.text('ReadAlarm Premium'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.textContaining('trial'), findsNothing);
    expect(state.onboardingDone, isFalse);
    await tapText(tester, 'Use The Free Version');
    expect(state.isPremium, isFalse);

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
    // Tapping a book offers reading or an alarm; it's 18% in.
    expect(find.text('Set an alarm'), findsOneWidget);
    await tapText(tester, 'Continue reading');

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

  testWidgets('a ringing alarm starts reading by itself after 30 seconds',
      (tester) async {
    final (state, fakes) = await demoState();
    await tester.pumpWidget(ReadAlarmApp(state: state));
    await tester.pumpAndSettle();
    final alarm = state.alarms.first;
    fakes.alarms
        .onLaunch!(AlarmLaunch(AlarmPayload.forAlarm(alarm), AlarmAction.open));
    await tester.pumpAndSettle();
    expect(find.text('Reading starts by itself in 30 s'), findsOneWidget);

    await tester.pump(const Duration(seconds: 10));
    expect(find.text('Reading starts by itself in 20 s'), findsOneWidget);
    expect(state.reader.active, isFalse);

    await tester.pump(const Duration(seconds: 20));
    await tester.pumpAndSettle();
    expect(state.reader.active, isTrue);
    expect(fakes.alarms.dismissed, [alarm.id], reason: 'the ringing stops');
    expect(find.text('Alarm session'), findsOneWidget);
    await close(tester, state);
  });

  testWidgets('snoozing stops the countdown; a preview has none',
      (tester) async {
    final (state, fakes) = await demoState();
    await tester.pumpWidget(ReadAlarmApp(state: state));
    await tester.pumpAndSettle();

    // The preview from Home never starts by itself.
    await tester.tap(find.byTooltip('Preview alarm screen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('starts by itself'), findsNothing);
    await tester.pump(const Duration(seconds: 40));
    expect(state.reader.active, isFalse);
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();

    final alarm = state.alarms.first;
    fakes.alarms
        .onLaunch!(AlarmLaunch(AlarmPayload.forAlarm(alarm), AlarmAction.open));
    await tester.pumpAndSettle();
    await tapText(tester, 'Snooze 10 min');
    await tester.pump(const Duration(seconds: 40));
    await tester.pumpAndSettle();
    expect(state.reader.active, isFalse);
    expect(fakes.alarms.once, hasLength(1), reason: 'snoozed');
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

    // Only monthly and yearly plans: no lifetime option.
    expect(find.text('Lifetime'), findsNothing);
    expect(find.textContaining('once'), findsNothing);
    for (final plan in ['Yearly', 'Monthly']) {
      final rect = tester.getRect(find.text(plan));
      expect(rect.bottom, lessThan(tester.view.physicalSize.height / 3),
          reason: '$plan should be on screen');
    }
    expect(find.text('₦1,500 / month'), findsOneWidget);

    // No free trial on either plan.
    expect(find.textContaining('trial'), findsNothing);
    await tester.tap(find.text('Monthly'));
    await tester.pumpAndSettle();
    expect(find.text('Continue'), findsOneWidget);
    expect(find.textContaining('trial'), findsNothing);
    await close(tester, state);
  });

  testWidgets('without Google Play, Premium can\'t be bought', (tester) async {
    final (state, _) = await demoState();
    await tester.pumpWidget(ReadAlarmApp(state: state));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go ad-free').first);
    await tester.pumpAndSettle();

    await tapText(tester, 'Continue');
    expect(find.textContaining('Purchases aren\'t available'), findsOneWidget);
    expect(state.isPremium, isFalse);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5)); // Let the message go.

    // No switch in Settings to turn Premium on or off.
    await tapText(tester, 'Settings');
    expect(find.text('Test mode: Premium'), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);
    await close(tester, state);
  });

  testWidgets('buying Premium on Google Play unlocks it', (tester) async {
    final (state, fakes) = await demoState();
    fakes.billing.available = true;
    await state.loadPrices();
    await tester.pumpWidget(ReadAlarmApp(state: state));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go ad-free').first);
    await tester.pumpAndSettle();

    // Google Play's prices.
    expect(find.text('₦12,000.00 / year'), findsOneWidget);
    expect(find.text('₦1,500.00 / month'), findsOneWidget);

    await tester.tap(find.text('Monthly'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Continue');
    expect(fakes.billing.bought, [PremiumPlans.monthly]);
    expect(state.isPremium, isTrue);
    // The paywall closes and Premium is welcomed.
    expect(find.text('ReadAlarm Premium'), findsNothing);
    expect(find.text('Welcome to Premium!'), findsOneWidget);
    expect(find.text('Go ad-free'), findsNothing, reason: 'no banner');
    await close(tester, state);
  });

  testWidgets('a pending payment says so and doesn\'t unlock Premium',
      (tester) async {
    final (state, fakes) = await demoState();
    fakes.billing
      ..available = true
      ..nextPurchase = BillingEventKind.pending;
    await tester.pumpWidget(ReadAlarmApp(state: state));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go ad-free').first);
    await tester.pumpAndSettle();
    await tapText(tester, 'Continue');
    expect(state.isPremium, isFalse);
    expect(find.textContaining('Payment pending'), findsOneWidget);
    await close(tester, state);
  });

  testWidgets('Restore purchases finds an active subscription', (tester) async {
    final (state, fakes) = await demoState();
    await tester.pumpWidget(ReadAlarmApp(state: state));
    await tapText(tester, 'Settings');

    // Not reachable.
    await tapText(tester, 'Restore purchases');
    expect(find.textContaining('Couldn\'t reach Google Play'), findsOneWidget);

    fakes.billing.available = true;
    await tapText(tester, 'Restore purchases');
    expect(find.textContaining('No active subscription'), findsOneWidget);

    fakes.billing.owned.add(PremiumPlans.yearly);
    await tapText(tester, 'Restore purchases');
    expect(find.text('Premium restored.'), findsOneWidget);
    expect(state.isPremium, isTrue);
    await close(tester, state);
  });

  testWidgets('60-minute sessions open the paywall on the free plan',
      (tester) async {
    final (state, _) = await demoState();
    await tester.pumpWidget(ReadAlarmApp(state: state));
    await tester.pumpAndSettle();
    await tapText(tester, 'Read 30 min');

    // Drag the duration slider to its last stop, 60 minutes.
    final slider = find.byType(Slider);
    await tester.drag(slider, const Offset(400, 0));
    await tester.pumpAndSettle();
    expect(find.text('ReadAlarm Premium'), findsOneWidget);
    expect(find.textContaining('Watch'), findsNothing, reason: 'no ad offer');
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('60 min'), findsNothing);
    await close(tester, state);
  });

  testWidgets('a free user can switch on only one alarm', (tester) async {
    final (state, fakes) = await demoState();
    await tester.pumpWidget(ReadAlarmApp(state: state));
    await tester.pumpAndSettle();

    // The demo's second alarm is off; switching it on needs Premium.
    await tester.tap(find.byType(Switch).last);
    await tester.pumpAndSettle();
    expect(find.text('ReadAlarm Premium'), findsOneWidget);
    expect(state.alarms.where((a) => a.enabled), hasLength(1));
    expect(fakes.alarms.scheduled.keys, ['a1']);
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

  testWidgets('a library book can start an alarm for itself', (tester) async {
    final (state, fakes) = await demoState();
    for (final a in List.of(state.alarms)) {
      await state.deleteAlarm(a);
    }
    await tester.pumpWidget(ReadAlarmApp(state: state));
    await tapText(tester, 'Library');
    await tapText(tester, 'Project Hail Mary');
    await tapText(tester, 'Set an alarm');

    // Free users can add one alarm; the editor has the book chosen.
    expect(find.text('Set new alarm'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(DropdownButton<BookInfo>),
            matching: find.text('Project Hail Mary')),
        findsWidgets);
    await tapText(tester, 'Save alarm');

    final added = state.alarms.last;
    expect(state.alarms, hasLength(1));
    expect(added.book.id, 'b3');
    expect(fakes.alarms.scheduled.containsKey(added.id), isTrue);

    // A second alarm needs Premium.
    await tapText(tester, 'Library');
    await tester.tap(find.byTooltip('Book options').first);
    await tester.pumpAndSettle();
    await tapText(tester, 'Set an alarm');
    expect(find.text('ReadAlarm Premium'), findsOneWidget);
    await close(tester, state);
  });

  testWidgets('the editor refuses a second alarm for the same moment',
      (tester) async {
    final (state, _) = await demoState(premium: true);
    await tester.pumpWidget(ReadAlarmApp(state: state));
    await tester.pumpAndSettle();

    // 7:00 Mon/Wed/Fri is taken, so a new alarm starts at 7:30.
    await tester.tap(find.bySemanticsLabel('Add alarm'));
    await tester.pumpAndSettle();
    expect(find.text('07'), findsOneWidget);
    expect(find.text('30'), findsWidgets); // minutes (and the 30-min slider)

    for (var i = 0; i < 30; i++) {
      await tester.tap(find.byTooltip('Earlier minute'));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(find.text('00'), findsOneWidget);
    final count = state.alarms.length;
    await tapText(tester, 'Save alarm');

    expect(find.text('An alarm is already set for then'), findsOneWidget);
    expect(find.textContaining('The Midnight Library'), findsWidgets);
    await tapText(tester, 'OK');
    expect(state.alarms, hasLength(count));
    expect(find.text('Set new alarm'), findsOneWidget, reason: 'still open');
    await close(tester, state);
  });

  testWidgets('an alarm without repeat days asks for its date', (tester) async {
    final (state, fakes) = await demoState();
    for (final a in List.of(state.alarms)) {
      await state.deleteAlarm(a);
    }
    await tester.pumpWidget(ReadAlarmApp(state: state));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Add alarm').first);
    await tester.pumpAndSettle();

    expect(find.text('Date'), findsNothing);
    for (final day in ['Monday', 'Wednesday', 'Friday']) {
      await tester.tap(find.bySemanticsLabel(RegExp('^$day')));
    }
    await tester.pumpAndSettle();
    expect(find.text('Date'), findsOneWidget);
    expect(find.textContaining(RegExp('^(Today|Tomorrow), ')), findsOneWidget);

    await tapText(tester, 'Save alarm');
    final added = state.alarms.last;
    expect(added.isOneOff, isTrue);
    expect(added.date, isNotNull);
    expect(added.onceAt!.isAfter(DateTime.now()), isTrue);
    expect(fakes.alarms.scheduled.containsKey(added.id), isTrue);
    expect(find.textContaining('Once · '), findsOneWidget);
    await close(tester, state);
  });

  testWidgets('using up the free minutes shows when reading resets',
      (tester) async {
    final (state, _) = await demoState();
    state.updatePosition('b2', 0);
    await tester.pumpWidget(ReadAlarmApp(state: state));
    await tapText(tester, 'Library');
    await tapText(tester, 'Atomic Habits');
    await tapText(tester, 'Start reading');
    expect(
        find.textContaining('Free reading left today: 15:00'), findsOneWidget);

    await tester.pump(const Duration(minutes: 15, seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('You\'ve used today\'s 15 free minutes'), findsOneWidget);
    expect(find.textContaining('resets at midnight'), findsOneWidget);

    // Billing isn't connected: buying doesn't unlock Premium.
    await tapText(tester, 'Continue');
    expect(find.textContaining('Purchases aren\'t available'), findsOneWidget);
    expect(state.isPremium, isFalse);

    // Closing it shows the session summary; reading again is refused.
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Session complete'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5)); // Let the message go.
    await tapText(tester, 'Done');
    await tapText(tester, 'Library');
    await tapText(tester, 'Atomic Habits');
    await tapText(tester, 'Continue reading');
    expect(find.text('You\'ve used today\'s 15 free minutes'), findsOneWidget);
    expect(state.reader.active, isFalse);
    await close(tester, state);
  });

  testWidgets('returning to the app puts back dropped alarms', (tester) async {
    final (state, fakes) = await demoState();
    await tester.pumpWidget(ReadAlarmApp(state: state));
    await tester.pumpAndSettle();
    fakes.alarms.dropAll();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(fakes.alarms.scheduled.keys, ['a1']);
    await close(tester, state);
  });

  testWidgets('returning to the app picks up another instance\'s changes',
      (tester) async {
    final (state, fakes) = await demoState();
    await tester.pumpWidget(ReadAlarmApp(state: state));
    await tapText(tester, 'Library');

    // Another copy of the app (started by an alarm) read on.
    final other = await AppState.load(fakes.services);
    other.updatePosition('b2', 500);
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.textContaining('50%'), findsOneWidget);

    other.dispose();
    await close(tester, state);
  });
}

Future<PickedBook> _blankPdf() async =>
    pickedFile('scan.pdf', buildPdfBytesWithoutText());
