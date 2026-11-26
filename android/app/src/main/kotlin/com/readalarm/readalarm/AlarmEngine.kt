package com.readalarm.readalarm

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONObject
import java.io.File
import java.util.Calendar

/**
 * Reading alarms, scheduled as alarm clocks (AlarmManager.setAlarmClock),
 * which Android and phone makers' power managers let through even when
 * the app was closed, Doze included.
 *
 * At the alarm time Android sends [AlarmReceiver] a broadcast, which
 * starts [AlarmRingService]: the alarm sound and a full-screen
 * notification, before Flutter is even running. In case a phone blocks
 * that broadcast (some Tecno phones block broadcasts to closed apps), a
 * second alarm clock 20 seconds later opens ReadAlarm's screen directly,
 * which rings it. A push from readalarm.net a minute later is the last
 * backup ([PushService]).
 *
 * Each ring sounds once, whichever comes first. Alarms are stored, and put
 * back after a reboot, an update, a clock or time-zone change, and when
 * exact alarms are allowed again.
 */
object AlarmEngine {
    const val ACTION_RING = "com.readalarm.readalarm.RING"
    const val ACTION_RING_SCREEN = "com.readalarm.readalarm.RING_SCREEN"
    const val ACTION_OPEN = "com.readalarm.readalarm.OPEN_ALARM"
    const val ACTION_START = "com.readalarm.readalarm.START_ALARM"
    const val ACTION_SNOOZE = "com.readalarm.readalarm.SNOOZE"
    const val EXTRA_ID = "alarm_id"

    private const val PREFS = "readalarm_alarms"
    private const val RUNG = "readalarm_rung"
    private const val SCREEN_BACKUP_MS = 20_000L
    private const val SNOOZE_MS = 10 * 60_000L

    /** Rings within this of each other are the same ring. */
    private const val SAME_RING_MS = 10 * 60_000L

    /**
     * One ring. [weekday] 1–7 (Monday–Sunday) repeats weekly at
     * [hour]:[minute]; 0 rings once at [at] (ms since 1970).
     */
    data class Entry(
        val id: Int,
        val weekday: Int,
        val hour: Int,
        val minute: Int,
        val at: Long,
        val payload: String,
        val title: String,
        val body: String,
    ) {
        fun toJson(): String = JSONObject()
            .put("id", id).put("weekday", weekday).put("hour", hour).put("minute", minute)
            .put("at", at).put("payload", payload).put("title", title).put("body", body)
            .toString()

        companion object {
            fun fromJson(s: String): Entry? = try {
                val o = JSONObject(s)
                Entry(
                    o.getInt("id"), o.optInt("weekday"), o.optInt("hour"), o.optInt("minute"),
                    o.optLong("at"), o.getString("payload"), o.optString("title"), o.optString("body"),
                )
            } catch (e: Exception) {
                null
            }

            fun fromMap(m: Map<*, *>): Entry = Entry(
                (m["id"] as Number).toInt(),
                (m["weekday"] as Number?)?.toInt() ?: 0,
                (m["hour"] as Number?)?.toInt() ?: 0,
                (m["minute"] as Number?)?.toInt() ?: 0,
                (m["at"] as Number?)?.toLong() ?: 0L,
                m["payload"] as String,
                m["title"] as String? ?: "Time to read",
                m["body"] as String? ?: "",
            )
        }
    }

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun rung(context: Context) = context.getSharedPreferences(RUNG, Context.MODE_PRIVATE)

    fun stored(context: Context): List<Entry> =
        prefs(context).all.values.mapNotNull { (it as? String)?.let(Entry::fromJson) }

    fun entry(context: Context, id: Int): Entry? = prefs(context).getString("$id", null)?.let(Entry::fromJson)

    /** The notification id the app gives [alarmId]'s ring in [slot] (alarm_scheduler.dart). */
    fun notificationId(alarmId: String, slot: Int): Int {
        var hash = 0x811c9dc5L // FNV-1a, as in Dart
        for (c in alarmId) hash = ((hash xor c.code.toLong()) * 0x01000193L) and 0x7fffffffL
        return ((hash % 200_000_000L) * 10 + slot).toInt()
    }

    // ---- Scheduling ---------------------------------------------------

