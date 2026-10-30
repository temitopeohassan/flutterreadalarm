import 'package:flutter/material.dart';

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

/// Alarms can't be set until auto-start and the recent-apps lock are done
/// (they decide whether alarms ring). Returns true if they are; otherwise
/// explains, offers each missing step, and returns whether they're done
/// afterwards.
Future<bool> ensureAlarmSetup(BuildContext context) async {
  final state = AppScope.of(context);
  while (!state.alarmSetupDone) {
    final step = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finish alarm setup first'),
        content: const Text(
          'Your phone can stop ReadAlarm\'s alarms unless these two settings '
          'are done. Alarms can be set once they are.',
        ),
        actions: [
          for (final (key, label, done) in [
            ('autoStart', 'Turn on auto-start', state.autoStartConfirmed),
            ('recentsLock', 'Lock in recent apps', state.recentsLockConfirmed),
          ])
            TextButton.icon(
              onPressed: done ? null : () => Navigator.pop(ctx, key),
              icon: Icon(done
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded),
              label: Text(label),
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
    await openAlarmSetupStep(context, step);
    if (!context.mounted) return false;
  }
  return true;
}
