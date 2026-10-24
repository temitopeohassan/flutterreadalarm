import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/permission_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart';

/// Onboarding 5 — brand-specific auto-start guide (ONB-3). The phone's brand
/// is preselected; Android has no API to check this setting, so the user
/// confirms it themselves.
class OemAutostartScreen extends StatefulWidget {
  const OemAutostartScreen({super.key, required this.onNext});
  final VoidCallback onNext;

  /// The guide matching a manufacturer name from device info.
  static String brandFor(String manufacturer) {
    final m = manufacturer.toLowerCase();
    if (['tecno', 'infinix', 'itel', 'transsion'].any(m.contains)) {
      return 'Tecno / Infinix / itel';
    }
    if (['xiaomi', 'redmi', 'poco'].any(m.contains)) {
      return 'Xiaomi / Redmi / Poco';
    }
    if (m.contains('samsung')) return 'Samsung';
    if (['oppo', 'realme', 'oneplus'].any(m.contains)) return 'Oppo / Realme';
    return 'Other';
  }

  @override
  State<OemAutostartScreen> createState() => _OemAutostartScreenState();
}

class _OemAutostartScreenState extends State<OemAutostartScreen> {
  String? _brand;

  static const _guides = <String, List<String>>{
    'Tecno / Infinix / itel': [
      'Tap Open auto-start settings below. It opens Phone Master\'s '
          'Auto-start list (it isn\'t in Android\'s app settings).',
      'Find ReadAlarm and turn it on.',
      'If Phone Master opens on its home screen, look for Auto-start '
          'management (sometimes under Toolbox or App management).',
      'Then in Settings → Apps → ReadAlarm → Battery, allow background '
          'activity.',
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

  /// Opens the phone maker's auto-start page, with a hint if only a nearby
  /// page could be opened.
  Future<void> _openAutoStart(AppState state) async {
    final page = await state.services.permissions.openAutoStartSettings();
    if (!mounted) return;
    switch (page) {
      case AutoStartPage.autoStart:
        break;
      case AutoStartPage.phoneManager:
        showSnack(
            context,
            'Look for Auto-start management (sometimes under Toolbox or App '
            'management) and turn ReadAlarm on.');
      case AutoStartPage.appInfo:
        showSnack(
            context,
            'No separate auto-start page was found on this phone. Open '
            'Battery and allow ReadAlarm to run in the background.');
    }
  }

  Future<void> _copyReport(AppState state) async {
    final report = await state.services.permissions.autoStartReport();
    await Clipboard.setData(
        ClipboardData(text: 'ReadAlarm auto-start\n$report'));
    if (!mounted) return;
    showSnack(context, 'Phone details copied. Paste them to support.');
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final steps = _guides[_brand ??=
        OemAutostartScreen.brandFor(state.services.deviceBrand)]!;

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
        Align(
          alignment: Alignment.centerRight,
          // Long press: copy what this phone has, to send to support.
          child: GestureDetector(
            onLongPress: () => _copyReport(state),
            child: TextButton.icon(
              onPressed: () => _openAutoStart(state),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Open auto-start settings'),
              style: TextButton.styleFrom(foregroundColor: AppColors.orange),
            ),
          ),
        ),
        const SizedBox(height: 12),
        PrimaryButton(
          label: 'I\'ve done this',
          onPressed: () async {
            await state.requestPermission('autoStart');
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
