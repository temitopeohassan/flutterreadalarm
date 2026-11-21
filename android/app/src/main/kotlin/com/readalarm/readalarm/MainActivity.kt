package com.readalarm.readalarm

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val autoStart = AutoStart(this)

    override fun onStop() {
        autoStart.stops++
        super.onStop()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
                        result.success(ids.map { Diagnostics.isRegistered(this, it) })
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
