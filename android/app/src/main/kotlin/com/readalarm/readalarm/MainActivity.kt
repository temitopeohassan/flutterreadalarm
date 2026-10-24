package com.readalarm.readalarm

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "readalarm/autostart")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "open" -> result.success(openAutoStart())
                    "report" -> result.success(report())
                    else -> result.notImplemented()
                }
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
        // The screen's name changes between versions (Tecno's Phone Master
        // especially), so look through the apps' screens for one.
        for (pkg in PHONE_MANAGERS + SETTINGS_APPS) {
            for (cls in autoStartScreensIn(pkg)) {
                if (start(Intent().setComponent(ComponentName(pkg, cls)))) return "autostart"
            }
        }
        for (pkg in PHONE_MANAGERS) {
            val launch = packageManager.getLaunchIntentForPackage(pkg) ?: continue
            if (start(launch)) return "manager"
        }
        return null
    }

    /** Screens of [pkg] other apps may open whose names suggest auto-start. */
    private fun autoStartScreensIn(pkg: String): List<String> = try {
        @Suppress("DEPRECATION")
        val activities = packageManager
            .getPackageInfo(pkg, PackageManager.GET_ACTIVITIES).activities ?: emptyArray()
        activities
            .filter { it.exported && it.permission == null && AUTO_START_NAME.containsMatchIn(it.name) }
            // Lists of apps first, then the rest.
            .sortedBy { if (Regex("(?i)list|manage|mgr").containsMatchIn(it.name)) 0 else 1 }
            .map { it.name }
    } catch (e: Exception) {
        emptyList()
    }

    /** What this phone has, for support: managers and auto-start screens. */
    private fun report(): String {
        val lines = mutableListOf(
            "${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL}, Android ${android.os.Build.VERSION.RELEASE}",
        )
        for (pkg in PHONE_MANAGERS + SETTINGS_APPS) {
            val installed = try {
                packageManager.getPackageInfo(pkg, 0)
                true
            } catch (e: Exception) {
                false
            }
            if (!installed) continue
            val launchable = packageManager.getLaunchIntentForPackage(pkg) != null
            lines += "$pkg (icon: $launchable)"
            for (cls in autoStartScreensIn(pkg)) lines += "  $cls"
        }
        for ((pkg, cls) in AUTO_START_SCREENS) {
            val found = try {
                packageManager.getActivityInfo(ComponentName(pkg, cls), 0).exported
            } catch (e: Exception) {
                null
            }
            if (found != null) lines += "known: $pkg/$cls exported=$found"
        }
        return lines.joinToString("\n")
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

        private val AUTO_START_NAME = Regex("(?i)auto.?start|autoboot|auto.?launch|startup|bootstart")

        /** Some phones put auto-start in their Settings app. */
        private val SETTINGS_APPS = listOf("com.android.settings", "com.transsion.settings")

        private val PHONE_MANAGERS = listOf(
            "com.transsion.phonemaster",
            "com.transsion.phonemanager",
            "com.itel.autobootmanager",
            "com.miui.securitycenter",
            "com.coloros.safecenter",
            "com.huawei.systemmanager",
        )
    }
}
