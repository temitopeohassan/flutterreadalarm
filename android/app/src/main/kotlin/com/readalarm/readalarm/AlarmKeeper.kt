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
 * "Keep alarms ready" (Settings): while an alarm is set, a foreground
 * service with a quiet notification ("Next reading: Sat 7:00 PM"). To
 * Android an app with a foreground service is in use, so a low-memory kill
 * passes it by, and the phone doesn't drop its alarm clocks. On by default
 * on phones known to close apps and drop their alarms.
 */
object AlarmKeeper {
    private const val PREFS = "readalarm_keeper"
    private const val CHANNEL = "alarm_standby"
    const val NOTIFICATION_ID = 7_000_001

    @Volatile
    var running = false
        internal set

    fun enabled(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean("enabled", false)

    fun setEnabled(context: Context, on: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean("enabled", on).apply()
        AlarmEngine.log(context, "Keep alarms ready: ${if (on) "on" else "off"}")
        update(context)
    }

    /** Starts, refreshes or stops the service to match the setting and the alarms. */
    fun update(context: Context) {
        val app = context.applicationContext
        val next = AlarmEngine.nextRing(app)
        if (!enabled(app) || next == null) {
            if (running) app.stopService(Intent(app, AlarmKeeperService::class.java))
            return
        }
        try {
            val intent = Intent(app, AlarmKeeperService::class.java)
            if (Build.VERSION.SDK_INT >= 26) app.startForegroundService(intent) else app.startService(intent)
        } catch (e: Exception) {
            // Android 12+ refuses from the background: started again when
            // the app opens or an alarm rings.
            AlarmEngine.log(app, "Keep alarms ready: couldn't start (${e.javaClass.simpleName})")
        }
    }

    internal fun notification(context: Context): Notification {
        val nm = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26 && nm.getNotificationChannel(CHANNEL) == null) {
            val channel = NotificationChannel(CHANNEL, "Alarm standby", NotificationManager.IMPORTANCE_MIN)
            channel.description = "Shows your next reading alarm while ReadAlarm keeps it ready"
            channel.setShowBadge(false)
            channel.setSound(null, null)
            nm.createNotificationChannel(channel)
        }
        val next = AlarmEngine.nextRing(context)
        val title = next?.let {
            "Next reading: " + java.text.SimpleDateFormat("EEE h:mm a", java.util.Locale.getDefault())
                .format(java.util.Date(it))
        } ?: "No reading alarms set"
        val open = PendingIntent.getActivity(
            context, NOTIFICATION_ID,
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
            .setContentTitle(title)
            .setContentText("ReadAlarm is keeping your alarm ready")
            .setOngoing(true)
            .setShowWhen(false)
            .setContentIntent(open)
            .setCategory(Notification.CATEGORY_SERVICE)
            .build()
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
            AlarmEngine.log(this, "Keep alarms ready: running" + if (intent == null) " (restarted by Android)" else "")
        }
        if (!AlarmKeeper.enabled(this) || AlarmEngine.nextRing(this) == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        // Restarted after the phone closed the app: put the alarms back.
        if (intent == null) AlarmEngine.watchdog(this, "standby restarted")
        return START_STICKY
    }

    private fun goForeground(): Boolean {
        val notification = AlarmKeeper.notification(this)
        if (Build.VERSION.SDK_INT < 34) {
            return try {
                startForeground(AlarmKeeper.NOTIFICATION_ID, notification)
                true
            } catch (e: Exception) {
                false
            }
        }
        // Android 14+: the alarm apps' type, else the declared special use.
        for (type in listOf(
            ServiceInfo.FOREGROUND_SERVICE_TYPE_SYSTEM_EXEMPTED,
            ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
        )) {
            try {
                startForeground(AlarmKeeper.NOTIFICATION_ID, notification, type)
                return true
            } catch (e: Exception) {
                AlarmEngine.log(this, "Keep alarms ready: type $type refused")
            }
        }
        return false
    }

    override fun onDestroy() {
        AlarmKeeper.running = false
        super.onDestroy()
    }
}
