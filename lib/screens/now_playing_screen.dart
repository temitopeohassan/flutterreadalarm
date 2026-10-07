import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/reading_alarm.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../widgets/book_cover.dart';
import '../widgets/common.dart';
import 'session_complete_screen.dart';

/// Screen — Now playing: the reading session player (TTS-2..5, PRG-1, SVC-2).
///
/// A view of [AppState.reader]: reading continues when this screen is
/// minimised or the phone is locked. No ads on this screen (ADS-5).
class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});

  /// Starts reading [book] (or resumes it) and shows the player.
  /// [durationMin] set = alarm session with a countdown.
  static Future<void> open(
    BuildContext context,
    BookInfo book, {
    int? durationMin,
    bool replace = false,
  }) async {
    final state = AppScope.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final started = await state.reader.start(book, durationMin: durationMin);
    if (!started) {
      messenger.showSnackBar(const SnackBar(
          content: Text('This book\'s text is missing. Import it again.')));
      return;
    }
    final route =
        MaterialPageRoute<void>(builder: (_) => const NowPlayingScreen());
    replace
        ? await navigator.pushReplacement(route)
        : await navigator.push(route);
  }

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  ReadingController? _reader;
  bool _leaving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reader = AppScope.of(context).reader;
    if (reader != _reader) {
      _reader?.removeListener(_onReaderChanged);
      _reader = reader..addListener(_onReaderChanged);
    }
  }

  /// When the session ends (time's up, book finished, stopped from the
  /// lock screen), move on to the summary.
  void _onReaderChanged() {
    final reader = _reader!;
    if (reader.active || _leaving || !mounted) return;
    _leaving = true;
    final completed = reader.lastCompleted;
    if (completed == null) {
      Navigator.of(context).maybePop();
      return;
    }
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => SessionCompleteScreen(session: completed),
    ));
  }

  @override
  void dispose() {
    _reader?.removeListener(_onReaderChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return ListenableBuilder(
      listenable: state.reader,
      builder: (context, _) => _player(context, state),
    );
  }

  Widget _player(BuildContext context, AppState state) {
    final reader = state.reader;
    final bookId = reader.bookId ?? reader.lastCompleted?.bookId;
    final book = bookId == null ? null : state.findBook(bookId);
    if (book == null) return const Scaffold();
    final limit = reader.durationMin;
    final remaining = reader.remaining;
    final chapter = reader.chapter;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.cream,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          tooltip: 'Minimise',
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          limit == null ? 'Reading now' : 'Alarm session',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            Center(child: BookCover(book: book, width: 140)),
            const SizedBox(height: 20),
            Text(
              book.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              chapter.isEmpty ? book.author : '${book.author}  •  $chapter',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            AppCard(
              color: AppColors.peach,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(
                  reader.currentSentence,
                  key: ValueKey(reader.index),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 17, height: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 20),
            ProgressBar(value: reader.progress, height: 6),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${(reader.progress * 100).toStringAsFixed(1)}% of book',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textMuted)),
                Text(
                  remaining == null
                      ? formatClock(reader.elapsed)
                      : '${formatClock(remaining)} left',
                  style:
                      const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  tooltip: 'Previous sentence',
                  iconSize: 34,
                  color: AppColors.navy,
                  onPressed: () => reader.skip(-1),
                  icon: const Icon(Icons.replay_rounded),
                ),
                SizedBox(
                  width: 76,
                  height: 76,
                  child: FilledButton(
                    onPressed: reader.toggle,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.orange,
                      shape: const CircleBorder(),
                      padding: EdgeInsets.zero,
                    ),
                    child: Icon(
                      reader.playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 40,
                      semanticLabel: reader.playing ? 'Pause' : 'Play',
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Next sentence',
                  iconSize: 34,
                  color: AppColors.navy,
                  onPressed: () => reader.skip(1),
                  icon: const Icon(Icons.forward_rounded),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text('Speed',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final s in const [0.75, 1.0, 1.25, 1.5, 2.0])
                  ChoiceChip(
                    label: Text('${s}x'),
                    selected: state.speed == s,
                    onSelected: (_) => state.setSpeed(s),
                    showCheckmark: false,
                    selectedColor: AppColors.orange,
                    backgroundColor: AppColors.surface,
                    side: BorderSide(
                      color: state.speed == s
                          ? AppColors.orange
                          : AppColors.border,
                    ),
                    labelStyle: TextStyle(
                      color: state.speed == s
                          ? Colors.white
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.record_voice_over_rounded,
                    size: 18, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(state.effectiveVoice?.label ?? 'Default voice',
                      style: const TextStyle(color: AppColors.textSecondary)),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 50,
              child: OutlinedButton(
                onPressed: () => reader.finish('stop'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.navy,
                  side: const BorderSide(color: AppColors.border),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 16,
                      fontWeight: FontWeight.w600),
                ),
                child: const Text('Stop and save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
