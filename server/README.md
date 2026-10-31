# ReadAlarm backup push server

A small PHP server that sends each reading alarm as a high-priority
Firebase push at its time: a backup for phones that hold back or drop
alarms of closed apps. The design is in
[docs/alarm-reliability.md](../docs/alarm-reliability.md).

Needs PHP 8.1+ with `pdo_mysql` (or `pdo_sqlite`), `curl` and `openssl`,
Apache, HTTPS (Android refuses plain http), and cron.

## Set up

1. **Firebase project** (free): console.firebase.google.com → Add project.
   Add an Android app with package name `com.readalarm.readalarm`. From its
   settings note the *App ID* (`1:…:android:…`), *Web API key*, *Project
   ID* and *Project number* (the sender id). There's no need to download
   google-services.json: the build takes these four values.
2. **Service account key**: Project settings → Service accounts → Generate
   new private key. Save it as `server/firebase-service-account.json`.
3. **Upload** the `server` folder, *outside* the web root if you can, and
   point Apache at `server/public` (or a subdomain, e.g.
   `https://push.example.com` with `DocumentRoot /path/to/server/public`).
   If the folder must sit inside the web root, `server/.htaccess` keeps
   everything but `public/` private (needs `AllowOverride All`).
4. **Config**: copy `config.sample.php` to `config.php` and fill in the
   database and a long random `api_key`
   (`php -r 'echo bin2hex(random_bytes(24));'`).
5. **Database**: create it, then run `mysql readalarm < schema.sql`
   (the cron script also creates the tables if they're missing).
6. **Cron**, every minute:
   ```
   * * * * * php /path/to/server/cron/send_due.php >> /path/to/server/data/cron.log 2>&1
   ```
7. **Check**: `curl https://push.example.com/api/sync.php` answers
   `{"error":"POST only"}`.
8. **The app**: add these GitHub Actions secrets (Settings → Secrets and
   variables → Actions), and the next CI build has the backup on:

   | Secret | Value |
   |---|---|
   | `PUSH_SERVER_URL` | `https://push.example.com` (no trailing `/api`) |
   | `PUSH_API_KEY` | the `api_key` from config.php |
   | `FIREBASE_APP_ID` | the App ID |
   | `FIREBASE_API_KEY` | the Web API key |
   | `FIREBASE_PROJECT_ID` | the Project ID |
   | `FIREBASE_SENDER_ID` | the Project number |

   A problem report from the app then says "Backup push: On. Last sent to
   the server: …", and cron.log shows `{"sent":1,…}` at each alarm.

## Files

- `public/api/sync.php`: the app sends its alarms here when they change.
- `cron/send_due.php`: sends the pushes; checks every 5 seconds.
- `lib/`: the code (`sync.php`, `schedule.php`, `fcm.php`, `db.php`).
- `schema.sql`: two tables, `devices` and `alarms`.
- `tests/run.php`: `php server/tests/run.php` (SQLite, no network).
