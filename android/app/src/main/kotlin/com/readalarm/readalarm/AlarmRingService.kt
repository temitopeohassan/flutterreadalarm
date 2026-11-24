package com.readalarm.readalarm

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator

/**
 * Rings a reading alarm natively: the alarm sound on the alarm volume, a
 * vibration, and a full-screen notification that opens ReadAlarm over the
 * lock screen. Runs before Flutter has started, so it rings at once even
 * when the app was closed. Stops when the user acts on it, or after 10
 * minutes.
 */
class AlarmRingService : Service() {
    companion object {
        private const val CHANNEL = "alarm_ringing"
        private const val RING_FOR_MS = 10 * 60_000L

        /** The alarm ringing now, if any. */
        @Volatile
        var ringingId: Int? = null
            private set

        fun start(context: Context, id: Int) {
            val intent = Intent(context, AlarmRingService::class.java).putExtra(AlarmEngine.EXTRA_ID, id)
            try {
                if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent) else context.startService(intent)
            } catch (e: Exception) {
                // Refused (background start limits): ReadAlarm's screen
                // rings it instead (the backup alarm clock, or the push).
                AlarmEngine.log(context, "Alarm $id: couldn't start ringing (${e.javaClass.simpleName})")
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, AlarmRingService::class.java))
        }
    }

    private var player: MediaPlayer? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private val handler = Handler(Looper.getMainLooper())

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val id = intent?.getIntExtra(AlarmEngine.EXTRA_ID, -1) ?: -1
        val notification = notification(id)
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(id.coerceAtLeast(1), notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        } else {
            startForeground(id.coerceAtLeast(1), notification)
        }
        if (id < 0) {
            stopSelf()
            return START_NOT_STICKY
        }
        ringingId = id
        wakeLock?.release()
        wakeLock = getSystemService(PowerManager::class.java)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "readalarm:ringing")
            .apply { acquire(RING_FOR_MS) }
        play()
        vibrate()
        handler.removeCallbacksAndMessages(null)
        handler.postDelayed({ stopSelf() }, RING_FOR_MS)
        // Open ReadAlarm's alarm screen. Android 10+ may refuse from the
        // background; the full-screen notification opens it then.
        try {
            startActivity(
                Intent(this, MainActivity::class.java).setAction(AlarmEngine.ACTION_OPEN)
                    .putExtra(AlarmEngine.EXTRA_ID, id).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        } catch (e: Exception) {
            // The notification's full-screen intent covers it.
        }
        return START_NOT_STICKY
    }

    private fun play() {
        player?.release()
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        player = try {
            MediaPlayer().apply {
                setAudioAttributes(attributes)
                setDataSource(this@AlarmRingService, Uri.parse("android.resource://$packageName/${R.raw.readalarm_alarm}"))
                isLooping = true
                prepare()
                start()
            }
        } catch (e: Exception) {
            AlarmEngine.log(this, "Alarm sound failed (${e.javaClass.simpleName}): the phone's alarm sound instead")
            try {
                MediaPlayer().apply {
                    setAudioAttributes(attributes)
                    setDataSource(this@AlarmRingService, RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM))
                    isLooping = true
                    prepare()
                    start()
                }
            } catch (e2: Exception) {
                null
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun vibrate() {
        val vibrator = getSystemService(Vibrator::class.java) ?: return
        val pattern = longArrayOf(0, 800, 600)
        if (Build.VERSION.SDK_INT >= 26) {
            vibrator.vibrate(
                VibrationEffect.createWaveform(pattern, 0),
                AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build(),
            )
        } else {
            vibrator.vibrate(pattern, 0)
        }
    }

    @Suppress("DEPRECATION")
    private fun notification(id: Int): Notification {
        val nm = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26 && nm.getNotificationChannel(CHANNEL) == null) {
            val channel = NotificationChannel(CHANNEL, "Ringing alarms", NotificationManager.IMPORTANCE_HIGH)
            channel.description = "Shows a reading alarm while it rings"
            // The service plays the sound itself, on the alarm volume.
            channel.setSound(null, null)
            channel.lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            channel.setBypassDnd(true)
            nm.createNotificationChannel(channel)
        }
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(this, CHANNEL)
        } else {
            Notification.Builder(this).setPriority(Notification.PRIORITY_MAX)
        }
        val open = AlarmEngine.screenIntent(this, AlarmEngine.ACTION_OPEN, id)
        val icon = Icon.createWithResource(this, R.drawable.ic_stat_readalarm)
        return builder
            .setSmallIcon(R.drawable.ic_stat_readalarm)
            .setContentTitle(AlarmEngine.rungTitle(this, id))
            .setContentText(AlarmEngine.rungBody(this, id))
            .setCategory(Notification.CATEGORY_ALARM)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(open)
            .setFullScreenIntent(open, true)
            .addAction(
                Notification.Action.Builder(
                    icon, "Start reading", AlarmEngine.screenIntent(this, AlarmEngine.ACTION_START, id),
                ).build(),
            )
            .addAction(Notification.Action.Builder(icon, "Snooze 10 min", AlarmEngine.snoozeIntent(this, id)).build())
            .build()
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        player?.run {
            try {
                stop()
            } catch (_: Exception) {
            }
            release()
        }
        player = null
        getSystemService(Vibrator::class.java)?.cancel()
        wakeLock?.takeIf { it.isHeld }?.release()
        ringingId = null
        super.onDestroy()
    }
}

/**
 * The alarm clock going off, Snooze, and putting alarms back after a
 * reboot, an update, a clock change, or exact alarms being allowed again.
 */
class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // Keep the phone awake until the ringing service has started.
        val wakeLock = context.getSystemService(PowerManager::class.java)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "readalarm:alarm")
            .apply { acquire(10_000L) }
        try {
            val id = intent.getIntExtra(AlarmEngine.EXTRA_ID, -1)
            when (intent.action) {
                AlarmEngine.ACTION_RING -> if (id >= 0) AlarmEngine.ring(context, id, AlarmEngine.Source.ALARM)
                AlarmEngine.ACTION_SNOOZE -> if (id >= 0) AlarmEngine.snooze(context, id)
                else -> AlarmEngine.rearmAll(context, intent.action?.substringAfterLast('.') ?: "")
            }
        } finally {
            if (wakeLock.isHeld) wakeLock.release()
        }
    }
}
