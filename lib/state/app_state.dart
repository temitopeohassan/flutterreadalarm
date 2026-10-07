import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/reading_alarm.dart';
import '../services/alarm_scheduler.dart';
import '../services/book_importer.dart';
import '../services/book_text.dart';
import '../services/permission_service.dart';
import '../services/playback_service.dart';
import '../services/services.dart';
import '../services/speech.dart';

/// App state, persisted through [AppServices.storage] after every change.
///
/// Billing (RevenueCat) and ads are simulated: [setPremium] and
/// [unlockRewarded] stand in for real purchases and rewarded ads.
class AppState extends ChangeNotifier {
  AppState({
    required this.services,
    List<BookInfo>? books,
    List<ReadingAlarm>? alarms,
    List<ReadingSession>? sessions,
  })  : books = books ?? [],
        alarms = alarms ?? [],
        sessions = sessions ?? [] {
    reader = ReadingController(this);
  }

  static const freeBookLimit = 3; // PAY-2
  static const freeAlarmLimit = 2; // PAY-2
  static const maxStoredSessions = 1000;

  final AppServices services;
  late final ReadingController reader;

  bool onboardingDone = false;
  bool isPremium = false;

  final List<BookInfo> books;
  final List<ReadingAlarm> alarms;
  final List<ReadingSession> sessions;

  /// Null = the engine's default voice.
  VoiceOption? voice;
  List<VoiceOption> voices = const [];
  double speed = 1.0;
  double pitch = 1.0;

  /// Rewarded-ad unlock of the 60-min duration (ADS-4).
  DateTime? rewardedUnlockUntil;

  /// The user confirmed following the phone-brand auto-start guide.
  bool autoStartConfirmed = false;

  final Map<String, bool> permissions = {
    for (final key in permissionKeys) key: false,
  };

  /// An alarm the user opened, waiting to be shown by the UI.
  final pendingAlarm = ValueNotifier<(ReadingAlarm, AlarmAction)?>(null);

  final _texts = <String, BookText>{};
  bool _saveQueued = false;
  bool _disposed = false;

  /// Loads saved state and connects the services. Call once at startup.
  static Future<AppState> load(AppServices services) async {
    final state = AppState(services: services);
    final json = await services.storage.loadState();
    if (json != null) state._restore(json);
    await services.speech.init();
    await services.playback.init(state.reader.onCommand);
    await services.alarms.init(state.openAlarm);
    await state.refreshPermissions();
    unawaited(state.loadVoices());
    await state._syncAlarms();
    final launch = await services.alarms.takeLaunch();
    if (launch != null) state.openAlarm(launch);
    return state;
  }

  @override
  void dispose() {
    _disposed = true;
    reader.dispose();
    pendingAlarm.dispose();
    super.dispose();
  }

  // ---- Persistence ------------------------------------------------------

  Map<String, Object?> toJson() => {
        'version': 1,
        'onboardingDone': onboardingDone,
        'isPremium': isPremium,
        'rewardedUnlockUntil': rewardedUnlockUntil?.toIso8601String(),
        'autoStartConfirmed': autoStartConfirmed,
        'voice': voice?.toMap(),
        'speed': speed,
        'pitch': pitch,
        'books': [for (final b in books) b.toJson()],
        'alarms': [for (final a in alarms) a.toJson()],
        'sessions': [for (final s in sessions) s.toJson()],
      };

  void _restore(Map<String, Object?> json) {
    onboardingDone = json['onboardingDone'] as bool? ?? false;
    isPremium = json['isPremium'] as bool? ?? false;
    rewardedUnlockUntil =
        DateTime.tryParse(json['rewardedUnlockUntil'] as String? ?? '');
    autoStartConfirmed = json['autoStartConfirmed'] as bool? ?? false;
    voice = VoiceOption.fromMap(json['voice']);
    speed = (json['speed'] as num?)?.toDouble() ?? 1.0;
    pitch = (json['pitch'] as num?)?.toDouble() ?? 1.0;
    books
      ..clear()
      ..addAll([
        for (final b in json['books'] as List? ?? const [])
          BookInfo.fromJson((b as Map).cast()),
      ]);
    alarms
      ..clear()
      ..addAll([
        for (final a in json['alarms'] as List? ?? const [])
          if (ReadingAlarm.fromJson((a as Map).cast(), _findBook)
              case final alarm?)
            alarm,
      ]);
    sessions
      ..clear()
      ..addAll([
        for (final s in json['sessions'] as List? ?? const [])
          ReadingSession.fromJson((s as Map).cast()),
      ]);
  }

