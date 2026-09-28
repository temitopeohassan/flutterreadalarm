import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart';

/// Shared layout for onboarding steps.
class OnboardingPage extends StatelessWidget {
  const OnboardingPage({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.skipConsequence,
    this.granted = false,
    this.child,
  });

  final IconData icon;
  final String title;
  final String body;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  /// Shown under the skip button so users know what breaks (ONB-2).
  final String? skipConsequence;
  final bool granted;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight - 32),
          child: IntrinsicHeight(
            child: Column(
              children: [
                const Spacer(),
                IconBadge(icon: granted ? Icons.check_rounded : icon),
                const SizedBox(height: 28),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.45,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (child != null) ...[const SizedBox(height: 20), child!],
                const Spacer(),
                const SizedBox(height: 24),
                PrimaryButton(label: primaryLabel, onPressed: onPrimary),
                if (secondaryLabel != null)
                  TextButton(
                    onPressed: onSecondary,
                    child: Text(
                      secondaryLabel!,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                if (skipConsequence != null)
                  Text(
                    skipConsequence!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textMuted),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
