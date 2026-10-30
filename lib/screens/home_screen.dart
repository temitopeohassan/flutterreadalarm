import 'package:flutter/material.dart';
import '../models/reading_alarm.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../widgets/ad_banner_slot.dart';
import '../widgets/book_cover.dart';
import '../widgets/navy_header.dart';
import 'onboarding/alarm_test_screen.dart';
import '../widgets/alarm_setup_gate.dart';
import 'paywall_screen.dart';
import 'reading_reminder_screen.dart';
import 'set_alarm_screen.dart';

/// Screen — Home: reading alarms with enable toggles (ALM-1, ALM-4).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  /// Opens the alarm editor for [existing], or for a new alarm (reading
  /// [book] if given). Free users at the alarm limit get the paywall.
  static Future<void> openEditor(BuildContext context,
      {ReadingAlarm? existing, BookInfo? book}) async {
    final state = AppScope.of(context);
    if (!await ensureAlarmSetup(context) || !context.mounted) return;
    if (existing == null && !state.canAddAlarm) {
      await PaywallScreen.open(context);
      return;
    }
    if (state.books.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a book in Library first.')),
      );
      return;
    }
    // The editor saves the alarm itself (it checks for clashes first).
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SetAlarmScreen(initial: existing, initialBook: book),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final alarms = state.alarms;
    final next = state.nextAlarm;

    return Scaffold(
      body: Column(
        children: [
          NavyHeader(
            title: 'ReadAlarm',
            leading: IconButton(
              tooltip: 'Preview alarm screen',
              onPressed: next == null
                  ? null
                  : () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ReadingReminderScreen(alarm: next),
                        ),
                      ),
              icon:
                  const Icon(Icons.notifications_rounded, color: Colors.white),
            ),
            trailing: _AddButton(onTap: () => openEditor(context)),
          ),
          if (state.alarms.any((a) => a.enabled) && !state.alarmsVerified)
            _AlarmWarning(dropped: state.alarmsDroppedAt != null),
          Expanded(
            child: alarms.isEmpty
                ? _EmptyState(onAdd: () => openEditor(context))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                    children: [
                      Text(
                        next == null
                            ? 'Your reading alarms'
                            : 'Next: ${formatTime(next.time)}, ${next.book.title}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      for (final alarm in alarms)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Dismissible(
                            key: ValueKey(alarm.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 24),
                              decoration: BoxDecoration(
                                color: AppColors.peach,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(Icons.delete_outline_rounded,
                                  color: AppColors.orangeDark),
                            ),
                            onDismissed: (_) => state.deleteAlarm(alarm),
                            child: _AlarmCard(
                              alarm: alarm,
                              onTap: () => openEditor(context, existing: alarm),
                              onToggle: (v) async {
                                final result =
                                    await state.toggleAlarm(alarm, v);
                                if (!context.mounted) return;
                                if (result == AlarmSaveStatus.limitReached) {
                                  await PaywallScreen.open(context);
                                } else if (result ==
                                        AlarmSaveStatus.setupNeeded &&
                                    await ensureAlarmSetup(context)) {
                                  await state.toggleAlarm(alarm, v);
                                }
                              },
                            ),
                          ),
                        ),
                      if (!state.isPremium)
                        Text(
                          _freeAlarmNote(alarms.length),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textMuted),
                        ),
                    ],
                  ),
          ),
          const AdBannerSlot(),
        ],
      ),
    );
  }
}

/// Under the alarm list for free users.
String _freeAlarmNote(int count) {
  const limit = AppState.freeAlarmLimit;
  const noun = limit == 1 ? 'alarm' : 'alarms';
  if (count <= limit) return '$count of $limit free $noun used';
  // Left from an earlier version or Premium: the extras stay off.
  return 'The free plan includes $limit $noun. Upgrade to switch on more.';
}

/// Shown while alarms aren't known to work on this phone: the alarm test
/// hasn't passed, or the phone has removed an alarm since.
class _AlarmWarning extends StatelessWidget {
  const _AlarmWarning({required this.dropped});
  final bool dropped;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFDECEA),
      child: InkWell(
        onTap: () => AlarmTestScreen.open(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Color(0xFFC0392B)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Your alarm may not ring',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF8E2A20)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dropped
                          ? 'Your phone removed ReadAlarm\'s alarm while it was '
                              'closed. Run the alarm test to fix it.'
                          : 'The alarm test hasn\'t passed on this phone yet.',
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF8E2A20)),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => AlarmTestScreen.open(context),
                child: const Text('Fix'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Add alarm',
      child: Material(
        color: AppColors.orange,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: const SizedBox(
            width: 34,
            height: 34,
            child: Icon(Icons.add_rounded, color: Colors.white, size: 24),
          ),
        ),
      ),
    );
  }
}

class _AlarmCard extends StatelessWidget {
  const _AlarmCard({
    required this.alarm,
    required this.onTap,
    required this.onToggle,
  });

  final ReadingAlarm alarm;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 14, offset: Offset(0, 4)),
        ],
      ),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                BookCover(book: alarm.book, width: 50),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatTime(alarm.time),
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: alarm.enabled
                              ? AppColors.textPrimary
                              : AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Read ${alarm.durationMin} min',
                        style: const TextStyle(
                            fontSize: 14, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        alarm.scheduleLabel,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: alarm.enabled,
                  onChanged: onToggle,
                  thumbColor: const WidgetStatePropertyAll(Colors.white),
                  trackColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? AppColors.orange
                        : AppColors.switchOff,
                  ),
                  trackOutlineColor:
                      const WidgetStatePropertyAll(Colors.transparent),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'No alarms yet. Add one and your book will start reading at that time.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onAdd,
              style: FilledButton.styleFrom(backgroundColor: AppColors.orange),
              child: const Text('Add alarm'),
            ),
          ],
        ),
      ),
    );
  }
}
