import 'dart:async';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../models/reading_alarm.dart';
import '../services/alarm_scheduler.dart';
import '../services/billing_service.dart';
import '../services/event_log.dart';
import '../services/book_importer.dart';
import '../services/book_text.dart';
import '../services/permission_service.dart';
import '../services/playback_service.dart';
import '../services/services.dart';
import '../services/speech.dart';

/// App state, persisted through [AppServices.storage] after every change.
///
/// Premium is bought through Google Play Billing ([buyPremium]); the
/// last known state is saved so the app works offline.
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
  static const freeAlarmLimit = 1; // PAY-2
  static const maxStoredSessions = 1000;

  final AppServices services;
  late final ReadingController reader;

  bool onboardingDone = false;

  /// Premium bought: an active Google Play subscription, as last checked.
  bool purchased = false;

  /// Google Play's prices by product id; empty until loaded (or if the
  /// store isn't available).
  Map<String, String> storePrices = const {};

  /// A message about a purchase for the UI to show, e.g. a pending payment.
  final billingNotice = ValueNotifier<String?>(null);

  /// Premium features are on (bought; simulated until billing is wired).
  bool get isPremium => purchased;

  final List<BookInfo> books;
  final List<ReadingAlarm> alarms;
  final List<ReadingSession> sessions;

  /// Null = the engine's default voice.
  VoiceOption? voice;
  List<VoiceOption> voices = const [];
  double speed = 1.0;
  double pitch = 1.0;

  /// Free reading allowance per day, reset at local midnight.
  static const freeDailyReading = Duration(minutes: 15);

  /// Day (yyyy-mm-dd) that [_freeReadToday] counts.
  String _freeReadDay = '';
  Duration _freeReadToday = Duration.zero;

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
    await services.billing.init(state._onBilling);
    unawaited(state.refreshPurchases());
    unawaited(state.loadPrices());
    await state.refreshPermissions();
    unawaited(state.loadVoices());
    await state._applyFreeAlarmLimit();
    await state._syncAlarms();
    final launch = await services.alarms.takeLaunch();
    logEvent('App started${launch == null ? '' : ' by alarm '
            '${launch.payload.alarmId} (${launch.action.name})'}. '
        '${state.alarms.where((a) => a.enabled).length} alarm(s) on, '
        'Premium: ${state.isPremium}');
    if (launch != null) state.openAlarm(launch);
    return state;
  }

  @override
  void dispose() {
    _disposed = true;
    reader.dispose();
    pendingAlarm.dispose();
    billingNotice.dispose();
    super.dispose();
  }

  // ---- Persistence ------------------------------------------------------

  Map<String, Object?> toJson() => {
        'version': 1,
        'onboardingDone': onboardingDone,
        'isPremium': purchased,
        'freeReadDay': _freeReadDay,
        'freeReadSeconds': _freeReadToday.inSeconds,
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
    purchased = json['isPremium'] as bool? ?? false;
    _freeReadDay = json['freeReadDay'] as String? ?? '';
    _freeReadToday = Duration(seconds: json['freeReadSeconds'] as int? ?? 0);
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

  /// Re-reads saved state, so this copy of the app never acts on (and then
  /// saves over) data another copy has changed since: on Android an alarm
  /// can start a second instance. Every change is saved as it happens, so
  /// what's on disk is never older than what's in memory. Skipped while a
  /// book is being read, as this instance is then the one saving.
  Future<void> reloadFromStorage() async {
    if (reader.active || _disposed) return;
    // Let a save queued by a change just made start first; loading then
    // waits for it, so it can't bring back older data.
    await Future<void>.microtask(() {});
    final json = await services.storage.loadState();
    if (json == null || reader.active || _disposed) return;
    _restore(json);
    _texts.removeWhere((id, _) => _findBook(id) == null);
    permissions['autoStart'] = autoStartConfirmed;
    notifyListeners();
    await _applyFreeAlarmLimit();
  }

  // ---- Derived ----------------------------------------------------------

  bool get canAddBook => isPremium || books.length < freeBookLimit;
  bool get canAddAlarm => isPremium || alarms.length < freeAlarmLimit;

  /// 60-minute sessions are Premium only.
  bool get has60MinAccess => isPremium;

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

  /// Sets whether Premium was bought (from the store's answer).
  void setPremium(bool value) {
    if (purchased == value) return;
    purchased = value;
    _changed();
    if (!value) unawaited(_applyFreeAlarmLimit());
  }

  Future<void> loadPrices() async {
    try {
      final prices = await services.billing.prices();
      if (_disposed || prices.isEmpty) return;
      storePrices = prices;
      notifyListeners();
    } catch (e) {
      debugPrint('Loading prices failed: $e');
    }
  }

  /// Asks Google Play which subscriptions are active. Returns null if it
  /// couldn't be reached (Premium then stays as last known).
  Future<bool?> refreshPurchases() async {
    final owned = await services.billing.ownedPremium();
    if (owned == null || _disposed) return null;
    setPremium(owned.isNotEmpty);
    return owned.isNotEmpty;
  }

  /// Opens Google Play's purchase sheet for a Premium plan.
  Future<BuyResult> buyPremium(String productId) =>
      services.billing.buy(productId);

  void _onBilling(BillingEvent event) {
    if (_disposed) return;
    logEvent('Purchase ${event.kind.name} ${event.productId ?? ''} '
        '${event.message ?? ''}');
    switch (event.kind) {
      case BillingEventKind.purchased:
        if (!purchased) billingNotice.value = 'Welcome to Premium!';
        setPremium(true);
      case BillingEventKind.pending:
        billingNotice.value = 'Payment pending. Premium starts as soon as '
            'Google Play confirms it.';
      case BillingEventKind.failed:
        billingNotice.value = 'The purchase didn\'t go through. '
            '${event.message ?? 'Please try again.'}';
      case BillingEventKind.cancelled:
        break;
    }
  }

  /// Alarms that may ring on the free tier: without Premium (e.g. alarms
  /// set up by an earlier version, which allowed 3), alarms beyond
  /// [freeAlarmLimit] are switched off. The earliest-added stay on. Returns the alarms switched off.
  List<ReadingAlarm> _enforceFreeAlarms() {
    if (isPremium) return const [];
    final off = <ReadingAlarm>[];
    var on = 0;
    for (var i = 0; i < alarms.length; i++) {
      if (!alarms[i].enabled) continue;
      if (++on > freeAlarmLimit) {
        alarms[i] = alarms[i].copyWith(enabled: false);
        off.add(alarms[i]);
      }
    }
    if (off.isNotEmpty) _changed();
    return off;
  }

  /// [_enforceFreeAlarms], cancelling the alarms it switches off.
  Future<void> _applyFreeAlarmLimit() async {
    for (final alarm in _enforceFreeAlarms()) {
      await _schedule(alarm);
    }
  }

  Future<void> refreshPermissions() async {
    try {
      permissions.addAll(await services.permissions.status());
    } catch (e) {
      debugPrint('Permission check failed: $e');
    }
    permissions['autoStart'] = autoStartConfirmed;
    final missing = [
      for (final e in permissions.entries)
        if (!e.value) e.key,
    ];
    if (missing.join() != _lastMissing) {
      _lastMissing = missing.join();
      logEvent('Permissions: ${missing.isEmpty ? 'all OK' : 'missing '
          '${missing.join(', ')}'}');
    }
    if (!_disposed) notifyListeners();
  }

  String? _lastMissing;

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

  /// Saves an alarm from the editor, enforcing the free alarm limit, one
  /// alarm per moment, and one-off alarms being in the future.
  Future<AlarmSaveResult> saveAlarm(ReadingAlarm alarm) async {
    final isNew = !alarms.any((a) => a.id == alarm.id);
    if (isNew && !canAddAlarm) return const AlarmSaveResult.limitReached();
    final once = alarm.onceAt;
    if (once != null && !once.isAfter(DateTime.now())) {
      return const AlarmSaveResult.inPast();
    }
    final clash = clashFor(alarm);
    if (clash != null) return AlarmSaveResult.clash(clash);
    await upsertAlarm(alarm);
    return const AlarmSaveResult.saved();
  }

  /// Another alarm that would ring at the same moment as [alarm].
  ReadingAlarm? clashFor(ReadingAlarm alarm) =>
      alarms.where(alarm.clashesWith).firstOrNull;

  /// Switches an alarm on or off. On the free tier only [freeAlarmLimit]
  /// alarms can be on; switching on another returns limitReached.
  Future<AlarmSaveStatus> toggleAlarm(ReadingAlarm alarm, bool enabled) async {
    if (enabled &&
        !isPremium &&
        alarms.where((a) => a.enabled && a.id != alarm.id).length >=
            freeAlarmLimit) {
      return AlarmSaveStatus.limitReached;
    }
    var updated = alarm.copyWith(enabled: enabled);
    // A dated one-off alarm switched back on after its day rings next time.
    final once = updated.onceAt;
    if (enabled && once != null && !once.isAfter(DateTime.now())) {
      final next =
          updated.copyWith(date: () => null).nextOccurrence(DateTime.now());
      updated = updated.copyWith(date: () => next);
    }
    await upsertAlarm(updated);
    return AlarmSaveStatus.saved;
  }

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
      logEvent('ERROR scheduling alarm ${alarm.id}: $e');
      debugPrint('Scheduling alarm failed: $e');
    }
  }

  /// One-off alarms that already rang are switched off, and every enabled
  /// alarm is scheduled again, whether or not the plugin lists it as
  /// pending: its list is its own record, which survives the system
  /// dropping the alarms (some phones do when they stop an app in the
  /// background). Run at start-up and whenever the app comes back.
  Future<void> _syncAlarms() async {
    final pending = await services.alarms.pendingAlarmIds();
    final now = clock.now();
    for (var i = 0; i < alarms.length; i++) {
      final a = alarms[i];
      if (!a.enabled || a.repeatDays.isNotEmpty) continue;
      final once = a.onceAt;
      final rang = once != null ? !once.isAfter(now) : !pending.contains(a.id);
      if (rang) {
        alarms[i] = a.copyWith(enabled: false);
        logEvent('One-off alarm ${a.id} has passed: switched off');
      }
    }
    for (final alarm in alarms.where((a) => a.enabled)) {
      // Before setting it again: did Android still hold it? If not, the
      // phone removed it while the app was away.
      final held = await services.alarms.heldByAndroid(alarm);
      if (held != null) {
        final missing = [
          for (final e in held.entries)
            if (!e.value) e.key,
        ];
        logEvent('Alarm ${alarm.id} before resetting: Android held '
            '${held.length - missing.length} of ${held.length} rings'
            '${missing.isEmpty ? '' : ' (missing ${missing.join(', ')})'}');
      }
      await _schedule(alarm);
      logEvent('Alarm ${alarm.id} set: ${formatTime(alarm.time)} '
          '${alarm.scheduleLabel}, next ${alarm.nextOccurrence(now)}');
    }
    _changed();
  }

  /// Puts back any alarms the system dropped while the app was away.
  Future<void> resyncAlarms() async {
    if (_disposed) return;
    await _syncAlarms();
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
    logEvent('Test alarm set for 1 minute from now');
    return true;
  }

  /// Handles a ringing alarm the user opened or acted on.
  void openAlarm(AlarmLaunch launch) {
    final p = launch.payload;
    logEvent('Alarm ${p.alarmId} opened (${launch.action.name})');
    final book = _findBook(p.bookId);
    if (book == null) {
      logEvent('Alarm ${p.alarmId}: its book is no longer in the library');
      return;
    }
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

  /// Stops a ringing alarm's sound and notification, keeping its future
  /// rings.
  Future<void> silenceAlarm(ReadingAlarm alarm) async {
    logEvent('Alarm ${alarm.id} silenced');
    try {
      await services.alarms.dismiss(alarm.id);
    } catch (e) {
      logEvent('ERROR silencing alarm ${alarm.id}: $e');
      debugPrint('Dismissing alarm failed: $e');
    }
    // Make sure a weekly alarm still rings next time.
    final saved = alarms.where((a) => a.id == alarm.id).firstOrNull;
    if (saved != null && saved.enabled && saved.repeatDays.isNotEmpty) {
      await _schedule(saved);
    }
  }

  Future<void> snoozeAlarm(ReadingAlarm alarm) async {
    logEvent('Alarm ${alarm.id} snoozed');
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
    final speech = services.speech
      ..onDone = null
      ..onError = null;
    await speech.configure(
        speed: speed, pitch: effectivePitch, voice: effectiveVoice);
    await speech.play(
        ['Good morning. This is how ReadAlarm will read your book to you.']);
  }

  // ---- Free daily reading allowance ------------------------------------

  static String _dayKey(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}';

  /// Free reading left today; null for Premium (unlimited).
  Duration? get freeReadingLeft {
    if (isPremium) return null;
    final used =
        _freeReadDay == _dayKey(clock.now()) ? _freeReadToday : Duration.zero;
    final left = freeDailyReading - used;
    return left.isNegative ? Duration.zero : left;
  }

  bool get dailyLimitReached => freeReadingLeft == Duration.zero;

  /// Time until the free allowance resets, at local midnight.
  Duration get untilFreeReset {
    final now = clock.now();
    return DateTime(now.year, now.month, now.day + 1).difference(now);
  }

  /// Counts [read] against today's free allowance (no-op for Premium).
  /// Saved with the next change, e.g. the reading position.
  void countFreeReading(Duration read) {
    if (isPremium || read <= Duration.zero) return;
    final today = _dayKey(clock.now());
    if (_freeReadDay != today) {
      _freeReadDay = today;
      _freeReadToday = Duration.zero;
    }
    _freeReadToday += read;
  }
}

