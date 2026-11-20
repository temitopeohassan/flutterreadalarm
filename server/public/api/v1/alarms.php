<?php
// POST /api/v1/alarms.php {device}: the device's alarms as the server has
// them, with each one's next ring (for problem reports).
require __DIR__ . '/../../app.php';

Api::run('POST', function (array $body, PDO $db) {
    $device = Store::device($db, $body, readalarm_now_ms());
    return ['alarms' => Store::listAlarms($db, $device), 'push' => $device['push_token'] !== null];
});
