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

/// Reads text aloud, one utterance at a time.
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

  /// Completes with true once [text] has been spoken, or false if it was
  /// interrupted by [stop] or failed.
  Future<bool> speak(String text);

  Future<void> stop();
}

class TtsSpeechEngine implements SpeechEngine {
  final _tts = FlutterTts();
  Completer<bool>? _utterance;

  /// Utterances we interrupted whose cancel event hasn't arrived yet.
  /// Android reports a cancel after the fact; without this count it would
  /// be taken for the next utterance's and stop it.
  int _pendingCancels = 0;

  @override
  Future<void> init() async {
    await _tts.awaitSpeakCompletion(false);
    if (defaultTargetPlatform == TargetPlatform.android) {
      await _tts.setQueueMode(0); // Flush: a new utterance replaces the old.
    }
    _tts.setCompletionHandler(() => _finish(true));
    _tts.setCancelHandler(() {
      if (_pendingCancels > 0) {
        _pendingCancels--;
      } else {
        _finish(false);
      }
    });
    _tts.setErrorHandler((_) => _finish(false));
  }

  void _finish(bool completed) {
    final utterance = _utterance;
    _utterance = null;
    if (utterance != null && !utterance.isCompleted) {
      utterance.complete(completed);
    }
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
  Future<bool> speak(String text) async {
    _interrupt();
    final utterance = _utterance = Completer<bool>();
    final result = await _tts.speak(text);
    if (result != 1) _finish(false);
    return utterance.future;
  }

  @override
  Future<void> stop() async {
    _interrupt();
    await _tts.stop();
  }

  /// Ends the current utterance ourselves, expecting its cancel event.
  void _interrupt() {
    if (_utterance == null) return;
    if (defaultTargetPlatform == TargetPlatform.android) _pendingCancels++;
    _finish(false);
  }
}
