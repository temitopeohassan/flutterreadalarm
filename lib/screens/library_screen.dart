import 'package:flutter/material.dart';
import '../models/reading_alarm.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../widgets/ad_banner_slot.dart';
import '../widgets/book_cover.dart';
import '../widgets/common.dart';
import '../widgets/import_sheet.dart';
import '../widgets/navy_header.dart';
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
    final book = await ImportSheet.show(context);
    if (book != null) state.addBook(book);
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
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
            '"${book.title}" and your progress will be removed. Alarms using it will be turned off.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.orangeDark)),
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
                          const IconBadge(icon: Icons.local_library_rounded, size: 96),
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
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => NowPlayingScreen(bookId: book.id),
                          ),
                        ),
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
    required this.onRename,
    required this.onDelete,
  });

  final BookInfo book;
  final VoidCallback onTap;
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
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${book.author}  •  ${book.format}',
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 10),
                ProgressBar(value: book.progress),
                const SizedBox(height: 6),
                Text(
                  book.lastReadAt == null
                      ? '$pct%  •  Not started'
                      : '$pct%  •  ${relativeDay(book.lastReadAt!)}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Book options',
            icon: const Icon(Icons.more_vert_rounded, color: AppColors.textMuted),
            onSelected: (v) => v == 'rename' ? onRename() : onDelete(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }
}
