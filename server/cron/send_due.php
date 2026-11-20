<?php
// Sends the pushes for alarms that are due. Run every minute by cron
// (hosting panel → Cron Jobs):
//   * * * * * php /home/USER/readalarm-server/cron/send_due.php >> /home/USER/readalarm-server/logs/cron.log 2>&1
// Each run checks every 10 seconds for just under a minute.

declare(strict_types=1);

if (PHP_SAPI !== 'cli') exit("Run from cron, not the web.\n");

require __DIR__ . '/../src/bootstrap.php';

$config = readalarm_config();
@mkdir(__DIR__ . '/../logs');

// One run at a time.
$lock = fopen(__DIR__ . '/../logs/send_due.lock', 'c');
if (!$lock || !flock($lock, LOCK_EX | LOCK_NB)) exit(0);

$db = Db::connect($config);
$fcm = null;
$send = function (string $token, string $platform, array $alarm, int $due, int $slot) use (&$fcm, $config) {
    $fcm ??= new Fcm((string)$config['firebase_service_account']);
    return $fcm->sendAlarm($token, $platform, $alarm, $due, $slot);
};

Sender::prune($db, readalarm_now_ms());
$until = time() + 50;
while (true) {
    try {
        $done = Sender::sendDue($db, $config, $send, readalarm_now_ms());
        if (array_sum($done) > 0) echo gmdate('c') . ' ' . json_encode($done) . "\n";
    } catch (Throwable $e) {
        echo gmdate('c') . ' ERROR ' . $e->getMessage() . "\n";
    }
    if (time() + 10 > $until) break;
    sleep(10);
}
