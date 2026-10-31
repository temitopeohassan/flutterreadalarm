<?php
// POST /api/sync.php: the app's alarms and push token (see lib/sync.php).

declare(strict_types=1);

require __DIR__ . '/../../lib/db.php';
require __DIR__ . '/../../lib/sync.php';

header('Content-Type: application/json');
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['error' => 'POST only']);
    exit;
}
$config = require __DIR__ . '/../../config.php';
$raw = file_get_contents('php://input', false, null, 0, 64 * 1024);
try {
    [$status, $response] = readalarm_sync(
        readalarm_db($config),
        $config,
        $_SERVER['HTTP_X_READALARM_KEY'] ?? null,
        json_decode((string)$raw, true),
        (int)(microtime(true) * 1000),
    );
} catch (Throwable $e) {
    error_log('ReadAlarm sync: ' . $e->getMessage());
    [$status, $response] = [500, ['error' => 'server error']];
}
http_response_code($status);
echo json_encode($response);
