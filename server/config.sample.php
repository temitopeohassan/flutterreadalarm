<?php
// Copy to config.php (same folder) and fill in. Keep config.php and the
// Firebase key outside public_html: only public/ is for the web.

return [
    // MySQL from your hosting panel (Databases → MySQL).
    'db_dsn' => 'mysql:host=localhost;dbname=readalarm;charset=utf8mb4',
    'db_user' => 'readalarm',
    'db_password' => 'change-me',

    // Sent by the app in X-ReadAlarm-Key (the build's READALARM_API_KEY).
    // Keeps casual callers out; it is inside the app, so it isn't a real
    // secret: each device also proves itself with its own secret. '' turns
    // the check off.
    'api_key' => 'change-me-to-a-long-random-string',

    // Firebase console → Project settings → Service accounts → Generate new
    // private key. Store it next to this file, not in public_html.
    'firebase_service_account' => __DIR__ . '/firebase-service-account.json',

    // The app rings each alarm itself; the push is a backup that rings it
    // if the phone held the alarm back. It is sent this long after the
    // alarm's time, so an alarm that rang on time isn't rung again.
    'send_delay_seconds' => 60,

    // Pushes more than this late are dropped: the moment has passed.
    'stale_after_seconds' => 15 * 60,

    // iPhones: only with a paid Apple developer account (APNs key uploaded
    // to Firebase). Apps installed with SideStore can't receive pushes.
    'ios_push' => false,
];
