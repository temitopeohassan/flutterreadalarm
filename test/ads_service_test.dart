import 'package:flutter_test/flutter_test.dart';
import 'package:readalarm/services/ads_service.dart';

void main() {
  test('interstitials: never for Premium, at most one per 10 minutes', () {
    final ads = PlaceholderAds();
    expect(ads.maybeShowInterstitial(isPremium: true), isFalse);
    expect(ads.maybeShowInterstitial(isPremium: false), isTrue);
    expect(ads.maybeShowInterstitial(isPremium: false), isFalse,
        reason: 'too soon after the last one');
  });
}
