import 'package:flutter/material.dart';
import 'screens/main_shell.dart';
import 'screens/onboarding/onboarding_flow.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

void main() => runApp(ReadAlarmApp(state: AppState()));

class ReadAlarmApp extends StatelessWidget {
  const ReadAlarmApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: MaterialApp(
        title: 'ReadAlarm',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const _Root(),
      ),
    );
  }
}

/// Shows onboarding on first launch, then the tabbed app.
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final done = AppScope.of(context).onboardingDone;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: done
          ? const MainShell(key: ValueKey('shell'))
          : const OnboardingFlow(key: ValueKey('onboarding')),
    );
  }
}