/// Outcome of [AppState.saveAlarm].
class AlarmSaveResult {
  const AlarmSaveResult.saved()
      : status = AlarmSaveStatus.saved,
        clash = null;
  const AlarmSaveResult.limitReached()
      : status = AlarmSaveStatus.limitReached,
        clash = null;
  const AlarmSaveResult.inPast()
      : status = AlarmSaveStatus.inPast,
        clash = null;
  const AlarmSaveResult.clash(ReadingAlarm this.clash)
      : status = AlarmSaveStatus.clash;

  final AlarmSaveStatus status;

  /// The alarm already set for that moment, when [status] is clash.
  final ReadingAlarm? clash;
}

enum AlarmSaveStatus { saved, limitReached, inPast, clash }

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

/// How [ReadingController.start] went.
enum ReadingStart { started, missingText, dailyLimit }

/// Reads a book aloud (TTS-2..5), tracks the session clock and saves the
/// reading position as it goes (PRG-1).
///
/// Sentences are queued with the speech engine [queueAhead] at a time, so
/// reading carries on even while Android pauses the app with the screen
/// locked; time is measured by the clock, not by counting timer ticks, so
/// such pauses still count.
class ReadingController extends ChangeNotifier {
  ReadingController(this._state);

  /// Sentences handed to the speech engine ahead of the current one.
  static const queueAhead = 40;

