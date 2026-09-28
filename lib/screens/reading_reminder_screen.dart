import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/reading_alarm.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'now_playing_screen.dart';
import '../theme/app_colors.dart';
import '../widgets/reminder_illustration.dart';

/// Screen — Reading reminder, shown when an alarm fires (full-screen intent
/// over the lock screen, or from the alarm notification). Never shows ads.
///
/// Production: Start reading attaches to the already-running foreground
/// session; Snooze reschedules +10 min with the remaining duration (SVC-3).
class ReadingReminderScreen extends StatelessWidget {
  const ReadingReminderScreen({super.key, required this.alarm});

  final ReadingAlarm alarm;

  @override
  Widget build(BuildContext context) {
    final minutesThisWeek = AppScope.of(context).minutesThisWeek;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _NotificationBar(onClose: () => Navigator.of(context).maybePop()),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    const ReminderIllustration(size: 230),
                    const SizedBox(height: 20),
                    const Text(
                      'Reading reminder',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: AppColors.navy,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Time to read!',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.orange,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _AlarmCard(
                      alarm: alarm,
                      onStart: () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (_) => NowPlayingScreen(
                            bookId: alarm.book.id,
                            durationMin: alarm.durationMin,
                          ),
                        ),
                      ),
                      onSnooze: () {
                        showSnack(
                            context, 'Snoozed. Reading starts in 10 minutes.');
                        Navigator.of(context).maybePop();
                      },
                    ),
                    const SizedBox(height: 14),
                    if (minutesThisWeek > 0)
                      _WeeklyNudge(minutes: minutesThisWeek),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationBar extends StatelessWidget {
  const _NotificationBar({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const SizedBox(width: 48),
          const Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'ReadAlarm',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text: '  •  Now',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: AppColors.navy),
            ),
          ),
          IconButton(
            tooltip: 'Dismiss',
            onPressed: onClose,
            icon: const Icon(Icons.notifications_rounded,
                color: AppColors.switchOff),
          ),
        ],
      ),
    );
  }
}

class _AlarmCard extends StatelessWidget {
  const _AlarmCard({
    required this.alarm,
    required this.onStart,
    required this.onSnooze,
  });

  final ReadingAlarm alarm;
  final VoidCallback onStart;
  final VoidCallback onSnooze;

  @override
  Widget build(BuildContext context) {
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
    const labelStyle = TextStyle(
      fontFamily: AppTheme.fontFamily,
      fontSize: 15,
      fontWeight: FontWeight.w600,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.peach,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.peachBorder),
      ),
      child: Column(
        children: [
          Text(
            '${formatTime(alarm.time)} — Read ${alarm.durationMin} min',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            alarm.book.title,
            textAlign: TextAlign.center,
            style:
                const TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: onStart,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.orange,
                      shape: shape,
                      textStyle: labelStyle,
                    ),
                    child: const Text('Start reading'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    onPressed: onSnooze,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.orange,
                      backgroundColor: AppColors.surface,
                      side:
                          const BorderSide(color: AppColors.orange, width: 1.4),
                      shape: shape,
                      textStyle: labelStyle,
                    ),
                    child: const Text('Snooze 10 min'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WeeklyNudge extends StatelessWidget {
  const _WeeklyNudge({required this.minutes});
  final int minutes;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.eco_rounded, color: AppColors.orange, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "You've listened for $minutes minutes this week. Keep going!",
              style: const TextStyle(
                fontSize: 14,
                height: 1.35,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
