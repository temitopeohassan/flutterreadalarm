import 'package:flutter/material.dart';
import '../models/reading_alarm.dart';

/// Demo app state. In production, split into Riverpod providers backed by
/// SQLite (books, alarms, sessions, settings) and RevenueCat (entitlement).
class AppState extends ChangeNotifier {
  static const freeBookLimit = 3; // PAY-2
  static const freeAlarmLimit = 2; // PAY-2

  bool onboardingDone = false;
  bool isPremium = false; // RevenueCat 'pro' entitlement

  final List<BookInfo> books = List.of(SampleData.books);
  final List<ReadingAlarm> alarms = SampleData.alarms();
  final List<ReadingSession> sessions = SampleData.sessions();

  String voice = SampleData.voices.first;
  double speed = 1.0;
  double pitch = 1.0;

  /// Rewarded-ad unlock of the 60-min duration (ADS-4).
  DateTime? rewardedUnlockUntil;

  final Map<String, bool> permissions = {
    'notifications': false,
    'exactAlarm': false,
    'battery': false,
    'autoStart': false,
  };

  // ---- Derived ----------------------------------------------------------

  bool get canAddBook => isPremium || books.length < freeBookLimit;
  bool get canAddAlarm => isPremium || alarms.length < freeAlarmLimit;

  bool get has60MinAccess =>
      isPremium ||
      (rewardedUnlockUntil != null &&
          rewardedUnlockUntil!.isAfter(DateTime.now()));

  bool get allPermissionsGranted => permissions.values.every((v) => v);

  int minutesOnDay(DateTime day) => sessions
      .where((s) =>
          s.startedAt.year == day.year &&
          s.startedAt.month == day.month &&
          s.startedAt.day == day.day)
      .fold(0, (sum, s) => sum + s.minutes);

  int get minutesThisWeek {
    final now = DateTime.now();
    var total = 0;
    for (var i = 0; i < 7; i++) {
      total += minutesOnDay(now.subtract(Duration(days: i)));
    }
    return total;
  }

  int get streakDays {
    final now = DateTime.now();
    var streak = 0;
    for (var i = 0; i < 365; i++) {
      if (minutesOnDay(now.subtract(Duration(days: i))) > 0) {
        streak++;
      } else if (i > 0) {
        break;
      }
    }
    return streak;
  }

  ReadingAlarm? get nextAlarm {
    final enabled = alarms.where((a) => a.enabled).toList()
      ..sort((a, b) => (a.time.hour * 60 + a.time.minute)
          .compareTo(b.time.hour * 60 + b.time.minute));
    return enabled.isEmpty ? null : enabled.first;
  }

  // ---- Mutations --------------------------------------------------------

  void completeOnboarding() {
    onboardingDone = true;
    notifyListeners();
  }

  void setPremium(bool value) {
    isPremium = value;
    notifyListeners();
  }

  void grantPermission(String key) {
    // TODO: real request via permission_handler / flutter_local_notifications
    permissions[key] = true;
    notifyListeners();
  }

  void addBook(BookInfo book) {
    books.add(book);
    notifyListeners();
  }

  void renameBook(BookInfo book, String title) {
    final i = books.indexOf(book);
    if (i >= 0) books[i] = book.copyWith(title: title);
    notifyListeners();
  }

  void deleteBook(BookInfo book) {
    books.remove(book);
    for (var i = 0; i < alarms.length; i++) {
      if (alarms[i].book == book) {
        alarms[i] = alarms[i].copyWith(enabled: false);
      }
    }
    notifyListeners();
  }

  void updateProgress(BookInfo book, double progress) {
    final i = books.indexOf(book);
    if (i >= 0) {
      books[i] = book.copyWith(progress: progress, lastReadAt: DateTime.now());
    }
    notifyListeners();
  }

  BookInfo bookById(String id) => books.firstWhere((b) => b.id == id);

  void upsertAlarm(ReadingAlarm alarm) {
    final i = alarms.indexWhere((a) => a.id == alarm.id);
    if (i >= 0) {
      alarms[i] = alarm;
    } else {
      alarms.add(alarm);
    }
    notifyListeners();
  }

  void toggleAlarm(ReadingAlarm alarm, bool enabled) {
    upsertAlarm(alarm.copyWith(enabled: enabled));
  }

  void deleteAlarm(ReadingAlarm alarm) {
    alarms.removeWhere((a) => a.id == alarm.id);
    notifyListeners();
  }

  void addSession(ReadingSession s) {
    sessions.insert(0, s);
    notifyListeners();
  }

  void unlockRewarded() {
    rewardedUnlockUntil = DateTime.now().add(const Duration(hours: 24));
    notifyListeners();
  }

  void setVoice(String v) {
    voice = v;
    notifyListeners();
  }

  void setSpeed(double v) {
    speed = v;
    notifyListeners();
  }

  void setPitch(double v) {
    pitch = v;
    notifyListeners();
  }
}

/// Makes [AppState] available to the widget tree and rebuilds on change.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
