<?php
// When an alarm rings next, in its phone's time zone.

declare(strict_types=1);

final class Schedule
{
    /** The app's notification slot for a one-off ring. */
    public const ONCE_SLOT = 7;

    /**
     * The next ring after $afterMs (ms since 1970), as [dueMs, slot], or
     * null if there's none (switched off, or a one-off that has passed).
     *
     * @param int[] $days weekdays, 0 = Monday … 6 = Sunday; empty = one-off.
     */
    public static function next(
        bool $enabled, array $days, int $hour, int $minute, ?int $onceAt, string $tz, int $afterMs
    ): ?array {
        if (!$enabled) return null;
        if ($days === []) {
            return $onceAt !== null && $onceAt > $afterMs ? [$onceAt, self::ONCE_SLOT] : null;
        }
        $zone = new DateTimeZone($tz);
        $start = (new DateTimeImmutable('@' . intdiv($afterMs, 1000)))->setTimezone($zone);
        for ($i = 0; $i <= 7; $i++) {
            $day = $start->setTime(0, 0)->modify("+$i days");
            $weekday = (int)$day->format('N') - 1; // 0 = Monday
            if (!in_array($weekday, $days, true)) continue;
            $at = $day->setTime($hour, $minute, 0);
            $ms = $at->getTimestamp() * 1000;
            if ($ms > $afterMs) return [$ms, $weekday];
        }
        return null;
    }
}
