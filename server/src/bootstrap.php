<?php
// Loads the server's code and its config.php.

declare(strict_types=1);

require __DIR__ . '/Db.php';
require __DIR__ . '/Schedule.php';
require __DIR__ . '/Api.php';
require __DIR__ . '/Store.php';
require __DIR__ . '/Fcm.php';
require __DIR__ . '/Sender.php';

function readalarm_config(): array
{
    static $config = null;
    if ($config === null) {
        $file = dirname(__DIR__) . '/config.php';
        if (!is_file($file)) throw new RuntimeException('config.php is missing: copy config.sample.php');
        $config = require $file;
    }
    return $config;
}

function readalarm_now_ms(): int
{
    return (int)floor(microtime(true) * 1000);
}
