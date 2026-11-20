<?php
// POST /api/v1/alarm-delete.php {device, alarm_id}: removes one alarm.
require __DIR__ . '/../../app.php';

Api::run('POST', function (array $body, PDO $db) {
    $device = Store::device($db, $body, readalarm_now_ms());
    $id = $body['alarm_id'] ?? null;
    if (!is_string($id) || $id === '') throw new ApiError(400, 'alarm_id missing');
    return ['deleted' => Store::deleteAlarm($db, $device, $id)];
});