  /// Notifies listeners and saves (once per microtask, however many
  /// changes were made).
  void _changed() {
    if (_disposed) return;
    notifyListeners();
    if (_saveQueued) return;
    _saveQueued = true;
    scheduleMicrotask(() {
      _saveQueued = false;
      if (!_disposed) services.storage.saveState(toJson());
    });
  }

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

  /// The enabled alarm that rings soonest.
  ReadingAlarm? get nextAlarm {
    final now = DateTime.now();
    final enabled = alarms.where((a) => a.enabled).toList()
      ..sort((a, b) => a.nextOccurrence(now).compareTo(b.nextOccurrence(now)));
    return enabled.isEmpty ? null : enabled.first;
  }

  /// The book most recently read (or added), for the test alarm.
  BookInfo? get lastReadBook {
    if (books.isEmpty) return null;
    final sorted = List.of(books)
      ..sort((a, b) =>
          (b.lastReadAt ?? DateTime(0)).compareTo(a.lastReadAt ?? DateTime(0)));
    return sorted.first.lastReadAt == null ? books.last : sorted.first;
  }

  BookInfo? _findBook(String id) => books.where((b) => b.id == id).firstOrNull;

  BookInfo bookById(String id) => books.firstWhere((b) => b.id == id);

  BookInfo? findBook(String id) => _findBook(id);

  // ---- Onboarding, premium, permissions ---------------------------------

  void completeOnboarding() {
    onboardingDone = true;
    _changed();
  }

  /// Simulated purchase (billing is not wired up yet).
  void setPremium(bool value) {
    isPremium = value;
    _changed();
  }

  Future<void> refreshPermissions() async {
    try {
      permissions.addAll(await services.permissions.status());
    } catch (e) {
      debugPrint('Permission check failed: $e');
    }
    permissions['autoStart'] = autoStartConfirmed;
    if (!_disposed) notifyListeners();
  }

  Future<void> requestPermission(String key) async {
    if (key == 'autoStart') {
      autoStartConfirmed = true;
      _changed();
    } else {
      try {
        await services.permissions.request(key);
      } catch (e) {
        debugPrint('Permission request failed: $e');
      }
    }
    await refreshPermissions();
  }

  // ---- Books ------------------------------------------------------------

  /// Text of [bookId], loaded from storage on first use.
  Future<BookText?> textFor(String bookId) async {
    final cached = _texts[bookId];
    if (cached != null) return cached;
    final text = await services.storage.loadBookText(bookId);
    if (text != null) _texts[bookId] = text;
    return text;
  }

  /// Saves an extracted book and adds it to the library.
  Future<BookInfo> addExtractedBook({
    required String fileName,
    required String format,
    required ExtractedBook extracted,
  }) async {
    final id = 'b${DateTime.now().microsecondsSinceEpoch}';
    final fallbackTitle = fileName.replaceFirst(RegExp(r'\.[^.]+$'), '');
    final title = extracted.title.isNotEmpty ? extracted.title : fallbackTitle;
    final book = BookInfo(
      id: id,
      title: title,
      author: extracted.author.isNotEmpty ? extracted.author : 'Unknown author',
      format: format,
      chapter: extracted.text.chapterAt(0),
      sentenceCount: extracted.text.sentences.length,
      coverColors: coverPalette[title.hashCode.abs() % coverPalette.length],
    );
    await services.storage.saveBookText(id, extracted.text);
    _texts[id] = extracted.text;
    books.add(book);
    _changed();
    return book;
  }

  void renameBook(BookInfo book, String title) {
    _replaceBook(bookById(book.id).copyWith(title: title));
  }

