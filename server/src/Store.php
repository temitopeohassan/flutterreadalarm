<?php
// Devices and their alarms.

declare(strict_types=1);

final class Store
{
    public const MAX_ALARMS = 100;
    private const MAX_PAYLOAD = 3000; // A push carries at most 4 KB.

    /**
     * The device the request comes from ($body['device']): created on its
     * first request, then it must give the same secret. Its time zone,
     * version and (if sent) push token are kept up to date.
     * Returns the device row.
     */
    public static function device(PDO $db, array $body, int $nowMs): array
    {
        $d = $body['device'] ?? null;
        if (!is_array($d)) throw new ApiError(400, 'device missing');
        $id = $d['id'] ?? null;
        $secret = $d['secret'] ?? null;
        $platform = $d['platform'] ?? null;
        $tz = $d['timezone'] ?? null;
        $version = substr((string)($d['app_version'] ?? ''), 0, 32);
        if (!is_string($id) || !preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/', $id)) {
            throw new ApiError(400, 'bad device id');
        }
        if (!is_string($secret) || strlen($secret) < 32 || strlen($secret) > 128) {
            throw new ApiError(400, 'bad device secret');
        }
        if (!in_array($platform, ['android', 'ios'], true)) throw new ApiError(400, 'bad platform');
        if (!is_string($tz) || !in_array($tz, DateTimeZone::listIdentifiers(DateTimeZone::ALL_WITH_BC), true)) {
            // Some phones report zones PHP doesn't list (e.g. 'GMT'): UTC.
            $tz = is_string($tz) && in_array($tz, ['GMT', 'UTC', 'Etc/UTC'], true) ? 'UTC' : null;
            if ($tz === null) throw new ApiError(400, 'bad time zone');
        }
        $token = array_key_exists('push_token', $d) ? $d['push_token'] : false;
        if ($token !== false && $token !== null && (!is_string($token) || strlen($token) > 4096)) {
            throw new ApiError(400, 'bad push token');
        }

        $q = $db->prepare('SELECT * FROM devices WHERE id = ?');
        $q->execute([$id]);
        $row = $q->fetch();
        $now = Db::now($nowMs);
        if ($row === false) {
            $db->prepare(
                'INSERT INTO devices (id, secret_hash, platform, push_token, timezone, app_version, created_at, last_seen_at)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?)'
            )->execute([$id, password_hash($secret, PASSWORD_DEFAULT), $platform, $token ?: null, $tz, $version, $now, $now]);
        } else {
            if (!password_verify($secret, $row['secret_hash'])) throw new ApiError(403, 'wrong device secret');
            $tzChanged = $row['timezone'] !== $tz;
            if ($token === false) {
                $db->prepare('UPDATE devices SET platform = ?, timezone = ?, app_version = ?, last_seen_at = ? WHERE id = ?')
                    ->execute([$platform, $tz, $version, $now, $id]);
            } else {
                $db->prepare(
                    'UPDATE devices SET platform = ?, push_token = ?, timezone = ?, app_version = ?, last_seen_at = ? WHERE id = ?'
                )->execute([$platform, $token ?: null, $tz, $version, $now, $id]);
            }
            // A new time zone moves every alarm's next ring.
            if ($tzChanged) self::reschedule($db, $id, $tz, $nowMs);
        }
        $q->execute([$id]);
        return $q->fetch();
    }

    /** Checks an alarm from the app and returns it as a row. */
    public static function alarm(mixed $a): array
    {
        if (!is_array($a)) throw new ApiError(400, 'alarm must be an object');
        $id = $a['id'] ?? null;
        if (!is_string($id) || !preg_match('/^[A-Za-z0-9_.-]{1,64}$/', $id)) throw new ApiError(400, 'bad alarm id');
        $hour = $a['hour'] ?? null;
        $minute = $a['minute'] ?? null;
        if (!is_int($hour) || $hour < 0 || $hour > 23 || !is_int($minute) || $minute < 0 || $minute > 59) {
            throw new ApiError(400, "alarm $id: bad time");
        }
        $days = $a['days'] ?? [];
        if (!is_array($days) || count($days) > 7) throw new ApiError(400, "alarm $id: bad days");
        foreach ($days as $d) {
            if (!is_int($d) || $d < 0 || $d > 6) throw new ApiError(400, "alarm $id: bad days");
        }
        $days = array_values(array_unique($days));
        sort($days);
        $onceAt = $a['once_at'] ?? null;
        if ($onceAt !== null && !is_int($onceAt)) throw new ApiError(400, "alarm $id: bad once_at");
        $title = $a['title'] ?? 'Time to read';
        $body = $a['body'] ?? '';
        $payload = $a['payload'] ?? '';
        if (!is_string($title) || !is_string($body) || !is_string($payload) || strlen($payload) > self::MAX_PAYLOAD) {
            throw new ApiError(400, "alarm $id: bad text");
        }
        return [
            'alarm_id' => $id,
            'enabled' => ($a['enabled'] ?? true) === true,
            'hour' => $hour,
            'minute' => $minute,
            'days' => $days,
            'once_at' => $onceAt,
            'title' => mb_substr($title, 0, 120),
            'body' => mb_substr($body, 0, 255),
            'payload' => $payload,
        ];
    }

