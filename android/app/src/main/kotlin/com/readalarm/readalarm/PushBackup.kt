package com.readalarm.readalarm

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.TimeZone
import java.util.UUID

/**
 * Backup for the alarms: ReadAlarm's server sends a high-priority push
 * (Firebase Cloud Messaging) at each alarm's time. Google Play services
 * delivers it even to a closed app, and it rings the alarm if Android
 * hasn't yet. Each ring sounds once (see [AlarmEngine.ring]).
 *
 * The server only gets alarm times, the time zone and a random device id:
 * no names, books or accounts. Off until the build is given a Firebase
 * project and the server's address (see docs/alarm-reliability.md).
 */
object PushBackup {
    private const val PREFS = "readalarm_push"
    private const val DEBOUNCE_MS = 3_000L
    private val main = Handler(Looper.getMainLooper())
    private val syncToken = Any()

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun serverUrl(context: Context) = context.getString(R.string.readalarm_push_url).trimEnd('/')

    /** Whether this build has a server and a Firebase project. */
    fun enabled(context: Context): Boolean =
        serverUrl(context).isNotEmpty() && FirebaseApp.getApps(context).isNotEmpty()

    /** For reports. */
    fun describe(context: Context): String {
        if (serverUrl(context).isEmpty()) return "Off in this build (no server set)"
        if (FirebaseApp.getApps(context).isEmpty()) return "Off in this build (no Firebase project)"
        val p = prefs(context)
        val last = p.getLong("syncedAt", 0L)
        return "On. Last sent to the server: " +
            (if (last == 0L) "never" else java.util.Date(last).toString()) +
            (if (p.getBoolean("dirty", false)) " (changes waiting to be sent)" else "")
    }

    /** The alarms or the push token changed: send them to the server soon. */
    fun changed(context: Context) {
        val app = context.applicationContext
        if (!enabled(app)) return
        prefs(app).edit().putBoolean("dirty", true).apply()
        // Coalesce the many changes of one save into one request.
        main.removeCallbacksAndMessages(syncToken)
        main.postAtTime({ sync(app) }, syncToken, android.os.SystemClock.uptimeMillis() + DEBOUNCE_MS)
    }

    /** Retries a send that failed (no internet, server down). */
    fun syncIfNeeded(context: Context) {
        val app = context.applicationContext
        if (enabled(app) && prefs(app).getBoolean("dirty", false)) sync(app)
    }

    private fun sync(context: Context) {
        try {
            FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                val token = if (task.isSuccessful) task.result else null
                if (token == null) {
                    AlarmEngine.log(context, "Backup push: no push token (${task.exception?.javaClass?.simpleName})")
                    return@addOnCompleteListener
                }
                Thread { post(context, token) }.start()
            }
        } catch (e: Exception) {
            AlarmEngine.log(context, "Backup push: ${e.javaClass.simpleName}")
        }
    }

    private fun device(context: Context): Pair<String, String> {
        val p = prefs(context)
        val id = p.getString("deviceId", null) ?: UUID.randomUUID().toString()
        val secret = p.getString("secret", null) ?: (UUID.randomUUID().toString() + UUID.randomUUID())
        p.edit().putString("deviceId", id).putString("secret", secret).apply()
        return id to secret
    }

    private fun post(context: Context, token: String) {
        val (id, secret) = device(context)
        val alarms = JSONArray()
        for (e in AlarmEngine.stored(context)) {
            val next = AlarmEngine.nextTrigger(e) ?: continue
            alarms.put(
                JSONObject().put("id", e.id).put("weekday", e.weekday)
                    .put("hour", e.hour).put("minute", e.minute).put("next", next),
            )
        }
        val body = JSONObject()
            .put("device_id", id).put("secret", secret).put("token", token)
            .put("tz", TimeZone.getDefault().id).put("alarms", alarms)
            .toString().toByteArray()
        try {
            val conn = URL(serverUrl(context) + "/api/sync.php").openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.connectTimeout = 15_000
            conn.readTimeout = 15_000
            conn.doOutput = true
            conn.setRequestProperty("Content-Type", "application/json")
            conn.setRequestProperty("X-ReadAlarm-Key", context.getString(R.string.readalarm_push_key))
            conn.outputStream.use { it.write(body) }
            val code = conn.responseCode
            conn.disconnect()
            if (code in 200..299) {
                prefs(context).edit().putBoolean("dirty", false)
                    .putLong("syncedAt", System.currentTimeMillis()).apply()
                AlarmEngine.log(context, "Backup push: sent ${alarms.length()} alarms to the server")
            } else {
                AlarmEngine.log(context, "Backup push: server answered $code")
            }
        } catch (e: Exception) {
            AlarmEngine.log(context, "Backup push: couldn't reach the server (${e.javaClass.simpleName})")
        }
    }

    /** A push from the server: ring the alarm it names, if it's due. */
    fun onPush(context: Context, data: Map<String, String>) {
        if (data["type"] != "ring") return
        val id = data["id"]?.toIntOrNull() ?: return
        val due = data["due"]?.toLongOrNull() ?: return
        // Too old to be useful: the phone held the push back.
        if (System.currentTimeMillis() - due > 15 * 60_000L) {
            AlarmEngine.log(context, "Backup push for alarm $id came too late: ignored")
            return
        }
        AlarmEngine.ring(context, id, AlarmEngine.Source.PUSH, due)
        // A high-priority push may start the standby from the background.
        AlarmKeeper.update(context)
    }
}

/** Receives the server's pushes (registered in AndroidManifest.xml). */
class PushService : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        PushBackup.onPush(this, message.data)
    }

    override fun onNewToken(token: String) {
        PushBackup.changed(this)
    }
}
