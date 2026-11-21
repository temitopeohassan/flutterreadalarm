<?php
// Database access (MySQL on the server; SQLite in the tests).

declare(strict_types=1);

final class Db
{
    public static function connect(array $config): PDO
    {
        $db = new PDO($config['db_dsn'], $config['db_user'] ?? null, $config['db_password'] ?? null, [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
        ]);
        if ($db->getAttribute(PDO::ATTR_DRIVER_NAME) === 'mysql') {
            $db->exec("SET time_zone = '+00:00'");
        }
        return $db;
    }

    /** Now, UTC, as MySQL DATETIME text. */
    public static function now(?int $ms = null): string
    {
        $s = $ms === null ? time() : intdiv($ms, 1000);
        return gmdate('Y-m-d H:i:s', $s);
    }
}
