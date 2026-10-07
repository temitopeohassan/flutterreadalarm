import 'package:flutter/material.dart';

class BookInfo {
  const BookInfo({
    required this.id,
    required this.title,
    required this.coverColors,
    this.author = 'Unknown author',
    this.format = 'EPUB',
    this.chapter = '',
    this.position = 0,
    this.sentenceCount = 0,
    this.lastReadAt,
  });

  final String id;
  final String title;
  final String author;

  /// 'PDF' or 'EPUB'.
  final String format;

  /// Title of the chapter at [position], or '' if the book has none.
  final String chapter;

  /// Index of the next sentence to read.
  final int position;

  /// Number of sentences extracted from the book.
  final int sentenceCount;
  final DateTime? lastReadAt;

  /// Cover gradient, picked when the book is imported.
  final List<Color> coverColors;

  /// 0.0 – 1.0
  double get progress =>
      sentenceCount == 0 ? 0 : (position / sentenceCount).clamp(0.0, 1.0);

  bool get isFinished => sentenceCount > 0 && position >= sentenceCount;

  BookInfo copyWith({
    String? title,
    String? chapter,
    int? position,
    DateTime? lastReadAt,
  }) {
    return BookInfo(
      id: id,
      title: title ?? this.title,
      author: author,
      format: format,
      chapter: chapter ?? this.chapter,
      position: position ?? this.position,
      sentenceCount: sentenceCount,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      coverColors: coverColors,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'format': format,
        'chapter': chapter,
        'position': position,
        'sentenceCount': sentenceCount,
        'lastReadAt': lastReadAt?.toIso8601String(),
        'coverColors': [for (final c in coverColors) c.toARGB32()],
      };

  factory BookInfo.fromJson(Map<String, Object?> json) => BookInfo(
        id: json['id'] as String,
        title: json['title'] as String,
        author: json['author'] as String? ?? 'Unknown author',
        format: json['format'] as String? ?? 'EPUB',
        chapter: json['chapter'] as String? ?? '',
        position: json['position'] as int? ?? 0,
        sentenceCount: json['sentenceCount'] as int? ?? 0,
        lastReadAt: _parseDate(json['lastReadAt']),
        coverColors: [
          for (final c in json['coverColors'] as List? ?? const [])
            Color(c as int),
        ],
      );

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

  /// The next moment this alarm rings, strictly after [from].
  DateTime nextOccurrence(DateTime from) {
    for (var add = 0; add <= 7; add++) {
      final day = DateTime(from.year, from.month, from.day + add);
      final at = DateTime(day.year, day.month, day.day, time.hour, time.minute);
      if (!at.isAfter(from)) continue;
      if (repeatDays.isEmpty || repeatDays.contains(at.weekday - 1)) return at;
    }
    throw StateError('unreachable');
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'hour': time.hour,
        'minute': time.minute,
        'bookId': book.id,
        'durationMin': durationMin,
        'repeatDays': repeatDays.toList()..sort(),
        'enabled': enabled,
      };

  /// Returns null if the alarm's book no longer exists.
  static ReadingAlarm? fromJson(
    Map<String, Object?> json,
    BookInfo? Function(String id) findBook,
  ) {
    final book = findBook(json['bookId'] as String);
    if (book == null) return null;
    return ReadingAlarm(
      id: json['id'] as String,
      time: TimeOfDay(hour: json['hour'] as int, minute: json['minute'] as int),
      book: book,
      durationMin: json['durationMin'] as int,
      repeatDays: {for (final d in json['repeatDays'] as List) d as int},
      enabled: json['enabled'] as bool? ?? true,
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

  Map<String, Object?> toJson() => {
        'bookTitle': bookTitle,
        'startedAt': startedAt.toIso8601String(),
        'minutes': minutes,
        'endReason': endReason,
      };

  factory ReadingSession.fromJson(Map<String, Object?> json) => ReadingSession(
        bookTitle: json['bookTitle'] as String,
        startedAt: DateTime.parse(json['startedAt'] as String),
        minutes: json['minutes'] as int,
        endReason: json['endReason'] as String? ?? 'stop',
      );
}

/// Cover gradients given to imported books.
const List<List<Color>> coverPalette = [
  [Color(0xFF2F4858), Color(0xFF4F7A8C)],
  [Color(0xFFFCE3CF), Color(0xFFF2A772)],
  [Color(0xFF3A2E4F), Color(0xFF6A5A8C)],
  [Color(0xFF1F4D3A), Color(0xFF3E7C5E)],
  [Color(0xFF1E2F5E), Color(0xFF3B4F86)],
  [Color(0xFF5E2B2B), Color(0xFF8C4A3E)],
];

DateTime? _parseDate(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

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

/// Demo content used by tests and the screenshot generator.
class SampleData {
  SampleData._();

  static final books = <BookInfo>[
    BookInfo(
      id: 'b1',
      title: 'The Midnight Library',
      author: 'Matt Haig',
      chapter: 'Chapter 12',
      position: 420,
      sentenceCount: 1000,
      lastReadAt: DateTime.now().subtract(const Duration(hours: 20)),
      coverColors: const [Color(0xFF1E2F5E), Color(0xFF3B4F86)],
    ),
    BookInfo(
      id: 'b2',
      title: 'Atomic Habits',
      author: 'James Clear',
      format: 'PDF',
      chapter: 'Chapter 4',
      position: 180,
      sentenceCount: 1000,
      lastReadAt: DateTime.now().subtract(const Duration(days: 3)),
      coverColors: const [Color(0xFFFBD9BF), Color(0xFFF4B083)],
    ),
    BookInfo(
      id: 'b3',
      title: 'Project Hail Mary',
      author: 'Andy Weir',
      chapter: 'Chapter 21',
      position: 670,
      sentenceCount: 1000,
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
}
