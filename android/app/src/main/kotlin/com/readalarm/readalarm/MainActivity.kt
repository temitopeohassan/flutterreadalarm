package com.readalarm.readalarm

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val autoStart = AutoStart(this)
    private var alarms: MethodChannel? = null

    /** An alarm that opened the app, until Dart takes it. */
    private var pendingLaunch: Map<String, Any?>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Alarm clocks the phone dropped while ReadAlarm was closed: back.
        AlarmEngine.watchdog(this, "ReadAlarm opened")
        AlarmWatchdog.schedule(this)
        AlarmKeeper.update(this)
        pendingLaunch = launchFrom(intent)
    }

    /** The last alarm handed to Dart, to drop the same one opened twice. */
    private var lastLaunch: Pair<Int, Long>? = null

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val launch = launchFrom(intent) ?: return
        val channel = alarms
        if (channel == null) pendingLaunch = launch else channel.invokeMethod("launch", launch)
    }

    /** The alarm [intent] is about, if any (AlarmEngine's actions). */
    private fun launchFrom(intent: Intent?): Map<String, Any?>? {
        val id = intent?.getIntExtra(AlarmEngine.EXTRA_ID, -1) ?: -1
        if (id < 0) return null
        val (payload, action) = when (intent?.action) {
            // The backup alarm clock: rings it if the broadcast didn't.
            AlarmEngine.ACTION_RING_SCREEN -> AlarmEngine.ring(this, id, AlarmEngine.Source.SCREEN) to "open"
            AlarmEngine.ACTION_OPEN -> AlarmEngine.rungPayload(this, id) to "open"
            AlarmEngine.ACTION_START -> {
                AlarmEngine.dismiss(this, listOf(id))
                AlarmEngine.rungPayload(this, id) to "start"
            }
            else -> null to null
        }
        // Handled once: recreating the screen mustn't ring it again.
        intent?.removeExtra(AlarmEngine.EXTRA_ID)
        if (payload == null) return null
        // The ringing service and its full-screen alert can both open the
        // screen for the same ring: hand it to Dart once.
        val now = System.currentTimeMillis()
        val last = lastLaunch
        if (action == "open" && last != null && last.first == id && now - last.second < 5_000L) return null
        lastLaunch = id to now
        return mapOf("payload" to payload, "action" to action)
    }

    override fun onPause() {
        autoStart.onPause()
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        autoStart.onResume()
    }

    override fun onStop() {
        autoStart.stops++
        super.onStop()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Reading alarms (AlarmEngine.kt), from alarm_scheduler.dart.
        alarms = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "readalarm/alarms").also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "set" -> {
                        for (m in call.argument<List<Map<*, *>>>("entries") ?: emptyList()) {
                            AlarmEngine.set(this, AlarmEngine.Entry.fromMap(m))
                        }
                        result.success(null)
                    }
                    "cancel" -> {
                        for (id in call.argument<List<Int>>("ids") ?: emptyList()) AlarmEngine.cancel(this, id)
                        result.success(null)
                    }
                    "dismiss" -> {
                        AlarmEngine.dismiss(this, call.argument<List<Int>>("ids") ?: emptyList())
                        result.success(null)
                    }
                    "pending" -> result.success(AlarmEngine.stored(this).map { e -> e.payload })
                    "registered" -> {
                        val ids = call.argument<List<Int>>("ids") ?: emptyList()
                        result.success(ids.map { id -> AlarmEngine.isRegistered(this, id) })
                    }
                    // Settings → Keep alarms ready (AlarmKeeper.kt).
                    "setStandby" -> {
                        AlarmKeeper.setEnabled(this, call.argument<Boolean>("on") == true)
                        result.success(null)
                    }
                    // The app couldn't reach readalarm.net: retry natively.
                    "syncLater" -> {
                        ServerSync.later(this)
                        result.success(null)
                    }
                    "takeLaunch" -> {
                        result.success(pendingLaunch)
                        pendingLaunch = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "readalarm/autostart")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Answers once a screen has really shown (AutoStart.kt).
                    "open" -> autoStart.open { result.success(it) }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "readalarm/diagnostics")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "phone" -> result.success(
                        Diagnostics.phone(this) + "\n\nAUTO-START ON THIS PHONE\n" + autoStart.report(),
                    )
                    "registered" -> {
                        val ids = call.argument<List<Int>>("ids") ?: emptyList()
                        result.success(ids.map { AlarmEngine.isRegistered(this, it) })
                    }
                    "logcat" -> Thread {
                        val text = Diagnostics.logcat(call.argument<Int>("lines") ?: 400)
                        runOnUiThread { result.success(text) }
                    }.start()
                    "email" -> result.success(
                        Diagnostics.email(
                            this,
                            call.argument<String>("to") ?: "",
                            call.argument<String>("subject") ?: "",
                            call.argument<String>("body") ?: "",
                        ),
                    )
                    "share" -> result.success(
                        Diagnostics.share(
                            this,
                            call.argument<String>("subject") ?: "",
                            call.argument<String>("body") ?: "",
                        ),
                    )
                    else -> result.notImplemented()
                }
            }
    }
}