    /** The next time [e] rings after [now], or null for a past one-off. */
    fun nextTrigger(e: Entry, now: Long = System.currentTimeMillis()): Long? {
        if (e.weekday == 0) return if (e.at > now) e.at else null
        val c = Calendar.getInstance()
        c.timeInMillis = now
        c.set(Calendar.HOUR_OF_DAY, e.hour)
        c.set(Calendar.MINUTE, e.minute)
        c.set(Calendar.SECOND, 0)
        c.set(Calendar.MILLISECOND, 0)
        // Calendar: Sunday = 1 … Saturday = 7. Ours: Monday = 1 … Sunday = 7.
        val target = if (e.weekday == 7) Calendar.SUNDAY else e.weekday + 1
        for (i in 0..7) {
            if (c.get(Calendar.DAY_OF_WEEK) == target && c.timeInMillis > now) return c.timeInMillis
            c.add(Calendar.DAY_OF_YEAR, 1)
        }
        return null
    }

    private const val IMMUTABLE = PendingIntent.FLAG_IMMUTABLE

    private fun ringBroadcast(context: Context, id: Int, create: Boolean = true): PendingIntent? =
        PendingIntent.getBroadcast(
            context, id,
            Intent(context, AlarmReceiver::class.java).setAction(ACTION_RING).putExtra(EXTRA_ID, id),
            IMMUTABLE or (if (create) PendingIntent.FLAG_UPDATE_CURRENT else PendingIntent.FLAG_NO_CREATE),
        )

