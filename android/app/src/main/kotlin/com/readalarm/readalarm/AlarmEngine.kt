package com.readalarm.readalarm

import android.app.ActivityOptions
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.Process
import android.os.SystemClock
import org.json.JSONObject
import java.util.Calendar

/**
 * Reading alarms, scheduled the way clock apps schedule theirs: with
 * AlarmManager.setAlarmClock and an *activity* to open at the alarm time.
 *
 * Android opens ReadAlarm's screen directly when the alarm is due, even if
 * the app was closed. That path is meant for alarm clocks, so phone makers'
 * power managers rarely block it, unlike waking a closed app with a
 * background broadcast. A broadcast a little later is the fallback, in case
 * a phone blocks the activity: it posts the ringing notification.
 *
 * Alarms are stored, so they're put back after a reboot, an app update or
 * a change of time or time zone.
 */
object AlarmEngine {
    const val ACTION_RING = "com.readalarm.readalarm.RING"
    const val ACTION_OPEN = "com.readalarm.readalarm.OPEN_ALARM"
    const val ACTION_START = "com.readalarm.readalarm.START_ALARM"
    const val EXTRA_ID = "alarm_id"

    private const val ACTION_SHOW = "com.readalarm.readalarm.SHOW_ALARM"
    private const val ACTION_FALLBACK = "com.readalarm.readalarm.FALLBACK_RING"
    private const val ACTION_SNOOZE = "com.readalarm.readalarm.SNOOZE"
    private const val CHANNEL = "reading_alarms"
    private const val PREFS = "readalarm_alarms"
    private const val RUNG = "readalarm_rung"
    private const val FALLBACK_DELAY_MS = 20_000L
    private const val SNOOZE_MS = 10 * 60_000L
    private const val RING_FOR_MS = 10 * 60_000L

    // ---- Stored alarms ------------------------------------------------

    /**
     * One ring. [weekday] 1–7 (Monday–Sunday) repeats weekly at
     * [hour]:[minute]; otherwise it rings once at [at] (epoch ms).
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

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun stored(context: Context): List<Entry> =
        prefs(context).all.values.mapNotNull { (it as? String)?.let(Entry::fromJson) }

    private fun entry(context: Context, id: Int): Entry? =
        prefs(context).getString("$id", null)?.let(Entry::fromJson)

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

    private fun activityIntent(context: Context, action: String, id: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .setAction(action)
            .putExtra(EXTRA_ID, id)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        // Android 14+: let the alarm open the screen from the background.
        val options = if (Build.VERSION.SDK_INT >= 34) {
            ActivityOptions.makeBasic()
                .setPendingIntentCreatorBackgroundActivityStartMode(
                    ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED,
                ).toBundle()
        } else {
            null
        }
        return PendingIntent.getActivity(context, id, intent, flags, options)
    }

    private fun broadcastIntent(context: Context, action: String, id: Int, create: Boolean = true): PendingIntent? {
        val intent = Intent(context, AlarmReceiver::class.java).setAction(action).putExtra(EXTRA_ID, id)
        val flags = PendingIntent.FLAG_IMMUTABLE or
            (if (create) PendingIntent.FLAG_UPDATE_CURRENT else PendingIntent.FLAG_NO_CREATE)
        return PendingIntent.getBroadcast(context, id, intent, flags)
    }

    /** Stores and schedules [e], replacing any ring with its id. */
    fun set(context: Context, e: Entry) {
        prefs(context).edit().putString("${e.id}", e.toJson()).apply()
        arm(context, e)
    }

