import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/reading_alarm.dart';
import '../services/ads_service.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'paywall_screen.dart';
import '../theme/app_colors.dart';
import '../widgets/book_cover.dart';
import '../widgets/navy_header.dart';

/// Screen — create or edit an alarm (ALM-1). Pops with the saved [ReadingAlarm].
/// 60-min sessions need Premium or a rewarded-ad unlock (PAY-2, ADS-4).
class SetAlarmScreen extends StatefulWidget {
  const SetAlarmScreen({super.key, this.initial, this.initialBook});

  final ReadingAlarm? initial;

  /// Book preselected for a new alarm (e.g. from the Library).
  final BookInfo? initialBook;

  @override
  State<SetAlarmScreen> createState() => _SetAlarmScreenState();
}

class _SetAlarmScreenState extends State<SetAlarmScreen> {
  late TimeOfDay _time;
  late BookInfo _book;
  late int _durationIndex;
  late Set<int> _repeat;

  /// Day a one-off alarm rings; null = the next time [_time] comes round.
  DateTime? _date;
  bool _initialised = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialised) return;
    _initialised = true;
    final books = AppScope.of(context).books;
    final a = widget.initial;
    _time = a?.time ?? const TimeOfDay(hour: 7, minute: 0);
    final wanted = a?.book.id ?? widget.initialBook?.id;
    _book = books.where((b) => b.id == wanted).firstOrNull ?? books.first;
    _durationIndex =
        ReadingAlarm.allowedDurations.indexOf(a?.durationMin ?? 30);
    _repeat = Set.of(a?.repeatDays ?? {0, 2, 4});
    _date = a?.date;
    if (a == null) _time = _firstFreeTime(AppScope.of(context));
  }

  /// For a new alarm: 7:00 AM, or the next half hour without an alarm on
  /// the default days, so saving straight away doesn't clash.
  TimeOfDay _firstFreeTime(AppState state) {
    var minutes = _time.hour * 60 + _time.minute;
    for (var i = 0; i < 48; i++) {
      final time = TimeOfDay(hour: minutes ~/ 60 % 24, minute: minutes % 60);
      _time = time;
      if (state.clashFor(_draft()) == null) return time;
      minutes += 30;
    }
    return const TimeOfDay(hour: 7, minute: 0);
  }

  /// The day a one-off alarm with the current settings rings on.
  DateTime get _onceDay {
    final at = _draft(date: _date).nextOccurrence(DateTime.now());
    return DateTime(at.year, at.month, at.day);
  }

  ReadingAlarm _draft({DateTime? date}) => ReadingAlarm(
        id: widget.initial?.id ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        time: _time,
        book: _book,
        durationMin: _duration,
        repeatDays: Set.of(_repeat),
        enabled: widget.initial?.enabled ?? true,
        date: _repeat.isEmpty ? date : null,
      );

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _onceDay.isBefore(today) ? today : _onceDay,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      helpText: 'Alarm date',
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _onDurationChanged(int index) async {
    final state = AppScope.of(context);
    final wants60 = ReadingAlarm.allowedDurations[index] == 60;
    if (!wants60 || state.has60MinAccess) {
      setState(() => _durationIndex = index);
      return;
    }
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.cream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const IconBadge(icon: Icons.timer_rounded, size: 80),
              const SizedBox(height: 16),
              const Text('60-minute sessions',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text(
                'Watch a short ad to unlock 60 minutes for the next 24 hours, '
                'or go Premium for no ads and no limits.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 20),
              PrimaryButton(
                label: 'Watch ad to unlock',
                icon: Icons.play_circle_outline_rounded,
                onPressed: () => Navigator.pop(ctx, 'ad'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'premium'),
                child: const Text('Go Premium',
                    style: TextStyle(color: AppColors.orange)),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'ad') {
      final earned = await AdsService.instance.showRewarded();
      if (earned && mounted) {
        state.unlockRewarded();
        setState(() => _durationIndex = index);
      }
    } else if (choice == 'premium') {
      await PaywallScreen.open(context);
      if (mounted && state.has60MinAccess) {
        setState(() => _durationIndex = index);
      }
    }
  }

  int get _duration => ReadingAlarm.allowedDurations[_durationIndex];

  Future<void> _save() async {
    final state = AppScope.of(context);
    final alarm = _draft(date: _repeat.isEmpty ? _onceDay : null);
    final result = await state.saveAlarm(alarm);
    if (!mounted) return;
    switch (result.status) {
      case AlarmSaveStatus.saved:
        Navigator.of(context).pop(true);
      case AlarmSaveStatus.limitReached:
        await PaywallScreen.open(context);
      case AlarmSaveStatus.inPast:
        showSnack(context, 'That time has already passed. Pick a later time.');
      case AlarmSaveStatus.clash:
        final other = result.clash!;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('An alarm is already set for then'),
            content: Text(
              '${formatTime(other.time)} · ${other.scheduleLabel}\n'
              '${other.book.title}\n\n'
              'Pick another time or day, or edit that alarm instead.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          NavyHeader(
            title: widget.initial == null ? 'Set new alarm' : 'Edit alarm',
            titleSize: 19,
            leading: IconButton(
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.chevron_left_rounded,
                  color: Colors.white, size: 32),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              children: [
                const _SectionLabel('Time'),
                _TimeSpinner(
                  time: _time,
                  onChanged: (t) => setState(() => _time = t),
                ),
                const SizedBox(height: 24),
                const _SectionLabel('Book'),
                _BookDropdown(
                  books: AppScope.of(context).books,
                  value: _book,
                  onChanged: (b) => setState(() => _book = b),
                ),
                const SizedBox(height: 24),
                const _SectionLabel('Reading time'),
                Text(
                  '$_duration minutes',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.orange,
                  ),
                ),
                _DurationSlider(
                  index: _durationIndex,
                  onChanged: _onDurationChanged,
                ),
                if (!AppScope.of(context).has60MinAccess)
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: EdgeInsets.only(right: 12),
                      child: PremiumChip(),
                    ),
                  ),
                const SizedBox(height: 20),
                const _SectionLabel('Repeat'),
                _RepeatDays(
                  selected: _repeat,
                  onToggle: (d) => setState(() {
                    _repeat.contains(d) ? _repeat.remove(d) : _repeat.add(d);
                  }),
                ),
                if (_repeat.isEmpty) ...[
                  const SizedBox(height: 20),
                  const _SectionLabel('Date'),
                  _DateField(day: _onceDay, onTap: _pickDate),
                  const SizedBox(height: 6),
                  const Text(
                    'No repeat days: rings once on this date.',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.orange,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: const Text('Save alarm'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

/// Hour : minute : AM/PM spinner with chevrons. Tap a column to focus it.
class _TimeSpinner extends StatefulWidget {
  const _TimeSpinner({required this.time, required this.onChanged});
  final TimeOfDay time;
  final ValueChanged<TimeOfDay> onChanged;

  @override
  State<_TimeSpinner> createState() => _TimeSpinnerState();
}

class _TimeSpinnerState extends State<_TimeSpinner> {
  int _focus = 1; // 0 hour, 1 minute, 2 period

  void _step(int field, int delta) {
    final t = widget.time;
    setState(() => _focus = field);
    switch (field) {
      case 0:
        widget.onChanged(t.replacing(hour: (t.hour + delta) % 24));
      case 1:
        widget.onChanged(t.replacing(minute: (t.minute + delta) % 60));
      case 2:
        widget.onChanged(t.replacing(hour: (t.hour + 12) % 24));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.time;
    final hour =
        (t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod).toString().padLeft(2, '0');
    final minute = t.minute.toString().padLeft(2, '0');
    final period = t.period == DayPeriod.am ? 'AM' : 'PM';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 14, offset: Offset(0, 4)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _column(0, hour, 'Hour'),
          const _Colon(),
          _column(1, minute, 'Minute'),
          const _Colon(),
          _column(2, period, 'AM or PM', alwaysOrange: true),
        ],
      ),
    );
  }

  Widget _column(int field, String value, String label,
      {bool alwaysOrange = false}) {
    final focused = _focus == field && !alwaysOrange;
    return Semantics(
      label: '$label $value',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Chevron(
            icon: Icons.keyboard_arrow_up_rounded,
            tooltip: 'Later ${label.toLowerCase()}',
            onTap: () => _step(field, 1),
          ),
          GestureDetector(
            onTap: () => setState(() => _focus = field),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 64,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: focused ? AppColors.orange : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                value,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: field == 2 ? 20 : 26,
                  fontWeight: FontWeight.w600,
                  color: focused
                      ? Colors.white
                      : alwaysOrange
                          ? AppColors.orange
                          : AppColors.textPrimary,
                ),
              ),
            ),
          ),
          _Chevron(
            icon: Icons.keyboard_arrow_down_rounded,
            tooltip: 'Earlier ${label.toLowerCase()}',
            onTap: () => _step(field, -1),
          ),
        ],
      ),
    );
  }
}

