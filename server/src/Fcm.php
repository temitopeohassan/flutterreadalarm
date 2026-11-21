<?php
// Firebase Cloud Messaging (HTTP v1), signed in with the Firebase
// project's service account key. Needs PHP's curl and openssl extensions.

declare(strict_types=1);

final class Fcm
{
    private array $account;
    private ?string $accessToken = null;
    private int $expiresAt = 0;

    public function __construct(string $serviceAccountFile)
    {
        $account = is_file($serviceAccountFile)
            ? json_decode((string)file_get_contents($serviceAccountFile), true) : null;
        if (!is_array($account) || empty($account['private_key']) || empty($account['client_email'])
            || empty($account['project_id'])) {
            throw new RuntimeException("Not a Firebase service account key: $serviceAccountFile");
        }
        $this->account = $account;
    }

    /**
     * Sends an alarm's push. Returns ['ok'], ['gone'] (the app was
     * uninstalled, or the token replaced) or ['error', detail].
     *
     * Android: a data message at high priority, which wakes the app even
     * when it's closed; the app rings the alarm unless it already rang.
     * iPhone: a visible notification with the alarm sound.
     */
    public function sendAlarm(string $token, string $platform, array $alarm, int $dueMs, int $slot): array
    {
        $data = [
            'type' => 'alarm',
            'alarm_id' => $alarm['alarm_id'],
            'slot' => (string)$slot,
            'due' => (string)$dueMs,
            'title' => $alarm['title'],
            'body' => $alarm['body'],
            'payload' => $alarm['payload'],
        ];
        $message = ['token' => $token, 'data' => $data];
        if ($platform === 'ios') {
            $message['apns'] = [
                'headers' => ['apns-priority' => '10', 'apns-push-type' => 'alert',
                    'apns-collapse-id' => substr('readalarm-' . $alarm['alarm_id'], 0, 64)],
                'payload' => ['aps' => [
                    'alert' => ['title' => $alarm['title'], 'body' => $alarm['body']],
                    'sound' => 'readalarm_alarm.wav',
                    'category' => 'readalarm_alarm',
                    'interruption-level' => 'time-sensitive',
                ]],
            ];
        } else {
            // Useless after 10 minutes: the moment has passed.
            $message['android'] = ['priority' => 'HIGH', 'ttl' => '600s'];
        }
        $url = 'https://fcm.googleapis.com/v1/projects/' . rawurlencode($this->account['project_id']) . '/messages:send';
        [$code, $body] = $this->post($url, (string)json_encode(['message' => $message]), [
            'Content-Type: application/json',
            'Authorization: Bearer ' . $this->token(),
        ]);
        if ($code === 200) return ['ok'];
        $error = json_decode($body, true);
        $status = $error['error']['details'][0]['errorCode'] ?? $error['error']['status'] ?? '';
        if ($code === 404 || $status === 'UNREGISTERED') return ['gone'];
        return ['error', substr("$code $status " . ($error['error']['message'] ?? $body), 0, 250)];
    }

    /** An OAuth access token for FCM, kept until shortly before it expires. */
    private function token(): string
    {
        if ($this->accessToken !== null && time() < $this->expiresAt - 60) return $this->accessToken;
        $now = time();
        $b64 = fn(string $s) => rtrim(strtr(base64_encode($s), '+/', '-_'), '=');
        $tokenUri = $this->account['token_uri'] ?? 'https://oauth2.googleapis.com/token';
        $unsigned = $b64((string)json_encode(['alg' => 'RS256', 'typ' => 'JWT'])) . '.' . $b64((string)json_encode([
            'iss' => $this->account['client_email'],
            'scope' => 'https://www.googleapis.com/auth/firebase.messaging',
            'aud' => $tokenUri,
            'iat' => $now,
            'exp' => $now + 3600,
        ]));
        if (!openssl_sign($unsigned, $signature, $this->account['private_key'], OPENSSL_ALGO_SHA256)) {
            throw new RuntimeException('Could not sign with the Firebase key');
        }
        [$code, $body] = $this->post($tokenUri, http_build_query([
            'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
            'assertion' => $unsigned . '.' . $b64($signature),
        ]), ['Content-Type: application/x-www-form-urlencoded']);
        $answer = json_decode($body, true);
        if ($code !== 200 || empty($answer['access_token'])) {
            throw new RuntimeException("Google sign-in failed ($code): " . substr($body, 0, 200));
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