  Future<void> deleteBook(BookInfo book) async {
    if (reader.bookId == book.id) await reader.finish('stop');
    books.removeWhere((b) => b.id == book.id);
    _texts.remove(book.id);
    for (final alarm in alarms.where((a) => a.book.id == book.id).toList()) {
      await deleteAlarm(alarm);
    }
    await services.storage.deleteBook(book.id);
    _changed();
  }

  /// Moves [bookId]'s reading position to sentence [position].
  void updatePosition(String bookId, int position) {
    final book = _findBook(bookId);
    if (book == null) return;
    final text = _texts[bookId];
    _replaceBook(book.copyWith(
      position: position,
      chapter: text?.chapterAt(position),
      lastReadAt: DateTime.now(),
    ));
    if (text == null) {
      // Chapter names live in the book text; fill it in once loaded.
      textFor(bookId).then((loaded) {
        final current = _findBook(bookId);
        if (loaded == null || current == null || _disposed) return;
        if (current.position != position) return;
        _replaceBook(current.copyWith(chapter: loaded.chapterAt(position)));
      });
    }
  }

  void _replaceBook(BookInfo updated) {
    final i = books.indexWhere((b) => b.id == updated.id);
    if (i < 0) return;
    books[i] = updated;
    for (var j = 0; j < alarms.length; j++) {
      if (alarms[j].book.id == updated.id) {
        alarms[j] = alarms[j].copyWith(book: updated);
      }
    }
    _changed();
  }

  // ---- Alarms -----------------------------------------------------------

  Future<void> upsertAlarm(ReadingAlarm alarm) async {
    final i = alarms.indexWhere((a) => a.id == alarm.id);
    if (i >= 0) {
      alarms[i] = alarm;
    } else {
      alarms.add(alarm);
    }
    _changed();
    await _schedule(alarm);
  }

  Future<void> toggleAlarm(ReadingAlarm alarm, bool enabled) =>
      upsertAlarm(alarm.copyWith(enabled: enabled));

  Future<void> deleteAlarm(ReadingAlarm alarm) async {
    alarms.removeWhere((a) => a.id == alarm.id);
    _changed();
    try {
      await services.alarms.cancel(alarm.id);
    } catch (e) {
      debugPrint('Cancelling alarm failed: $e');
    }
  }

  Future<void> _schedule(ReadingAlarm alarm) async {
    try {
      await services.alarms.schedule(alarm);
    } catch (e) {
      debugPrint('Scheduling alarm failed: $e');
    }
  }

  /// One-off alarms that already rang are switched off; every enabled
  /// alarm is (re)scheduled so the OS schedule matches the app.
  Future<void> _syncAlarms() async {
    final pending = await services.alarms.pendingAlarmIds();
    for (var i = 0; i < alarms.length; i++) {
      final a = alarms[i];
      if (a.enabled && a.repeatDays.isEmpty && !pending.contains(a.id)) {
        alarms[i] = a.copyWith(enabled: false);
      }
    }
    for (final alarm in alarms.where((a) => a.enabled)) {
      if (!pending.contains(alarm.id)) await _schedule(alarm);
    }
    _changed();
  }

  /// Rings in one minute with a 1-minute session of the last-read book.
  /// Returns false if there's no book yet.
  Future<bool> scheduleTestAlarm() async {
    final book = lastReadBook;
    if (book == null) return false;
    await services.alarms.scheduleOnce(
      AlarmPayload(
        alarmId: 'test',
        bookId: book.id,
        durationMin: 1,
        title: 'Test alarm',
        body: '${book.title} · Read 1 min',
      ),
      DateTime.now().add(const Duration(minutes: 1)),
    );
    return true;
  }

  /// Handles a ringing alarm the user opened or acted on.
  void openAlarm(AlarmLaunch launch) {
    final p = launch.payload;
    final book = _findBook(p.bookId);
    if (book == null) return;
    final known = alarms.where((a) => a.id == p.alarmId).firstOrNull;
    final alarm = known ??
        ReadingAlarm(
          id: p.alarmId,
          time: p.time ?? TimeOfDay.now(),
          book: book,
          durationMin: p.durationMin,
          repeatDays: const {},
        );
    // A one-off alarm is done once it has rung.
    if (known != null && known.repeatDays.isEmpty && known.enabled) {
      final i = alarms.indexOf(known);
      alarms[i] = known.copyWith(enabled: false);
      _changed();
    }
    pendingAlarm.value = (alarm, launch.action);
  }

