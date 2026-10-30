import 'package:flutter/material.dart';

import '../screens/onboarding/alarm_test_screen.dart';
import '../screens/onboarding/oem_autostart_screen.dart';
import '../screens/onboarding/recents_lock_screen.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';

/// Opens the auto-start ('autoStart') or recent-apps lock ('recentsLock')
/// step on its own.
Future<void> openAlarmSetupStep(BuildContext context, String key) =>
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.cream,
          surfaceTintColor: Colors.transparent,
        ),
        body: key == 'autoStart'
            ? OemAutostartScreen(onNext: () => Navigator.pop(context))
            : RecentsLockScreen(onNext: () => Navigator.pop(context)),
      ),
    ));

/// Alarms can't be set until the alarm test has passed, which confirms
/// auto-start and the recent-apps lock work (Android can't report those
/// settings, so tapping through them isn't enough). Returns true if it has;
/// otherwise explains, offers the two settings and the test, and returns
/// whether it has passed afterwards.
Future<bool> ensureAlarmSetup(BuildContext context) async {
  final state = AppScope.of(context);
  while (!state.alarmSetupDone) {
    final dropped = state.alarmsDroppedAt != null;
    final step = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finish alarm setup first'),
        content: Text(
          '${dropped ? 'Your phone removed ReadAlarm\'s alarm while it was '
              'closed. ' : ''}'
          'Turn on auto-start and lock ReadAlarm in recent apps, then pass '
          'the alarm test. Alarms can be set once the test passes.',
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(ctx, 'autoStart'),
            icon: const Icon(Icons.power_settings_new_rounded),
            label: const Text('Turn on auto-start'),
          ),
          TextButton.icon(
            onPressed: () => Navigator.pop(ctx, 'recentsLock'),
            icon: const Icon(Icons.lock_rounded),
            label: const Text('Lock in recent apps'),
          ),
          TextButton.icon(
            onPressed: () => Navigator.pop(ctx, 'alarmTest'),
            icon: const Icon(Icons.alarm_on_rounded),
            label: const Text('Run the alarm test'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Not now',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
    if (step == null || !context.mounted) return false;
    if (step == 'alarmTest') {
      await AlarmTestScreen.open(context);
    } else {
      await openAlarmSetupStep(context, step);
    }
    if (!context.mounted) return false;
  }
  return true;
}