class _Chevron extends StatelessWidget {
  const _Chevron({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        child: SizedBox(
          width: 48,
          height: 32,
          child: Icon(icon, color: AppColors.textMuted),
        ),
      ),
    );
  }
}

class _Colon extends StatelessWidget {
  const _Colon();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        ':',
        style: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _BookDropdown extends StatelessWidget {
  const _BookDropdown({
    required this.books,
    required this.value,
    required this.onChanged,
  });

  final List<BookInfo> books;
  final BookInfo value;
  final ValueChanged<BookInfo> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.navy, width: 1.4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<BookInfo>(
          value: value,
          isExpanded: true,
          borderRadius: BorderRadius.circular(12),
          icon: const Icon(Icons.arrow_drop_down_rounded,
              color: AppColors.textSecondary),
          items: [
            for (final b in books)
              DropdownMenuItem(
                value: b,
                child: Row(
                  children: [
                    BookCover(book: b, width: 26),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        b.title,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          onChanged: (b) {
            if (b != null) onChanged(b);
          },
        ),
      ),
    );
  }
}

class _DurationSlider extends StatelessWidget {
  const _DurationSlider({required this.index, required this.onChanged});
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const values = ReadingAlarm.allowedDurations;
    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppColors.orange,
            inactiveTrackColor: AppColors.peach,
            thumbColor: AppColors.orange,
            overlayColor: const Color(0x29EF7A3B),
            activeTickMarkColor: Colors.white,
            inactiveTickMarkColor: AppColors.peachBorder,
            trackHeight: 4,
            showValueIndicator: ShowValueIndicator.never,
          ),
          child: Slider(
            value: index.toDouble(),
            min: 0,
            max: (values.length - 1).toDouble(),
            divisions: values.length - 1,
            semanticFormatterCallback: (v) => '${values[v.round()]} minutes',
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final v in values)
                Text(
                  '$v',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RepeatDays extends StatelessWidget {
  const _RepeatDays({required this.selected, required this.onToggle});
  final Set<int> selected;
  final ValueChanged<int> onToggle;

  static const _letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _names = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var d = 0; d < 7; d++)
          Semantics(
            button: true,
            selected: selected.contains(d),
            label: _names[d],
            child: GestureDetector(
              onTap: () => onToggle(d),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected.contains(d)
                      ? AppColors.orange
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected.contains(d)
                        ? AppColors.orange
                        : AppColors.border,
                  ),
                ),
                child: Text(
                  _letters[d],
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: selected.contains(d)
                        ? Colors.white
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.day, required this.onTap});
  final DateTime day;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final label = switch (day.difference(today).inDays) {
      0 => 'Today, ${formatDay(day)}',
      1 => 'Tomorrow, ${formatDay(day)}',
      _ => '${formatDay(day)} ${day.year}',
    };
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.navy, width: 1.4),
          ),
          child: Row(
            children: [
              const Icon(Icons.event_rounded, color: AppColors.navy),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 16, color: AppColors.textPrimary)),
              ),
              const Icon(Icons.edit_calendar_rounded,
                  color: AppColors.textSecondary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
