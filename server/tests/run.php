<?php
// php server/tests/run.php: checks scheduling, storage and sending on
// SQLite (no network, no MySQL needed).

declare(strict_types=1);

require __DIR__ . '/../src/bootstrap.php';

$failures = 0;
function check(bool $ok, string $what): void
{
    global $failures;
    echo ($ok ? 'ok   ' : 'FAIL ') . $what . "\n";
    if (!$ok) $failures++;
}
function fails(callable $f, int $status): bool
{
    try {
        $f();
    } catch (ApiError $e) {
        return $e->status === $status;
    }
    return false;
}

$db = Db::connect(['db_dsn' => 'sqlite::memory:']);
$db->exec(file_get_contents(__DIR__ . '/schema.sqlite.sql'));
$lagos = 'Africa/Lagos';
$ms = fn(string $s, string $tz = 'Africa/Lagos') => (new DateTimeImmutable($s, new DateTimeZone($tz)))->getTimestamp() * 1000;

// ---- Schedule
$fri = $ms('2026-11-20 18:00'); // A Friday.
check(Schedule::next(true, [5], 19, 0, null, $lagos, $fri) === [$ms('2026-11-21 19:00'), 5], 'weekly: next Saturday 7 pm');
check(Schedule::next(true, [4], 19, 0, null, $lagos, $fri) === [$ms('2026-11-20 19:00'), 4], 'weekly: later today');
check(Schedule::next(true, [4], 17, 0, null, $lagos, $fri) === [$ms('2026-11-27 17:00'), 4], 'weekly: today has passed, next week');
check(Schedule::next(true, [], 7, 0, $fri + 3600_000, $lagos, $fri) === [$fri + 3600_000, 7], 'one-off: at its time, slot 7');
check(Schedule::next(true, [], 7, 0, $fri - 1, $lagos, $fri) === null, 'one-off in the past: none');
check(Schedule::next(false, [5], 19, 0, null, $lagos, $fri) === null, 'switched off: none');
check(Schedule::next(true, [6], 19, 0, null, 'Europe/London', $ms('2026-10-18 20:00', 'Europe/London'))[0]
    === $ms('2026-10-25 19:00', 'Europe/London'), '7 pm stays 7 pm across a clock change');

// ---- Devices
$device = ['id' => '0b6f2a3e-1c2d-4e5f-8a9b-0c1d2e3f4a5b', 'secret' => str_repeat('s', 40),
    'platform' => 'android', 'timezone' => $lagos, 'app_version' => '0.1.0'];
$d = Store::device($db, ['device' => $device], $fri);
check($d['push_token'] === null, 'device registered, no push token yet');
$d = Store::device($db, ['device' => $device + ['push_token' => 'tok-1']], $fri);
check($d['push_token'] === 'tok-1', 'push token stored');
$d = Store::device($db, ['device' => $device], $fri);
check($d['push_token'] === 'tok-1', 'token kept when not sent');
check(fails(fn() => Store::device($db, ['device' => ['secret' => str_repeat('x', 40)] + $device], $fri), 403),
    "another device can't use this id");
check(fails(fn() => Store::device($db, ['device' => ['id' => 'nope'] + $device], $fri), 400), 'bad id refused');
check(fails(fn() => Store::device($db, ['device' => ['timezone' => 'Mars/Base'] + $device], $fri), 400), 'bad time zone refused');

// ---- Alarms
$alarm = ['id' => 'a1', 'enabled' => true, 'hour' => 19, 'minute' => 0, 'days' => [5],
    'title' => 'Time to read', 'body' => 'Book · Read 15 min', 'payload' => '{"alarmId":"a1"}'];
$saved = Store::saveAlarm($db, $d, Store::alarm($alarm), $fri);
check($saved['next_due_at'] === $ms('2026-11-21 19:00'), 'alarm saved with its next ring');
Store::saveAlarm($db, $d, Store::alarm(['minute' => 30] + $alarm), $fri);
check(Store::listAlarms($db, $d)[0]['minute'] === 30 && count(Store::listAlarms($db, $d)) === 1, 'saving again updates it');
check(fails(fn() => Store::alarm(['hour' => 24] + $alarm), 400), 'bad time refused');
check(fails(fn() => Store::alarm(['days' => [7]] + $alarm), 400), 'bad day refused');
Store::replaceAlarms($db, $d, [Store::alarm($alarm), Store::alarm(['id' => 'a2', 'days' => [],
    'once_at' => $fri + 600_000] + $alarm)], $fri);
check(count(Store::listAlarms($db, $d)) === 2, 'sync replaces all alarms');
check(Store::deleteAlarm($db, $d, 'a2') && count(Store::listAlarms($db, $d)) === 1, 'alarm deleted');

// ---- Sending
$config = ['send_delay_seconds' => 60, 'stale_after_seconds' => 900, 'ios_push' => false];
$sent = [];
$ok = function ($token, $platform, $alarm, $due, $slot) use (&$sent) {
    $sent[] = [$token, $alarm['alarm_id'], $due, $slot];
    return ['ok'];
};
$sat7 = $ms('2026-11-21 19:00');
Sender::sendDue($db, $config, $ok, $sat7 + 30_000);
check($sent === [], 'not sent before the delay');
$r = Sender::sendDue($db, $config, $ok, $sat7 + 61_000);
check($r['sent'] === 1 && $sent[0] === ['tok-1', 'a1', $sat7, 5], 'sent a minute after the alarm time');
Sender::sendDue($db, $config, $ok, $sat7 + 70_000);
check(count($sent) === 1, 'only once');
check(Store::listAlarms($db, $d)[0]['next_due_at'] === $ms('2026-11-28 19:00'), 'moved on to next Saturday');

$r = Sender::sendDue($db, $config, fn() => ['error', 'down'], $ms('2026-11-28 19:01:05'));
check($r['failed'] === 1 && Store::listAlarms($db, $d)[0]['next_due_at'] === $ms('2026-11-28 19:00'), 'failed push kept for a retry');
$r = Sender::sendDue($db, $config, fn() => ['error', 'down'], $ms('2026-11-28 19:20'));
check($r['stale'] === 1 && Store::listAlarms($db, $d)[0]['next_due_at'] === $ms('2026-12-05 19:00'), 'too late: dropped, next week');

$r = Sender::sendDue($db, $config, fn() => ['gone'], $ms('2026-12-05 19:01:05'));
check($r['gone'] === 1 && Store::device($db, ['device' => $device], $fri)['push_token'] === null, 'uninstalled app: token cleared');
$r = Sender::sendDue($db, $config, $ok, $ms('2026-12-12 19:01:05'));
check($r['no_token'] === 1, 'no token: nothing sent, alarm moves on');

// A time-zone change moves the next ring.
Store::device($db, ['device' => ['timezone' => 'Europe/London'] + $device], $ms('2026-12-13 12:00'));
check(Store::listAlarms($db, $d)[0]['next_due_at'] === $ms('2026-12-19 19:00', 'Europe/London'), 'time-zone change reschedules');

$logged = (int)$db->query('SELECT COUNT(*) FROM push_log')->fetchColumn();
check($logged === 5, "push log kept ($logged entries)");

echo $failures === 0 ? "All passed\n" : "$failures failed\n";
exit($failures === 0 ? 0 : 1);