    /** ReadAlarm's screen for alarm [id] ([action]: open, start or the backup ring). */
    fun screenIntent(context: Context, action: String, id: Int): PendingIntent =
        PendingIntent.getActivity(
            context, id,
            Intent(context, MainActivity::class.java).setAction(action).putExtra(EXTRA_ID, id)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

    fun snoozeIntent(context: Context, id: Int): PendingIntent =
        PendingIntent.getBroadcast(
            context, id,
            Intent(context, AlarmReceiver::class.java).setAction(ACTION_SNOOZE).putExtra(EXTRA_ID, id),
            IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

    /** Stores and schedules [e], replacing any ring with its id. */
    fun set(context: Context, e: Entry) {
        prefs(context).edit().putString("${e.id}", e.toJson()).apply()
        arm(context, e)
        changed(context)
    }

    /** The soonest ring of all stored alarms, or null if none is set. */
    fun nextRing(context: Context): Long? = stored(context).mapNotNull { nextTrigger(it) }.minOrNull()

    /** The alarms changed: keep the watchdog and the standby in step. */
    private fun changed(context: Context) {
        AlarmWatchdog.schedule(context)
        AlarmKeeper.update(context)
    }

    /** How far back the watchdog rings an alarm that didn't ring. */
    private const val CATCH_UP_MS = 15 * 60_000L

    /**
     * Puts back alarm clocks the phone dropped (Tecno and others drop them
     * when they close the app for memory), and rings an alarm whose time
     * passed in the last 15 minutes without ringing. Run every 15 minutes
     * ([AlarmWatchdog]) and when ReadAlarm opens.
     */
    fun watchdog(context: Context, reason: String) {
        val list = stored(context)
        val dropped = list.count { !isRegistered(context, it.id) }
        val stats = rung(context).edit().putLong("watchdog_at", System.currentTimeMillis())
        if (dropped > 0) {
            val times = rung(context).getInt("dropped_times", 0) + 1
            stats.putInt("dropped_times", times).putLong("dropped_at", System.currentTimeMillis())
                .putInt("dropped_last", dropped)
            log(context, "Found $dropped of ${list.size} alarm clocks dropped by the phone ($reason): putting them back")
        }
        stats.apply()
        val now = System.currentTimeMillis()
        val armed = rung(context)
        for (e in list) {
            // The ring it was set for passed recently and didn't sound.
            val due = armed.getLong("armed_${e.id}", 0L)
            if (due in (now - CATCH_UP_MS)..now) {
                log(context, "Alarm ${e.id}: its ${java.util.Date(due)} ring didn't sound ($reason)")
                ring(context, e.id, Source.WATCHDOG, due)
            }
        }
        if (dropped > 0) rearmAll(context, "dropped by the phone")
    }

    private fun arm(context: Context, e: Entry) {
        val trigger = nextTrigger(e)
        if (trigger == null) {
            cancel(context, e.id)
            log(context, "Alarm ${e.id} has no future ring: removed")
            return
        }
        val am = context.getSystemService(AlarmManager::class.java)
        val show = screenIntent(context, ACTION_OPEN, e.id)
        try {
            // The alarm clock: a broadcast, which rings without Flutter.
            am.setAlarmClock(AlarmManager.AlarmClockInfo(trigger, show), ringBroadcast(context, e.id)!!)
            // Backup: opens ReadAlarm's screen if the broadcast was blocked.
            am.setAlarmClock(
                AlarmManager.AlarmClockInfo(trigger + SCREEN_BACKUP_MS, show),
                screenIntent(context, ACTION_RING_SCREEN, e.id),
            )
            rung(context).edit().putLong("armed_${e.id}", trigger).apply()
            log(context, "Alarm ${e.id} set for ${java.util.Date(trigger)}")
        } catch (ex: SecurityException) {
            // Exact alarms not allowed (Android 12+): the next best thing.
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, trigger, ringBroadcast(context, e.id)!!)
            log(context, "Alarm ${e.id}: exact alarms not allowed, set as an inexact alarm")
        }
    }

    private fun disarm(context: Context, id: Int) {
        val am = context.getSystemService(AlarmManager::class.java)
        ringBroadcast(context, id, create = false)?.let { am.cancel(it); it.cancel() }
        am.cancel(screenIntent(context, ACTION_RING_SCREEN, id))
    }

    fun cancel(context: Context, id: Int) {
        disarm(context, id)
        prefs(context).edit().remove("$id").apply()
        AlarmKeeper.update(context)
    }

    /** Puts every stored alarm back (after a reboot or a clock change). */
    fun rearmAll(context: Context, reason: String) {
        log(context, "Putting all alarms back ($reason)")
        for (e in stored(context)) arm(context, e)
        changed(context)
    }

    /** Whether Android holds the alarm clock for [id]. */
    fun isRegistered(context: Context, id: Int): Boolean = ringBroadcast(context, id, create = false) != null

    // ---- Ringing ------------------------------------------------------

    enum class Source(val label: String) {
        ALARM("alarm clock"),
        SCREEN("backup: ReadAlarm's screen opened by Android"),
        PUSH("backup: push from readalarm.net"),
        WATCHDOG("late: the watchdog found it hadn't rung"),
    }

    /**
     * Alarm [id] is due: rings it ([AlarmRingService]) unless this ring
     * already sounded, and sets its next ring. [due]: the ring's time, for
     * a push. Returns the alarm's payload if it rang, else null.
     */
    fun ring(context: Context, id: Int, source: Source, due: Long? = null): String? {
        val prefs = rung(context)
        val occurrence = due ?: prefs.getLong("armed_$id", System.currentTimeMillis())
        val e = entry(context, id)
        val lastRang = prefs.getLong("rang_$id", 0L)
        if (Math.abs(lastRang - occurrence) < SAME_RING_MS) {
            if (source == Source.WATCHDOG) return null
            log(context, "Alarm $id (${source.label}): already rang")
            return null
        }
        if (e == null) {
            log(context, "Alarm $id (${source.label}): unknown")
            return null
        }
        log(
            context,
            "Alarm $id rang: ${source.label}" +
                if (source == Source.ALARM) "" else ", ${(System.currentTimeMillis() - occurrence) / 1000}s after its time",
        )
        prefs.edit().putString("$id", e.payload).putString("title_$id", e.title).putString("body_$id", e.body)
            .putLong("rang_$id", occurrence).apply()
        AlarmRingService.start(context, id)
        if (e.weekday == 0) {
            cancel(context, id)
        } else {
            arm(context, e) // Same day next week.
        }
        changed(context)
        return e.payload
    }

    /** The payload of the alarm that last rang as [id]. */
    fun rungPayload(context: Context, id: Int): String? =
        rung(context).getString("$id", null) ?: entry(context, id)?.payload

    fun rungTitle(context: Context, id: Int): String =
        rung(context).getString("title_$id", null) ?: entry(context, id)?.title ?: "Time to read"

    fun rungBody(context: Context, id: Int): String =
        rung(context).getString("body_$id", null) ?: entry(context, id)?.body ?: ""

    /**
     * A push from readalarm.net says an alarm is due (data from
     * server/src/Fcm.php): rings it unless the phone already rang it or
     * the user already dealt with it.
     */
    fun ringFromPush(context: Context, data: Map<String, String>) {
        if (data["type"] != "alarm") return
        val alarmId = data["alarm_id"] ?: return
        val slot = data["slot"]?.toIntOrNull() ?: 7
        val due = data["due"]?.toLongOrNull() ?: System.currentTimeMillis()
        val id = notificationId(alarmId, slot)
        if (handledSince(context, alarmId) >= due - 5 * 60_000L) {
            log(context, "Push for alarm $id: already dealt with")
            return
        }
        if (AlarmRingService.ringingId == id) return
        if (entry(context, id) == null) {
            // Not stored on the phone (e.g. data cleared): ring from the push.
            prefs(context).edit().putString(
                "$id",
                Entry(id, 0, 0, 0, due + 1, data["payload"] ?: return, data["title"] ?: "Time to read", data["body"] ?: "")
                    .toJson(),
            ).apply()
            rung(context).edit().putLong("armed_$id", due).apply()
        }
        ring(context, id, Source.PUSH, due)
    }

    /** When the app last recorded [alarmId] as opened, silenced or snoozed (alarm_scheduler.dart). */
    private fun handledSince(context: Context, alarmId: String): Long = try {
        val file = File(context.filesDir, "alarms_handled.json")
        if (file.exists()) JSONObject(file.readText()).optLong(alarmId, 0L) else 0L
    } catch (e: Exception) {
        0L
    }

    /** Stops the ringing of [ids], keeping their future rings. */
    fun dismiss(context: Context, ids: List<Int>) {
        val ringing = AlarmRingService.ringingId
        if (ringing != null && ringing in ids) AlarmRingService.stop(context)
    }

    /** Silences [id] and rings again in 10 minutes, as its snooze slot. */
    fun snooze(context: Context, id: Int) {
        log(context, "Alarm $id snoozed")
        AlarmRingService.stop(context)
        val snoozeId = id - id % 10 + 8
        val title = rungTitle(context, id)
        val body = rungBody(context, id)
        val payload = rungPayload(context, id) ?: return
        set(context, Entry(snoozeId, 0, 0, 0, System.currentTimeMillis() + SNOOZE_MS, payload, title, body))
    }

    // ---- Log, for problem reports -------------------------------------

    private const val LOG = "readalarm_engine_log"

    fun log(context: Context, message: String) {
        val p = context.getSharedPreferences(LOG, Context.MODE_PRIVATE)
        val stamp = java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.US).format(java.util.Date())
        val lines = (p.getString("log", "") ?: "").split("\n").filter { it.isNotEmpty() }
        p.edit().putString("log", (lines.takeLast(299) + "$stamp $message").joinToString("\n")).apply()
    }

