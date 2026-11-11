import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../models/reading_alarm.dart';
import '../../state/app_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/book_cover.dart';
import '../../widgets/common.dart';
import '../../widgets/import_sheet.dart';

/// Onboarding 6 — add a first book and run the 1-minute test alarm (ONB-4).
class FirstBookScreen extends StatefulWidget {
  const FirstBookScreen({super.key, required this.onFinish});
  final VoidCallback onFinish;

  @override
  State<FirstBookScreen> createState() => _FirstBookScreenState();
}

class _FirstBookScreenState extends State<FirstBookScreen> {
  BookInfo? _book;
  bool _testScheduled = false;

  Future<void> _import() async {
    final book = await ImportSheet.show(context);
    if (book == null || !mounted) return;
    setState(() => _book = book);
  }

  /// Rings in 60 s and reads the new book for a minute (ONB-4).
  Future<void> _testAlarm() async {
    final scheduled = await AppScope.of(context).scheduleTestAlarm();
    if (!mounted || !scheduled) return;
    setState(() => _testScheduled = true);
    showSnack(
        context, 'Test alarm set for 1 minute from now. Lock your phone.');
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      children: [
        const SizedBox(height: 12),
        const Center(
            child: IconBadge(icon: Icons.library_add_rounded, size: 96)),
        const SizedBox(height: 20),
        const Text(
          'Add your first book',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Then run a 1-minute test to check reading starts with your screen locked.',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 15, height: 1.45, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 24),
        if (_book == null)
          PrimaryButton(
            label: 'Choose a PDF or EPUB',
            icon: Icons.upload_file_rounded,
            onPressed: _import,
          )
        else ...[
          AppCard(
            child: Row(
              children: [
                BookCover(book: _book!, width: 44),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_book!.title,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text('${_book!.format} · ${_book!.author}',
                          style:
                              const TextStyle(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                const Icon(Icons.check_circle_rounded, color: AppColors.orange),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: OutlinedButton.icon(
              onPressed: _testScheduled ? null : _testAlarm,
              icon: Icon(
                  _testScheduled ? Icons.check_rounded : Icons.timer_outlined),
              label: Text(_testScheduled
                  ? 'Test alarm scheduled'
                  : 'Run 1-minute test alarm'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.orange,
                side: const BorderSide(color: AppColors.orange, width: 1.4),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 16,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
        const SizedBox(height: 32),
        PrimaryButton(
          label: 'Finish setup',
          onPressed: _book == null ? null : widget.onFinish,
        ),
        TextButton(
          onPressed: widget.onFinish,
          child: const Text('I\'ll add a book later',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
      ],
    );
  }
}