  final AppState _state;

  String? bookId;
  BookText? text;
  int index = 0;
  bool playing = false;

  /// Session length for alarm sessions; null = open-ended "Read now".
  int? durationMin;
  CompletedSession? lastCompleted;

  DateTime? _startedAt;
  double _progressBefore = 0;
  Timer? _ticker;
  bool _disposed = false;

  /// Reading time before the current stretch of playing.
  Duration _banked = Duration.zero;
  DateTime? _playingSince;

  /// When reading time was last counted against the free allowance.
  DateTime? _countedUntil;

  /// First sentence not yet handed to the speech engine.
  int _queuedUntil = 0;

  /// Bumped whenever the queue is replaced, so callbacks from an older
  /// queue are ignored.
  int _generation = 0;

  bool get active => bookId != null;

  Duration get elapsed {
    final since = _playingSince;
    return since == null ? _banked : _banked + clock.now().difference(since);
  }

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
  /// finished first.
  ///
  /// The position always comes from the latest saved progress, never from
  /// [book]: an alarm can carry an older copy of the book (for example
  /// when it reaches an instance of the app that was in the background).
  Future<ReadingStart> start(BookInfo book, {int? durationMin}) async {
    if (_state.dailyLimitReached) {
      logEvent('Reading refused: today\'s free minutes are used up');
      return ReadingStart.dailyLimit;
    }
    if (!active) {
      await _state.reloadFromStorage();
      book = _state.findBook(book.id) ?? book;
    }
    if (bookId == book.id) {
      this.durationMin = durationMin ?? this.durationMin;
      if (!playing) resume();
      return ReadingStart.started;
    }
    if (active) await finish('stop');
    final loaded = await _state.textFor(book.id);
    if (loaded == null || loaded.sentences.isEmpty) {
      logEvent('Reading refused: no text for "${book.title}"');
      return ReadingStart.missingText;
    }

    bookId = book.id;
    text = loaded;
    index = book.isFinished ? 0 : book.position;
    this.durationMin = durationMin;
    _banked = Duration.zero;
    _playingSince = null;
    lastCompleted = null;
    _startedAt = clock.now();
    _progressBefore = book.isFinished ? 0 : book.progress;
    _beatMinute = 0;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    resume();
    logEvent('Reading started: "${book.title}" at sentence $index of '
        '${loaded.sentences.length}, ${durationMin ?? 'no'} min limit');
    return ReadingStart.started;
  }

