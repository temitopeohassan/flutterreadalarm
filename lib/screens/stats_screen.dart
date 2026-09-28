import 'package:flutter/material.dart';
import '../models/reading_alarm.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../widgets/ad_banner_slot.dart';
import '../widgets/common.dart';
import '../widgets/navy_header.dart';
import 'paywall_screen.dart';

/// Screen — Stats: weekly minutes, streak, session history (PRG-3).
/// Free: last 7 days of history; Premium: full history (PAY-2).
class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  static const _dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final now = DateTime.now();
    final days = [for (var i = 6; i >= 0; i--) now.subtract(Duration(days: i))];
    final values = [for (final d in days) state.minutesOnDay(d)];
    final maxValue = values.fold<int>(1, (m, v) => v > m ? v : m);

    final cutoff = now.subtract(const Duration(days: 7));
    final history = state.isPremium
        ? state.sessions
        : state.sessions.where((s) => s.startedAt.isAfter(cutoff)).toList();
    final hidden = state.sessions.length - history.length;

    return Scaffold(
      body: Column(
        children: [
          const NavyHeader(title: 'Stats'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _StatTile(
                        value: '${state.minutesThisWeek}',
                        label: 'min this week',
                        icon: Icons.headphones_rounded,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatTile(
                        value: '${state.streakDays}',
                        label: 'day streak',
                        icon: Icons.local_fire_department_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const SectionTitle('Last 7 days'),
                AppCard(
                  child: SizedBox(
                    height: 160,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (var i = 0; i < 7; i++)
                          Expanded(
                            child: Semantics(
                              label: '${values[i]} minutes',
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (values[i] > 0)
                                    Text('${values[i]}',
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textSecondary)),
                                  const SizedBox(height: 4),
                                  Container(
                                    width: 22,
                                    height: 4 + 100 * values[i] / maxValue,
                                    decoration: BoxDecoration(
                                      color: i == 6
                                          ? AppColors.orange
                                          : AppColors.peachBorder,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _dayLetters[days[i].weekday - 1],
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: i == 6
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                      color: i == 6
                                          ? AppColors.orange
                                          : AppColors.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const SectionTitle('Sessions'),
                if (history.isEmpty)
                  const Text('No sessions yet. Your first alarm will show up here.',
                      style: TextStyle(color: AppColors.textSecondary)),
                for (final s in history)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppCard(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s.bookTitle,
                                    style: const TextStyle(
                                        fontSize: 15, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(
                                  '${relativeDay(s.startedAt)}, '
                                  '${formatTime(TimeOfDay.fromDateTime(s.startedAt))}',
                                  style: const TextStyle(
                                      fontSize: 13, color: AppColors.textMuted),
                                ),
                              ],
                            ),
                          ),
                          Text('${s.minutes} min',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.orange)),
                        ],
                      ),
                    ),
                  ),
                if (hidden > 0)
                  AppCard(
                    color: AppColors.peach,
                    onTap: () => PaywallScreen.open(context),
                    child: Row(
                      children: [
                        const Icon(Icons.lock_rounded, color: AppColors.orangeDark),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '$hidden older sessions. See your full history with Premium.',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded,
                            color: AppColors.orangeDark),
                      ],
                    ),
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

class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label, required this.icon});
  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Icon(icon, color: AppColors.orange, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w700)),
                Text(label,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
