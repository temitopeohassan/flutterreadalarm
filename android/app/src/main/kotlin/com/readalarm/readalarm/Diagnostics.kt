package com.readalarm.readalarm

import android.app.ActivityManager
import android.app.AlarmManager
import android.app.ApplicationExitInfo
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.usage.UsageStatsManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** What the phone says about ReadAlarm, for diagnostics reports. */
object Diagnostics {
    private const val RECEIVER =
        "com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"

    private fun time(ms: Long): String =
        SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date(ms))

    private fun line(lines: MutableList<String>, label: String, value: () -> Any?) {
        val v = try {
            value()
        } catch (e: Throwable) {
            "unknown (${e.javaClass.simpleName})"
        }
        lines += "$label: $v"
    }

    fun phone(context: Context): String {
        val lines = mutableListOf<String>()
        val pm = context.packageManager
        val pkg = context.packageName

        lines += "PHONE"
        line(lines, "Model") { "${Build.MANUFACTURER} ${Build.MODEL} (${Build.DEVICE})" }
        line(lines, "Android") { "${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})" }
        line(lines, "Build") { Build.DISPLAY }

        lines += ""
        lines += "APP"
        line(lines, "Version") {
            @Suppress("DEPRECATION")
            val info = pm.getPackageInfo(pkg, 0)
            "${info.versionName} (installed ${time(info.firstInstallTime)}, updated ${time(info.lastUpdateTime)})"
        }

        lines += ""
        lines += "WHAT CAN STOP ALARMS"
        val alarms = context.getSystemService(AlarmManager::class.java)
        val power = context.getSystemService(PowerManager::class.java)
        val activity = context.getSystemService(ActivityManager::class.java)
        val notifications = context.getSystemService(NotificationManager::class.java)
        line(lines, "Exact alarms allowed") {
            if (Build.VERSION.SDK_INT >= 31) alarms.canScheduleExactAlarms() else true
        }
        line(lines, "Battery optimisation off for ReadAlarm") { power.isIgnoringBatteryOptimizations(pkg) }
        line(lines, "Background restricted by user") {
            if (Build.VERSION.SDK_INT >= 28) activity.isBackgroundRestricted else "n/a"
        }
        line(lines, "App standby bucket") {
            if (Build.VERSION.SDK_INT >= 28) {
                val usage = context.getSystemService(UsageStatsManager::class.java)
                when (val b = usage.appStandbyBucket) {
                    5 -> "EXEMPTED (5)"
                    10 -> "ACTIVE (10)"
                    20 -> "WORKING_SET (20)"
                    30 -> "FREQUENT (30)"
                    40 -> "RARE (40)"
                    45 -> "RESTRICTED (45) - alarms can be held back"
                    50 -> "NEVER (50)"
                    else -> "$b"
                }
            } else {
                "n/a"
            }
        }
        line(lines, "Battery saver on now") { power.isPowerSaveMode }
        line(lines, "Doze now") { power.isDeviceIdleMode }
        line(lines, "Notifications allowed") { notifications.areNotificationsEnabled() }
        line(lines, "Alarm channel") {
            if (Build.VERSION.SDK_INT >= 26) {
                val channel = notifications.getNotificationChannel("reading_alarms")
                if (channel == null) "not created yet" else "importance ${channel.importance} (4+ rings and pops up; 0 = off)"
            } else {
                "n/a"
            }
        }
        line(lines, "Full-screen alarms allowed") {
            if (Build.VERSION.SDK_INT >= 34) notifications.canUseFullScreenIntent() else true
        }
        line(lines, "Next alarm on the phone") {
            val next = alarms.nextAlarmClock
            if (next == null) "none" else "${time(next.triggerTime)} by ${next.showIntent?.creatorPackage ?: "?"}"
        }

        lines += ""
        lines += "WHY READALARM WAS LAST CLOSED (newest first)"
        if (Build.VERSION.SDK_INT >= 30) {
            try {
                val exits = activity.getHistoricalProcessExitReasons(pkg, 0, 30)
                if (exits.isEmpty()) lines += "No record."
                for (e in exits) {
                    lines += "${time(e.timestamp)}  ${reason(e.reason)}  importance=${e.importance}" +
                        (e.description?.let { "  \"$it\"" } ?: "")
                }
            } catch (e: Throwable) {
                lines += "Unavailable (${e.javaClass.simpleName})"
            }
        } else {
            lines += "Needs Android 11."
        }
        return lines.joinToString("\n")
    }

    private fun reason(code: Int): String = when (code) {
        ApplicationExitInfo.REASON_EXIT_SELF -> "EXIT_SELF"
        ApplicationExitInfo.REASON_SIGNALED -> "SIGNALED (killed by the system)"
        ApplicationExitInfo.REASON_LOW_MEMORY -> "LOW_MEMORY"
        ApplicationExitInfo.REASON_CRASH -> "CRASH"
        ApplicationExitInfo.REASON_CRASH_NATIVE -> "CRASH_NATIVE"
        ApplicationExitInfo.REASON_ANR -> "ANR (not responding)"
        ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "INITIALIZATION_FAILURE"
        ApplicationExitInfo.REASON_PERMISSION_CHANGE -> "PERMISSION_CHANGE"
        ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "EXCESSIVE_RESOURCE_USAGE"
        ApplicationExitInfo.REASON_USER_REQUESTED -> "USER_REQUESTED (force stop: alarms removed)"
        ApplicationExitInfo.REASON_USER_STOPPED -> "USER_STOPPED"
        ApplicationExitInfo.REASON_DEPENDENCY_DIED -> "DEPENDENCY_DIED"
        ApplicationExitInfo.REASON_OTHER -> "OTHER (often the phone's power manager)"
        14 -> "FREEZER"
        15 -> "PACKAGE_STATE_CHANGE"
        16 -> "PACKAGE_UPDATED (app updated)"
        else -> "UNKNOWN ($code)"
    }

    /**
     * Whether Android still holds the alarm for notification [id]. The
     * notification plugin keeps its own list, which survives the phone
     * removing the app's alarms; this asks Android itself.
     */
    fun isRegistered(context: Context, id: Int): Boolean {
        val intent = Intent().setComponent(ComponentName(context, RECEIVER))
        return PendingIntent.getBroadcast(
            context,
            id,
            intent,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        ) != null
    }

    /** The app's recent log lines (an app can read only its own). */
    fun logcat(lines: Int): String = try {
        val process = Runtime.getRuntime().exec(arrayOf("logcat", "-d", "-v", "time", "-t", "$lines"))
        process.inputStream.bufferedReader().use { it.readText() }
    } catch (e: Throwable) {
        "Unavailable (${e.javaClass.simpleName}: ${e.message})"
    }

    /** Opens an email app with the report filled in. */
    fun email(context: Context, to: String, subject: String, body: String): Boolean {
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "message/rfc822"
            putExtra(Intent.EXTRA_EMAIL, arrayOf(to))
            putExtra(Intent.EXTRA_SUBJECT, subject)
            putExtra(Intent.EXTRA_TEXT, body)
        }
        return try {
            context.startActivity(Intent.createChooser(intent, "Send report"))
            true
        } catch (e: Throwable) {
            false
        }
    }
}