  /// Stops a ringing alarm's sound and notification.
  Future<void> silenceAlarm(ReadingAlarm alarm) async {
    try {
      await services.alarms.dismiss(alarm.id);
    } catch (e) {
      debugPrint('Dismissing alarm failed: $e');
    }
  }

  Future<void> snoozeAlarm(ReadingAlarm alarm) async {
    await silenceAlarm(alarm);
    await services.alarms.scheduleOnce(
      AlarmPayload.forAlarm(alarm),
      DateTime.now().add(snoozeDuration),
    );
  }

  // ---- Sessions ---------------------------------------------------------

  void addSession(ReadingSession s) {
    sessions.insert(0, s);
    if (sessions.length > maxStoredSessions) sessions.removeLast();
    _changed();
  }

  /// Simulated rewarded ad (ads are not wired up yet).
  void unlockRewarded() {
    rewardedUnlockUntil = DateTime.now().add(const Duration(hours: 24));
    _changed();
  }

  // ---- Voice ------------------------------------------------------------

  Future<void> loadVoices() async {
    try {
      voices = await services.speech.voices();
    } catch (_) {
      voices = const [];
    }
    if (voice != null && !voices.contains(voice)) voice = null;
    if (!_disposed) notifyListeners();
  }

  void setVoice(VoiceOption? v) {
    voice = v;
    _changed();
    reader.applyVoiceSettings();
  }

  void setSpeed(double v) {
    speed = v;
    _changed();
    reader.applyVoiceSettings();
  }

  void setPitch(double v) {
    pitch = v;
    _changed();
    reader.applyVoiceSettings();
  }

  /// Voice used for speech: Premium users get their choice (TTS-2).
  VoiceOption? get effectiveVoice => isPremium ? voice : null;
  double get effectivePitch => isPremium ? pitch : 1.0;

  Future<void> previewVoice() async {
    if (reader.active) return;
    await services.speech
        .configure(speed: speed, pitch: effectivePitch, voice: effectiveVoice);
    await services.speech.speak(
        'Good morning. This is how ReadAlarm will read your book to you.');
  }
}

/// A finished reading session, for the Session complete screen.
class CompletedSession {
  const CompletedSession({
    required this.bookId,
    required this.minutes,
    required this.progressBefore,
    required this.reason,
  });

  final String bookId;
  final int minutes;
  final double progressBefore;
  final String reason;
}

/// Reads a book aloud sentence by sentence (TTS-2..5), tracks the session
/// clock and saves the reading position as it goes (PRG-1).
class ReadingController extends ChangeNotifier {
  ReadingController(this._state);

  final AppState _state;

  String? bookId;
  BookText? text;
  int index = 0;
  bool playing = false;
  Duration elapsed = Duration.zero;

  /// Session length for alarm sessions; null = open-ended "Read now".
  int? durationMin;
  CompletedSession? lastCompleted;

  DateTime? _startedAt;
  double _progressBefore = 0;
  Timer? _ticker;
  int _generation = 0;
  bool _disposed = false;

  bool get active => bookId != null;
  String get currentSentence {
    final t = text;
    if (t == null || t.sentences.isEmpty) return '';
    return t.sentences[index.clamp(0, t.sentences.length - 1)];
  }

  Duration? get remaining =>
      durationMin == null ? null : Duration(minutes: durationMin!) - elapsed;

  double get progress {
    final count = text?.sentences.length ?? 0;
    return count == 0 ? 0 : (index / count).clamp(0.0, 1.0);
  }

  String get chapter => text?.chapterAt(index) ?? '';

