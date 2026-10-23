import 'package:flutter/material.dart';
import 'models/reading_alarm.dart';
import 'screens/main_shell.dart';
import 'screens/now_playing_screen.dart';
import 'screens/paywall_screen.dart';
import 'screens/onboarding/onboarding_flow.dart';
import 'screens/reading_reminder_screen.dart';
import 'services/ads_service.dart';
import 'services/alarm_scheduler.dart';
import 'services/services.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

/// CI's emulator check builds with this on, to start past onboarding
/// (where ads and billing start). Never set in builds for people.
const _skipOnboarding = bool.fromEnvironment('READALARM_SKIP_ONBOARDING');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AdsService.instance = MobileAdsService();
  final state = await AppState.load(await AppServices.device());
  if (_skipOnboarding && !state.onboardingDone) state.completeOnboarding();
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
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  bool _adsStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.state.pendingAlarm.addListener(_showPendingAlarm);
    widget.state.reader.addListener(_onReaderChanged);
    widget.state.billingNotice.addListener(_showBillingNotice);
    widget.state.addListener(_maybeStartAds);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showPendingAlarm();
      _maybeStartAds();
    });
  }

  @override
  void dispose() {
    widget.state.pendingAlarm.removeListener(_showPendingAlarm);
    widget.state.reader.removeListener(_onReaderChanged);
    widget.state.billingNotice.removeListener(_showBillingNotice);
    widget.state.removeListener(_maybeStartAds);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// On return: pick up changes saved by another instance of the app, and
  /// permissions granted in system settings.
  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.resumed) {
      widget.state
          .reloadFromStorage()
          .whenComplete(widget.state.refreshPermissions)
          .whenComplete(widget.state.resyncAlarms)
          .whenComplete(widget.state.refreshPurchases);
    }
  }

  /// Ads (and the consent form, where required) start after onboarding,
  /// for free users only (ADS-1, ADS-6).
  void _maybeStartAds() {
    final state = widget.state;
    if (_adsStarted || !state.onboardingDone || state.isPremium) return;
    _adsStarted = true;
    AdsService.instance.start();
  }

  void _showBillingNotice() {
    final message = widget.state.billingNotice.value;
    if (message == null) return;
    widget.state.billingNotice.value = null;
    _messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ));
  }

  CompletedSession? _limitShownFor;

  /// A free session that used up today's reading gets the paywall, which
  /// explains the midnight reset — wherever in the app the user is.
  void _onReaderChanged() {
    final done = widget.state.reader.lastCompleted;
    final navigator = _navigatorKey.currentState;
    if (done == null || done.reason != 'limit' || navigator == null) return;
    if (identical(done, _limitShownFor)) return;
    _limitShownFor = done;
    // After the player has moved on to the session summary.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PaywallScreen.open(navigator.context, reason: PaywallReason.dailyLimit);
    });
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
        builder: (_) => ReadingReminderScreen(
          alarm: alarm,
          autoStartAfter: ReadingReminderScreen.autoStartDelay,
        ),
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
        scaffoldMessengerKey: _messengerKey,
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
