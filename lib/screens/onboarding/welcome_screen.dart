import 'package:flutter/material.dart';
import '../../widgets/reminder_illustration.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart';

/// Onboarding 1 — value proposition.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.onNext});
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        children: [
          const Spacer(),
          const ReminderIllustration(size: 260),
          const SizedBox(height: 28),
          const Text(
            'Wake up to your book',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Set a time and ReadAlarm reads your PDF or EPUB aloud, even with '
            'your phone locked. Tomorrow it picks up where you stopped.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              height: 1.45,
              color: AppColors.textSecondary,
            ),
          ),
          const Spacer(),
          PrimaryButton(label: 'Get started', onPressed: onNext),
          const SizedBox(height: 8),
          const Text(
            'Takes about a minute. We\'ll ask for a few permissions the alarm needs.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
