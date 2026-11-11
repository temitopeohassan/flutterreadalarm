import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

/// Premium subscriptions sold through Google Play Billing.
///
/// Play Console needs two subscriptions with these product ids, each with
/// one auto-renewing base plan (no free trial): monthly ₦1,500 and yearly
/// ₦12,000. Purchases are checked on the phone only (no server).
class PremiumPlans {
  static const monthly = 'readalarm_premium_monthly';
  static const yearly = 'readalarm_premium_yearly';
  static const all = {monthly, yearly};
}

/// Something the store reported about a purchase.
enum BillingEventKind {
  /// Premium was bought (or an earlier purchase was found).
  purchased,

  /// Payment is waiting, e.g. cash at a shop. Premium starts once it's paid.
  pending,

  /// The purchase failed; [BillingEvent.message] says why.
  failed,

  /// The user backed out of the Play purchase sheet.
  cancelled,
}

class BillingEvent {
  const BillingEvent(this.kind, {this.productId, this.message});
  final BillingEventKind kind;
  final String? productId;
  final String? message;
}

/// Why a purchase couldn't start.
enum BuyResult { started, unavailable, failed }

abstract class BillingService {
  /// Connects to the store; [onEvent] receives purchase updates.
  Future<void> init(void Function(BillingEvent event) onEvent);

  /// Store prices by product id, e.g. '₦1,500.00'. Empty when the store or
  /// the products aren't available (not set up yet, or no Play Store).
  Future<Map<String, String>> prices();

  /// Opens Google Play's purchase sheet for [productId].
  Future<BuyResult> buy(String productId);

  /// Premium products the user owns now, or null if the store couldn't be
  /// asked (offline, no Play Store): keep what was known before.
  Future<Set<String>?> ownedPremium();
}

class PlayBillingService implements BillingService {
  final _iap = InAppPurchase.instance;
  final _details = <String, ProductDetails>{};
  StreamSubscription<List<PurchaseDetails>>? _sub;
  void Function(BillingEvent event)? _onEvent;

  @override
  Future<void> init(void Function(BillingEvent event) onEvent) async {
    _onEvent = onEvent;
    _sub ??= _iap.purchaseStream.listen(
      _handle,
      onError: (Object e) => debugPrint('Purchase stream failed: $e'),
    );
  }

  Future<void> _handle(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (!PremiumPlans.all.contains(p.productID)) continue;
      switch (p.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          _onEvent?.call(
              BillingEvent(BillingEventKind.purchased, productId: p.productID));
        case PurchaseStatus.pending:
          _onEvent?.call(
              BillingEvent(BillingEventKind.pending, productId: p.productID));
        case PurchaseStatus.error:
          _onEvent?.call(BillingEvent(BillingEventKind.failed,
              productId: p.productID, message: p.error?.message));
        case PurchaseStatus.canceled:
          _onEvent?.call(
              BillingEvent(BillingEventKind.cancelled, productId: p.productID));
      }
      // Unacknowledged purchases are refunded by Google after 3 days.
      if (p.pendingCompletePurchase) {
        try {
          await _iap.completePurchase(p);
        } catch (e) {
          debugPrint('Completing purchase failed: $e');
        }
      }
    }
  }

  Future<bool> _load() async {
    if (_details.length == PremiumPlans.all.length) return true;
    try {
      if (!await _iap.isAvailable()) return false;
      final response = await _iap.queryProductDetails(PremiumPlans.all);
      for (final d in response.productDetails) {
        // Each base plan and offer is listed; take the base plan.
        final existing = _details[d.id];
        if (existing == null || _isBasePlan(d)) _details[d.id] = d;
      }
    } catch (e) {
      debugPrint('Loading products failed: $e');
    }
    return _details.isNotEmpty;
  }

  bool _isBasePlan(ProductDetails d) {
    if (d is! GooglePlayProductDetails) return true;
    final index = d.subscriptionIndex;
    final offers = d.productDetails.subscriptionOfferDetails;
    if (index == null || offers == null) return true;
    return offers[index].offerId == null;
  }

  @override
  Future<Map<String, String>> prices() async {
    await _load();
    return {for (final d in _details.values) d.id: d.price};
  }

  @override
  Future<BuyResult> buy(String productId) async {
    if (!await _load()) return BuyResult.unavailable;
    final details = _details[productId];
    if (details == null) return BuyResult.unavailable;
    try {
      final ok = await _iap.buyNonConsumable(
          purchaseParam: GooglePlayPurchaseParam(productDetails: details));
      return ok ? BuyResult.started : BuyResult.failed;
    } catch (e) {
      debugPrint('Starting purchase failed: $e');
      return BuyResult.failed;
    }
  }

  @override
  Future<Set<String>?> ownedPremium() async {
    try {
      if (!await _iap.isAvailable()) return null;
      final android =
          _iap.getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
      final response = await android.queryPastPurchases();
      if (response.error != null) return null;
      final owned = <String>{};
      for (final p in response.pastPurchases) {
        if (!PremiumPlans.all.contains(p.productID)) continue;
        if (p.status != PurchaseStatus.purchased &&
            p.status != PurchaseStatus.restored) {
          continue;
        }
        owned.add(p.productID);
        if (p.pendingCompletePurchase) await _iap.completePurchase(p);
      }
      return owned;
    } catch (e) {
      debugPrint('Checking purchases failed: $e');
      return null;
    }
  }
}
