<?php
// Firebase Cloud Messaging (HTTP v1), signed in with the Firebase project's
// service account key. Needs PHP's curl and openssl extensions.

declare(strict_types=1);

final class Fcm
{
    private array $account;
    private ?string $accessToken = null;
    private int $expiresAt = 0;

    public function __construct(string $serviceAccountFile)
    {
        $account = json_decode((string)file_get_contents($serviceAccountFile), true);
        if (!is_array($account) || empty($account['private_key']) || empty($account['client_email'])
            || empty($account['project_id'])) {
            throw new RuntimeException("Not a service account key: $serviceAccountFile");
        }
        $this->account = $account;
    }

    /** Sends the ring push. Returns 'ok', 'gone' (app uninstalled) or 'error'. */
    public function sendRing(string $token, int $alarmId, int $dueMs): string
    {
        $message = [
            'message' => [
                'token' => $token,
                // Data only, so the app decides what to show.
                'data' => ['type' => 'ring', 'id' => (string)$alarmId, 'due' => (string)$dueMs],
                // High priority wakes a sleeping phone; useless after 10 min.
                'android' => ['priority' => 'HIGH', 'ttl' => '600s'],
            ],
        ];
        $url = 'https://fcm.googleapis.com/v1/projects/' . rawurlencode($this->account['project_id'])
            . '/messages:send';
        [$code, $body] = $this->post($url, json_encode($message), [
            'Content-Type: application/json',
            'Authorization: Bearer ' . $this->token(),
        ]);
        if ($code === 200) return 'ok';
        $error = json_decode($body, true);
        $status = $error['error']['details'][0]['errorCode'] ?? $error['error']['status'] ?? '';
        if ($code === 404 || $status === 'UNREGISTERED') return 'gone';
        error_log("ReadAlarm push failed ($code): $body");
        return 'error';
    }

    /** An OAuth access token for FCM, kept until shortly before it expires. */
    private function token(): string
    {
        if ($this->accessToken !== null && time() < $this->expiresAt - 60) return $this->accessToken;
        $now = time();
        $b64 = fn(string $s) => rtrim(strtr(base64_encode($s), '+/', '-_'), '=');
        $tokenUri = $this->account['token_uri'] ?? 'https://oauth2.googleapis.com/token';
        $unsigned = $b64(json_encode(['alg' => 'RS256', 'typ' => 'JWT'])) . '.' . $b64(json_encode([
            'iss' => $this->account['client_email'],
            'scope' => 'https://www.googleapis.com/auth/firebase.messaging',
            'aud' => $tokenUri,
            'iat' => $now,
            'exp' => $now + 3600,
        ]));
        if (!openssl_sign($unsigned, $signature, $this->account['private_key'], OPENSSL_ALGO_SHA256)) {
            throw new RuntimeException('Could not sign with the service account key');
        }
        [$code, $body] = $this->post($tokenUri, http_build_query([
            'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
            'assertion' => $unsigned . '.' . $b64($signature),
        ]), ['Content-Type: application/x-www-form-urlencoded']);
        $answer = json_decode($body, true);
        if ($code !== 200 || empty($answer['access_token'])) {
            throw new RuntimeException("Google sign-in failed ($code): $body");
        }
        $this->accessToken = $answer['access_token'];
        $this->expiresAt = $now + (int)($answer['expires_in'] ?? 3600);
        return $this->accessToken;
    }

    private function post(string $url, string $body, array $headers): array
    {
        $c = curl_init($url);
        curl_setopt_array($c, [
            CURLOPT_POST => true,
            CURLOPT_POSTFIELDS => $body,
            CURLOPT_HTTPHEADER => $headers,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => 15,
        ]);
        $response = curl_exec($c);
        $code = (int)curl_getinfo($c, CURLINFO_RESPONSE_CODE);
        $error = curl_error($c);
        curl_close($c);
        if ($response === false) throw new RuntimeException("Network error: $error");
        return [$code, (string)$response];
    }
}
