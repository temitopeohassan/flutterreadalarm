import 'package:flutter/material.dart';

class BookInfo {
  const BookInfo({
    required this.id,
    required this.title,
    required this.coverColors,
    this.author = 'Unknown author',
    this.format = 'EPUB',
    this.chapter = 'Chapter 1',
    this.progress = 0,
    this.lastReadAt,
  });

  final String id;
  final String title;
  final String author;

  /// 'PDF' or 'EPUB'.
  final String format;
  final String chapter;

  /// 0.0 – 1.0
  final double progress;
  final DateTime? lastReadAt;

  /// Placeholder cover gradient until real cover extraction is wired up.
  final List<Color> coverColors;

  BookInfo copyWith({
    String? title,
    String? chapter,
    double? progress,
    DateTime? lastReadAt,
  }) {
    return BookInfo(
      id: id,
      title: title ?? this.title,
      author: author,
      format: format,
      chapter: chapter ?? this.chapter,
      progress: progress ?? this.progress,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      coverColors: coverColors,
    );
  }

  @override
  bool operator ==(Object other) => other is BookInfo && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class ReadingAlarm {
  const ReadingAlarm({
    required this.id,
    required this.time,
    required this.book,
    required this.durationMin,
    required this.repeatDays,
    this.enabled = true,
  });

  final String id;
  final TimeOfDay time;
  final BookInfo book;

  /// One of [allowedDurations] (PRD ALM-1).
  final int durationMin;

  /// 0 = Monday ... 6 = Sunday. Empty set = one-off alarm.
  final Set<int> repeatDays;
  final bool enabled;

  static const List<int> allowedDurations = [15, 30, 60];

  ReadingAlarm copyWith({
    TimeOfDay? time,
    BookInfo? book,
    int? durationMin,
    Set<int>? repeatDays,
    bool? enabled,
  }) {
    return ReadingAlarm(
      id: id,
      time: time ?? this.time,
      book: book ?? this.book,
      durationMin: durationMin ?? this.durationMin,
      repeatDays: repeatDays ?? this.repeatDays,
      enabled: enabled ?? this.enabled,
    );
  }
}

class ReadingSession {
  const ReadingSession({
    required this.bookTitle,
    required this.startedAt,
    required this.minutes,
    this.endReason = 'duration',
  });

  final String bookTitle;
  final DateTime startedAt;
  final int minutes;

  /// duration | stop | snooze | finished | error
  final String endReason;
}

String formatTime(TimeOfDay t) {
  final hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
  final minute = t.minute.toString().padLeft(2, '0');
  final period = t.period == DayPeriod.am ? 'AM' : 'PM';
  return '$hour:$minute $period';
}

String relativeDay(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return '$diff days ago';
}

String formatClock(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
}

/// Sample data for the UI demo. Replace with the SQLite repositories.
class SampleData {
  SampleData._();

  static final books = <BookInfo>[
    BookInfo(
      id: 'b1',
      title: 'The Midnight Library',
      author: 'Matt Haig',
      chapter: 'Chapter 12',
      progress: 0.42,
      lastReadAt: DateTime.now().subtract(const Duration(hours: 20)),
      coverColors: const [Color(0xFF1E2F5E), Color(0xFF3B4F86)],
    ),
    BookInfo(
      id: 'b2',
      title: 'Atomic Habits',
      author: 'James Clear',
      format: 'PDF',
      chapter: 'Chapter 4',
      progress: 0.18,
      lastReadAt: DateTime.now().subtract(const Duration(days: 3)),
      coverColors: const [Color(0xFFFBD9BF), Color(0xFFF4B083)],
    ),
    BookInfo(
      id: 'b3',
      title: 'Project Hail Mary',
      author: 'Andy Weir',
      chapter: 'Chapter 21',
      progress: 0.67,
      lastReadAt: DateTime.now().subtract(const Duration(days: 1)),
      coverColors: const [Color(0xFF14182B), Color(0xFF2D3558)],
    ),
  ];

  static List<ReadingAlarm> alarms() => [
        ReadingAlarm(
          id: 'a1',
          time: const TimeOfDay(hour: 7, minute: 0),
          book: books[0],
          durationMin: 30,
          repeatDays: {0, 2, 4},
        ),
        ReadingAlarm(
          id: 'a2',
          time: const TimeOfDay(hour: 8, minute: 0),
          book: books[1],
          durationMin: 15,
          repeatDays: {5, 6},
          enabled: false,
        ),
      ];

  static List<ReadingSession> sessions() {
    const minutes = [30, 15, 0, 30, 60, 30, 15, 30, 0, 30, 15, 30, 60, 30];
    final now = DateTime.now();
    return [
      for (var i = 0; i < minutes.length; i++)
        if (minutes[i] > 0)
          ReadingSession(
            bookTitle: books[i % books.length].title,
            startedAt: DateTime(now.year, now.month, now.day, 7)
                .subtract(Duration(days: i)),
            minutes: minutes[i],
          ),
    ];
  }

  static const voices = [
    'English (Nigeria), female',
    'English (UK), male',
    'English (US), female',
    'English (US), male',
  ];

  static final List<List<Color>> coverPalette = [
    const [Color(0xFF2F4858), Color(0xFF4F7A8C)],
    const [Color(0xFFFCE3CF), Color(0xFFF2A772)],
    const [Color(0xFF3A2E4F), Color(0xFF6A5A8C)],
    const [Color(0xFF1F4D3A), Color(0xFF3E7C5E)],
  ];
}
