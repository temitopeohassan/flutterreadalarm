package com.readalarm.readalarm

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Keeps ReadAlarm running while an alarm is set, with a quiet notification
 * ("Next reading: Sat 7:00 PM").
 *
 * Phones like Tecno's close apps in the background and hold back the
 * alarms of closed apps, sometimes for many minutes. An app with a running
 * foreground service counts as in use: it's rarely closed, and its alarms
 * reach it on time. If the phone still closes it, Android restarts the
 * service (START_STICKY), and the alarms are still set either way.
 */
object AlarmKeeper {
    private const val CHANNEL = "alarm_standby"
    const val NOTIFICATION_ID = 7_000_001

    /** Whether the service is running (in this process). */
    @Volatile
    var running = false
        internal set

    /** Starts, refreshes or stops the service to match the stored alarms. */
    fun update(context: Context) {
        val app = context.applicationContext
        val next = AlarmEngine.nextRing(app)
        if (next == null) {
            if (running) {
                AlarmEngine.log(app, "Standby: no alarms set, stopping")
                app.stopService(Intent(app, AlarmKeeperService::class.java))
            }
            return
        }
        try {
            if (Build.VERSION.SDK_INT >= 26) {
                app.startForegroundService(Intent(app, AlarmKeeperService::class.java))
            } else {
                app.startService(Intent(app, AlarmKeeperService::class.java))
            }
        } catch (e: Exception) {
            // Android 12+ refuses to start it from the background. It's
            // started again the next time the app opens or an alarm rings.
            AlarmEngine.log(app, "Standby could not start: ${e.javaClass.simpleName}")
        }
    }

    internal fun notification(context: Context): Notification {
        ensureChannel(context)
        val next = AlarmEngine.nextRing(context)
        val text = next?.let {
            "Next reading: " + java.text.SimpleDateFormat(
                if (isWithinWeek(it)) "EEE h:mm a" else "EEE d MMM h:mm a",
                java.util.Locale.getDefault(),
            ).format(java.util.Date(it))
        } ?: "No reading alarms set"
        val open = PendingIntent.getActivity(
            context,
            NOTIFICATION_ID,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(context, CHANNEL)
        } else {
            Notification.Builder(context).setPriority(Notification.PRIORITY_MIN)
        }
        return builder
            .setSmallIcon(R.drawable.ic_stat_readalarm)
            .setContentTitle(text)
            .setContentText("ReadAlarm is keeping your alarm ready")
            .setOngoing(true)
            .setShowWhen(false)
            .setContentIntent(open)
            .setCategory(Notification.CATEGORY_SERVICE)
            .apply { if (Build.VERSION.SDK_INT >= 31) setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE) }
            .build()
    }

    private fun isWithinWeek(at: Long) = at - System.currentTimeMillis() < 6L * 24 * 3600 * 1000

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val nm = context.getSystemService(NotificationManager::class.java)
        if (nm.getNotificationChannel(CHANNEL) != null) return
        val channel = NotificationChannel(CHANNEL, "Alarm standby", NotificationManager.IMPORTANCE_LOW)
        channel.description = "Shows your next reading alarm while ReadAlarm keeps it ready"
        channel.setShowBadge(false)
        channel.setSound(null, null)
        nm.createNotificationChannel(channel)
    }
}

class AlarmKeeperService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!goForeground()) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (!AlarmKeeper.running) {
            AlarmKeeper.running = true
            AlarmEngine.log(this, "Standby running" + if (intent == null) " (restarted by Android)" else "")
        }
        if (AlarmEngine.nextRing(this) == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        // A restart after the phone closed the app: make sure the alarms
        // are still set, and retry sending them to the backup server.
        if (intent == null) AlarmEngine.rearmAll(this, "standby restarted")
        PushBackup.syncIfNeeded(this)
        // Restarted by Android if the phone closes the app.
        return START_STICKY
    }

    private fun goForeground(): Boolean {
        val notification = AlarmKeeper.notification(this)
        if (Build.VERSION.SDK_INT < 34) {
            return try {
                startForeground(AlarmKeeper.NOTIFICATION_ID, notification)
                true
            } catch (e: Exception) {
                AlarmEngine.log(this, "Standby refused: ${e.javaClass.simpleName}")
                false
            }
        }
        // Android 14+: the type for alarm apps, else the declared special use.
        for (type in listOf(
            ServiceInfo.FOREGROUND_SERVICE_TYPE_SYSTEM_EXEMPTED,
            ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
        )) {
            try {
                startForeground(AlarmKeeper.NOTIFICATION_ID, notification, type)
                return true
            } catch (e: Exception) {
                AlarmEngine.log(this, "Standby type $type refused: ${e.javaClass.simpleName}")
            }
        }
        return false
    }

    override fun onDestroy() {
        AlarmKeeper.running = false
        AlarmEngine.log(this, "Standby stopped")
        super.onDestroy()
    }
}
