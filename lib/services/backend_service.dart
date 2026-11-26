import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:path_provider/path_provider.dart';

import '../models/reading_alarm.dart';
import 'alarm_scheduler.dart';
import 'event_log.dart';

/// ReadAlarm's server (server/ in this repository, at readalarm.net). It
/// keeps each phone's alarms and sends a push when one is due, a backup
/// for phones that hold back or drop alarms (see server/README.md).
///
/// Set at build time:
/// --dart-define=READALARM_API_URL=https://readalarm.net (the default)
/// --dart-define=READALARM_API_KEY=... (the server's api_key)
class BackendConfig {
  static const url = String.fromEnvironment('READALARM_API_URL',
      defaultValue: 'https://readalarm.net');
  static const apiKey = String.fromEnvironment('READALARM_API_KEY');
  static const appVersion =
      String.fromEnvironment('READALARM_VERSION', defaultValue: '0.1.1');
}

abstract class BackendService {
  /// Sends a new or changed alarm (also switched on or off).
  Future<void> saveAlarm(ReadingAlarm alarm);

  Future<void> deleteAlarm(String alarmId);

  /// Sends all alarms, replacing what the server has (at start-up and on
  /// return to the app, which also catches up on changes sent offline).
  Future<void> syncAlarms(List<ReadingAlarm> alarms);

  /// The phone's push token (Firebase Cloud Messaging), or null if none.
  Future<void> setPushToken(String? token);

  /// For problem reports.
  String get status;
}

/// No server (tests, screenshots).
class NoBackend implements BackendService {
  const NoBackend();

  @override
  Future<void> saveAlarm(ReadingAlarm alarm) async {}

  @override
  Future<void> deleteAlarm(String alarmId) async {}

  @override
  Future<void> syncAlarms(List<ReadingAlarm> alarms) async {}

  @override
  Future<void> setPushToken(String? token) async {}

  @override
  String get status => 'No server in this build';
}

/// What the server gets for [alarm]: its time and days, and the payload
/// the push carries back so the app can ring it like its own alarm.
@visibleForTesting
Map<String, Object?> alarmForServer(ReadingAlarm alarm, DateTime now) {
  final payload = AlarmPayload.forAlarm(alarm);
  final once = alarm.repeatDays.isEmpty ? alarm.nextOccurrence(now) : null;
  return {
    'id': alarm.id,
    'enabled': alarm.enabled,
    'hour': alarm.time.hour,
    'minute': alarm.time.minute,
    'days': alarm.repeatDays.toList()..sort(),
    'once_at': once?.millisecondsSinceEpoch,
    'title': payload.title,
    'body': payload.body,
    'payload': payload.encode(),
  };
}

/// The server over HTTPS. Each phone has a random id and secret, made on
/// first use and kept in the app's files: no account or name is sent.
class HttpBackend implements BackendService {
  HttpBackend._(this._file, this._identity);

