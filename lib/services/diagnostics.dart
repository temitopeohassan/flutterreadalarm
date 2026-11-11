import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/reading_alarm.dart';
import '../state/app_state.dart';
import 'alarm_scheduler.dart';
import 'event_log.dart';

/// Builds and sends diagnostics reports: what ReadAlarm and the phone say
/// about alarms, permissions and why the app was closed, plus the app's
/// activity log.
class Diagnostics {
  static const _channel = MethodChannel('readalarm/diagnostics');

  /// Where "Send report" addresses the email.
  static const reportEmail = 'temitope.hassan.2@gmail.com';

  /// The diagnostics bar shows on every screen in builds made with
  /// --dart-define=READALARM_DIAGNOSTICS=true.
  static const enabled = bool.fromEnvironment('READALARM_DIAGNOSTICS');

  static Future<T?> _call<T>(String method, [Object? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } catch (e) {
      debugPrint('Diagnostics $method failed: $e');
      return null;
    }
  }

  /// The full report as plain text.
  static Future<String> buildReport(AppState state) async {
    final now = clock.now();
    final phone = await _call<String>('phone') ?? 'Phone details unavailable.';
    final alarmLines = <String>[];
    final findings = <String>[];

    // Alarms, and whether Android itself still holds each ring.
    final pending = await state.services.alarms.pendingAlarmIds();
    for (final alarm in state.alarms) {
      final ids = alarmNotificationIds(alarm);
      final registered = await _call<List<Object?>>(
          'registered', {'ids': ids.values.toList()});
      alarmLines.add('Alarm ${alarm.id}: ${formatTime(alarm.time)} '
          '${alarm.scheduleLabel}, read ${alarm.durationMin} min, '
          '"${alarm.book.title}", ${alarm.enabled ? 'ON' : 'off'}');
      if (alarm.enabled) {
        alarmLines.add('  Next ring: ${alarm.nextOccurrence(now)}');
      }
      alarmLines.add('  In the notification plugin\'s list: '
          '${pending.contains(alarm.id) ? 'yes' : 'no'}');
      final missing = <String>[];
      var i = 0;
      for (final label in ids.keys) {
        final held = registered == null ? null : registered[i] == true;
        i++;
        alarmLines.add('  $label ring held by Android: '
            '${held == null ? 'unknown' : held ? 'yes' : 'no'}');
        if (alarm.enabled && label != 'Snooze' && held == false) {
          missing.add(label);
        }
      }
      if (missing.isNotEmpty) {
        findings.add('Alarm ${alarm.id} (${formatTime(alarm.time)}) is ON in '
            'ReadAlarm, but Android no longer holds its ring for '
            '${missing.join(', ')}. The phone removed it, which happens when '
            'it force-stops ReadAlarm. Opening ReadAlarm puts it back; '
            'locking ReadAlarm in recent apps and allowing auto-start stop '
            'it happening.');
      }
    }
    if (state.alarms.where((a) => a.enabled).isEmpty) {
      findings.add('No alarm is switched on.');
    }

    // What the phone reports.
    bool says(String label, String value) => phone.contains('$label: $value');
    if (says('Exact alarms allowed', 'false')) {
      findings.add('Exact alarms are not allowed: alarms can\'t ring on '
          'time. Settings → Apps → ReadAlarm → Alarms & reminders.');
    }
    if (says('Background restricted by user', 'true')) {
      findings.add('ReadAlarm is restricted in the background: Android '
          'blocks its alarms. Settings → Apps → ReadAlarm → Battery → '
          'Unrestricted.');
    }
    if (says('Battery optimisation off for ReadAlarm', 'false')) {
      findings.add('Battery optimisation is on for ReadAlarm.');
    }
    if (phone.contains('RESTRICTED (45)')) {
      findings.add('Android put ReadAlarm in the RESTRICTED standby group, '
          'which holds back its alarms.');
    }
    if (says('Notifications allowed', 'false')) {
      findings.add('Notifications are off for ReadAlarm: the alarm can\'t '
          'ring.');
    }
    if (says('Alarm channel', 'importance 0') ||
        says('Alarm channel', 'importance 1') ||
        says('Alarm channel', 'importance 2')) {
      findings.add('The "Reading alarms" notification category is silenced '
          'in the phone\'s settings.');
    }
    if (says('Full-screen alarms allowed', 'false')) {
      findings.add('Full-screen alarms are not allowed: the alarm only shows '
          'as a notification.');
    }
    final forceStops =
        RegExp(r'USER_REQUESTED|OTHER \(often').allMatches(phone).length;
    if (forceStops > 0) {
      findings.add('The phone recorded $forceStops time(s) ReadAlarm was '
          'force-stopped or closed by the system (see "Why ReadAlarm was '
          'last closed"). Each force stop removes its alarms until it\'s '
          'opened again.');
    }
    if (!state.autoStartConfirmed) {
      findings.add('Auto-start hasn\'t been confirmed in ReadAlarm.');
    }

    // Alarm times since logging began with no record of the alarm opening.
    final log = EventLog.instance.lines;
    final missed = _unopenedRings(state, log, now);
    if (missed.isNotEmpty) {
      findings.add('No record of these alarms being opened (they may not '
          'have rung, or nobody tapped them): ${missed.join('; ')}');
    }

    final logcat =
        await _call<String>('logcat', {'lines': 300}) ?? 'Unavailable.';
    final b = StringBuffer()
      ..writeln('READALARM DIAGNOSTICS REPORT')
      ..writeln('Generated $now')
      ..writeln()
      ..writeln('FINDINGS')
      ..writeln(findings.isEmpty
          ? 'Nothing found that would stop alarms.'
          : findings.map((f) => '- $f').join('\n'))
      ..writeln()
      ..writeln('ALARMS')
      ..writeln(alarmLines.isEmpty ? 'None.' : alarmLines.join('\n'))
      ..writeln()
      ..writeln(phone)
      ..writeln()
      ..writeln('READALARM\'S SETTINGS')
      ..writeln('Permissions: ${state.permissions}')
      ..writeln('Auto-start confirmed: ${state.autoStartConfirmed}')
      ..writeln('Premium: ${state.isPremium}')
      ..writeln('Free reading left today: ${state.freeReadingLeft}')
      ..writeln('Books: ${state.books.map((b) => '"${b.title}" '
          '${(b.progress * 100).toStringAsFixed(1)}%').join(', ')}')
      ..writeln(
          'Last sessions: ${state.sessions.take(10).map((s) => '${s.startedAt} '
              '${s.minutes} min ${s.endReason}').join('; ')}')
      ..writeln()
      ..writeln('ACTIVITY LOG (${log.length} lines, oldest first)')
      ..writeln(log.length > 1500
          ? log.sublist(log.length - 1500).join('\n')
          : log.join('\n'))
      ..writeln()
      ..writeln('SYSTEM LOG (ReadAlarm only, latest)')
      ..writeln(logcat);
    return b.toString();
  }

  /// Ring times in the last 7 days, after logging began, with no "opened"
  /// record within 30 minutes.
  static List<String> _unopenedRings(
      AppState state, List<String> log, DateTime now) {
    DateTime? parse(String line) =>
        line.length < 19 ? null : DateTime.tryParse(line.substring(0, 19));
    final first = log.map(parse).whereType<DateTime>().firstOrNull;
    if (first == null) return const [];
    final opened = <String, List<DateTime>>{};
    for (final line in log) {
      final m = RegExp(r'Alarm (\S+) opened').firstMatch(line);
      final at = parse(line);
      if (m != null && at != null) {
        (opened[m.group(1)!] ??= []).add(at);
      }
    }
    final from = now.subtract(const Duration(days: 7)).isAfter(first)
        ? now.subtract(const Duration(days: 7))
        : first;
    final out = <String>[];
    // Repeating alarms only: one-offs switch off once they've rung.
    for (final alarm
        in state.alarms.where((a) => a.enabled && a.repeatDays.isNotEmpty)) {
      var t = alarm.nextOccurrence(from);
      while (t.isBefore(now.subtract(const Duration(minutes: 30)))) {
        final hit = (opened[alarm.id] ?? const []).any((o) =>
            !o.isBefore(t) && o.isBefore(t.add(const Duration(minutes: 30))));
        if (!hit) out.add('${alarm.id} at $t');
        t = alarm.nextOccurrence(t);
      }
    }
    return out;
  }

  /// Opens an email app with [report], addressed to [reportEmail]; with
  /// no email app, the share sheet. Returns how it was sent, or null.
  static Future<ReportSent?> email(String report) async {
    final how = await _call<String>('email', {
      'to': reportEmail,
      'subject': 'ReadAlarm diagnostics report',
      'body': report,
    });
    return switch (how) {
      'email' => ReportSent.email,
      'share' => ReportSent.share,
      _ => null,
    };
  }

  /// The share sheet (WhatsApp and so on) with [report].
  static Future<bool> share(String report) async =>
      await _call<bool>('share', {
        'subject': 'ReadAlarm diagnostics report',
        'body': report,
      }) ??
      false;
}

/// How [Diagnostics.email] sent the report.
enum ReportSent { email, share }
