<?php
// POST /api/v1/alarm-save.php {device, alarm}: creates or updates one alarm.
require __DIR__ . '/../../app.php';

Api::run('POST', function (array $body, PDO $db) {
    $now = readalarm_now_ms();
    $device = Store::device($db, $body, $now);
    return ['alarm' => Store::saveAlarm($db, $device, Store::alarm($body['alarm'] ?? null), $now)];
});
