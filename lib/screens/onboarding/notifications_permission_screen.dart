import 'package:flutter/material.dart';
import '../../services/permission_service.dart';
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
      // On iPhone, the alarm itself comes as a notification.
      title: onIOS
          ? 'Get your reading alarms'
          : 'Control reading from your lock screen',
      body: onIOS
          ? 'Your reading alarms ring as notifications, with Start reading '
              'and Snooze buttons on the lock screen.'
          : 'Notifications let you pause, stop or snooze a session without '
              'unlocking your phone.',
      primaryLabel: granted ? 'Continue' : 'Allow notifications',
      onPrimary: () async {
        if (!granted) await state.requestPermission('notifications');
        onNext();
      },
      secondaryLabel: granted ? null : 'Skip for now',
      onSecondary: onNext,
      skipConsequence: granted
          ? null
          : onIOS
              ? 'Without this, your alarms can\'t ring.'
              : 'Without this, you won\'t see reading controls.',
    );
  }
}
