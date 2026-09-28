import 'package:flutter/material.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../widgets/common.dart';

/// Premium paywall (PAY-1, PAY-3). Dismissible.
///
/// Production: load the RevenueCat offering (Purchases.getOfferings) and use
/// each package's storeProduct.priceString; or swap this screen for
/// purchases_ui_flutter's RevenueCatUI.presentPaywall().
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
          fullscreenDialog: true, builder: (_) => const PaywallScreen()),
    );
  }

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _Plan {
  const _Plan(this.id, this.name, this.price, this.note);
  final String id, name, price, note;
}

class _PaywallScreenState extends State<PaywallScreen> {
  // PLACEHOLDER prices — replace with RevenueCat priceString values.
  static const _plans = [
    _Plan('yearly', 'Yearly', '₦12,000 / year', '7-day free trial, best value'),
    _Plan('monthly', 'Monthly', '₦1,500 / month', 'Cancel anytime'),
    _Plan('lifetime', 'Lifetime', '₦25,000 once', 'Pay once, keep forever'),
  ];

  static const _benefits = [
    (Icons.block_rounded, 'No ads, anywhere in the app'),
    (Icons.library_books_rounded, 'Unlimited books'),
    (Icons.alarm_add_rounded, 'Unlimited alarms'),
    (Icons.timer_rounded, '60-minute sessions'),
    (Icons.record_voice_over_rounded, 'Every voice, plus pitch control'),
    (Icons.insights_rounded, 'Full reading history'),
  ];

  String _selected = 'yearly';
  bool _busy = false;

  Future<void> _purchase() async {
    setState(() => _busy = true);
    // TODO: Purchases.purchasePackage(package) → check entitlement 'pro'.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    AppScope.of(context).setPremium(true);
    Navigator.pop(context);
  }

  Future<void> _restore() async {
    // TODO: Purchases.restorePurchases()
    showSnack(context, 'No previous purchases found.');
  }

  @override
  Widget build(BuildContext context) {
    final cta = _selected == 'yearly' ? 'Start 7-day free trial' : 'Continue';

    return Scaffold(
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: AppColors.navy,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 28),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white),
                      ),
                    ),
                    const Icon(Icons.auto_stories_rounded,
                        color: AppColors.orange, size: 48),
                    const SizedBox(height: 12),
                    const Text(
                      'ReadAlarm Premium',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'No ads. Every feature. More reading.',
                      style: TextStyle(color: Color(0xFFC9CFE3), fontSize: 15),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              children: [
                for (final b in _benefits)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: AppColors.peach,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(b.$1, size: 18, color: AppColors.orange),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(b.$2,
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w500)),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                for (final p in _plans)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _PlanTile(
                      plan: p,
                      selected: p.id == _selected,
                      onTap: () => setState(() => _selected = p.id),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Column(
                children: [
                  PrimaryButton(
                    label: _busy ? 'Processing…' : cta,
                    onPressed: _busy ? null : _purchase,
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: _restore,
                        child: const Text('Restore purchases',
                            style: TextStyle(color: AppColors.textSecondary)),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Continue with ads',
                            style: TextStyle(color: AppColors.textSecondary)),
                      ),
                    ],
                  ),
                  const Text(
                    'Billed through Google Play. Cancel anytime in Play Store subscriptions.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile(
      {required this.plan, required this.selected, required this.onTap});
  final _Plan plan;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: selected ? AppColors.peach : AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.orange : AppColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? AppColors.orange : AppColors.textMuted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(plan.name,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    Text(plan.note,
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Text(plan.price,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
