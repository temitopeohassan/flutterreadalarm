import 'package:flutter/material.dart';
import '../../state/app_state.dart';
import 'onboarding_page.dart';

/// Onboarding 3 — SCHEDULE_EXACT_ALARM (Android 12+).
///
/// Production: check AlarmManager.canScheduleExactAlarms(); if false, open
/// ACTION_REQUEST_SCHEDULE_EXACT_ALARM settings and re-check on resume.
class ExactAlarmPermissionScreen extends StatelessWidget {
  const ExactAlarmPermissionScreen({super.key, required this.onNext});
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final granted = state.permissions['exactAlarm']!;
    return OnboardingPage(
      icon: Icons.alarm_on_rounded,
      granted: granted,
      title: 'Start reading on time',
      body: 'Allow alarms and reminders so your book starts at the exact '
          'minute you set, not whenever Android decides.',
      primaryLabel: granted ? 'Continue' : 'Open alarm settings',
      onPrimary: () {
        if (!granted) state.grantPermission('exactAlarm');
        onNext();
      },
      secondaryLabel: granted ? null : 'Skip for now',
      onSecondary: onNext,
      skipConsequence: granted
          ? null
          : 'Without this, alarms can start late or not at all.',
    );
  }
}
