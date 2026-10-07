import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/ads_service.dart';
import '../services/speech.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../widgets/common.dart';
import '../widgets/navy_header.dart';
import 'onboarding/oem_autostart_screen.dart';
import 'paywall_screen.dart';

/// Screen — Settings: Premium, voice, permission health, privacy, purchases
/// (TTS-2, ONB-2, ADS-1, PAY-4).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const _permissionLabels = {
    'notifications': ('Notifications', 'Lock-screen reading controls'),
    'exactAlarm': ('Alarms and reminders', 'Start on the exact minute'),
    'battery': ('Background reading', 'Not stopped by battery saver'),
    'autoStart': ('Auto-start', 'Phone brand settings'),
  };

  /// Fixes a missing permission. Auto-start has no system prompt, so it
  /// opens the phone-brand guide instead.
  Future<void> _fix(BuildContext context, String key) async {
    final state = AppScope.of(context);
    if (key != 'autoStart') return state.requestPermission(key);
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.cream,
          surfaceTintColor: Colors.transparent,
        ),
        body: OemAutostartScreen(onNext: () => Navigator.pop(context)),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);

    return Scaffold(
      body: Column(
        children: [
          const NavyHeader(title: 'Settings'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              children: [
                _PremiumCard(isPremium: state.isPremium),
                const SizedBox(height: 24),
                const SectionTitle('Voice'),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text('Voice',
                                style: TextStyle(fontWeight: FontWeight.w600)),
                          ),
                          if (!state.isPremium) const PremiumChip(),
                        ],
                      ),
                      const SizedBox(height: 6),
                      DropdownButton<VoiceOption?>(
                        value: state.voices.contains(state.voice)
                            ? state.voice
                            : null,
                        isExpanded: true,
                        underline: const SizedBox.shrink(),
                        items: [
                          const DropdownMenuItem(
                              value: null, child: Text('Default voice')),
                          for (final v in state.voices)
                            DropdownMenuItem(
                              value: v,
                              child: Text(v.label,
                                  overflow: TextOverflow.ellipsis),
                            ),
                        ],
                        onChanged: (v) {
                          if (!state.isPremium) {
                            PaywallScreen.open(context);
                          } else {
                            state.setVoice(v);
                          }
                        },
                      ),
                      const Divider(color: AppColors.border),
                      _SliderRow(
                        label: 'Speed',
                        value: state.speed,
                        onChanged: state.setSpeed,
                      ),
                      _SliderRow(
                        label: 'Pitch',
                        value: state.pitch,
                        locked: !state.isPremium,
                        onChanged: state.setPitch,
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed:
                              state.reader.active ? null : state.previewVoice,
                          icon: const Icon(Icons.play_circle_outline_rounded),
                          label: const Text('Preview voice'),
                          style: TextButton.styleFrom(
                              foregroundColor: AppColors.orange),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SectionTitle(
                  'Alarm health',
                  trailing: Text(
                    state.allPermissionsGranted ? 'All set' : 'Needs attention',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: state.allPermissionsGranted
                          ? const Color(0xFF3E8E5E)
                          : AppColors.orangeDark,
                    ),
                  ),
                ),
                AppCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      for (final e in _permissionLabels.entries)
                        ListTile(
                          leading: Icon(
                            state.permissions[e.key]!
                                ? Icons.check_circle_rounded
                                : Icons.error_rounded,
                            color: state.permissions[e.key]!
                                ? const Color(0xFF3E8E5E)
                                : AppColors.orange,
                          ),
                          title: Text(e.value.$1),
                          subtitle: Text(e.value.$2),
                          trailing: state.permissions[e.key]!
                              ? null
                              : TextButton(
                                  onPressed: () => _fix(context, e.key),
                                  child: const Text('Fix'),
                                ),
                        ),
                      ListTile(
                        leading: const Icon(Icons.timer_outlined,
                            color: AppColors.navy),
                        title: const Text('Run 1-minute test alarm'),
                        onTap: () async {
                          final scheduled = await state.scheduleTestAlarm();
                          if (!context.mounted) return;
                          showSnack(
                              context,
                              scheduled
                                  ? 'Test alarm set for 1 minute from now. '
                                      'Lock your phone.'
                                  : 'Add a book in Library first.');
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const SectionTitle('Account'),
                AppCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.restore_rounded,
                            color: AppColors.navy),
                        title: const Text('Restore purchases'),
                        // TODO: Purchases.restorePurchases()
                        onTap: () =>
                            showSnack(context, 'No previous purchases found.'),
                      ),
                      if (!state.isPremium)
                        ListTile(
                          leading: const Icon(Icons.privacy_tip_outlined,
                              color: AppColors.navy),
                          title: const Text('Ad privacy options'),
                          onTap: AdsService.instance.showPrivacyOptions,
                        ),
                      ListTile(
                        leading: const Icon(Icons.info_outline_rounded,
                            color: AppColors.navy),
                        title: const Text('About ReadAlarm'),
                        subtitle: const Text('Version 0.1.0'),
                        onTap: () => showAboutDialog(
                          context: context,
                          applicationName: 'ReadAlarm',
                          applicationVersion: '0.1.0',
                        ),
                      ),
                      if (kDebugMode)
                        SwitchListTile(
                          secondary: const Icon(Icons.bug_report_outlined,
                              color: AppColors.navy),
                          title: const Text('Debug: simulate Premium'),
                          value: state.isPremium,
                          activeTrackColor: AppColors.orange,
                          onChanged: state.setPremium,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumCard extends StatelessWidget {
  const _PremiumCard({required this.isPremium});
  final bool isPremium;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: AppColors.navy,
      onTap: isPremium ? null : () => PaywallScreen.open(context),
      child: Row(
        children: [
          const Icon(Icons.auto_stories_rounded,
              color: AppColors.orange, size: 36),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPremium ? 'Premium is active' : 'Go ad-free with Premium',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isPremium
                      ? 'No ads. Unlimited books and alarms.'
                      : 'Unlimited books, 60-min sessions, every voice.',
                  style:
                      const TextStyle(color: Color(0xFFC9CFE3), fontSize: 13),
                ),
              ],
            ),
          ),
          if (!isPremium)
            const Icon(Icons.chevron_right_rounded, color: Colors.white),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.locked = false,
  });

  final String label;
  final double value;
  final bool locked;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 56,
          child:
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: GestureDetector(
            // Locked slider is disabled; tapping it opens the paywall.
            onTap: locked ? () => PaywallScreen.open(context) : null,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppColors.orange,
                inactiveTrackColor: AppColors.peach,
                thumbColor: AppColors.orange,
                disabledActiveTrackColor: AppColors.peachBorder,
                disabledInactiveTrackColor: AppColors.peach,
                disabledThumbColor: AppColors.peachBorder,
              ),
              child: Slider(
                value: value,
                min: 0.5,
                max: 2.0,
                divisions: 6,
                label: '${value.toStringAsFixed(2)}x',
                onChanged: locked ? null : onChanged,
              ),
            ),
          ),
        ),
        SizedBox(
          // Wide enough for the Premium chip (lock icon + label).
          width: locked ? 84 : 60,
          child: locked
              ? const PremiumChip()
              : Text('${value.toStringAsFixed(2)}x',
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: AppColors.textSecondary)),
        ),
      ],
    );
  }
}