    fun logText(context: Context): String =
        context.getSharedPreferences(LOG, Context.MODE_PRIVATE).getString("log", "") ?: ""

    /** Stored alarms with their next ring and whether Android holds them. */
    fun describe(context: Context): String {
        val fmt = java.text.SimpleDateFormat("EEE yyyy-MM-dd HH:mm", java.util.Locale.US)
        val list = stored(context)
        if (list.isEmpty()) return "No alarms stored."
        val exact = Build.VERSION.SDK_INT < 31 ||
            context.getSystemService(AlarmManager::class.java).canScheduleExactAlarms()
        val r = rung(context)
        val watchdog = r.getLong("watchdog_at", 0L).let { if (it == 0L) "never" else fmt.format(java.util.Date(it)) }
        val dropped = r.getInt("dropped_times", 0).let {
            if (it == 0) "never" else "$it times, last ${fmt.format(java.util.Date(r.getLong("dropped_at", 0L)))} " +
                "(${r.getInt("dropped_last", 0)} alarm clocks)"
        }
        return "Exact alarms allowed: $exact\n" +
            "Keep alarms ready: ${if (AlarmKeeper.enabled(context)) "on" else "off"}" +
            (if (AlarmKeeper.running) ", running" else ", not running") + "\n" +
            "Watchdog last checked: $watchdog\n" +
            "Phone dropped ReadAlarm's alarm clocks: $dropped\n" +
            list.joinToString("\n") { e ->
            val next = nextTrigger(e)?.let { fmt.format(java.util.Date(it)) } ?: "none"
            val kind = if (e.weekday == 0) "once" else "weekly day ${e.weekday} ${e.hour}:${"%02d".format(e.minute)}"
            "${e.id}: $kind, next $next, held by Android: ${isRegistered(context, e.id)}"
        }
    }
}
