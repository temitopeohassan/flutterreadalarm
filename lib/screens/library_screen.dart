import 'package:flutter/material.dart';
import '../models/reading_alarm.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../widgets/ad_banner_slot.dart';
import '../widgets/book_cover.dart';
import '../widgets/common.dart';
import '../widgets/import_sheet.dart';
import '../widgets/navy_header.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';
import 'now_playing_screen.dart';
import 'paywall_screen.dart';

/// Screen — Library: books, progress, import, rename, delete (LIB-1..3).
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  Future<void> _import(BuildContext context) async {
    final state = AppScope.of(context);
    if (!state.canAddBook) {
      await PaywallScreen.open(context);
      return;
    }
    await ImportSheet.show(context);
  }

  /// Tapping a book asks whether to read it now or set an alarm for it.
  Future<void> _chooseAction(BuildContext context, BookInfo book) async {
    final choice = await showModalBottomSheet<_BookAction>(
      context: context,
      backgroundColor: AppColors.cream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _BookActionSheet(book: book),
    );
    if (!context.mounted) return;
    switch (choice) {
      case _BookAction.read:
        await NowPlayingScreen.open(context, book);
      case _BookAction.alarm:
        await HomeScreen.openEditor(context, book: book);
      case null:
        break;
    }
  }

  Future<void> _rename(BuildContext context, BookInfo book) async {
    final state = AppScope.of(context);
    final controller = TextEditingController(text: book.title);
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename book'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    if (title != null && title.isNotEmpty) state.renameBook(book, title);
  }

  Future<void> _delete(BuildContext context, BookInfo book) async {
    final state = AppScope.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete book?'),
        content: Text(
            '"${book.title}", your progress and any alarms for it will be removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(color: AppColors.orangeDark)),
          ),
        ],
      ),
    );
    if (ok == true) state.deleteBook(book);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final books = state.books;

    return Scaffold(
      body: Column(
        children: [
          NavyHeader(
            title: 'Library',
            trailing: IconButton(
              tooltip: 'Add book',
              onPressed: () => _import(context),
              icon: const Icon(Icons.add_circle_rounded,
                  color: AppColors.orange, size: 32),
            ),
          ),
          Expanded(
            child: books.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const IconBadge(
                              icon: Icons.local_library_rounded, size: 96),
                          const SizedBox(height: 16),
                          const Text(
                            'Your library is empty. Add a PDF or EPUB to start.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 16),
                          PrimaryButton(
                            label: 'Add a book',
                            onPressed: () => _import(context),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                    itemCount: books.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      if (i == books.length) {
                        return state.isPremium
                            ? const SizedBox.shrink()
                            : Text(
                                '${books.length} of ${AppState.freeBookLimit} free books used',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontSize: 12, color: AppColors.textMuted),
                              );
                      }
                      final book = books[i];
                      return _BookRow(
                        book: book,
                        onTap: () => _chooseAction(context, book),
                        onSetAlarm: () =>
                            HomeScreen.openEditor(context, book: book),
                        onRename: () => _rename(context, book),
                        onDelete: () => _delete(context, book),
                      );
                    },
                  ),
          ),
          const AdBannerSlot(),
        ],
      ),
    );
  }
}

class _BookRow extends StatelessWidget {
  const _BookRow({
    required this.book,
    required this.onTap,
    required this.onSetAlarm,
    required this.onRename,
    required this.onDelete,
  });

  final BookInfo book;
  final VoidCallback onTap;
  final VoidCallback onSetAlarm;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final pct = (book.progress * 100).round();
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 14, 4, 14),
      child: Row(
        children: [
          BookCover(book: book, width: 52),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${book.author}  •  ${book.format}',
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 10),
                ProgressBar(value: book.progress),
                const SizedBox(height: 6),
                Text(
                  book.lastReadAt == null
                      ? '$pct%  •  Not started'
                      : '$pct%  •  ${relativeDay(book.lastReadAt!)}',
                  style:
                      const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Book options',
            icon:
                const Icon(Icons.more_vert_rounded, color: AppColors.textMuted),
            onSelected: (v) => switch (v) {
              'alarm' => onSetAlarm(),
              'rename' => onRename(),
              _ => onDelete(),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'alarm', child: Text('Set an alarm')),
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }
}

enum _BookAction { read, alarm }

class _BookActionSheet extends StatelessWidget {
  const _BookActionSheet({required this.book});
  final BookInfo book;

  @override
  Widget build(BuildContext context) {
    final started = book.position > 0 && !book.isFinished;
    final where = [
      '${(book.progress * 100).round()}% read',
      if (book.chapter.isNotEmpty) book.chapter,
    ].join('  •  ');

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
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
            Row(
              children: [
                BookCover(book: book, width: 48),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(where,
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            PrimaryButton(
              label: started ? 'Continue reading' : 'Start reading',
              icon: Icons.play_arrow_rounded,
              onPressed: () => Navigator.pop(context, _BookAction.read),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, _BookAction.alarm),
                icon: const Icon(Icons.alarm_add_rounded),
                label: const Text('Set an alarm'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.orange,
                  side: const BorderSide(color: AppColors.orange, width: 1.4),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
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
        ),
      ),
    );
  }
}
