<?php
// Request handling shared by the endpoints in public/api/v1.

declare(strict_types=1);

final class ApiError extends Exception
{
    public function __construct(public readonly int $status, string $message)
    {
        parent::__construct($message);
    }
}

final class Api
{
    private const MAX_BODY = 256 * 1024;

    /**
     * Runs one endpoint: checks the method and the app key, gives
     * $handler the JSON body and a database, and answers with what it
     * returns, as JSON.
     */
    public static function run(string $method, callable $handler): void
    {
        header('Content-Type: application/json; charset=utf-8');
        header('Cache-Control: no-store');
        try {
            if (($_SERVER['REQUEST_METHOD'] ?? '') !== $method) {
                throw new ApiError(405, "$method only");
            }
            $config = readalarm_config();
            $key = (string)($config['api_key'] ?? '');
            $given = $_SERVER['HTTP_X_READALARM_KEY'] ?? '';
            if ($key !== '' && !hash_equals($key, (string)$given)) {
                throw new ApiError(401, 'bad app key');
            }
            $body = [];
            if ($method === 'POST') {
                $raw = file_get_contents('php://input', false, null, 0, self::MAX_BODY + 1);
                if (strlen((string)$raw) > self::MAX_BODY) throw new ApiError(413, 'too large');
                $body = json_decode((string)$raw, true);
                if (!is_array($body)) throw new ApiError(400, 'body must be a JSON object');
            }
            $result = $handler($body, Db::connect($config), $config);
            http_response_code(200);
            echo json_encode(['ok' => true] + $result, JSON_UNESCAPED_SLASHES);
        } catch (ApiError $e) {
            http_response_code($e->status);
            echo json_encode(['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            error_log('ReadAlarm API: ' . $e);
            http_response_code(500);
            echo json_encode(['ok' => false, 'error' => 'server error']);
        }
    }
}