    private fun arm(context: Context, e: Entry) {
        val am = context.getSystemService(AlarmManager::class.java)
        val trigger = nextTrigger(e)
        if (trigger == null) {
            disarm(context, e.id)
            prefs(context).edit().remove("${e.id}").apply()
            return
        }
        try {
            am.setAlarmClock(
                AlarmManager.AlarmClockInfo(trigger, activityIntent(context, ACTION_SHOW, e.id)),
                activityIntent(context, ACTION_RING, e.id),
            )
            // Fallback in case this phone blocks opening the screen.
            broadcastIntent(context, ACTION_FALLBACK, e.id)?.let {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, trigger + FALLBACK_DELAY_MS, it)
            }
        } catch (ex: SecurityException) {
            // Exact alarms not allowed: the app's health check reports it.
        }
    }

    private fun disarm(context: Context, id: Int) {
        val am = context.getSystemService(AlarmManager::class.java)
        am.cancel(activityIntent(context, ACTION_RING, id))
        broadcastIntent(context, ACTION_FALLBACK, id, create = false)?.let { am.cancel(it) }
    }

    fun cancel(context: Context, id: Int) {
        disarm(context, id)
        prefs(context).edit().remove("$id").apply()
    }

    /** Puts every stored alarm back (after a reboot or a clock change). */
    fun rearmAll(context: Context) {
        for (e in stored(context)) arm(context, e)
    }

    /** Whether Android still holds the alarm for [id]. */
    fun isRegistered(context: Context, id: Int): Boolean {
        val intent = Intent(context, MainActivity::class.java).setAction(ACTION_RING)
        return PendingIntent.getActivity(
            context, id, intent, PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        ) != null
    }

    // ---- Ringing ------------------------------------------------------

    /**
     * The alarm [id] is due: ring (a notification with the alarm sound),
     * and set its next ring. [opened] is false for the fallback broadcast.
     * Returns the alarm's payload, or null if it's unknown or already rang.
     */
    fun ring(context: Context, id: Int, opened: Boolean): String? {
        val e = entry(context, id) ?: return null
        val am = context.getSystemService(AlarmManager::class.java)
        if (opened) {
            broadcastIntent(context, ACTION_FALLBACK, id, create = false)?.let { am.cancel(it) }
        } else if (isRinging(context, id)) {
            return null // The screen opened already.
        }
        notify(context, e)
        // Kept for the notification's buttons, after a one-off is removed.
        context.getSharedPreferences(RUNG, Context.MODE_PRIVATE).edit()
            .putString("$id", e.payload).apply()
        if (e.weekday == 0) {
            prefs(context).edit().remove("$id").apply()
        } else {
            arm(context, e) // Same day next week.
        }
        return e.payload
    }

    /** The payload of the alarm that last rang as [id]. */
    fun rungPayload(context: Context, id: Int): String? =
        context.getSharedPreferences(RUNG, Context.MODE_PRIVATE).getString("$id", null)
            ?: entry(context, id)?.payload

    private fun isRinging(context: Context, id: Int): Boolean =
        context.getSystemService(NotificationManager::class.java)
            .activeNotifications.any { it.id == id }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val nm = context.getSystemService(NotificationManager::class.java)
        if (nm.getNotificationChannel(CHANNEL) != null) return
        val channel = NotificationChannel(CHANNEL, "Reading alarms", NotificationManager.IMPORTANCE_HIGH)
        channel.description = "Rings when it is time to read"
        channel.setSound(
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM),
            AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build(),
        )
        channel.enableVibration(true)
        channel.lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        nm.createNotificationChannel(channel)
    }

    @Suppress("DEPRECATION")
    private fun notify(context: Context, e: Entry) {
        ensureChannel(context)
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(context, CHANNEL).setTimeoutAfter(RING_FOR_MS)
        } else {
            Notification.Builder(context)
                .setPriority(Notification.PRIORITY_MAX)
                .setSound(
                    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM),
                    AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build(),
                )
        }
        val icon = Icon.createWithResource(context, R.drawable.ic_stat_readalarm)
        val open = activityIntent(context, ACTION_OPEN, e.id)
        val notification = builder
            .setSmallIcon(R.drawable.ic_stat_readalarm)
            .setContentTitle(e.title)
            .setContentText(e.body)
            .setCategory(Notification.CATEGORY_ALARM)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(open)
            .setFullScreenIntent(open, true)
            .addAction(Notification.Action.Builder(icon, "Start reading", activityIntent(context, ACTION_START, e.id)).build())
            .addAction(Notification.Action.Builder(icon, "Snooze 10 min", broadcastIntent(context, ACTION_SNOOZE, e.id)).build())
            .build()
        // Keep ringing until the user responds.
        notification.flags = notification.flags or Notification.FLAG_INSISTENT
        context.getSystemService(NotificationManager::class.java).notify(e.id, notification)
    }

    /** Stops the ringing of [ids]. */
    fun dismiss(context: Context, ids: List<Int>) {
        val nm = context.getSystemService(NotificationManager::class.java)
        for (id in ids) nm.cancel(id)
    }

    /** Silences [id] and rings again in 10 minutes under [snoozeId]. */
    fun snooze(context: Context, id: Int, snoozeId: Int) {
        dismiss(context, listOf(id))
        val e = entry(context, id) ?: entry(context, snoozeId) ?: return
        set(context, e.copy(id = snoozeId, weekday = 0, at = System.currentTimeMillis() + SNOOZE_MS))
    }

    /** Whether this process started just now (the app was closed). */
    fun processJustStarted(): Boolean =
        SystemClock.elapsedRealtime() - Process.getStartElapsedRealtime() < 20_000L

    /** An alarm's snooze id: the same block of 10, slot 8. */
    fun snoozeIdFor(id: Int): Int = id - id % 10 + 8

    /** Called by [AlarmReceiver] for the fallback ring and for Snooze. */
    fun onBroadcast(context: Context, intent: Intent) {
        val id = intent.getIntExtra(EXTRA_ID, -1)
        if (id < 0) return
        when (intent.action) {
            ACTION_FALLBACK -> ring(context, id, opened = false)
            ACTION_SNOOZE -> snooze(context, id, snoozeIdFor(id))
        }
    }
}

/** Fallback ring, Snooze, and putting alarms back after a reboot. */
class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            "android.intent.action.QUICKBOOT_POWERON",
            -> AlarmEngine.rearmAll(context)
            else -> AlarmEngine.onBroadcast(context, intent)
        }
    }
}
