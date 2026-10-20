import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../theme/app_colors.dart';

/// AdMob ad units. Google's test units by default, so test builds never
/// show real ads; the release build passes the real ones with
/// --dart-define (see README). The app id is set in android/app's
/// build.gradle.kts (admobAppId).
class AdUnits {
  static const banner = String.fromEnvironment('ADMOB_BANNER_ID',
      defaultValue: 'ca-app-pub-3940256099942544/9214589741');
  static const interstitial = String.fromEnvironment('ADMOB_INTERSTITIAL_ID',
      defaultValue: 'ca-app-pub-3940256099942544/1033173712');
  static const rewarded = String.fromEnvironment('ADMOB_REWARDED_ID',
      defaultValue: 'ca-app-pub-3940256099942544/5224354917');
}

/// Ads for free users (PRD ADS-1..7): a banner on the main screens, an
/// interstitial now and then after a session, and a rewarded ad that
/// unlocks 60-minute sessions for a day. Never on the alarm screens.
abstract class AdsService {
  /// The app's ads; tests keep the placeholder.
  static AdsService instance = PlaceholderAds();

  static const interstitialMinGap = Duration(minutes: 10);
  static const interstitialDailyCap = 3;

  /// Asks for consent where the law requires it (EEA, UK), then starts the
  /// ads SDK. Call once, after onboarding, for free users only.
  Future<void> start();

  /// Whether ads can be shown (consent gathered, SDK started).
  ValueListenable<bool> get ready;

  /// The bottom banner, or nothing if no ad could be loaded.
  Widget banner();

  /// Shows an interstitial if one is loaded and the caps allow. Returns
  /// true if one was shown.
  bool maybeShowInterstitial({required bool isPremium});

  /// Shows a rewarded ad; true once the reward is earned.
  Future<bool> showRewarded();

  /// Whether the user must be offered ad privacy choices (EEA, UK).
  Future<bool> privacyOptionsRequired();

  Future<void> showPrivacyOptions();
}

/// Interstitial caps, shared by the real and placeholder ads.
class _InterstitialCaps {
  DateTime? _last;
  int _shown = 0;
  DateTime _day = DateTime.now();

  bool allows(DateTime now) {
    if (!DateUtils.isSameDay(now, _day)) {
      _day = now;
      _shown = 0;
    }
    if (_shown >= AdsService.interstitialDailyCap) return false;
    final last = _last;
    return last == null ||
        now.difference(last) >= AdsService.interstitialMinGap;
  }

  void record(DateTime now) {
    _last = now;
    _shown++;
  }
}

/// Stands in for ads in tests and screenshots: a labelled box, and a
/// rewarded ad that always pays out.
class PlaceholderAds implements AdsService {
  final _caps = _InterstitialCaps();
  final _ready = ValueNotifier(true);

  @override
  Future<void> start() async {}

  @override
  ValueListenable<bool> get ready => _ready;

  @override
  Widget banner() => Container(
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.cream,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.border),
        ),
        child: const Text('Ad',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
      );

  @override
  bool maybeShowInterstitial({required bool isPremium}) {
    final now = DateTime.now();
    if (isPremium || !_caps.allows(now)) return false;
    _caps.record(now);
    return true;
  }

  @override
  Future<bool> showRewarded() async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    return true;
  }

  @override
  Future<bool> privacyOptionsRequired() async => false;

  @override
  Future<void> showPrivacyOptions() async {}
}

/// Google AdMob, with Google's consent form (UMP) where required.
class MobileAdsService implements AdsService {
  final _caps = _InterstitialCaps();
  final _ready = ValueNotifier(false);
  bool _starting = false;
  InterstitialAd? _interstitial;

  @override
  ValueListenable<bool> get ready => _ready;

  @override
  Future<void> start() async {
    if (_starting) return;
    _starting = true;
    try {
      await _gatherConsent();
      if (!await ConsentInformation.instance.canRequestAds()) return;
      await MobileAds.instance.initialize();
      _ready.value = true;
      _loadInterstitial();
    } catch (e) {
      debugPrint('Starting ads failed: $e');
    }
  }

