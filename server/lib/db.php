<?php
// Database access. Works with MySQL/MariaDB (the usual on Apache hosting)
// and SQLite (tests, small servers): see config.sample.php.

declare(strict_types=1);

function readalarm_db(array $config): PDO
{
    $db = new PDO($config['db_dsn'], $config['db_user'] ?? null, $config['db_password'] ?? null, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);
    return $db;
}

/** Creates the tables if they don't exist (also: schema.sql). */
function readalarm_install(PDO $db): void
{
    $schema = preg_replace('/--.*$/m', '', file_get_contents(__DIR__ . '/../schema.sql'));
    foreach (explode(';', $schema) as $sql) {
        $sql = trim($sql);
        if ($sql === '') continue;
        try {
            $db->exec($sql);
        } catch (PDOException $e) {
            // MySQL has no CREATE INDEX IF NOT EXISTS: the index is there.
            if (stripos($sql, 'CREATE INDEX') !== 0) throw $e;
        }
    }
}
