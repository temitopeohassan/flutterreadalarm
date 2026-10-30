import 'dart:async';

import 'package:flutter/material.dart';
import '../../models/reading_alarm.dart';
import '../../state/app_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart';

/// The alarm test (onboarding, and Settings → Alarm health): proves alarms
/// work on this phone. ReadAlarm sets an alarm for a minute from now and
/// closes itself, as the phone's power manager might; the test passes when
/// that alarm opens ReadAlarm again. Android can't report auto-start or
/// the recent-apps lock, so this checks their result instead.
class AlarmTestScreen extends StatefulWidget {
  const AlarmTestScreen({
    super.key,
    required this.onPassed,
    this.onCheckSettings,
  });

  /// Continue (onboarding) or close (Settings) once the test has passed,
  /// or when the user chooses to carry on after a failure.
  final VoidCallback onPassed;

  /// Back to the auto-start and recent-apps steps.
  final VoidCallback? onCheckSettings;

  /// Opened from Settings or Home's warning.
  static Future<void> open(BuildContext context) =>
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (context) => Scaffold(
            appBar: AppBar(
              backgroundColor: AppColors.cream,
              surfaceTintColor: Colors.transparent,
            ),
            body: AlarmTestScreen(onPassed: () => Navigator.pop(context)),
          ),
        ),
      );

  @override
  State<AlarmTestScreen> createState() => _AlarmTestScreenState();
}

class _AlarmTestScreenState extends State<AlarmTestScreen> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Moves from "waiting" to "failed" when the wait is over.
    _tick = Timer.periodic(
        const Duration(seconds: 5), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// Says what's about to happen (ReadAlarm closes itself), then starts.
  Future<void> _start(AppState state) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ReadAlarm will close now'),
        content: const Text(
          'This checks an alarm can open ReadAlarm when it\'s closed.\n\n'
          '1. ReadAlarm closes.\n'
          '2. Lock your phone and wait.\n'
          '3. In about a minute the test alarm rings and opens ReadAlarm.\n\n'
          'If nothing rings within 2 minutes, open ReadAlarm again: it will '
          'say what to check.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Close ReadAlarm and test'),
          ),
        ],
      ),
    );
    if (ok == true) await state.startAlarmTest();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final status = state.alarmTestStatus;
    final started = state.alarmTestStartedAt;
    final ringsAt = started == null
        ? null
        : TimeOfDay.fromDateTime(started.add(const Duration(minutes: 1)));

    final (icon, title, body) = switch (status) {
      AlarmTestStatus.notRun => (
          Icons.alarm_rounded,
          'Check your alarm works',
          'Tap Start test. ReadAlarm sets an alarm for one minute from now and '
              'closes itself. Lock your phone and wait: the alarm should ring '
              'and open ReadAlarm.',
        ),
      AlarmTestStatus.waiting => (
          Icons.hourglass_top_rounded,
          'Waiting for the test alarm',
          'It rings at ${ringsAt == null ? 'any moment' : formatTime(ringsAt)}. '
              'Close ReadAlarm and lock your phone until then.',
        ),
      AlarmTestStatus.passed => (
          Icons.check_rounded,
          'Your alarms work',
          'The test alarm opened ReadAlarm while it was closed, so your '
              'reading alarms will ring on this phone.',
        ),
      AlarmTestStatus.ranWhileOpen => (
          Icons.refresh_rounded,
          'Let\'s try that again',
          'ReadAlarm was still open when the alarm rang, so this didn\'t test '
              'a closed app. Start the test again and leave ReadAlarm closed.',
        ),
      AlarmTestStatus.failed => (
          Icons.error_outline_rounded,
          'The alarm didn\'t open ReadAlarm',
          'Your phone stopped the alarm while ReadAlarm was closed. Check that '
              'auto-start is on and ReadAlarm is locked in recent apps, then '
              'try again.',
        ),
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      children: [
        Center(child: IconBadge(icon: icon, size: 96)),
        const SizedBox(height: 20),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          body,
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 15, height: 1.45, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 28),
        if (status == AlarmTestStatus.passed)
          PrimaryButton(label: 'Continue', onPressed: widget.onPassed)
        else ...[
          PrimaryButton(
            label:
                status == AlarmTestStatus.notRun ? 'Start test' : 'Test again',
            icon: Icons.alarm_on_rounded,
            onPressed: () => _start(state),
          ),
          if (status == AlarmTestStatus.failed) ...[
            if (widget.onCheckSettings != null)
              TextButton(
                onPressed: widget.onCheckSettings,
                child: const Text('Check auto-start and recent apps'),
              ),
            TextButton(
              onPressed: widget.onPassed,
              child: const Text(
                'Continue anyway (alarms may not ring)',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ],
        ],
      ],
    );
  }
}
