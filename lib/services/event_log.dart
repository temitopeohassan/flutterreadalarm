import 'dart:async';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// A record of what the app did (started, scheduled alarms, rang, read,
/// failed), kept on the phone for diagnostics reports. Never leaves the
/// phone unless the user sends a report.
class EventLog {
  EventLog._(this._file);

  /// In memory only (tests, or before [open]).
  EventLog.memory() : _file = null;

  /// The app's log; tests keep the in-memory one.
  static EventLog instance = EventLog.memory();

  /// Lines kept; older ones are dropped.
  static const maxLines = 3000;

  final File? _file;
  final _lines = <String>[];
  Future<void> _writing = Future.value();
  int _sinceTrim = 0;

  static Future<EventLog> open() async {
    final dir = await getApplicationSupportDirectory();
    final log = EventLog._(File('${dir.path}/events.log'));
    try {
      final file = log._file!;
      if (file.existsSync()) log._lines.addAll(await file.readAsLines());
    } catch (e) {
      debugPrint('Reading the event log failed: $e');
    }
    return log;
  }

  /// Records [event] with the time.
  void add(String event) {
    final line = '${_stamp(clock.now())} $event';
    _lines.add(line);
    if (_lines.length > maxLines) {
      _lines.removeRange(0, _lines.length - maxLines);
    }
    final file = _file;
    if (file == null) return;
    // Appends in order; rewrites the file now and then to drop old lines.
    final trim = ++_sinceTrim >= 500;
    if (trim) _sinceTrim = 0;
    final snapshot = trim ? _lines.join('\n') : null;
    _writing = _writing.then((_) async {
      try {
        if (snapshot != null) {
          await file.writeAsString('$snapshot\n');
        } else {
          await file.writeAsString('$line\n', mode: FileMode.append);
        }
      } catch (e) {
        debugPrint('Writing the event log failed: $e');
      }
    });
  }

  List<String> get lines => List.unmodifiable(_lines);

  static String _stamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}

/// Records [event] in the app's log.
void logEvent(String event) => EventLog.instance.add(event);