  /// Last minute logged by [_tick]'s heartbeat.
  int _beatMinute = 0;

  void _tick() {
    if (!active || _ending) return;
    _countReading();
    if (_state.dailyLimitReached) {
      _endOnTimer('limit');
      return;
    }
    final limit = durationMin;
    if (limit != null && elapsed >= Duration(minutes: limit)) {
      _endOnTimer('duration');
      return;
    }
    if (clock.now().second == 0) _updateNotification();
    // A heartbeat in the diagnostics log: if these stop while reading,
    // the phone paused the app.
    final minute = elapsed.inMinutes;
    if (minute > _beatMinute) {
      _beatMinute = minute;
      logEvent('Still reading: sentence $index, $minute min, '
          '${playing ? 'playing' : 'paused'}');
    }
    _notify();
  }

  /// Counts time read since the last call against the free allowance.
  void _countReading() {
    final now = clock.now();
    final from = _countedUntil;
    _countedUntil = playing ? now : null;
    if (playing && from != null) _state.countFreeReading(now.difference(from));
  }

  void resume() {
    if (!active || playing) return;
    playing = true;
    _playingSince = _countedUntil = clock.now();
    _updateNotification();
    _notify();
    _speakFromHere();
  }

  Future<void> pause() async {
    if (!active || !playing) return;
    _countReading();
    _banked = elapsed;
    _playingSince = null;
    playing = false;
    _countedUntil = null;
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
    if (playing) await _speakFromHere();
  }

