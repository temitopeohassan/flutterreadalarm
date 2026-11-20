# ReadAlarm push server (readalarm.net)

A PHP + MySQL server that keeps each phone's reading alarms and sends a
push when one is due. The app still rings every alarm itself; the push is
a backup for phones that hold back or drop the alarms of closed apps
(Tecno, Infinix, Xiaomi and others). If the phone already rang the alarm,
or the user already opened, silenced or snoozed it, the push does nothing.

```
 app ── POST /api/v1/alarm-save.php ──► readalarm.net (PHP) ── MySQL
  │     (on every new or changed alarm;        │
  │      alarms-sync.php at start-up)          │ cron, every minute:
  │                                            │ alarms due a minute ago?
  ▼                                            ▼
 rings the alarm unless it ◄── Firebase Cloud Messaging (high priority)
 already rang (same notification id)
```

Needs PHP 8.1+ with `pdo_mysql`, `curl` and `openssl` (standard on cPanel
hosting), MySQL or MariaDB, HTTPS, and cron.

## Endpoints

All answers are JSON: `{"ok": true, ...}` or `{"ok": false, "error": "..."}`.
Every POST sends the header `X-ReadAlarm-Key: <api_key>` and a JSON body
with the phone:

```json
"device": {
  "id": "0b6f2a3e-1c2d-4e5f-8a9b-0c1d2e3f4a5b",
  "secret": "64 random hex characters",
  "platform": "android",
  "timezone": "Africa/Lagos",
  "app_version": "0.1.0",
  "push_token": "Firebase token, or null"
}
```

The first request registers the phone; after that, the same `secret` must
come with its `id`. There are no accounts or names.

| Endpoint | Body | Does |
|---|---|---|
| `GET /api/v1/health.php` | | Checks the API and the database |
| `POST /api/v1/register.php` | `device` | Registers the phone, updates its push token |
| `POST /api/v1/alarm-save.php` | `device`, `alarm` | Creates or updates one alarm |
| `POST /api/v1/alarm-delete.php` | `device`, `alarm_id` | Removes one alarm |
| `POST /api/v1/alarms-sync.php` | `device`, `alarms: [...]` | Replaces all of the phone's alarms |
| `POST /api/v1/alarms.php` | `device` | Lists the phone's alarms with their next push |

An alarm:

```json
{
  "id": "a1",
  "enabled": true,
  "hour": 7, "minute": 30,
  "days": [0, 2, 4],
  "once_at": null,
  "title": "Time to read",
  "body": "The Quiet Morning · Read 15 min",
  "payload": "{...}"
}
```

`days` are 0 = Monday … 6 = Sunday; empty for a one-off, which rings at
`once_at` (milliseconds since 1970). `payload` is the app's own alarm data,
handed back in the push.

## Setting up readalarm.net

1. **Firebase project** (free) at console.firebase.google.com:
   - Add an Android app with package name `com.readalarm.readalarm`.
   - From Project settings, note the *Web API key*, the Android app's
     *App ID* (`1:…:android:…`), the *Project ID* and the *Project number*
     (the sender id). There's no need to download google-services.json.
   - Project settings → Service accounts → **Generate new private key**:
     save it as `firebase-service-account.json`.
2. **Database**: in the hosting panel create a MySQL database and user,
   then import `schema.sql` (phpMyAdmin → Import).
3. **Upload** this `server` folder to your home folder as
   `readalarm-server/` (next to `public_html`, not inside it). Then either:
   - point readalarm.net's document root at `readalarm-server/public`, or
   - copy the contents of `readalarm-server/public/` into `public_html/`.
     `public/app.php` finds the code in `../readalarm-server/src`.
4. **Config**: copy `config.sample.php` to `config.php` in
   `readalarm-server/`, and fill in the database details and a long random
   `api_key` (e.g. `php -r 'echo bin2hex(random_bytes(24));'`). Put
   `firebase-service-account.json` in the same folder.
5. **Cron** (hosting panel → Cron Jobs), every minute:
   ```
   * * * * * php /home/USER/readalarm-server/cron/send_due.php >> /home/USER/readalarm-server/logs/cron.log 2>&1
   ```
6. **Check**: https://readalarm.net/api/v1/health.php answers
   `{"ok":true,"service":"readalarm",...,"push":true}` (`push` is true once
   the Firebase key is in place).
7. **The app**: add these GitHub Actions secrets (repository Settings →
   Secrets and variables → Actions); the next CI build sends alarms and
   receives pushes:

   | Secret | Value |
   |---|---|
   | `READALARM_API_KEY` | the `api_key` from config.php |
   | `FIREBASE_API_KEY` | the Web API key |
   | `FIREBASE_APP_ID` | the Android App ID |
   | `FIREBASE_SENDER_ID` | the Project number |
   | `FIREBASE_PROJECT_ID` | the Project ID |
   | `READALARM_API_URL` | only if not `https://readalarm.net` |

   Without the Firebase secrets the app still sends its alarms to the
   server, but gets no pushes. A problem report (Settings → Send a problem
   report) shows the server status under "PUSH FROM READALARM.NET", and the
   `push_log` table shows each push the cron job sent.

## iPhone

Pushes to iPhones need a paid Apple developer account (an APNs key
uploaded to Firebase). Apps installed with SideStore can't receive them,
so iPhone push is off: `ios_push` in config.php, and the app's
`READALARM_IOS_PUSH` build setting. iPhones still send their alarms to the
server, and their alarms ring from the phone as before.

## Files

- `public/api/v1/*.php`: the endpoints; `public/app.php` finds the code.
- `src/`: `Store.php` (devices, alarms), `Schedule.php` (next ring, in the
  phone's time zone), `Sender.php` (what's due), `Fcm.php` (Firebase).
- `cron/send_due.php`: sends due pushes, checking every 10 seconds.
- `schema.sql`: tables `devices`, `alarms`, `push_log`.
- `tests/run.php`: `php server/tests/run.php` (SQLite, no network).
