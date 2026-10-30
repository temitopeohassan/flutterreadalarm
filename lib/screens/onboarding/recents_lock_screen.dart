import 'package:flutter/material.dart';
import '../../state/app_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart';
import 'oem_autostart_screen.dart';

/// Onboarding — lock ReadAlarm in recent apps, so the phone's cleaner
/// doesn't close it. Step by step, with a drawing of what to look for at
/// each step. Android can't report this setting; the alarm test that
/// follows checks the result.
class RecentsLockScreen extends StatelessWidget {
  const RecentsLockScreen({super.key, required this.onNext});
  final VoidCallback onNext;

  static const _openRecents = _Step(
    'Open your recent apps',
    'Tap the Recent apps button: on most Tecno, Infinix and itel phones it\'s '
        'the LEFT of the three buttons at the bottom of the screen. '
        'No buttons? Swipe up from the bottom edge, hold for a second, then '
        'let go.',
    _Picture.navButtons,
  );

  static const _findCard = _Step(
    'Find the ReadAlarm card',
    'Your open apps show as cards. Swipe left or right until you see the '
        'ReadAlarm card. Don\'t swipe it UP: that closes it.',
    _Picture.cards,
  );

  static const _comeBack = _Step(
    'Come back to ReadAlarm',
    'Tap the ReadAlarm card to return here, then tap "I\'ve locked it".\n'
        'If the card disappeared, you closed it: open ReadAlarm again and '
        'start from step 1.',
    _Picture.none,
  );

  static const _guides = <String, List<_Step>>{
    'Tecno / Infinix / itel': [
      _openRecents,
      _findCard,
      _Step(
        'Pull the card DOWN, then let go',
        'Put your finger on the ReadAlarm card and drag it down a little '
            '(about a finger\'s width), then let go. A small lock appears '
            'on the card. That means it\'s locked.\n'
            'No lock? Press and hold the card instead, and tap "Lock".',
        _Picture.pullDown,
      ),
      _comeBack,
    ],
    'Xiaomi / Redmi / Poco': [
      _openRecents,
      _findCard,
      _Step(
        'Press and hold the card, then tap the lock',
        'Press and hold the ReadAlarm card until icons appear, then tap the '
            'lock. (On some models, pull the card down instead.) A lock '
            'appears on the card.',
        _Picture.pullDown,
      ),
      _comeBack,
    ],
    'Samsung': [
      _openRecents,
      _findCard,
      _Step(
        'Tap the ReadAlarm icon, then "Keep open"',
        'Tap the small ReadAlarm icon at the top of its card. In the menu, '
            'tap "Keep open" (or "Lock this app"). A lock appears on the card.',
        _Picture.menu,
      ),
      _comeBack,
    ],
    'Oppo / Realme': [
      _openRecents,
      _findCard,
      _Step(
        'Tap ⋮ on the card, then "Lock"',
        'Tap the ⋮ (three dots) on the ReadAlarm card, or pull the card down, '
            'then tap "Lock". A lock appears on the card.',
        _Picture.menu,
      ),
      _comeBack,
    ],
    'Other': [
      _openRecents,
      _findCard,
      _Step(
        'Lock the card',
        'Press and hold the ReadAlarm card, or pull it down, or tap its icon '
            'or ⋮. If you see "Lock" or "Keep open", tap it. A lock appears '
            'on the card. (If your phone has no lock option, that\'s fine.)',
        _Picture.pullDown,
      ),
      _comeBack,
    ],
  };

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final steps =
        _guides[OemAutostartScreen.brandFor(state.services.deviceBrand)]!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        const Center(child: IconBadge(icon: Icons.lock_rounded, size: 84)),
        const SizedBox(height: 16),
        const Text(
          'Lock ReadAlarm in recent apps',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Your phone closes apps in the background to save battery. A locked '
          'app is left alone, so your alarms ring. Do these steps now: they '
          'take about 20 seconds.',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 15, height: 1.45, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _StepCard(number: i + 1, step: steps[i]),
          ),
        const SizedBox(height: 8),
        PrimaryButton(
          label: 'I\'ve locked it',
          onPressed: () async {
            await state.requestPermission('recentsLock');
            onNext();
          },
        ),
      ],
    );
  }
}

