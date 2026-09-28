import 'package:flutter/material.dart';
import '../../state/app_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart';

/// Onboarding 5 — brand-specific auto-start guide (ONB-3).
///
/// Production: preselect the brand from device_info_plus
/// (AndroidDeviceInfo.manufacturer) and deep-link to the OEM settings page
/// where possible.
class OemAutostartScreen extends StatefulWidget {
  const OemAutostartScreen({super.key, required this.onNext});
  final VoidCallback onNext;

  @override
  State<OemAutostartScreen> createState() => _OemAutostartScreenState();
}

class _OemAutostartScreenState extends State<OemAutostartScreen> {
  String _brand = 'Tecno / Infinix / itel';

  static const _guides = <String, List<String>>{
    'Tecno / Infinix / itel': [
      'Open Phone Master (or Settings → Battery).',
      'Go to App launch / Auto-start management.',
      'Find ReadAlarm and turn Auto-start on.',
      'Set Background activity to Allow.',
    ],
    'Xiaomi / Redmi / Poco': [
      'Open Settings → Apps → Manage apps → ReadAlarm.',
      'Turn Autostart on.',
      'Battery saver → No restrictions.',
      'In Recents, pull down on ReadAlarm to lock it.',
    ],
    'Samsung': [
      'Open Settings → Battery → Background usage limits.',
      'Remove ReadAlarm from Sleeping and Deep sleeping apps.',
      'Add ReadAlarm to Never sleeping apps.',
    ],
    'Oppo / Realme': [
      'Open Settings → Battery → App battery management.',
      'Find ReadAlarm and allow Auto launch and Run in background.',
    ],
    'Other': [
      'Open Settings → Apps → ReadAlarm → Battery.',
      'Choose Unrestricted.',
    ],
  };

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final steps = _guides[_brand]!;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      children: [
        const Center(
            child: IconBadge(icon: Icons.phone_android_rounded, size: 96)),
        const SizedBox(height: 20),
        const Text(
          'One more step for your phone',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Some phone brands close apps in the background. Pick yours and '
          'follow the steps.',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 15, height: 1.45, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (final brand in _guides.keys)
              ChoiceChip(
                label: Text(brand),
                selected: brand == _brand,
                onSelected: (_) => setState(() => _brand = brand),
                selectedColor: AppColors.orange,
                backgroundColor: AppColors.surface,
                showCheckmark: false,
                side: BorderSide(
                  color: brand == _brand ? AppColors.orange : AppColors.border,
                ),
                labelStyle: TextStyle(
                  color:
                      brand == _brand ? Colors.white : AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
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
                        child: Text(
                          steps[i],
                          style: const TextStyle(fontSize: 15, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        PrimaryButton(
          label: 'I\'ve done this',
          onPressed: () {
            state.grantPermission('autoStart');
            widget.onNext();
          },
        ),
        TextButton(
          onPressed: widget.onNext,
          child: const Text('Skip for now',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
      ],
    );
  }
}
