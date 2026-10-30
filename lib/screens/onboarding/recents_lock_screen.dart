import 'package:flutter/material.dart';
import '../../state/app_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart';
import 'oem_autostart_screen.dart';

/// Onboarding — lock ReadAlarm in recent apps, so the phone's cleaner
/// doesn't close it. Android can't report this setting, so the user
/// confirms it; the alarm test that follows checks the result.
class RecentsLockScreen extends StatelessWidget {
  const RecentsLockScreen({super.key, required this.onNext});
  final VoidCallback onNext;

  static const _guides = <String, List<String>>{
    'Tecno / Infinix / itel': [
      'Open recent apps: tap the square button, or swipe up from the bottom '
          'and hold.',
      'Find the ReadAlarm card and pull it down (or tap the lock icon on '
          'it) until a lock appears.',
    ],
    'Xiaomi / Redmi / Poco': [
      'Open recent apps.',
      'Pull the ReadAlarm card down (or long-press it and tap the lock) '
          'until a lock appears.',
    ],
    'Samsung': [
      'Open recent apps.',
      'Tap the ReadAlarm icon at the top of its card, then Keep open.',
    ],
    'Oppo / Realme': [
      'Open recent apps.',
      'Tap the ⋮ on the ReadAlarm card (or pull it down), then Lock.',
    ],
    'Other': [
      'Open recent apps.',
      'If the ReadAlarm card has a lock or "keep open" option (tap its '
          'icon, ⋮, or pull it down), turn it on. Some phones don\'t have one: '
          'that\'s fine.',
    ],
  };

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final steps =
        _guides[OemAutostartScreen.brandFor(state.services.deviceBrand)]!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      children: [
        const Center(child: IconBadge(icon: Icons.lock_rounded, size: 96)),
        const SizedBox(height: 20),
        const Text(
          'Lock ReadAlarm in recent apps',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Your phone\'s cleaner closes apps in the background. A locked app '
          'is left running, so your alarms always ring.',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 15, height: 1.45, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),
        AppCard(
          child: Column(
            children: [
              for (var i = 0; i < steps.length; i++)
                Padding(
                  padding:
                      EdgeInsets.only(bottom: i == steps.length - 1 ? 0 : 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: AppColors.peach,
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.orangeDark,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(steps[i],
                            style: const TextStyle(fontSize: 15, height: 1.35)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Then come back to ReadAlarm.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),
        PrimaryButton(
          label: 'I\'ve locked it',
          onPressed: () async {
            await state.requestPermission('recentsLock');
            onNext();
          },
        ),
      ],
    );
  }
}
