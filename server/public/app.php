<?php
// Finds the server's code (src/) and loads it. Works when:
// - the whole server folder is uploaded and the domain points at public/;
// - public/'s files are copied into public_html and the rest of the server
//   folder is uploaded next to it as readalarm-server/ (outside the web).

declare(strict_types=1);

(function () {
    foreach ([__DIR__ . '/../src', dirname(__DIR__) . '/readalarm-server/src'] as $dir) {
        if (is_file("$dir/bootstrap.php")) {
            require_once "$dir/bootstrap.php";
            return;
        }
    }
    http_response_code(500);
    header('Content-Type: application/json');
    exit('{"ok":false,"error":"server code not found: see public/app.php"}');
})();
