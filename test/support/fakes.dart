import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:readalarm/models/reading_alarm.dart';
import 'package:readalarm/services/alarm_scheduler.dart';
import 'package:readalarm/services/billing_service.dart';
import 'package:readalarm/services/book_extractor.dart';
import 'package:readalarm/services/book_importer.dart';
import 'package:readalarm/services/book_text.dart';
import 'package:readalarm/services/permission_service.dart';
import 'package:readalarm/services/playback_service.dart';
import 'package:readalarm/services/services.dart';
import 'package:readalarm/services/speech.dart';
import 'package:readalarm/services/storage.dart';
import 'package:readalarm/state/app_state.dart';

import 'sample_files.dart';

/// "Speaks" each queued utterance for 100 ms per word.
class FakeSpeech implements SpeechEngine {
  /// Every utterance started, in order.
  final spoken = <String>[];
  final _queue = <String>[];
  Timer? _timer;
  void Function()? _onDone;
  double speed = 1, pitch = 1;
  VoiceOption? voice;

  /// Utterances waiting after the current one.
  int get queued => _queue.length;

  static const voiceList = [
    VoiceOption(name: 'en-gb-x-rjs-local', locale: 'en-GB'),
    VoiceOption(name: 'en-ng-x-tfn-local', locale: 'en-NG'),
    VoiceOption(name: 'en-us-x-iob-local', locale: 'en-US'),
  ];

  @override
  Future<void> init() async {}

  @override
  Future<List<VoiceOption>> voices() async => voiceList;

  @override
  Future<void> configure({
    required double speed,
    required double pitch,
    VoiceOption? voice,
  }) async {
    this.speed = speed;
    this.pitch = pitch;
    this.voice = voice;
  }

  @override
  set onDone(void Function()? callback) => _onDone = callback;

  @override
  set onError(void Function()? callback) {}

  @override
  Future<void> play(List<String> texts) async {
    await stop();
    await enqueue(texts);
  }

  @override
  Future<void> enqueue(List<String> texts) async {
    _queue.addAll(texts);
    if (_timer == null) _next();
  }

  void _next() {
    if (_queue.isEmpty) return;
    final text = _queue.removeAt(0);
    spoken.add(text);
    final words = text.split(' ').length;
    _timer = Timer(Duration(milliseconds: 100 * words), () {
      _timer = null;
      final done = _onDone;
      _next();
      done?.call();
    });
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _queue.clear();
  }
}

class FakeAlarms implements AlarmScheduler {
  final scheduled = <String, ReadingAlarm>{};
  final once = <(AlarmPayload, DateTime)>[];
  final dismissed = <String>[];

  /// Alarms the plugin still lists after the system dropped them (as when
  /// a phone stops the app in the background).
  final stalePending = <String>{};
  AlarmLaunch? launch;
  void Function(AlarmLaunch)? onLaunch;

  @override
  Future<void> init(void Function(AlarmLaunch launch) onLaunch) async =>
      this.onLaunch = onLaunch;

  @override
  Future<AlarmLaunch?> takeLaunch() async => launch;

  @override
  Future<void> schedule(ReadingAlarm alarm) async {
    if (alarm.enabled) {
      scheduled[alarm.id] = alarm;
    } else {
      scheduled.remove(alarm.id);
    }
  }

  @override
  Future<void> cancel(String alarmId) async => scheduled.remove(alarmId);

  @override
  Future<void> scheduleOnce(AlarmPayload payload, DateTime at) async =>
      once.add((payload, at));

  @override
  Future<void> dismiss(String alarmId) async => dismissed.add(alarmId);

  @override
  Future<Set<String>> pendingAlarmIds() async =>
      {...scheduled.keys, ...stalePending};

  /// The system drops every alarm; the plugin's list still has them.
  void dropAll() {
    stalePending.addAll(scheduled.keys);
    scheduled.clear();
  }
}

class FakePermissions implements PermissionService {
  FakePermissions({bool granted = false})
      : granted = {
          'notifications': granted,
          'exactAlarm': granted,
          'battery': granted,
        };

  final Map<String, bool> granted;
  final requested = <String>[];

  @override
  Future<Map<String, bool>> status() async => Map.of(granted);

  @override
  Future<void> request(String key) async {
    requested.add(key);
    granted[key] = true;
  }

  @override
  Future<void> openAppSettings() async {}
}

class FakePlayback implements PlaybackService {
  void Function(String)? onCommand;

  @override
  final ValueNotifier<String?> problem = ValueNotifier(null);
  bool visible = false;
  String text = '';

  @override
  Future<void> init(void Function(String command) onCommand) async =>
      this.onCommand = onCommand;

  @override
  Future<void> show({
    required String title,
    required String text,
    required bool playing,
  }) async {
    visible = true;
    this.text = text;
  }

