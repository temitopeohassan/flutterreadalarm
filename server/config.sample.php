<?php
// Copy to config.php (next to this file, outside the web root) and fill in.

return [
    // MySQL/MariaDB on most Apache hosting:
    'db_dsn' => 'mysql:host=localhost;dbname=readalarm;charset=utf8mb4',
    'db_user' => 'readalarm',
    'db_password' => 'change-me',
    // Or SQLite (the folder must be writable by Apache and by cron):
    // 'db_dsn' => 'sqlite:' . __DIR__ . '/data/readalarm.sqlite',

    // Shared with the app (the build's pushApiKey). Keeps casual callers
    // out; it's in the app, so it isn't a real secret: each device also
    // proves itself with its own secret.
    'api_key' => 'change-me-to-a-long-random-string',

    // Firebase → Project settings → Service accounts → Generate new
    // private key. Keep it outside the web root.
    'service_account' => __DIR__ . '/firebase-service-account.json',
];
