-- schema.sql for SQLite, used by the tests.
CREATE TABLE devices (
    id TEXT PRIMARY KEY, secret_hash TEXT NOT NULL, platform TEXT NOT NULL, push_token TEXT NULL,
    timezone TEXT NOT NULL, app_version TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL, last_seen_at TEXT NOT NULL
);
CREATE TABLE alarms (
    device_id TEXT NOT NULL REFERENCES devices (id) ON DELETE CASCADE, alarm_id TEXT NOT NULL,
    enabled INTEGER NOT NULL DEFAULT 1, hour INTEGER NOT NULL, minute INTEGER NOT NULL, days TEXT NOT NULL DEFAULT '',
    once_at INTEGER NULL, title TEXT NOT NULL, body TEXT NOT NULL DEFAULT '', payload TEXT NOT NULL,
    next_due_at INTEGER NULL, next_slot INTEGER NULL, updated_at TEXT NOT NULL, PRIMARY KEY (device_id, alarm_id)
);
CREATE TABLE push_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT, device_id TEXT NOT NULL, alarm_id TEXT NOT NULL, due_at INTEGER NOT NULL,
    status TEXT NOT NULL, detail TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL
);
