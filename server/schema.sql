-- ReadAlarm push server: MySQL / MariaDB schema (utf8mb4, InnoDB).
-- Import once: mysql -u USER -p DATABASE < schema.sql
-- (or phpMyAdmin → your database → Import).

-- One row per installed app. No names or accounts: a random id the app
-- made, a hash of its secret, its push token and its time zone.
CREATE TABLE IF NOT EXISTS devices (
    id           CHAR(36)     NOT NULL PRIMARY KEY,
    secret_hash  VARCHAR(255) NOT NULL,
    platform     VARCHAR(16)  NOT NULL,          -- 'android' or 'ios'
    push_token   TEXT         NULL,              -- Firebase Cloud Messaging token
    timezone     VARCHAR(64)  NOT NULL,          -- IANA, e.g. 'Africa/Lagos'
    app_version  VARCHAR(32)  NOT NULL DEFAULT '',
    created_at   DATETIME     NOT NULL,
    last_seen_at DATETIME     NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- One row per reading alarm. days: weekdays it repeats on, '0'..'6' for
-- Monday..Sunday, comma separated; empty for a one-off ringing at once_at.
-- next_due_at / next_slot: its next ring (ms since 1970, UTC) and which of
-- the app's notification slots that is (0-6 weekday, 7 one-off).
CREATE TABLE IF NOT EXISTS alarms (
    device_id    CHAR(36)     NOT NULL,
    alarm_id     VARCHAR(64)  NOT NULL,
    enabled      TINYINT(1)   NOT NULL DEFAULT 1,
    hour         TINYINT      NOT NULL,
    minute       TINYINT      NOT NULL,
    days         VARCHAR(20)  NOT NULL DEFAULT '',
    once_at      BIGINT       NULL,
    title        VARCHAR(120) NOT NULL,
    body         VARCHAR(255) NOT NULL DEFAULT '',
    payload      TEXT         NOT NULL,          -- what the app needs to ring it
    next_due_at  BIGINT       NULL,
    next_slot    TINYINT      NULL,
    updated_at   DATETIME     NOT NULL,
    PRIMARY KEY (device_id, alarm_id),
    KEY alarms_next_due (next_due_at),
    CONSTRAINT alarms_device FOREIGN KEY (device_id) REFERENCES devices (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- What the cron job sent, for support (kept 30 days).
CREATE TABLE IF NOT EXISTS push_log (
    id         BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
    device_id  CHAR(36)     NOT NULL,
    alarm_id   VARCHAR(64)  NOT NULL,
    due_at     BIGINT       NOT NULL,
    status     VARCHAR(16)  NOT NULL,            -- sent, failed, stale, no_token, gone
    detail     VARCHAR(255) NOT NULL DEFAULT '',
    created_at DATETIME     NOT NULL,
    KEY push_log_device (device_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
