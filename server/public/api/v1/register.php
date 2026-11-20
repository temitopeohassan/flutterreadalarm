<?php
// POST /api/v1/register.php {device}: registers the app (first time) and
// updates its push token and time zone.
require __DIR__ . '/../../app.php';

Api::run('POST', function (array $body, PDO $db) {
    $device = Store::device($db, $body, readalarm_now_ms());
    return ['device_id' => $device['id'], 'push' => $device['push_token'] !== null];
});
