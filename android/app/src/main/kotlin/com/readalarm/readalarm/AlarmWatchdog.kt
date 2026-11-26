package com.readalarm.readalarm

import android.content.Context
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import androidx.work.BackoffPolicy
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.TimeZone
import java.util.concurrent.TimeUnit

/**
 * Every 15 minutes (WorkManager, which outlives the app's process): puts
 * back alarm clocks the phone dropped when it closed ReadAlarm (Tecno and
 * others drop them on a low-memory kill), and rings an alarm whose time
 * passed in the last 15 minutes without ringing.
 */
object AlarmWatchdog {
    private const val WORK = "readalarm-watchdog"

    fun schedule(context: Context) {
        try {
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK,
                ExistingPeriodicWorkPolicy.KEEP,
                PeriodicWorkRequestBuilder<AlarmWatchdogWorker>(15, TimeUnit.MINUTES).build(),
            )
        } catch (e: Exception) {
            AlarmEngine.log(context, "Watchdog not scheduled: ${e.javaClass.simpleName}")
        }
    }
}

class AlarmWatchdogWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        AlarmEngine.watchdog(applicationContext, "watchdog")
        AlarmKeeper.update(applicationContext)
        if (ServerSync.pending(applicationContext)) ServerSync.later(applicationContext)
        return Result.success()
    }
}

/**
 * Sends the alarms to readalarm.net when the app's own request failed (no
 * network, screen locked mid-request): retried by WorkManager once there's
 * a connection, with growing waits. Reads what the app wrote to
 * server_device.json (backend_service.dart) and the alarm engine's alarms.
 */
object ServerSync {
    private const val WORK = "readalarm-server-sync"

    private fun file(context: Context) = File(context.filesDir, "server_device.json")

    fun pending(context: Context): Boolean = try {
        JSONObject(file(context).readText()).optBoolean("dirty", false)
    } catch (e: Exception) {
        false
    }

    fun later(context: Context) {
        try {
            WorkManager.getInstance(context).enqueueUniqueWork(
                WORK,
                ExistingWorkPolicy.REPLACE,
                OneTimeWorkRequestBuilder<ServerSyncWorker>()
                    .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                    .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
                    .build(),
            )
        } catch (e: Exception) {
            AlarmEngine.log(context, "Server sync not scheduled: ${e.javaClass.simpleName}")
        }
    }

    /** The alarms as readalarm.net takes them (alarmForServer in Dart). */
    private fun alarms(context: Context): JSONArray {
        val byAlarm = linkedMapOf<String, MutableList<AlarmEngine.Entry>>()
        for (e in AlarmEngine.stored(context)) {
            if (e.id % 10 == 8) continue // Snoozes stay on the phone.
            val alarmId = try {
                JSONObject(e.payload).getString("alarmId")
            } catch (ex: Exception) {
                continue
            }
            byAlarm.getOrPut(alarmId) { mutableListOf() } += e
        }
        val out = JSONArray()
        for ((alarmId, entries) in byAlarm) {
            val first = entries.first()
            val weekly = entries.filter { it.weekday != 0 }
            val days = JSONArray()
            weekly.map { it.weekday - 1 }.sorted().forEach { days.put(it) }
            val once = entries.firstOrNull { it.weekday == 0 }
            out.put(
                JSONObject()
                    .put("id", alarmId).put("enabled", true)
                    .put("hour", weekly.firstOrNull()?.hour ?: hourOf(once?.at)).put("minute", weekly.firstOrNull()?.minute ?: minuteOf(once?.at))
                    .put("days", days)
                    .put("once_at", if (weekly.isEmpty() && once != null) once.at else JSONObject.NULL)
                    .put("title", first.title).put("body", first.body).put("payload", first.payload),
            )
        }
        return out
    }

    private fun hourOf(at: Long?) =
        java.util.Calendar.getInstance().apply { timeInMillis = at ?: 0 }.get(java.util.Calendar.HOUR_OF_DAY)

    private fun minuteOf(at: Long?) =
        java.util.Calendar.getInstance().apply { timeInMillis = at ?: 0 }.get(java.util.Calendar.MINUTE)

    /** Sends all alarms. Returns whether the server took them. */
    fun send(context: Context): Boolean {
        val identity = try {
            JSONObject(file(context).readText())
        } catch (e: Exception) {
            return true // Never set up by the app: nothing to send.
        }
        val url = identity.optString("url")
        if (url.isEmpty()) return true
        val device = JSONObject()
            .put("id", identity.optString("id")).put("secret", identity.optString("secret"))
            .put("platform", "android").put("timezone", TimeZone.getDefault().id)
            .put("app_version", identity.optString("app_version"))
            .put("push_token", identity.opt("push_token") ?: JSONObject.NULL)
        val list = alarms(context)
        val body = JSONObject().put("device", device).put("alarms", list).toString().toByteArray()
        return try {
            val conn = URL("$url/api/v1/alarms-sync.php").openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.connectTimeout = 30_000
            conn.readTimeout = 30_000
            conn.doOutput = true
            conn.setRequestProperty("Content-Type", "application/json")
            identity.optString("api_key").takeIf { it.isNotEmpty() }?.let { conn.setRequestProperty("X-ReadAlarm-Key", it) }
            conn.outputStream.use { it.write(body) }
            val code = conn.responseCode
            conn.disconnect()
            if (code == 200) {
                identity.put("dirty", false)
                file(context).writeText(identity.toString())
                AlarmEngine.log(context, "Server: ${list.length()} alarms sent (retry)")
                true
            } else {
                AlarmEngine.log(context, "Server: retry refused ($code)")
                code in 400..499 && code != 408 && code != 429 // Retrying won't help.
            }
        } catch (e: Exception) {
            AlarmEngine.log(context, "Server: retry failed (${e.javaClass.simpleName}), trying again later")
            false
        }
    }
}

class ServerSyncWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result = if (ServerSync.send(applicationContext)) Result.success() else Result.retry()
}
