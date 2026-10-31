<?php
// The app sends its alarms here whenever they change (api/sync.php).

declare(strict_types=1);

const READALARM_MAX_ALARMS = 100;

/**
 * Stores a device's push token and replaces its alarms.
 * Returns [HTTP status, response array].
 */
function readalarm_sync(PDO $db, array $config, ?string $apiKey, $body, int $nowMs): array
{
    if (!is_string($apiKey) || !hash_equals((string)$config['api_key'], $apiKey)) {
        return [401, ['error' => 'bad key']];
    }
    if (!is_array($body)) return [400, ['error' => 'not JSON']];

    $deviceId = $body['device_id'] ?? null;
    $secret = $body['secret'] ?? null;
    $token = $body['token'] ?? null;
    $tz = $body['tz'] ?? null;
    $alarms = $body['alarms'] ?? null;
    if (!is_string($deviceId) || !preg_match('/^[0-9a-f-]{36}$/', $deviceId)
        || !is_string($secret) || strlen($secret) < 32 || strlen($secret) > 128
        || !is_string($token) || $token === '' || strlen($token) > 4096
        || !is_string($tz) || !in_array($tz, DateTimeZone::listIdentifiers(DateTimeZone::ALL_WITH_BC), true)
        || !is_array($alarms) || count($alarms) > READALARM_MAX_ALARMS) {
        return [400, ['error' => 'bad request']];
    }
    $rows = [];
    foreach ($alarms as $a) {
        $ok = is_array($a);
        foreach (['id', 'weekday', 'hour', 'minute', 'next'] as $k) {
            $ok = $ok && isset($a[$k]) && is_int($a[$k]);
        }
        if (!$ok || $a['weekday'] < 0 || $a['weekday'] > 7 || $a['hour'] < 0 || $a['hour'] > 23
            || $a['minute'] < 0 || $a['minute'] > 59) {
            return [400, ['error' => 'bad alarm']];
        }
        // Rings already past are of no use.
        if ($a['next'] > $nowMs - 60_000) $rows[] = $a;
    }

    $db->beginTransaction();
    try {
        $q = $db->prepare('SELECT secret_hash FROM devices WHERE device_id = ?');
        $q->execute([$deviceId]);
        $known = $q->fetchColumn();
        if ($known === false) {
            $db->prepare('INSERT INTO devices (device_id, secret_hash, token, tz, updated_at) VALUES (?, ?, ?, ?, ?)')
                ->execute([$deviceId, password_hash($secret, PASSWORD_DEFAULT), $token, $tz, $nowMs]);
        } elseif (!password_verify($secret, $known)) {
            $db->rollBack();
            return [403, ['error' => 'wrong secret']];
        } else {
            $db->prepare('UPDATE devices SET token = ?, tz = ?, updated_at = ? WHERE device_id = ?')
                ->execute([$token, $tz, $nowMs, $deviceId]);
        }
        $db->prepare('DELETE FROM alarms WHERE device_id = ?')->execute([$deviceId]);
        $insert = $db->prepare(
            'INSERT INTO alarms (device_id, alarm_id, weekday, hour, minute, next_at) VALUES (?, ?, ?, ?, ?, ?)'
        );
        foreach ($rows as $a) {
            $insert->execute([$deviceId, $a['id'], $a['weekday'], $a['hour'], $a['minute'], $a['next']]);
        }
        $db->commit();
    } catch (Throwable $e) {
        $db->rollBack();
        throw $e;
    }
    return [200, ['ok' => true, 'alarms' => count($rows)]];
}
