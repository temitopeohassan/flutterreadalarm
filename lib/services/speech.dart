import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// A text-to-speech voice installed on the device.
class VoiceOption {
  const VoiceOption({required this.name, required this.locale});

  final String name;
  final String locale;

  String get label {
    final parts = locale.replaceAll('_', '-').split('-');
    final language = _languages[parts.first.toLowerCase()] ?? parts.first;
    final region = parts.length > 1 ? ' (${parts[1].toUpperCase()})' : '';
    // Android names look like "en-us-x-iob-local"; keep the distinctive bit.
    final match = RegExp(r'-x-([a-z0-9]+)').firstMatch(name);
    final variant = match?.group(1) ?? name;
    return '$language$region · $variant';
  }

  Map<String, String> toMap() => {'name': name, 'locale': locale};

  static VoiceOption? fromMap(Object? map) {
    if (map is! Map) return null;
    final name = map['name'], locale = map['locale'];
    if (name is! String || locale is! String) return null;
    return VoiceOption(name: name, locale: locale);
  }

  @override
  bool operator ==(Object other) =>
      other is VoiceOption && other.name == name && other.locale == locale;

  @override
  int get hashCode => Object.hash(name, locale);

  static const _languages = {
    'en': 'English',
    'fr': 'French',
    'de': 'German',
    'es': 'Spanish',
    'pt': 'Portuguese',
    'it': 'Italian',
    'nl': 'Dutch',
    'yo': 'Yoruba',
    'ha': 'Hausa',
    'ig': 'Igbo',
    'sw': 'Swahili',
    'ar': 'Arabic',
    'hi': 'Hindi',
    'zh': 'Chinese',
    'ja': 'Japanese',
    'ko': 'Korean',
    'ru': 'Russian',
    'tr': 'Turkish',
    'pl': 'Polish',
    'sv': 'Swedish',
  };
}

/// Reads text aloud from a queue of utterances.
///
/// The book is handed to the engine several minutes ahead, so it keeps
/// reading even when Android pauses the app with the screen locked; the app
/// tops the queue up whenever it runs.
abstract class SpeechEngine {
  Future<void> init();

  /// Voices worth offering: the device language's and English ones.
  Future<List<VoiceOption>> voices();

  /// [speed] 1.0 = normal. [voice] null = the engine's default voice.
  Future<void> configure({
    required double speed,
    required double pitch,
    VoiceOption? voice,
  });

  /// Called once for each queued text that finishes, in order.
  set onDone(void Function()? callback);

  /// Called when the engine fails; the queue is then empty.
  set onError(void Function()? callback);

  /// Replaces whatever is playing or queued with [texts].
  Future<void> play(List<String> texts);

  /// Adds [texts] after whatever is queued.
  Future<void> enqueue(List<String> texts);

  /// Stops speaking and empties the queue.
  Future<void> stop();
}

class TtsSpeechEngine implements SpeechEngine {
  final _tts = FlutterTts();

  /// Texts handed to the engine and not finished yet.
  int _queued = 0;

  /// Whether the current queue has started. Until it has, a completion
  /// event can only belong to an utterance from before the last [stop],
  /// delivered late, and is ignored.
  bool _started = false;

  void Function()? _onDone;
  void Function()? _onError;

  @override
  set onDone(void Function()? callback) => _onDone = callback;

  @override
  set onError(void Function()? callback) => _onError = callback;

  @override
  Future<void> init() async {
    await _tts.awaitSpeakCompletion(false);
    if (defaultTargetPlatform == TargetPlatform.android) {
      await _tts.setQueueMode(1); // Add: utterances play one after another.
    }
    _tts.setStartHandler(() => _started = true);
    _tts.setCompletionHandler(() {
      if (!_started || _queued == 0) return;
      _queued--;
      _onDone?.call();
    });
    // Cancels are always ours (stop()); our own state already reflects them.
    _tts.setCancelHandler(() {});
    _tts.setErrorHandler((_) {
      _queued = 0;
      _onError?.call();
    });
  }

  @override
  Future<List<VoiceOption>> voices() async {
    try {
      final raw = await _tts.getVoices as List? ?? const [];
      final all = {
        for (final v in raw)
          if (VoiceOption.fromMap(v) case final voice?) voice,
      }.toList();
      final device = PlatformDispatcher.instance.locale.languageCode;
      final wanted = all.where((v) {
        final lang = v.locale.split(RegExp('[-_]')).first.toLowerCase();
        return lang == 'en' || lang == device;
      }).toList();
      return (wanted.isEmpty ? all : wanted)
        ..sort((a, b) => a.label.compareTo(b.label));
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> configure({
    required double speed,
    required double pitch,
    VoiceOption? voice,
  }) async {
    // Engines treat 0.5 as normal speed.
    await _tts.setSpeechRate((0.5 * speed).clamp(0.1, 1.0));
    await _tts.setPitch(pitch.clamp(0.5, 2.0));
    if (voice != null) {
      await _tts.setVoice(voice.toMap());
    } else {
      await _tts.clearVoice();
    }
  }

  @override
  Future<void> play(List<String> texts) async {
    await stop();
    await enqueue(texts);
  }

  @override
  Future<void> enqueue(List<String> texts) async {
    for (final text in texts) {
      // focus: hold audio focus, as media playback does.
      final result = await _tts.speak(text, focus: true);
      if (result == 1) {
        _queued++;
      } else {
        _onError?.call();
        return;
      }
    }
  }

  @override
  Future<void> stop() async {
    _queued = 0;
    _started = false;
    await _tts.stop();
  }
}
