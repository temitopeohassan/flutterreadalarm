import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'home_screen.dart';
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
      bottomNavigationBar: Container(
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
    );
  }
}
