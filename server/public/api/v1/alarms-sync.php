<?php
// POST /api/v1/alarms-sync.php {device, alarms: [...]}: replaces all of
// the device's alarms (the app sends them all when it starts).
require __DIR__ . '/../../app.php';

Api::run('POST', function (array $body, PDO $db) {
    $now = readalarm_now_ms();
    $device = Store::device($db, $body, $now);
    $list = $body['alarms'] ?? null;
    if (!is_array($list) || !array_is_list($list)) throw new ApiError(400, 'alarms must be a list');
    $alarms = array_map([Store::class, 'alarm'], $list);
    return ['alarms' => Store::replaceAlarms($db, $device, $alarms, $now)];
});
