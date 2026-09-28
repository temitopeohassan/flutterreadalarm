import 'package:flutter/material.dart';
import '../../state/app_state.dart';
import '../../theme/app_colors.dart';
import '../paywall_screen.dart';
import 'battery_optimization_screen.dart';
import 'exact_alarm_permission_screen.dart';
import 'first_book_screen.dart';
import 'notifications_permission_screen.dart';
import 'oem_autostart_screen.dart';
import 'welcome_screen.dart';

/// Hosts the 6 onboarding screens with a step indicator (ONB-1).
/// On finish: dismissible paywall (PAY-3), then the main app.
/// Ad consent (ADS-1) is requested after this flow, before the first ad.
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key});

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  final _controller = PageController();
  int _page = 0;
  static const _count = 6;

  void _next() {
    if (_page < _count - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _back() {
    _controller.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finish() async {
    final state = AppScope.of(context);
    await PaywallScreen.open(context);
    state.completeOnboarding();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 56,
              child: Row(
                children: [
                  SizedBox(
                    width: 56,
                    child: _page == 0
                        ? null
                        : IconButton(
                            tooltip: 'Back',
                            onPressed: _back,
                            icon: const Icon(Icons.chevron_left_rounded,
                                size: 30, color: AppColors.navy),
                          ),
                  ),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < _count; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: i == _page ? 22 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: i <= _page
                                  ? AppColors.orange
                                  : AppColors.switchOff,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 56),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  WelcomeScreen(onNext: _next),
                  NotificationsPermissionScreen(onNext: _next),
                  ExactAlarmPermissionScreen(onNext: _next),
                  BatteryOptimizationScreen(onNext: _next),
                  OemAutostartScreen(onNext: _next),
                  FirstBookScreen(onFinish: _finish),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
