import 'package:flutter/material.dart';
import '../models/reading_alarm.dart';
import '../services/ads_service.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../widgets/book_cover.dart';
import '../widgets/common.dart';

/// Screen — Session complete (SVC-4, PRG-3).
/// Free users may see an interstitial when leaving this screen (ADS-3).
class SessionCompleteScreen extends StatelessWidget {
  const SessionCompleteScreen({super.key, required this.session});

  final CompletedSession session;

  void _done(BuildContext context) {
    final state = AppScope.of(context);
    AdsService.instance.maybeShowInterstitial(isPremium: state.isPremium);
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final book = state.findBook(session.bookId);
    if (book == null) return const Scaffold();
    final gained =
        ((book.progress - session.progressBefore) * 100).clamp(0, 100);
    final next = state.nextAlarm;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            children: [
              const Spacer(),
              const IconBadge(icon: Icons.check_rounded, size: 120),
              const SizedBox(height: 24),
              Text(
                session.reason == 'finished'
                    ? 'Book finished!'
                    : 'Session complete',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'You listened for ${session.minutes} min',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.orange,
                ),
              ),
              const SizedBox(height: 28),
              AppCard(
                child: Row(
                  children: [
                    BookCover(book: book, width: 48),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(book.title,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          ProgressBar(value: book.progress),
                          const SizedBox(height: 6),
                          Text(
                            '${(book.progress * 100).round()}% read  •  '
                            '+${gained.toStringAsFixed(1)}% today',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              AppCard(
                child: Row(
                  children: [
                    const Icon(Icons.local_fire_department_rounded,
                        color: AppColors.orange),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${state.streakDays}-day streak. Your place is saved.',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (next != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Next alarm: ${formatTime(next.time)}, ${next.book.title}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              PrimaryButton(label: 'Done', onPressed: () => _done(context)),
            ],
          ),
        ),
      ),
    );
  }
}
