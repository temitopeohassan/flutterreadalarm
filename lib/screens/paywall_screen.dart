import 'package:flutter/material.dart';
import '../models/reading_alarm.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../widgets/common.dart';

/// Why the paywall was shown.
enum PaywallReason { upgrade, dailyLimit }

/// Premium paywall (PAY-1, PAY-3). Dismissible.
///
/// The 7-day free trial works (once per install): Premium until it ends,
/// then back to the free tier. Billing isn't connected yet, so buying a
/// plan doesn't unlock Premium; it says Premium is coming soon. To connect
/// it: load the RevenueCat offering (Purchases.getOfferings), use each
/// package's storeProduct.priceString and free-trial intro offer, and
/// purchase with Purchases.purchasePackage.
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
  const _Plan(this.id, this.name, this.price, this.note);
  final String id, name, price, note;
}

String _trialDays() => '${AppState.trialLength.inDays}-day';

class _PaywallScreenState extends State<PaywallScreen> {
  // PLACEHOLDER prices — replace with RevenueCat priceString values.
  static const _plans = [
    _Plan('yearly', 'Yearly', '₦12,000 / year', 'Best value'),
    _Plan('monthly', 'Monthly', '₦1,500 / month', 'Cancel anytime'),
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

  String _selected = 'yearly';

  /// Starts the free trial if it hasn't been used. Billing isn't connected
  /// yet, so otherwise no plan can be bought.
  void _purchase() {
    final state = AppScope.of(context);
    if (state.startTrial()) {
      showSnack(
          context,
          'Your ${_trialDays()} free trial has started. Premium until '
          '${formatDay(state.trialEndsAt!)}.');
      Navigator.pop(context);
      return;
    }
    showSnack(
        context, 'Premium isn\'t available yet. Purchases are coming soon.');
  }

  Future<void> _restore() async {
    // TODO: Purchases.restorePurchases()
    showSnack(context, 'No previous purchases found.');
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final trial = state.canStartTrial;
    final cta = trial ? 'Start ${_trialDays()} free trial' : 'Continue';
    final plan = _plans.firstWhere((p) => p.id == _selected);

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
                      trial: trial,
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
                  if (trial)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Free for ${AppState.trialLength.inDays} days, then '
                        '${plan.price.replaceAll(' ', '')}. Cancel anytime '
                        'before the trial ends and you won\'t be charged.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ),
                  PrimaryButton(
                    label: cta,
                    onPressed: _purchase,
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
  const _PlanTile({
    required this.plan,
    required this.trial,
    required this.selected,
    required this.onTap,
  });
  final _Plan plan;
  final bool trial;
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
                    Text(
                        trial
                            ? '${_trialDays()} free trial · ${plan.note}'
                            : plan.note,
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
