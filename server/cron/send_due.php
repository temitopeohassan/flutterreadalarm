<?php
// Sends the pushes for alarms that are due. Run every minute by cron:
//   * * * * * php /path/to/server/cron/send_due.php >> /path/to/server/data/cron.log 2>&1
// Each run checks every 5 seconds for just under a minute, so a push goes
// out within seconds of its alarm's time.

declare(strict_types=1);

if (PHP_SAPI !== 'cli') exit("Run from cron, not the web.\n");

require __DIR__ . '/../lib/db.php';
require __DIR__ . '/../lib/schedule.php';
require __DIR__ . '/../lib/fcm.php';

$config = require __DIR__ . '/../config.php';

// One run at a time.
$lock = fopen(sys_get_temp_dir() . '/readalarm-send-due.lock', 'c');
if (!flock($lock, LOCK_EX | LOCK_NB)) exit(0);

$db = readalarm_db($config);
readalarm_install($db);
$fcm = new Fcm($config['service_account']);
$send = fn(string $token, int $id, int $due) => $fcm->sendRing($token, $id, $due);

$until = time() + 55;
while (true) {
    try {
        $done = readalarm_send_due($db, $send, (int)(microtime(true) * 1000));
        if (array_sum($done) > 0) echo date('c') . ' ' . json_encode($done) . "\n";
    } catch (Throwable $e) {
        echo date('c') . ' ERROR ' . $e->getMessage() . "\n";
    }
    if (time() + 5 > $until) break;
    sleep(5);
}
