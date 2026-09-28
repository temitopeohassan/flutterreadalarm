import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/reading_alarm.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../widgets/book_cover.dart';
import '../widgets/common.dart';
import 'session_complete_screen.dart';

/// Screen — Now playing: the reading session player (TTS-2..5, PRG-1, SVC-2).
///
/// [durationMin] set = alarm session with a countdown; null = open-ended
/// "Read now" from the Library. No ads on this screen (ADS-5).
///
/// Production: this screen only mirrors the foreground service; playback
/// state comes from the TaskHandler, and controls send commands to it.
class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key, required this.bookId, this.durationMin});

  final String bookId;
  final int? durationMin;

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  // Placeholder text shown until real chunks are loaded from SQLite.
  static const _sentences = [
    'The morning light came in low across the kitchen table.',
    'She had promised herself one chapter before the day began.',
    'The kettle clicked off, and the house went quiet again.',
    'Somewhere outside, a bus pulled away from the stop.',
    'She turned the page and kept listening.',
  ];

  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  bool _playing = true;
  int _sentence = 0;
  late double _startProgress;
  bool _initialised = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialised) {
      _startProgress = AppScope.of(context).bookById(widget.bookId).progress;
      _initialised = true;
      _start();
    }
  }

  void _start() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_playing) return;
      setState(() {
        _elapsed += const Duration(seconds: 1);
        if (_elapsed.inSeconds % 4 == 0) {
          _sentence = (_sentence + 1) % _sentences.length;
        }
      });
      // PRG-1: persist every 30 s.
      if (_elapsed.inSeconds % 30 == 0) _saveProgress();
      final limit = widget.durationMin;
      if (limit != null && _elapsed.inMinutes >= limit) _finish('duration');
    });
  }

  double get _currentProgress =>
      (_startProgress + _elapsed.inSeconds / 36000).clamp(0.0, 1.0).toDouble();

  void _saveProgress() {
    final state = AppScope.of(context);
    state.updateProgress(state.bookById(widget.bookId), _currentProgress);
  }

  void _finish(String reason) {
    _ticker?.cancel();
    final state = AppScope.of(context);
    final book = state.bookById(widget.bookId);
    _saveProgress();
    final minutes = math.max(1, (_elapsed.inSeconds / 60).ceil());
    state.addSession(ReadingSession(
      bookTitle: book.title,
      startedAt: DateTime.now().subtract(_elapsed),
      minutes: minutes,
      endReason: reason,
    ));
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => SessionCompleteScreen(
        bookId: widget.bookId,
        minutes: minutes,
        progressBefore: _startProgress,
      ),
    ));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final book = state.bookById(widget.bookId);
    final limit = widget.durationMin;
    final remaining =
        limit == null ? null : Duration(minutes: limit) - _elapsed;

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
              '${book.author}  •  ${book.chapter}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            AppCard(
              color: AppColors.peach,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(
                  _sentences[_sentence],
                  key: ValueKey(_sentence),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 17, height: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 20),
            ProgressBar(value: _currentProgress, height: 6),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${(_currentProgress * 100).toStringAsFixed(1)}% of book',
                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                Text(
                  remaining == null
                      ? formatClock(_elapsed)
                      : '${formatClock(remaining)} left',
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
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
                  onPressed: () =>
                      setState(() => _sentence = math.max(0, _sentence - 1)),
                  icon: const Icon(Icons.replay_rounded),
                ),
                SizedBox(
                  width: 76,
                  height: 76,
                  child: FilledButton(
                    onPressed: () => setState(() => _playing = !_playing),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.orange,
                      shape: const CircleBorder(),
                      padding: EdgeInsets.zero,
                    ),
                    child: Icon(
                      _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: 40,
                      semanticLabel: _playing ? 'Pause' : 'Play',
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Next sentence',
                  iconSize: 34,
                  color: AppColors.navy,
                  onPressed: () => setState(() =>
                      _sentence = (_sentence + 1) % _sentences.length),
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
                      color: state.speed == s ? AppColors.orange : AppColors.border,
                    ),
                    labelStyle: TextStyle(
                      color: state.speed == s ? Colors.white : AppColors.textSecondary,
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
                  child: Text(state.voice,
                      style: const TextStyle(color: AppColors.textSecondary)),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 50,
              child: OutlinedButton(
                onPressed: () => _finish('stop'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.navy,
                  side: const BorderSide(color: AppColors.border),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
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
