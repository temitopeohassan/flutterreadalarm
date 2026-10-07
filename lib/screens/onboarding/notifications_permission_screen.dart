import 'package:flutter/material.dart';
import '../../state/app_state.dart';
import 'onboarding_page.dart';

/// Onboarding 2 — POST_NOTIFICATIONS (Android 13+).
class NotificationsPermissionScreen extends StatelessWidget {
  const NotificationsPermissionScreen({super.key, required this.onNext});
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final granted = state.permissions['notifications']!;
    return OnboardingPage(
      icon: Icons.notifications_active_rounded,
      granted: granted,
      title: 'Control reading from your lock screen',
      body: 'Notifications let you pause, stop or snooze a session without '
          'unlocking your phone.',
      primaryLabel: granted ? 'Continue' : 'Allow notifications',
      onPrimary: () async {
        if (!granted) await state.requestPermission('notifications');
        onNext();
      },
      secondaryLabel: granted ? null : 'Skip for now',
      onSecondary: onNext,
      skipConsequence:
          granted ? null : 'Without this, you won\'t see reading controls.',
    );
  }
}
