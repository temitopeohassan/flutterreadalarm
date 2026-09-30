import 'package:flutter/material.dart';
import 'models/reading_alarm.dart';
import 'screens/main_shell.dart';
import 'screens/now_playing_screen.dart';
import 'screens/onboarding/onboarding_flow.dart';
import 'screens/reading_reminder_screen.dart';
import 'services/alarm_scheduler.dart';
import 'services/services.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = await AppState.load(await AppServices.device());
  runApp(ReadAlarmApp(state: state));
}

class ReadAlarmApp extends StatefulWidget {
  const ReadAlarmApp({super.key, required this.state});
  final AppState state;

  @override
  State<ReadAlarmApp> createState() => _ReadAlarmAppState();
}

class _ReadAlarmAppState extends State<ReadAlarmApp>
    with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.state.pendingAlarm.addListener(_showPendingAlarm);
    WidgetsBinding.instance.addPostFrameCallback((_) => _showPendingAlarm());
  }

  @override
  void dispose() {
    widget.state.pendingAlarm.removeListener(_showPendingAlarm);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Permissions granted in system settings take effect on return.
  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.resumed) {
      widget.state.refreshPermissions();
    }
  }

  /// Opens the reminder (or the session, for "Start reading" on the
  /// notification) for an alarm the user responded to.
  void _showPendingAlarm() {
    final pending = widget.state.pendingAlarm.value;
    final navigator = _navigatorKey.currentState;
    if (pending == null || navigator == null) return;
    widget.state.pendingAlarm.value = null;
    final (ReadingAlarm alarm, AlarmAction action) = pending;
    if (action == AlarmAction.start) {
      widget.state.silenceAlarm(alarm);
      NowPlayingScreen.open(navigator.context, alarm.book,
          durationMin: alarm.durationMin);
    } else {
      navigator.push(MaterialPageRoute<void>(
        builder: (_) => ReadingReminderScreen(alarm: alarm),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: widget.state,
      child: MaterialApp(
        title: 'ReadAlarm',
        navigatorKey: _navigatorKey,
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
