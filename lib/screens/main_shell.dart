import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../state/app_state.dart';
import '../widgets/book_cover.dart';
import 'home_screen.dart';
import 'now_playing_screen.dart';
import 'library_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';

/// Bottom-tab shell: Home, Library, Stats, Settings.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;

  static const _items = [
    (Icons.home_rounded, 'Home'),
    (Icons.local_library_rounded, 'Library'),
    (Icons.bar_chart_rounded, 'Stats'),
    (Icons.settings_rounded, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: const [
          HomeScreen(),
          LibraryScreen(),
          StatsScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _MiniPlayer(),
          Container(
            decoration: const BoxDecoration(
              color: AppColors.cream,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: 64,
                child: Row(
                  children: [
                    for (var i = 0; i < _items.length; i++)
                      Expanded(
                        child: Semantics(
                          selected: i == _tab,
                          button: true,
                          child: InkWell(
                            onTap: () => setState(() => _tab = i),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _items[i].$1,
                                  color: i == _tab
                                      ? AppColors.orange
                                      : AppColors.textMuted,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _items[i].$2,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: i == _tab
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: i == _tab
                                        ? AppColors.orange
                                        : AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown while a book is being read and the player is minimised.
class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return ListenableBuilder(
      listenable: state.reader,
      builder: (context, _) {
        final reader = state.reader;
        final id = reader.bookId;
        final book = id == null ? null : state.findBook(id);
        if (book == null) return const SizedBox.shrink();
        return Material(
          color: AppColors.navy,
          child: InkWell(
            onTap: () => NowPlayingScreen.open(context, book),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  BookCover(book: book, width: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          book.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          reader.playing ? 'Reading aloud' : 'Paused',
                          style: const TextStyle(
                              color: Color(0xFFC9CFE3), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: reader.playing ? 'Pause' : 'Play',
                    onPressed: reader.toggle,
                    color: Colors.white,
                    icon: Icon(reader.playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded),
                  ),
                  IconButton(
                    tooltip: 'Stop',
                    onPressed: () => reader.finish('stop'),
                    color: Colors.white,
                    icon: const Icon(Icons.stop_rounded),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
