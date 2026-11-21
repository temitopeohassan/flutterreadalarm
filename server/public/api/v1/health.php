<?php
// GET /api/v1/health.php: is the API up and the database reachable?
require __DIR__ . '/../../app.php';

Api::run('GET', function (array $body, PDO $db, array $config) {
    $db->query('SELECT COUNT(*) FROM devices')->fetchColumn();
    return [
        'service' => 'readalarm',
        'time' => readalarm_now_ms(),
        'push' => is_file((string)($config['firebase_service_account'] ?? '')),
    ];
});