  Future<void> _gatherConsent() {
    final done = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () => ConsentForm.loadAndShowConsentFormIfRequired((error) {
        if (error != null) debugPrint('Consent form: ${error.message}');
        if (!done.isCompleted) done.complete();
      }),
      (error) {
        // Offline etc.: ads may still be allowed from an earlier answer.
        debugPrint('Consent update failed: ${error.message}');
        if (!done.isCompleted) done.complete();
      },
    );
    return done.future;
  }

  void _loadInterstitial() {
    InterstitialAd.load(
      adUnitId: AdUnits.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitial = ad,
        onAdFailedToLoad: (error) =>
            debugPrint('Interstitial failed to load: ${error.message}'),
      ),
    );
  }

  @override
  Widget banner() => ValueListenableBuilder(
        valueListenable: _ready,
        builder: (context, ready, _) => ready
            ? LayoutBuilder(
                builder: (context, box) =>
                    _AdaptiveBanner(width: box.maxWidth.truncate()),
              )
            : const SizedBox.shrink(),
      );

  @override
  bool maybeShowInterstitial({required bool isPremium}) {
    final ad = _interstitial;
    final now = DateTime.now();
    // Only while the app is in front: never over the lock screen.
    final inFront =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (isPremium || ad == null || !inFront || !_caps.allows(now)) {
      return false;
    }
    _interstitial = null;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _loadInterstitial();
      },
    );
    ad.show();
    _caps.record(now);
    return true;
  }

  @override
  Future<bool> showRewarded() async {
    if (!_ready.value) await start();
    if (!_ready.value) return false;
    final loaded = Completer<RewardedAd?>();
    RewardedAd.load(
      adUnitId: AdUnits.rewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: loaded.complete,
        onAdFailedToLoad: (error) {
          debugPrint('Rewarded ad failed to load: ${error.message}');
          loaded.complete(null);
        },
      ),
    );
    final ad = await loaded.future
        .timeout(const Duration(seconds: 15), onTimeout: () => null);
    if (ad == null) return false;

    final closed = Completer<void>();
    var earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        closed.complete();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        closed.complete();
      },
    );
    await ad.show(onUserEarnedReward: (_, __) => earned = true);
    await closed.future;
    return earned;
  }

  @override
  Future<bool> privacyOptionsRequired() async {
    try {
      return await ConsentInformation.instance
              .getPrivacyOptionsRequirementStatus() ==
          PrivacyOptionsRequirementStatus.required;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> showPrivacyOptions() => ConsentForm.showPrivacyOptionsForm(
      (error) => error == null ? null : debugPrint(error.message));
}

/// An anchored adaptive banner [width] wide; takes no space until loaded.
class _AdaptiveBanner extends StatefulWidget {
  const _AdaptiveBanner({required this.width});
  final int width;

  @override
  State<_AdaptiveBanner> createState() => _AdaptiveBannerState();
}

class _AdaptiveBannerState extends State<_AdaptiveBanner> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(widget.width));
  }

  @override
  void didUpdateWidget(_AdaptiveBanner old) {
    super.didUpdateWidget(old);
    if (old.width != widget.width) _load(widget.width);
  }

  Future<void> _load(int width) async {
    final size =
        await AdSize.getLargeAnchoredAdaptiveBannerAdSizeWithOrientation(
            MediaQuery.orientationOf(context), width);
    if (!mounted || size == null) return;
    await _ad?.dispose();
    _loaded = false;
    final ad = BannerAd(
      size: size,
      adUnitId: AdUnits.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('Banner failed to load: ${error.message}');
          ad.dispose();
          if (mounted) setState(() => _ad = null);
        },
      ),
    );
    setState(() => _ad = ad);
    await ad.load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (ad == null || !_loaded) return const SizedBox.shrink();
    return SizedBox(
      width: ad.size.width.toDouble(),
      height: ad.size.height.toDouble(),
      child: AdWidget(ad: ad),
    );
  }
}
