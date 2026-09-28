import 'package:flutter/material.dart';
import '../screens/paywall_screen.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';

/// Bottom banner slot for free users (ADS-2). Renders nothing for Premium.
///
/// Production: replace the placeholder box with `AdWidget(ad: bannerAd)`
/// sized from `AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize`,
/// and hide the slot if the ad fails to load.
class AdBannerSlot extends StatelessWidget {
  const AdBannerSlot({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (state.isPremium) return const SizedBox.shrink();

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.cream,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border),
              ),
              child: const Text(
                'Ad',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ),
          ),
          TextButton(
            onPressed: () => PaywallScreen.open(context),
            style: TextButton.styleFrom(foregroundColor: AppColors.orange),
            child: const Text('Go ad-free'),
          ),
        ],
      ),
    );
  }
}
