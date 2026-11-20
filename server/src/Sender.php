<?php
// Finds alarms that are due and sends their pushes (cron/send_due.php).

declare(strict_types=1);

final class Sender
{
    /**
     * Sends a push for every ring due by $nowMs - delay, then moves each
     * alarm to its next ring. $send(token, platform, alarm, dueMs, slot)
     * returns ['ok'], ['gone'] or ['error', detail]; a failed push is
     * tried again on the next check until it's stale.
     * Returns counts, for the cron log.
     */
    public static function sendDue(PDO $db, array $config, callable $send, int $nowMs): array
    {
        $delay = (int)($config['send_delay_seconds'] ?? 60) * 1000;
        $stale = (int)($config['stale_after_seconds'] ?? 900) * 1000;
        $iosPush = (bool)($config['ios_push'] ?? false);
        $done = ['sent' => 0, 'failed' => 0, 'stale' => 0, 'no_token' => 0, 'gone' => 0];

        $q = $db->prepare(
            'SELECT a.*, d.push_token, d.platform, d.timezone
             FROM alarms a JOIN devices d ON d.id = a.device_id
             WHERE a.next_due_at IS NOT NULL AND a.next_due_at <= ? ORDER BY a.next_due_at'
        );
        $q->execute([$nowMs - $delay]);
        foreach ($q->fetchAll() as $r) {
            $due = (int)$r['next_due_at'];
            $status = null;
            $detail = '';
            if ($nowMs - $due > $stale) {
                $status = 'stale';
            } elseif (empty($r['push_token']) || ($r['platform'] === 'ios' && !$iosPush)) {
                $status = 'no_token';
            } else {
                try {
                    $result = $send($r['push_token'], $r['platform'], $r, $due, (int)$r['next_slot']);
                } catch (Throwable $e) {
                    $result = ['error', substr($e->getMessage(), 0, 250)];
                }
                if ($result[0] === 'ok') {
                    $status = 'sent';
                } elseif ($result[0] === 'gone') {
                    $status = 'gone';
                    $db->prepare('UPDATE devices SET push_token = NULL WHERE id = ? AND push_token = ?')
                        ->execute([$r['device_id'], $r['push_token']]);
                } else {
                    // Kept as due: tried again on the next check.
                    $done['failed']++;
                    self::log($db, $r, $due, 'failed', $result[1] ?? '', $nowMs);
                    continue;
                }
            }
            $done[$status]++;
            self::log($db, $r, $due, $status, $detail, $nowMs);
            // On to the next ring: next week for a weekly alarm; none for a one-off.
            $next = Store::nextFor($r, $r['timezone'], max($due, $nowMs - $delay));
            $db->prepare('UPDATE alarms SET next_due_at = ?, next_slot = ? WHERE device_id = ? AND alarm_id = ?')
                ->execute([$next[0] ?? null, $next[1] ?? null, $r['device_id'], $r['alarm_id']]);
        }
        return $done;
    }

    private static function log(PDO $db, array $r, int $due, string $status, string $detail, int $nowMs): void
    {
        $db->prepare('INSERT INTO push_log (device_id, alarm_id, due_at, status, detail, created_at) VALUES (?, ?, ?, ?, ?, ?)')
            ->execute([$r['device_id'], $r['alarm_id'], $due, $status, $detail, Db::now($nowMs)]);
    }

    /** Drops push log entries older than 30 days. */
    public static function prune(PDO $db, int $nowMs): void
    {
        $db->prepare('DELETE FROM push_log WHERE created_at < ?')->execute([Db::now($nowMs - 30 * 86400 * 1000)]);
    }
}
