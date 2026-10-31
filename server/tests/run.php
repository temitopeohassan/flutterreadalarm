<?php
// php server/tests/run.php — checks sync and scheduling on SQLite.

declare(strict_types=1);

require __DIR__ . '/../lib/db.php';
require __DIR__ . '/../lib/sync.php';
require __DIR__ . '/../lib/schedule.php';

$failures = 0;
function check(bool $ok, string $what): void
{
    global $failures;
    echo ($ok ? 'ok   ' : 'FAIL ') . $what . "\n";
    if (!$ok) $failures++;
}

$db = readalarm_db(['db_dsn' => 'sqlite::memory:']);
readalarm_install($db);
readalarm_install($db); // Twice is fine.
$config = ['api_key' => 'k'];
$ms = fn(string $s, string $tz = 'Africa/Lagos') => (new DateTimeImmutable($s, new DateTimeZone($tz)))->getTimestamp() * 1000;

$now = $ms('2026-10-30 18:00');   // A Friday.
$sat7 = $ms('2026-10-31 19:00');  // Saturday 7 pm.
$device = [
    'device_id' => '0b6f2a3e-1c2d-4e5f-8a9b-0c1d2e3f4a5b',
    'secret' => str_repeat('s', 40),
    'token' => 'push-token',
    'tz' => 'Africa/Lagos',
    'alarms' => [
        ['id' => 51, 'weekday' => 6, 'hour' => 19, 'minute' => 0, 'next' => $sat7],
        ['id' => 77, 'weekday' => 0, 'hour' => 0, 'minute' => 0, 'next' => $now + 60_000],
    ],
];

check(readalarm_sync($db, $config, 'wrong', $device, $now)[0] === 401, 'wrong app key refused');
check(readalarm_sync($db, $config, 'k', ['device_id' => 'x'], $now)[0] === 400, 'bad request refused');
[$code, $r] = readalarm_sync($db, $config, 'k', $device, $now);
check($code === 200 && $r['alarms'] === 2, 'device and alarms stored');
check(readalarm_sync($db, $config, 'k', ['secret' => str_repeat('x', 40)] + $device, $now)[0] === 403,
    "another device can't overwrite it");

$sent = [];
$send = function (string $token, int $id, int $due) use (&$sent) {
    $sent[] = [$token, $id, $due];
    return 'ok';
};
readalarm_send_due($db, $send, $now);
check($sent === [], 'nothing due yet');

readalarm_send_due($db, $send, $now + 61_000);
check($sent === [['push-token', 77, $now + 60_000]], 'one-off alarm pushed on time');
readalarm_send_due($db, $send, $now + 70_000);
check(count($sent) === 1, 'and only once');

readalarm_send_due($db, $send, $sat7 + 3_000);
check(end($sent) === ['push-token', 51, $sat7], 'weekly alarm pushed');
$next = (int)$db->query('SELECT next_at FROM alarms WHERE alarm_id = 51')->fetchColumn();
check($next === $ms('2026-11-07 19:00'), 'weekly alarm moved to next Saturday');

// Daylight saving: London clocks go back on 25 Oct 2026.
check(readalarm_next_weekly($ms('2026-10-18 20:00', 'Europe/London'), 7, 19, 0, 'Europe/London')
    === $ms('2026-10-25 19:00', 'Europe/London'), 'next ring keeps 7 pm across a clock change');

// A failed push is retried; a stale one is skipped.
$fail = fn() => 'error';
$sync2 = $device;
$sync2['alarms'] = [['id' => 51, 'weekday' => 6, 'hour' => 19, 'minute' => 0, 'next' => $ms('2026-11-07 19:00')]];
readalarm_sync($db, $config, 'k', $sync2, $sat7 + 60_000);
$r = readalarm_send_due($db, $fail, $ms('2026-11-07 19:00') + 1000);
check($r['failed'] === 1 && (int)$db->query('SELECT next_at FROM alarms')->fetchColumn() === $ms('2026-11-07 19:00'),
    'failed push kept for a retry');
$r = readalarm_send_due($db, $fail, $ms('2026-11-07 19:11'));
check($r['stale'] === 1 && (int)$db->query('SELECT next_at FROM alarms')->fetchColumn() === $ms('2026-11-14 19:00'),
    'too old: skipped, moved to the next week');

// Uninstalled app: forgotten.
readalarm_send_due($db, fn() => 'gone', $ms('2026-11-14 19:00'));
check((int)$db->query('SELECT COUNT(*) FROM devices')->fetchColumn() === 0, 'uninstalled device forgotten');

echo $failures === 0 ? "All passed\n" : "$failures failed\n";
exit($failures === 0 ? 0 : 1);
