<?php
// Finds alarms that are due and sends their pushes (cron/send_due.php).

declare(strict_types=1);

/** Pushes older than this aren't sent: the phone has moved on. */
const READALARM_STALE_MS = 10 * 60_000;

/**
 * The ring after $afterMs of a weekly alarm at $hour:$minute on $weekday
 * (1-7, Monday-Sunday) in time zone $tz, in ms. Daylight saving safe.
 */
function readalarm_next_weekly(int $afterMs, int $weekday, int $hour, int $minute, string $tz): int
{
    $zone = new DateTimeZone($tz);
    $d = (new DateTimeImmutable('@' . intdiv($afterMs, 1000)))->setTimezone($zone);
    $d = $d->setTime($hour, $minute, 0);
    for ($i = 0; $i < 9; $i++) {
        $c = $d->modify("+$i days")->setTime($hour, $minute, 0);
        if ((int)$c->format('N') === $weekday && $c->getTimestamp() * 1000 > $afterMs) {
            return $c->getTimestamp() * 1000;
        }
    }
    throw new LogicException('no next ring');
}

/**
 * Sends a push for every ring due by $nowMs, then moves each to its next
 * ring (weekly) or removes it (once). $send(token, alarmId, dueMs) returns
 * 'ok', 'gone' (the app was uninstalled: forget the device) or 'error'
 * (tried again on the next check).
 * Returns what was done, for the log.
 */
function readalarm_send_due(PDO $db, callable $send, int $nowMs): array
{
    $done = ['sent' => 0, 'stale' => 0, 'failed' => 0, 'gone' => 0];
    $q = $db->prepare(
        'SELECT a.device_id, a.alarm_id, a.weekday, a.hour, a.minute, a.next_at, d.token, d.tz
         FROM alarms a JOIN devices d ON d.device_id = a.device_id
         WHERE a.next_at <= ? ORDER BY a.next_at'
    );
    $q->execute([$nowMs]);
    $gone = [];
    foreach ($q->fetchAll() as $r) {
        if (isset($gone[$r['device_id']])) continue;
        $due = (int)$r['next_at'];
        if ($nowMs - $due > READALARM_STALE_MS) {
            $done['stale']++;
        } else {
            try {
                $result = $send($r['token'], (int)$r['alarm_id'], $due);
            } catch (Throwable $e) {
                error_log('ReadAlarm push: ' . $e->getMessage());
                $result = 'error';
            }
            if ($result === 'gone') {
                $gone[$r['device_id']] = true;
                $db->prepare('DELETE FROM alarms WHERE device_id = ?')->execute([$r['device_id']]);
                $db->prepare('DELETE FROM devices WHERE device_id = ?')->execute([$r['device_id']]);
                $done['gone']++;
                continue;
            }
            if ($result !== 'ok') {
                // Tried again on the next check, until it's too old.
                $done['failed']++;
                continue;
            }
            $done['sent']++;
        }
        if ((int)$r['weekday'] === 0) {
            $db->prepare('DELETE FROM alarms WHERE device_id = ? AND alarm_id = ?')
                ->execute([$r['device_id'], $r['alarm_id']]);
        } else {
            $next = readalarm_next_weekly(max($due, $nowMs), (int)$r['weekday'], (int)$r['hour'],
                (int)$r['minute'], $r['tz']);
            $db->prepare('UPDATE alarms SET next_at = ? WHERE device_id = ? AND alarm_id = ?')
                ->execute([$next, $r['device_id'], $r['alarm_id']]);
        }
    }
    return $done;
}