  /// Starts reading [book] from its saved position. Any other session is
  /// finished first. Returns false if the book's text is missing.
  Future<bool> start(BookInfo book, {int? durationMin}) async {
    if (bookId == book.id) {
      this.durationMin = durationMin ?? this.durationMin;
      if (!playing) resume();
      return true;
    }
    if (active) await finish('stop');
    final loaded = await _state.textFor(book.id);
    if (loaded == null || loaded.sentences.isEmpty) return false;

    bookId = book.id;
    text = loaded;
    index = book.isFinished ? 0 : book.position;
    this.durationMin = durationMin;
    elapsed = Duration.zero;
    lastCompleted = null;
    _startedAt = DateTime.now();
    _progressBefore = book.isFinished ? 0 : book.progress;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    resume();
    return true;
  }

  void _tick() {
    if (!playing) return;
    elapsed += const Duration(seconds: 1);
    final limit = durationMin;
    if (limit != null && elapsed >= Duration(minutes: limit)) {
      finish('duration');
      return;
    }
    if (elapsed.inSeconds % 60 == 0) _updateNotification();
    _notify();
  }

  void resume() {
    if (!active) return;
    playing = true;
    _updateNotification();
    _notify();
    _speakFromHere();
  }

  Future<void> pause() async {
    if (!active) return;
    playing = false;
    _generation++;
    _notify();
    _updateNotification();
    await _state.services.speech.stop();
    _savePosition();
  }

  void toggle() => playing ? pause() : resume();

  /// Moves [delta] sentences back or forward.
  Future<void> skip(int delta) async {
    final count = text?.sentences.length ?? 0;
    if (!active || count == 0) return;
    index = (index + delta).clamp(0, count - 1);
    _savePosition();
    _notify();
    if (playing) {
      _generation++;
      await _state.services.speech.stop();
      _speakFromHere();
    }
  }

  /// Re-applies voice, speed and pitch, restarting the current sentence.
  Future<void> applyVoiceSettings() async {
    if (!active || !playing) return;
    _generation++;
    await _state.services.speech.stop();
    _speakFromHere();
  }

  Future<void> _speakFromHere() async {
    final generation = ++_generation;
    final speech = _state.services.speech;
    await speech.configure(
      speed: _state.speed,
      pitch: _state.effectivePitch,
      voice: _state.effectiveVoice,
    );
    while (generation == _generation && playing && active) {
      final sentences = text!.sentences;
      if (index >= sentences.length) {
        await finish('finished');
        return;
      }
      final completed = await speech.speak(sentences[index]);
      if (generation != _generation || !playing || !active) return;
      if (!completed) {
        // The engine failed rather than being interrupted by us.
        await pause();
        return;
      }
      index++;
      _savePosition();
      _notify();
    }
  }

  void _savePosition() {
    final id = bookId;
    if (id != null) _state.updatePosition(id, index);
  }

  void _updateNotification() {
    final id = bookId;
    if (id == null) return;
    final book = _state.findBook(id);
    final left = remaining;
    _state.services.playback.show(
      title: book?.title ?? 'ReadAlarm',
      text: [
        playing ? 'Reading aloud' : 'Paused',
        if (left != null) '${left.inMinutes + 1} min left',
      ].join(' · '),
      playing: playing,
    );
  }

  /// Handles a lock-screen notification button.
  void onCommand(String command) {
    if (command == playbackToggle) toggle();
    if (command == playbackStop) finish('stop');
  }

  /// Ends the session, saves progress and records it in the stats.
  Future<CompletedSession?> finish(String reason) async {
    final id = bookId;
    if (id == null) return null;
    _generation++;
    _ticker?.cancel();
    _ticker = null;
    playing = false;
    _savePosition();
    await _state.services.speech.stop();
    await _state.services.playback.hide();

    final minutes = math.max(1, (elapsed.inSeconds / 60).ceil());
    final book = _state.findBook(id);
    if (book != null && elapsed > Duration.zero) {
      _state.addSession(ReadingSession(
        bookTitle: book.title,
        startedAt: _startedAt ?? DateTime.now(),
        minutes: minutes,
        endReason: reason,
      ));
    }
    final completed = lastCompleted = CompletedSession(
      bookId: id,
      minutes: minutes,
      progressBefore: _progressBefore,
      reason: reason,
    );
    bookId = null;
    text = null;
    durationMin = null;
    _notify();
    return completed;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _ticker?.cancel();
    super.dispose();
  }
}

/// Makes [AppState] available to the widget tree and rebuilds on change.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
