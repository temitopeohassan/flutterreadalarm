-- ReadAlarm backup push: devices and their alarm times.
-- Plain SQL that works in MySQL/MariaDB and SQLite.

-- One row per installed app. No names or accounts: a random id the app
-- made, a hash of its secret, its push token and its time zone.
CREATE TABLE IF NOT EXISTS devices (
    device_id   VARCHAR(64)  NOT NULL PRIMARY KEY,
    secret_hash VARCHAR(255) NOT NULL,
    token       TEXT         NOT NULL,
    tz          VARCHAR(64)  NOT NULL,
    updated_at  BIGINT       NOT NULL
);

-- One row per ring. weekday 1-7 (Monday-Sunday) repeats weekly at
-- hour:minute in the device's time zone; 0 rings once. next_at is the next
-- ring, in milliseconds since 1970 (UTC).
CREATE TABLE IF NOT EXISTS alarms (
    device_id VARCHAR(64) NOT NULL,
    alarm_id  BIGINT      NOT NULL,
    weekday   INT         NOT NULL,
    hour      INT         NOT NULL,
    minute    INT         NOT NULL,
    next_at   BIGINT      NOT NULL,
    PRIMARY KEY (device_id, alarm_id)
);

CREATE INDEX alarms_next_at ON alarms (next_at);