  /// Re-applies voice, speed and pitch, restarting the current sentence.
  Future<void> applyVoiceSettings() async {
    if (active && playing) await _speakFromHere();
  }

  /// (Re)starts the speech queue at the current sentence.
  Future<void> _speakFromHere() async {
    final generation = ++_generation;
    final speech = _state.services.speech
      ..onDone = (() => _onSentenceDone(generation))
      ..onError = (() => _onSpeechError(generation));
    await speech.configure(
      speed: _state.speed,
      pitch: _state.effectivePitch,
      voice: _state.effectiveVoice,
    );
    if (generation != _generation || !playing) return;
    _queuedUntil = index;
    await speech.play(_nextBatch());
  }

  List<String> _nextBatch() {
    final sentences = text!.sentences;
    final end = (index + queueAhead).clamp(0, sentences.length);
    if (_queuedUntil >= end) return const [];
    final batch = sentences.sublist(_queuedUntil, end);
    _queuedUntil = end;
    return batch;
  }

  void _onSentenceDone(int generation) {
    if (generation != _generation || !active || !playing) return;
    index++;
    _savePosition();
    if (index >= text!.sentences.length) {
      finish('finished');
      return;
    }
    // Keep the engine's queue topped up.
    if (_queuedUntil - index < queueAhead ~/ 2) {
      final batch = _nextBatch();
      if (batch.isNotEmpty) _state.services.speech.enqueue(batch);
    }
    _notify();
  }

  void _onSpeechError(int generation) {
    logEvent('ERROR text-to-speech reported an error at sentence $index');
    if (generation == _generation) pause();
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

  bool _ending = false;

  /// Ends a session whose time is up. If Android paused the app with the
  /// screen locked, the speech engine kept reading and its "sentence done"
  /// events are queued up; take them in first so the saved position
  /// matches what was actually read.
  Future<void> _endOnTimer(String reason) async {
    _ending = true;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _ending = false;
    if (active) await finish(reason);
  }

  /// Handles a lock-screen notification button.
  void onCommand(String command) {
    if (command == playbackToggle) toggle();
    if (command == playbackStop) finish('stop');
  }

  /// Ends the session, saves progress and records it in the stats.
  /// [reason]: duration | stop | finished | limit.
  Future<CompletedSession?> finish(String reason) async {
    final id = bookId;
    if (id == null) return null;
    _countReading();
    _banked = elapsed;
    _playingSince = null;
    _countedUntil = null;
    _generation++;
    _ticker?.cancel();
    _ticker = null;
    playing = false;
    _savePosition();
    final speech = _state.services.speech
      ..onDone = null
      ..onError = null;
    await speech.stop();
    await _state.services.playback.hide();

    final read = _banked;
    final minutes = math.max(1, (read.inSeconds / 60).ceil());
    logEvent('Reading ended ($reason) after ${read.inSeconds}s at sentence '
        '$index');
    final book = _state.findBook(id);
    if (book != null && read > Duration.zero) {
      _state.addSession(ReadingSession(
        bookTitle: book.title,
        startedAt: _startedAt ?? clock.now(),
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