    /** Stores (or replaces) one alarm with its next ring. */
    public static function saveAlarm(PDO $db, array $device, array $a, int $nowMs): array
    {
        $next = Schedule::next($a['enabled'], $a['days'], $a['hour'], $a['minute'], $a['once_at'], $device['timezone'], $nowMs);
        $values = [
            (int)$a['enabled'], $a['hour'], $a['minute'], implode(',', $a['days']), $a['once_at'],
            $a['title'], $a['body'], $a['payload'], $next[0] ?? null, $next[1] ?? null, Db::now($nowMs),
        ];
        $q = $db->prepare('SELECT 1 FROM alarms WHERE device_id = ? AND alarm_id = ?');
        $q->execute([$device['id'], $a['alarm_id']]);
        if ($q->fetchColumn() !== false) {
            $db->prepare(
                'UPDATE alarms SET enabled = ?, hour = ?, minute = ?, days = ?, once_at = ?, title = ?, body = ?,
                 payload = ?, next_due_at = ?, next_slot = ?, updated_at = ? WHERE device_id = ? AND alarm_id = ?'
            )->execute([...$values, $device['id'], $a['alarm_id']]);
        } else {
            $count = $db->prepare('SELECT COUNT(*) FROM alarms WHERE device_id = ?');
            $count->execute([$device['id']]);
            if ((int)$count->fetchColumn() >= self::MAX_ALARMS) throw new ApiError(400, 'too many alarms');
            $db->prepare(
                'INSERT INTO alarms (enabled, hour, minute, days, once_at, title, body, payload, next_due_at, next_slot,
                 updated_at, device_id, alarm_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
            )->execute([...$values, $device['id'], $a['alarm_id']]);
        }
        return ['id' => $a['alarm_id'], 'next_due_at' => $next[0] ?? null];
    }

    public static function deleteAlarm(PDO $db, array $device, string $alarmId): bool
    {
        $q = $db->prepare('DELETE FROM alarms WHERE device_id = ? AND alarm_id = ?');
        $q->execute([$device['id'], $alarmId]);
        return $q->rowCount() > 0;
    }

    /** Replaces all of the device's alarms with $alarms (already checked). */
    public static function replaceAlarms(PDO $db, array $device, array $alarms, int $nowMs): array
    {
        if (count($alarms) > self::MAX_ALARMS) throw new ApiError(400, 'too many alarms');
        $db->beginTransaction();
        try {
            $db->prepare('DELETE FROM alarms WHERE device_id = ?')->execute([$device['id']]);
            $saved = [];
            foreach ($alarms as $a) $saved[] = self::saveAlarm($db, $device, $a, $nowMs);
            $db->commit();
            return $saved;
        } catch (Throwable $e) {
            $db->rollBack();
            throw $e;
        }
    }

    public static function listAlarms(PDO $db, array $device): array
    {
        $q = $db->prepare(
            'SELECT alarm_id, enabled, hour, minute, days, once_at, title, next_due_at, next_slot, updated_at
             FROM alarms WHERE device_id = ? ORDER BY next_due_at IS NULL, next_due_at'
        );
        $q->execute([$device['id']]);
        return array_map(fn($r) => [
            'id' => $r['alarm_id'],
            'enabled' => (bool)$r['enabled'],
            'hour' => (int)$r['hour'],
            'minute' => (int)$r['minute'],
            'days' => $r['days'] === '' ? [] : array_map('intval', explode(',', $r['days'])),
            'once_at' => $r['once_at'] === null ? null : (int)$r['once_at'],
            'title' => $r['title'],
            'next_due_at' => $r['next_due_at'] === null ? null : (int)$r['next_due_at'],
        ], $q->fetchAll());
    }

    /** Works out every alarm's next ring again (after a time-zone change). */
    public static function reschedule(PDO $db, string $deviceId, string $tz, int $nowMs): void
    {
        $q = $db->prepare('SELECT * FROM alarms WHERE device_id = ?');
        $q->execute([$deviceId]);
        $u = $db->prepare('UPDATE alarms SET next_due_at = ?, next_slot = ? WHERE device_id = ? AND alarm_id = ?');
        foreach ($q->fetchAll() as $r) {
            $next = self::nextFor($r, $tz, $nowMs);
            $u->execute([$next[0] ?? null, $next[1] ?? null, $deviceId, $r['alarm_id']]);
        }
    }

    /** The next ring of a stored alarm row after $afterMs. */
    public static function nextFor(array $r, string $tz, int $afterMs): ?array
    {
        $days = $r['days'] === '' ? [] : array_map('intval', explode(',', (string)$r['days']));
        return Schedule::next((bool)$r['enabled'], $days, (int)$r['hour'], (int)$r['minute'],
            $r['once_at'] === null ? null : (int)$r['once_at'], $tz, $afterMs);
    }
}