  static Future<HttpBackend> open() async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/server_device.json');
    Map<String, Object?> identity = {};
    try {
      if (file.existsSync()) {
        identity =
            jsonDecode(await file.readAsString()) as Map<String, Object?>;
      }
    } catch (_) {
      // Unreadable: a new identity below.
    }
    if (identity['id'] is! String || identity['secret'] is! String) {
      identity = {'id': _uuid(), 'secret': _randomHex(32)};
    }
    // For the native retry (ServerSync in AlarmWatchdog.kt), which can't
    // read the build settings.
    identity['url'] = BackendConfig.url;
    identity['api_key'] = BackendConfig.apiKey;
    identity['app_version'] = BackendConfig.appVersion;
    await file.writeAsString(jsonEncode(identity));
    return HttpBackend._(file, identity);
  }

  final File _file;
  final Map<String, Object?> _identity;
  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  String? _timezone;
  String _status = 'Not contacted yet';

  /// The push token, once known (sent with every request).
  String? get _pushToken => _identity['push_token'] as String?;

  @override
  String get status =>
      '${BackendConfig.url}, device ${(_identity['id'] as String).substring(0, 8)}…, '
      'push ${_pushToken == null ? 'off' : 'on'}: $_status';

  Future<Map<String, Object?>> _device() async {
    _timezone ??= await () async {
      try {
        return (await FlutterTimezone.getLocalTimezone()).identifier;
      } catch (_) {
        return 'UTC';
      }
    }();
    return {
      'id': _identity['id'],
      'secret': _identity['secret'],
      'platform':
          defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
      'timezone': _timezone,
      'app_version': BackendConfig.appVersion,
      'push_token': _pushToken,
    };
  }

  /// POSTs [body] (plus the device) to [endpoint]. Returns the answer, or
  /// null on failure (logged; the next sync catches up).
  Future<Map<String, Object?>?> _post(
      String endpoint, Map<String, Object?> body) async {
    final what = endpoint.replaceAll('.php', '');
    try {
      final request = await _client
          .postUrl(Uri.parse('${BackendConfig.url}/api/v1/$endpoint'))
          .timeout(const Duration(seconds: 30));
      request.headers.contentType = ContentType.json;
      if (BackendConfig.apiKey.isNotEmpty) {
        request.headers.set('X-ReadAlarm-Key', BackendConfig.apiKey);
      }
      request
          .add(utf8.encode(jsonEncode({'device': await _device(), ...body})));
      final response =
          await request.close().timeout(const Duration(seconds: 30));
      final text = await response.transform(utf8.decoder).join();
      final answer = jsonDecode(text);
      if (response.statusCode != 200 ||
          answer is! Map ||
          answer['ok'] != true) {
        final error = answer is Map ? answer['error'] : text;
        _status = '$what refused (${response.statusCode} $error)';
        logEvent('Server: $_status');
        if (response.statusCode >= 500) await _retryLater();
        return null;
      }
      _status = '$what OK at ${DateTime.now()}';
      return answer.cast<String, Object?>();
    } catch (e) {
      _status = '$what failed (${e.runtimeType})';
      logEvent('Server: $_status: $e. Retrying when online');
      await _retryLater();
      return null;
    }
  }

  static const _alarms = MethodChannel('readalarm/alarms');

  /// The request didn't get through (often: the screen locked mid-request
  /// and the network slept). Android retries natively once online, with
  /// growing waits (ServerSync in AlarmWatchdog.kt); every platform also
  /// catches up at the next start or return to the app.
  Future<void> _retryLater() async {
    await _setDirty(true);
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _alarms.invokeMethod<void>('syncLater');
    } catch (_) {}
  }

  Future<void> _setDirty(bool dirty) async {
    if (_identity['dirty'] == dirty) return;
    _identity['dirty'] = dirty;
    try {
      await _file.writeAsString(jsonEncode(_identity));
    } catch (_) {}
  }

  @override
  Future<void> saveAlarm(ReadingAlarm alarm) async {
    final answer = await _post(
        'alarm-save.php', {'alarm': alarmForServer(alarm, DateTime.now())});
    if (answer != null) {
      final next = (answer['alarm'] as Map?)?['next_due_at'];
      logEvent('Server: alarm ${alarm.id} saved, next push '
          '${next is int ? DateTime.fromMillisecondsSinceEpoch(next) : 'none'}');
    }
  }

  @override
  Future<void> deleteAlarm(String alarmId) async {
    if (await _post('alarm-delete.php', {'alarm_id': alarmId}) != null) {
      logEvent('Server: alarm $alarmId deleted');
    }
  }

  @override
  Future<void> syncAlarms(List<ReadingAlarm> alarms) async {
    final now = DateTime.now();
    final answer = await _post('alarms-sync.php', {
      'alarms': [for (final a in alarms) alarmForServer(a, now)],
    });
    if (answer != null) {
      await _setDirty(false);
      logEvent('Server: ${alarms.length} alarms in step');
    }
  }

  @override
  Future<void> setPushToken(String? token) async {
    if (token == _pushToken && _status.contains('OK')) return;
    _identity['push_token'] = token;
    try {
      await _file.writeAsString(jsonEncode(_identity));
    } catch (_) {}
    if (await _post('register.php', {}) != null) {
      logEvent('Server: push ${token == null ? 'off' : 'on'} for this phone');
    }
  }

  static final _random = Random.secure();

  static String _randomHex(int bytes) => [
        for (var i = 0; i < bytes; i++)
          _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ].join();

  /// A random (version 4) UUID.
  static String _uuid() {
    final b = [for (var i = 0; i < 16; i++) _random.nextInt(256)];
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }
}
