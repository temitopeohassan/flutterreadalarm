package com.readalarm.readalarm

import android.content.ComponentName
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "readalarm/autostart")
            .setMethodCallHandler { call, result ->
                if (call.method == "open") result.success(openAutoStart()) else result.notImplemented()
            }
    }

    /**
     * Opens the phone maker's auto-start screen, which isn't in Android's own
     * app settings. Returns "autostart" if that screen opened, "manager" if
     * only the maker's phone-manager app did, or null if neither exists.
     */
    private fun openAutoStart(): String? {
        for ((pkg, cls) in AUTO_START_SCREENS) {
            if (start(Intent().setComponent(ComponentName(pkg, cls)))) return "autostart"
        }
        for (pkg in PHONE_MANAGERS) {
            val launch = packageManager.getLaunchIntentForPackage(pkg) ?: continue
            if (start(launch)) return "manager"
        }
        return null
    }

    private fun start(intent: Intent): Boolean = try {
        startActivity(intent)
        true
    } catch (e: Exception) {
        // Not on this phone, or not opened to other apps.
        false
    }

    companion object {
        private val AUTO_START_SCREENS = listOf(
            // Tecno, Infinix (Phone Master) and itel
            "com.transsion.phonemaster" to "com.cyin.himgr.autostart.AutoStartActivity",
            "com.itel.autobootmanager" to "com.itel.autobootmanager.activity.AutoBootMgrActivity",
            // Xiaomi, Redmi, Poco
            "com.miui.securitycenter" to "com.miui.permcenter.autostart.AutoStartManagementActivity",
            // Oppo, Realme
            "com.coloros.safecenter" to "com.coloros.safecenter.permission.startup.StartupAppListActivity",
            "com.coloros.safecenter" to "com.coloros.safecenter.startupapp.StartupAppListActivity",
            "com.oppo.safe" to "com.oppo.safe.permission.startup.StartupAppListActivity",
            // Vivo
            "com.vivo.permissionmanager" to "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
            "com.iqoo.secure" to "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity",
            // Huawei, Honor
            "com.huawei.systemmanager" to "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
            "com.huawei.systemmanager" to "com.huawei.systemmanager.optimize.process.ProtectActivity",
        )

        private val PHONE_MANAGERS = listOf(
            "com.transsion.phonemaster",
            "com.miui.securitycenter",
            "com.coloros.safecenter",
            "com.huawei.systemmanager",
        )
    }
}
