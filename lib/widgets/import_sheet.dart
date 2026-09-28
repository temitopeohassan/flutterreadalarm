import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/reading_alarm.dart';
import '../theme/app_colors.dart';
import 'common.dart';

/// Import flow as a bottom sheet (LIB-1, LIB-2, EXT-1..5).
/// Pops with the imported [BookInfo], or null if cancelled.
///
/// Production: file_picker → copy + SHA-256 → extract in an isolate,
/// streaming real progress here. Show the 'unsupported' state for scanned PDFs.
class ImportSheet extends StatefulWidget {
  const ImportSheet({super.key});

  static Future<BookInfo?> show(BuildContext context) {
    return showModalBottomSheet<BookInfo>(
      context: context,
      isDismissible: false,
      backgroundColor: AppColors.cream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const ImportSheet(),
    );
  }

  @override
  State<ImportSheet> createState() => _ImportSheetState();
}

enum _Stage { pick, extracting, done }

class _ImportSheetState extends State<ImportSheet> {
  _Stage _stage = _Stage.pick;
  double _progress = 0;
  Timer? _timer;
  BookInfo? _book;

  void _startImport(String format) {
    setState(() => _stage = _Stage.extracting);
    _timer = Timer.periodic(const Duration(milliseconds: 80), (t) {
      setState(() => _progress += 0.03);
      if (_progress >= 1) {
        t.cancel();
        final n = math.Random().nextInt(1000);
        final palette =
            SampleData.coverPalette[n % SampleData.coverPalette.length];
        setState(() {
          _stage = _Stage.done;
          _book = BookInfo(
            id: 'b${DateTime.now().millisecondsSinceEpoch}',
            title: 'Imported book $n',
            format: format,
            coverColors: palette,
          );
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.switchOff,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 20),
            switch (_stage) {
              _Stage.pick => _pick(),
              _Stage.extracting => _extracting(),
              _Stage.done => _done(),
            },
          ],
        ),
      ),
    );
  }

  Widget _pick() {
    return Column(
      children: [
        const Text(
          'Add a book',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        const Text(
          'PDF or EPUB, up to 100 MB. Scanned PDFs without text can\'t be read aloud.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary, height: 1.4),
        ),
        const SizedBox(height: 20),
        PrimaryButton(
          label: 'Choose PDF',
          icon: Icons.picture_as_pdf_rounded,
          onPressed: () => _startImport('PDF'),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: OutlinedButton.icon(
            onPressed: () => _startImport('EPUB'),
            icon: const Icon(Icons.menu_book_rounded),
            label: const Text('Choose EPUB'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.orange,
              side: const BorderSide(color: AppColors.orange, width: 1.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: const TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 17,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
      ],
    );
  }

  Widget _extracting() {
    return Column(
      children: [
        const IconBadge(icon: Icons.auto_stories_rounded, size: 88),
        const SizedBox(height: 16),
        const Text(
          'Preparing your book',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          'Extracting text  ${(_progress.clamp(0.0, 1.0) * 100).round()}%',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        ProgressBar(value: _progress, height: 8),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _done() {
    return Column(
      children: [
        const IconBadge(icon: Icons.check_rounded, size: 88),
        const SizedBox(height: 16),
        const Text(
          'Ready to read',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          _book!.title,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),
        PrimaryButton(
          label: 'Add to library',
          onPressed: () => Navigator.pop(context, _book),
        ),
      ],
    );
  }
}
