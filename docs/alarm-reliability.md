# Making alarms ring on every phone

Some phones (Tecno, Infinix, itel, Xiaomi, Oppo and others) close apps in
the background and hold back or drop the alarms of closed apps. On the
client's Tecno LE6 a test alarm rang 15 minutes late, and alarms were lost
after the phone closed ReadAlarm for memory. Asking each user to find
their maker's auto-start setting doesn't scale, so ReadAlarm has three
layers, each covering the last one's gaps:

```
                 alarm time
                     │
 1. Alarm clock ─────┼──► Android opens ReadAlarm's alarm screen
    (AlarmEngine)    │    (+20 s fallback broadcast posts the ringing
                     │     notification if the screen was blocked)
                     │
 2. Standby ─────────┤    keeps ReadAlarm running while an alarm is set,
    (AlarmKeeper)    │    so the phone doesn't close it or hold back its
                     │    alarms; restarted by Android if it's closed
                     │
 3. Backup push ─────┘    ReadAlarm's server sends a high-priority Firebase
    (PushBackup +         push at the alarm's time; Google Play services
     server/)             wakes the app, which rings if Android hasn't
```

Whichever comes first rings; the others see that this ring already
sounded and stay quiet (`AlarmEngine.ring` records each ring's time).

## 1. Alarm clock (AlarmEngine.kt)

`AlarmManager.setAlarmClock`, the call clock apps use, opening ReadAlarm's
screen directly. Stored alarms are set again after a reboot, an update, a
clock or time-zone change, and whenever the standby restarts.

## 2. Standby (AlarmKeeper.kt)

While any alarm is set, a foreground service runs with a quiet
notification: "Next reading: Sat 7:00 PM". To Android, an app with a
foreground service is in use: it's rarely closed for memory, and its
alarms aren't deferred. If the phone does close it, `START_STICKY` has
Android restart it, and it sets the alarms again. It stops when no alarm
is set. Nothing for the user to do.

- Costs: a permanent (silent, low-priority) notification, and a little
  memory. It does no work while waiting, so battery use is negligible.
- Android 14+ requires a type: `systemExempted` (alarm apps holding the
  exact-alarm permission), else `specialUse`. **Google Play**: declare the
  foreground service in Play Console → App content → Foreground service
  permissions, describing it as keeping the user's scheduled alarms ready,
  with a short video of the notification.
- Limits: swiping ReadAlarm away in recent apps still force-stops it on
  Tecno (Android then cancels its alarms too, and only opening the app
  again restores them). Locking it in recent apps prevents that, and the
  backup push covers it once that's on.

## 3. Backup push (PushBackup.kt + server/)

```
 app ── POST /api/sync.php ──► PHP server ── MySQL: devices, alarms
  ▲   (when alarms change:          │
  │    id, weekday, hour,           │ cron, every 5 s:
  │    minute, next ring,           │ rings due now?
  │    time zone, push token)       ▼
  └──── FCM high-priority ◄── Firebase Cloud Messaging (HTTP v1)
        data push {type: ring, id, due}
```

- **App side** (`PushBackup.kt`): sends the alarms to the server a few
  seconds after any change, and again after each ring (the server then
  knows the next one). On a push it calls `AlarmEngine.ring` with the due
  time: it rings only if that is the alarm's current ring and it hasn't
  sounded yet, and not if the push is over 15 minutes old. It also starts
  the standby (a high-priority push may do that from the background).
- **Server** (`server/`): stores each device's alarms with their next
  ring in UTC, and a cron script sends the push within ~5 seconds of each
  one, then moves weekly alarms on a week in the device's time zone
  (daylight saving safe). A failed push is retried for 10 minutes;
  uninstalled apps are forgotten.
- **Privacy**: only times, a time zone, a random device id and the push
  token reach the server: no names, books or accounts. Each device has
  its own secret, so one device can't change another's alarms. Mention it
  in the privacy policy and Play's data-safety form ("app activity",
  not shared, for app functionality).
- **Off by default**: the build includes it, but it does nothing until
  given a Firebase project and the server's address. Setup:
  [server/README.md](../server/README.md).
- **Limits**: needs internet at alarm time, and Google Play services.
  Some makers also hold back pushes to force-stopped apps, which is why it
  is a backup and not the main path.

## Checking it works

The alarm test closes ReadAlarm and passes only if the test alarm opens it
within 2 minutes of its time. A problem report (Settings → Send a problem
report) shows the standby and backup-push status and, in the engine log,
which layer rang each alarm ("Android opened ReadAlarm", "fallback
broadcast" or "backup push from the server").
