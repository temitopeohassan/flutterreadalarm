import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/reading_alarm.dart';
import '../services/book_importer.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import 'common.dart';

/// Import flow as a bottom sheet (LIB-1, LIB-2, EXT-1..5): pick a PDF or
/// EPUB, extract its text in the background, add it to the library.
/// Pops with the added [BookInfo], or null if cancelled.
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

enum _Stage { pick, extracting, done, failed }

class _ImportSheetState extends State<ImportSheet> {
  _Stage _stage = _Stage.pick;
  double _progress = 0;
  BookInfo? _book;
  String _error = '';

  Future<void> _import(String format) async {
    final state = AppScope.of(context);
    final PickedBook? file;
    try {
      file = await state.services.importer.pick(format);
    } catch (e) {
      _fail('Couldn\'t open the file picker.');
      return;
    }
    if (file == null || !mounted) return;
    setState(() {
      _stage = _Stage.extracting;
      _progress = 0;
    });
    try {
      final (detected, extracted) = await state.services.importer.extract(
        file,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      final book = await state.addExtractedBook(
        fileName: file.name,
        format: detected,
        extracted: extracted,
      );
      if (!mounted) return;
      setState(() {
        _stage = _Stage.done;
        _book = book;
      });
    } on BookImportException catch (e) {
      _fail(e.message);
    } catch (e, stack) {
      debugPrint('Import failed: $e\n$stack');
      _fail('Something went wrong reading this file. (${e.runtimeType})');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _stage = _Stage.failed;
      _error = message;
    });
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
              _Stage.failed => _failed(),
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
          onPressed: () => _import('PDF'),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: OutlinedButton.icon(
            onPressed: () => _import('EPUB'),
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
    final book = _book!;
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
          book.title,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        Text(
          '${book.author}  •  ${book.sentenceCount} sentences',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        const SizedBox(height: 20),
        PrimaryButton(
          label: 'Done',
          onPressed: () => Navigator.pop(context, book),
        ),
      ],
    );
  }

  Widget _failed() {
    return Column(
      children: [
        const IconBadge(icon: Icons.error_outline_rounded, size: 88),
        const SizedBox(height: 16),
        const Text(
          'Can\'t read this file',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          _error,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
        ),
        const SizedBox(height: 20),
        PrimaryButton(
          label: 'Choose another file',
          onPressed: () => setState(() => _stage = _Stage.pick),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
      ],
    );
  }
}
