import 'package:flutter/material.dart';
import '../screens/paywall_screen.dart';
import '../services/ads_service.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';

/// Bottom banner slot for free users (ADS-2). Renders nothing for Premium.
///
/// The banner is AdMob's (see [AdsService]); it takes no space until an ad
/// has loaded.
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
          Expanded(child: AdsService.instance.banner()),
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
