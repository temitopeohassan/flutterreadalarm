import 'package:flutter/material.dart';
import '../../models/reading_alarm.dart';
import '../../theme/app_colors.dart';
import '../../widgets/book_cover.dart';
import '../../widgets/common.dart';
import '../../widgets/import_sheet.dart';

/// Onboarding — add a first book (ONB-4). The alarm test comes next.
class FirstBookScreen extends StatefulWidget {
  const FirstBookScreen({super.key, required this.onNext});
  final VoidCallback onNext;

  @override
  State<FirstBookScreen> createState() => _FirstBookScreenState();
}

class _FirstBookScreenState extends State<FirstBookScreen> {
  BookInfo? _book;

  Future<void> _import() async {
    final book = await ImportSheet.show(context);
    if (book == null || !mounted) return;
    setState(() => _book = book);
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
          'Your alarms will read it to you.',
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
        ],
        const SizedBox(height: 32),
        PrimaryButton(
          label: 'Continue',
          onPressed: _book == null ? null : widget.onNext,
        ),
        TextButton(
          onPressed: widget.onNext,
          child: const Text('I\'ll add a book later',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
      ],
    );
  }
}
