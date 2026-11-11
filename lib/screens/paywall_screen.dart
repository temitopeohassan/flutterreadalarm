import 'package:flutter/material.dart';
import '../services/billing_service.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// Why the paywall was shown.
enum PaywallReason { upgrade, dailyLimit }

/// Premium paywall (PAY-1, PAY-3). Dismissible.
///
/// Plans are Google Play subscriptions ([PremiumPlans]), shown with Play's
/// prices once loaded. Premium starts when Play confirms the purchase; the
/// paywall then closes by itself.
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key, this.reason = PaywallReason.upgrade});

  final PaywallReason reason;

  static Future<void> open(
    BuildContext context, {
    PaywallReason reason = PaywallReason.upgrade,
  }) {
    return Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PaywallScreen(reason: reason),
      ),
    );
  }

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _Plan {
  const _Plan(this.id, this.name, this.fallbackPrice, this.period, this.note);
  final String id, name, fallbackPrice, period, note;

  /// Google Play's price if loaded, e.g. "₦12,000.00 / year".
  String price(AppState state) =>
      '${state.storePrices[id] ?? fallbackPrice} / $period';
}

class _PaywallScreenState extends State<PaywallScreen> {
  // Shown until Google Play's prices load.
  static const _plans = [
    _Plan(PremiumPlans.yearly, 'Yearly', '₦12,000', 'year', 'Best value'),
    _Plan(PremiumPlans.monthly, 'Monthly', '₦1,500', 'month', 'Cancel anytime'),
  ];

  static const _benefits = [
    (Icons.all_inclusive_rounded, 'Unlimited reading every day'),
    (Icons.block_rounded, 'No ads, anywhere in the app'),
    (Icons.library_books_rounded, 'Unlimited books'),
    (Icons.alarm_add_rounded, 'Unlimited alarms'),
    (Icons.timer_rounded, '60-minute sessions'),
    (Icons.record_voice_over_rounded, 'Every voice, plus pitch control'),
    (Icons.insights_rounded, 'Full reading history'),
  ];

  String _selected = PremiumPlans.yearly;
  bool _busy = false;
  AppState? _state;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.of(context);
    if (_state != state) {
      _state?.removeListener(_onStateChanged);
      _state = state..addListener(_onStateChanged);
      if (state.storePrices.isEmpty) state.loadPrices();
    }
  }

  @override
  void dispose() {
    _state?.removeListener(_onStateChanged);
    super.dispose();
  }

  /// Closes the paywall once Premium starts.
  void _onStateChanged() {
    if (!(_state?.isPremium ?? false) || !mounted) return;
    _state?.removeListener(_onStateChanged);
    Navigator.of(context).maybePop();
  }

  Future<void> _purchase() async {
    setState(() => _busy = true);
    final result = await AppScope.of(context).buyPremium(_selected);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result) {
      case BuyResult.started:
        break; // Google Play takes over; the result arrives as an event.
      case BuyResult.unavailable:
        showSnack(
            context,
            'Purchases aren\'t available. Install ReadAlarm from Google Play '
            'and sign in to the Play Store to subscribe.');
      case BuyResult.failed:
        showSnack(context, 'Couldn\'t open Google Play. Please try again.');
    }
  }

  Future<void> _restore() async {
    final found = await AppScope.of(context).refreshPurchases();
    if (!mounted) return;
    showSnack(
      context,
      switch (found) {
        true => 'Premium restored.',
        false => 'No active subscription on this Google account.',
        null => 'Couldn\'t reach Google Play. Please try again.',
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final cta = _busy ? 'Opening Google Play…' : 'Continue';

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
                if (widget.reason == PaywallReason.dailyLimit)
                  const _DailyLimitNotice(),
                // Plans first so every option is visible without scrolling.
                for (final p in _plans)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _PlanTile(
                      plan: p,
                      price: p.price(state),
                      selected: p.id == _selected,
                      onTap: () => setState(() => _selected = p.id),
                    ),
                  ),
                const SizedBox(height: 14),
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
                    label: cta,
                    onPressed: _busy ? null : _purchase,
                  ),
                  // The free option: as clear a choice as Premium.
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text(
                        'Use The Free Version',
                        style: TextStyle(
                          fontFamily: AppTheme.fontFamily,
                          color: AppColors.navy,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _restore,
                    child: const Text('Restore purchases',
                        style: TextStyle(color: AppColors.textSecondary)),
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
  const _PlanTile({
    required this.plan,
    required this.price,
    required this.selected,
    required this.onTap,
  });
  final _Plan plan;
  final String price;
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
              Text(price,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Explains the free daily reading limit and when it resets.
class _DailyLimitNotice extends StatelessWidget {
  const _DailyLimitNotice();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final wait = state.untilFreeReset;
    final hours = wait.inHours;
    final minutes = wait.inMinutes.remainder(60);
    final waitText = hours > 0 ? '$hours h $minutes min' : '$minutes min';
    final free = AppState.freeDailyReading.inMinutes;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.peach,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.peachBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.hourglass_bottom_rounded, color: AppColors.orange),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You\'ve used today\'s $free free minutes',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Free reading resets at midnight, in $waitText. '
                  'Wait until then, or upgrade to Premium to keep reading '
                  'now.',
                  style: const TextStyle(
                      fontSize: 14,
                      height: 1.35,
                      color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