  @override
  Future<void> hide() async => visible = false;
}

/// "Picks" the sample EPUB (or [file]) and extracts it for real.
class FakeImporter implements BookImporter {
  PickedBook? file;
  bool slow = false;

  @override
  Future<PickedBook?> pick(String format) async =>
      file ??
      PickedBook(
        name: 'quiet-morning.epub',
        read: () async => buildEpub(),
      );

  @override
  Future<(String, ExtractedBook)> extract(
    PickedBook file, {
    void Function(double progress)? onProgress,
  }) async {
    final bytes = await file.read();
    final format = detectFormat(bytes, file.name);
    if (slow) {
      // Show the progress bar moving, like a large book would.
      for (var p = 0.25; p < 1; p += 0.25) {
        onProgress?.call(p);
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }
    return (format, extractBook(bytes, format, onProgress: onProgress));
  }
}

/// Google Play, off by default (as on a sideloaded test build). With
/// [available] on, buying succeeds at once unless [nextPurchase] says
/// otherwise.
class FakeBilling implements BillingService {
  bool available = false;
  final owned = <String>{};
  BillingEventKind nextPurchase = BillingEventKind.purchased;
  final bought = <String>[];
  void Function(BillingEvent event)? _onEvent;

  @override
  Future<void> init(void Function(BillingEvent event) onEvent) async =>
      _onEvent = onEvent;

  @override
  Future<Map<String, String>> prices() async => available
      ? {
          PremiumPlans.monthly: '₦1,500.00',
          PremiumPlans.yearly: '₦12,000.00',
        }
      : const {};

  @override
  Future<BuyResult> buy(String productId) async {
    if (!available) return BuyResult.unavailable;
    bought.add(productId);
    final kind = nextPurchase;
    if (kind == BillingEventKind.purchased) owned.add(productId);
    // The store reports back after the purchase sheet closes.
    scheduleMicrotask(() => _onEvent
        ?.call(BillingEvent(kind, productId: productId, message: 'Declined')));
    return BuyResult.started;
  }

  @override
  Future<Set<String>?> ownedPremium() async => available ? Set.of(owned) : null;
}

class FakeServices {
  FakeServices({this.speechOverride});

  /// Used instead of [speech], e.g. the real engine on a fake platform.
  final SpeechEngine? speechOverride;

  final storage = MemoryAppStorage();
  final speech = FakeSpeech();
  final alarms = FakeAlarms();
  final permissions = FakePermissions();
  final playback = FakePlayback();
  final importer = FakeImporter();
  final billing = FakeBilling();

  AppServices get services => AppServices(
        storage: storage,
        speech: speechOverride ?? speech,
        alarms: alarms,
        permissions: permissions,
        playback: playback,
        importer: importer,
        billing: billing,
        deviceBrand: 'tecno',
      );
}

const _demoLines = [
  'The morning light came in low across the kitchen table.',
  'She had promised herself one chapter before the day began.',
  'The kettle clicked off, and the house went quiet again.',
  'Somewhere outside, a bus pulled away from the stop.',
  'She turned the page and kept listening.',
];

/// Text for a demo book: 1000 sentences in chapters of 100.
BookText demoText() => BookText(
      sentences: [for (var i = 0; i < 1000; i++) _demoLines[i % 5]],
      chapters: [
        for (var c = 0; c < 10; c++) ChapterMark('Chapter ${c + 1}', c * 100),
      ],
    );

/// A loaded [AppState] with the demo library, alarms and history.
Future<(AppState, FakeServices)> demoState({
  bool onboardingDone = true,
  bool premium = false,
  bool emptyLibrary = false,
  SpeechEngine? speech,
}) async {
  final fakes = FakeServices(speechOverride: speech);
  if (!emptyLibrary) {
    final seed = AppState(
      services: fakes.services,
      books: List.of(SampleData.books),
      alarms: SampleData.alarms(),
      sessions: SampleData.sessions(),
    )
      ..onboardingDone = onboardingDone
      ..purchased = premium;
    for (final book in seed.books) {
      await fakes.storage.saveBookText(book.id, demoText());
    }
    await fakes.storage.saveState(seed.toJson());
    seed.dispose();
  } else {
    final seed = AppState(services: fakes.services)
      ..onboardingDone = onboardingDone
      ..purchased = premium;
    await fakes.storage.saveState(seed.toJson());
    seed.dispose();
  }
  final state = await AppState.load(fakes.services);
  return (state, fakes);
}

/// A picked file with fixed contents.
PickedBook pickedFile(String name, Uint8List bytes) =>
    PickedBook(name: name, size: bytes.length, read: () async => bytes);

/// A one-page PDF with no text, like a scan.
Uint8List buildPdfBytesWithoutText() => buildPdf(pages: ['']);
