import 'package:flutter/foundation.dart';

/// Ads facade (PRD ADS-1..7). Dependency-free stub so the UI runs as-is.
///
/// Production wiring with `google_mobile_ads`:
/// 1. ConsentInformation.instance.requestConsentInfoUpdate(...) then
///    ConsentForm.loadAndShowConsentFormIfRequired(...)       (ADS-1)
/// 2. Only if !isPremium && consent resolved:
///    MobileAds.instance.initialize()                         (ADS-6)
/// 3. BannerAd with AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize
/// 4. InterstitialAd.load(...) after Session complete, respecting caps (ADS-3)
/// 5. RewardedAd.load(...) for the 60-min unlock                (ADS-4)
/// Use Google's test ad unit IDs in debug builds (ADS-7).
class AdsService {
  AdsService._();
  static final instance = AdsService._();

  static const interstitialMinGap = Duration(minutes: 10);
  static const interstitialDailyCap = 3;

  DateTime? _lastInterstitial;
  int _shownToday = 0;

  /// Returns true if an interstitial was (or would be) shown.
  bool maybeShowInterstitial({required bool isPremium}) {
    if (isPremium) return false;
    final now = DateTime.now();
    if (_shownToday >= interstitialDailyCap) return false;
    if (_lastInterstitial != null &&
        now.difference(_lastInterstitial!) < interstitialMinGap) {
      return false;
    }
    _lastInterstitial = now;
    _shownToday++;
    debugPrint('[Ads] interstitial shown ($_shownToday/$interstitialDailyCap)');
    return true;
  }

  /// Simulates a rewarded ad. Returns true when the reward is earned.
  Future<bool> showRewarded() async {
    debugPrint('[Ads] rewarded ad shown');
    await Future<void>.delayed(const Duration(milliseconds: 600));
    return true;
  }

  Future<void> showPrivacyOptions() async {
    // ConsentForm.showPrivacyOptionsForm(...)
    debugPrint('[Ads] privacy options form');
  }
}