enum _Picture { none, navButtons, cards, pullDown, menu }

class _Step {
  const _Step(this.title, this.body, this.picture);
  final String title;
  final String body;
  final _Picture picture;
}

class _StepCard extends StatelessWidget {
  const _StepCard({required this.number, required this.step});
  final int number;
  final _Step step;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: AppColors.orange,
                child: Text(
                  '$number',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  step.title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(step.body, style: const TextStyle(fontSize: 15, height: 1.4)),
          if (step.picture != _Picture.none) ...[
            const SizedBox(height: 12),
            Center(child: _StepPicture(step.picture)),
          ],
        ],
      ),
    );
  }
}

/// A simple drawing of what the user should see at a step.
class _StepPicture extends StatelessWidget {
  const _StepPicture(this.picture);
  final _Picture picture;

  static const _frame = Color(0xFF2B2F42);

  @override
  Widget build(BuildContext context) {
    return switch (picture) {
      _Picture.navButtons => _navButtons(),
      _Picture.cards => _cards(lock: false),
      _Picture.pullDown => _pullDown(),
      _Picture.menu => _menu(),
      _Picture.none => const SizedBox.shrink(),
    };
  }

  /// The bottom of a phone screen: Recent apps, Home, Back.
  Widget _navButtons() {
    Widget button(IconData icon, {bool highlight = false, String? label}) =>
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: highlight ? AppColors.orange : Colors.transparent,
              ),
              child: Icon(icon,
                  color: highlight ? Colors.white : Colors.white70, size: 28),
            ),
            if (label != null)
              Text(label,
                  style: const TextStyle(
                      color: AppColors.orange,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
          ],
        );
    return Container(
      width: 260,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: _frame,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          button(Icons.crop_square_rounded, highlight: true, label: 'Tap this'),
          button(Icons.circle_outlined),
          button(Icons.arrow_back_rounded),
        ],
      ),
    );
  }

  Widget _card(String name, {bool main = false, bool lock = false}) =>
      Container(
        width: main ? 96 : 64,
        height: main ? 150 : 110,
        decoration: BoxDecoration(
          color: main ? Colors.white : const Color(0xFFDADDE6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: main ? AppColors.orange : Colors.transparent, width: 2),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(main ? Icons.auto_stories_rounded : Icons.apps_rounded,
                    size: 16,
                    color: main ? AppColors.orange : AppColors.textMuted),
                if (main) ...[
                  const SizedBox(width: 4),
                  const Text('ReadAlarm',
                      style: TextStyle(fontSize: 10, color: AppColors.navy)),
                ],
              ],
            ),
            const Spacer(),
            if (lock)
              Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                    color: AppColors.orange, shape: BoxShape.circle),
                child: const Icon(Icons.lock_rounded,
                    size: 18, color: Colors.white),
              ),
            const SizedBox(height: 10),
          ],
        ),
      );

  /// The recent-apps screen with the ReadAlarm card in the middle.
  Widget _cards({required bool lock}) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _frame,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _card('Other'),
            const SizedBox(width: 8),
            _card('ReadAlarm', main: true, lock: lock),
            const SizedBox(width: 8),
            _card('Other'),
          ],
        ),
      );

  /// Pull the card down: before, then after with the lock.
  Widget _pullDown() => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            children: [
              _card('ReadAlarm', main: true),
              const Icon(Icons.arrow_downward_rounded,
                  color: AppColors.orange, size: 30),
              const Text('pull down',
                  style: TextStyle(
                      color: AppColors.orange,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child:
                Icon(Icons.arrow_forward_rounded, color: AppColors.textMuted),
          ),
          Column(
            children: [
              _card('ReadAlarm', main: true, lock: true),
              const SizedBox(height: 6),
              const Text('locked',
                  style: TextStyle(
                      color: AppColors.orange,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      );

  /// A card's menu with the lock option.
  Widget _menu() => Container(
        width: 200,
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              dense: true,
              leading: Icon(Icons.info_outline_rounded),
              title: Text('App info'),
            ),
            ListTile(
              dense: true,
              leading: Icon(Icons.lock_rounded, color: AppColors.orange),
              title: Text('Lock / Keep open',
                  style: TextStyle(
                      color: AppColors.orange, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
}
