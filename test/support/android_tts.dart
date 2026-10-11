import 'dart:async';
import 'dart:collection';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for flutter_tts's Android side on its method channel, so the
/// real [TtsSpeechEngine] can be tested. Mirrors the plugin: utterances
/// queue up (QUEUE_ADD), each reports onStart then onDone, and stop()
/// reports onStop (a cancel) for the current utterance and for every
/// queued one it flushes. Events arrive asynchronously, as on a device.
class FakeAndroidTts {
  FakeAndroidTts(this.binding) {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, _handle);
  }

  static const _channel = MethodChannel('flutter_tts');
  final TestWidgetsFlutterBinding binding;

  final _queue = Queue<String>();
  String? _current;
  Timer? _timer;

  /// Every utterance started, in order.
  final spoken = <String>[];

  void dispose() {
    _timer?.cancel();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null);
  }

  Future<Object?> _handle(MethodCall call) async {
    switch (call.method) {
      case 'speak':
        final args = call.arguments;
        _queue.add(args is Map ? args['text'] as String : args as String);
        if (_current == null) _startNext();
        return 1;
      case 'stop':
        _timer?.cancel();
        final flushed = (_current == null ? 0 : 1) + _queue.length;
        _current = null;
        _queue.clear();
        for (var i = 0; i < flushed; i++) {
          _send('speak.onCancel');
        }
        return 1;
      case 'getVoices':
        return <Object>[];
      default:
        return 1;
    }
  }

  void _startNext() {
    if (_queue.isEmpty) return;
    final text = _current = _queue.removeFirst();
    spoken.add(text);
    _send('speak.onStart');
    final words = text.split(' ').length;
    _timer = Timer(Duration(milliseconds: 100 * words), () {
      _current = null;
      _send('speak.onComplete');
      _startNext();
    });
  }

  /// Delivers a platform -> Dart call, after the current call returns.
  void _send(String method) {
    scheduleMicrotask(() {
      binding.defaultBinaryMessenger.handlePlatformMessage(
        _channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall(method, true)),
        (_) {},
      );
    });
  }
}
