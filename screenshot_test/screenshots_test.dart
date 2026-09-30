// Drives the real app through every screen and saves a PNG of each one to
// `screenshots/` at the repository root.
//
//   flutter test screenshot_test
//
// Rendering uses the Roboto and Material Icons fonts bundled with the Flutter
// SDK, on a 1080x2400 (360x800 dp @ 3x) phone-sized surface.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readalarm/main.dart';
import 'package:readalarm/state/app_state.dart';

import '../test/support/fakes.dart';
import '../test/support/finders.dart';

const _outDir = 'screenshots';
final _boundaryKey = GlobalKey();

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  final boundary =
      _boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final view = tester.view;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: view.devicePixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  File('$_outDir/$name.png').writeAsBytesSync(bytes!);
}

Future<void> _launch(WidgetTester tester, AppState state) async {
  await tester.pumpWidget(
    RepaintBoundary(key: _boundaryKey, child: ReadAlarmApp(state: state)),
  );
  await tester.pumpAndSettle();
}

/// Disposes the app (cancelling its timers) and restores debug flags, which
/// the test framework requires before the test body returns.
Future<void> _finish(WidgetTester tester, AppState state) async {
  await state.reader.finish('stop');
  await tester.pumpWidget(const SizedBox());
  state.dispose();
  debugDisableShadows = true;
}

void main() {
  setUpAll(() => Directory(_outDir).createSync(recursive: true));

  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1080, 2400);
    view.devicePixelRatio = 3;
    // Status bar and gesture-nav insets of a typical Android phone.
    view.padding = const FakeViewPadding(top: 72, bottom: 48);
    view.viewPadding = const FakeViewPadding(top: 72, bottom: 48);
    debugDisableShadows = false;
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.reset();
  });

  testWidgets('onboarding', (tester) async {
    final (state, fakes) =
        await demoState(onboardingDone: false, emptyLibrary: true);
    fakes.importer.slow = true;
    await _launch(tester, state);

    await _shot(tester, '01_onboarding_welcome');
    await tapText(tester, 'Get started');
    await _shot(tester, '02_onboarding_notifications');
    await tapText(tester, 'Allow notifications');
    await _shot(tester, '03_onboarding_exact_alarm');
    await tapText(tester, 'Open alarm settings');
    await _shot(tester, '04_onboarding_battery');
    await tapText(tester, 'Allow background reading');
    await _shot(tester, '05_onboarding_autostart');
    await tapText(tester, 'I\'ve done this');
    await _shot(tester, '06_onboarding_first_book');

    await tapText(tester, 'Choose a PDF or EPUB');
    await _shot(tester, '07_import_sheet');
    await tester.tap(find.text('Choose EPUB'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await _shot(tester, '08_import_sheet_extracting');
    await tester.pump(const Duration(seconds: 2));
    await _shot(tester, '09_import_sheet_ready');
    await tapText(tester, 'Done');
    await tapText(tester, 'Run 1-minute test alarm');
    await tester.pump(const Duration(seconds: 5)); // Let the snackbar go.
    await _shot(tester, '10_onboarding_first_book_added');

    await tapText(tester, 'Finish setup');
    await _shot(tester, '11_paywall');
    await tapText(tester, 'Continue with ads');
    await _shot(tester, '12_home_first_run');

    await _finish(tester, state);
  });

  testWidgets('main app', (tester) async {
    final (state, _) = await demoState();
    await _launch(tester, state);
    await _shot(tester, '13_home');

    await tapText(tester, 'Library');
    await _shot(tester, '14_library');
    await tapText(tester, 'Stats');
    await _shot(tester, '15_stats');
    await tapText(tester, 'Settings');
    await _shot(tester, '16_settings');
    await tapText(tester, 'Home');

    // Free tier already has the maximum number of alarms, so this opens the
    // paywall; close it and edit an existing alarm instead.
    await tester.tap(find.bySemanticsLabel('Add alarm'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('7:00 AM').first);
    await _shot(tester, '17_set_alarm');
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Preview alarm screen'));
    await _shot(tester, '18_reading_reminder');
    await tapText(tester, 'Start reading');
    await tester.pump(const Duration(seconds: 3));
    await _shot(tester, '19_now_playing');
    await tester.tap(find.byTooltip('Minimise'));
    await _shot(tester, '20_mini_player');
    await tapText(tester, 'The Midnight Library');
    await tapText(tester, 'Stop and save');
    await _shot(tester, '21_session_complete');
    await tapText(tester, 'Done');

    await tapText(tester, 'Library');
    await tester.tap(find.byTooltip('Add book'));
    await tester.pumpAndSettle();
    await _shot(tester, '22_free_book_limit');

    await _finish(tester, state);
  });
}
