import 'dart:async';
import 'dart:typed_data';

import 'package:readalarm/models/reading_alarm.dart';
import 'package:readalarm/services/alarm_scheduler.dart';
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

/// "Speaks" each utterance for 100 ms per word.
class FakeSpeech implements SpeechEngine {
  final spoken = <String>[];
  Completer<bool>? _current;
  Timer? _timer;
  double speed = 1, pitch = 1;
  VoiceOption? voice;

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
  Future<bool> speak(String text) {
    _end(false);
    spoken.add(text);
    final done = _current = Completer<bool>();
    final words = text.split(' ').length;
    _timer = Timer(Duration(milliseconds: 100 * words), () => _end(true));
    return done.future;
  }

  void _end(bool completed) {
    _timer?.cancel();
    final current = _current;
    _current = null;
    if (current != null && !current.isCompleted) current.complete(completed);
  }

  @override
  Future<void> stop() async => _end(false);
}

class FakeAlarms implements AlarmScheduler {
  final scheduled = <String, ReadingAlarm>{};
  final once = <(AlarmPayload, DateTime)>[];
  final dismissed = <String>[];
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
  Future<Set<String>> pendingAlarmIds() async => scheduled.keys.toSet();
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

class FakeServices {
  final storage = MemoryAppStorage();
  final speech = FakeSpeech();
  final alarms = FakeAlarms();
  final permissions = FakePermissions();
  final playback = FakePlayback();
  final importer = FakeImporter();

  AppServices get services => AppServices(
        storage: storage,
        speech: speech,
        alarms: alarms,
        permissions: permissions,
        playback: playback,
        importer: importer,
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
}) async {
  final fakes = FakeServices();
  if (!emptyLibrary) {
    final seed = AppState(
      services: fakes.services,
      books: List.of(SampleData.books),
      alarms: SampleData.alarms(),
      sessions: SampleData.sessions(),
    )
      ..onboardingDone = onboardingDone
      ..isPremium = premium;
    for (final book in seed.books) {
      await fakes.storage.saveBookText(book.id, demoText());
    }
    await fakes.storage.saveState(seed.toJson());
    seed.dispose();
  } else {
    final seed = AppState(services: fakes.services)
      ..onboardingDone = onboardingDone
      ..isPremium = premium;
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
