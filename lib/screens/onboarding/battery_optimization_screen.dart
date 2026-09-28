import 'package:flutter/material.dart';
import '../../state/app_state.dart';
import 'onboarding_page.dart';

/// Onboarding 4 — battery optimization whitelist (Doze).
///
/// Production: FlutterForegroundTask.requestIgnoreBatteryOptimization(),
/// or open the battery optimization settings list if Play policy requires.
class BatteryOptimizationScreen extends StatelessWidget {
  const BatteryOptimizationScreen({super.key, required this.onNext});
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final granted = state.permissions['battery']!;
    return OnboardingPage(
      icon: Icons.battery_charging_full_rounded,
      granted: granted,
      title: 'Keep reading with the screen off',
      body: 'Let ReadAlarm run in the background so Android\'s battery saver '
          'doesn\'t stop your book halfway through. It only runs during a '
          'session.',
      primaryLabel: granted ? 'Continue' : 'Allow background reading',
      onPrimary: () {
        if (!granted) state.grantPermission('battery');
        onNext();
      },
      secondaryLabel: granted ? null : 'Skip for now',
      onSecondary: onNext,
      skipConsequence: granted
          ? null
          : 'Without this, reading may stop after a few minutes.',
    );
  }
}
