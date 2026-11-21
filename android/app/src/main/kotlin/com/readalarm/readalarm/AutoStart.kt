package com.readalarm.readalarm

import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper

/**
 * Opens the phone maker's auto-start (background start) setting, which
 * isn't in Android's own app settings and differs on every brand.
 *
 * Tries, in order, until a screen really shows:
 * 1. the maker's auto-start screens known for each brand;
 * 2. screens found on the phone whose names suggest auto-start (their
 *    names change between versions);
 * 3. the brand's battery screen for background limits (Samsung and others
 *    have no auto-start list);
 * 4. the maker's phone-manager app at its home screen.
 *
 * A try counts only if ReadAlarm's screen went behind another: some phones
 * accept the request and show nothing (Tecno's Phone Master closes its
 * auto-start screen at once when another app opens it).
 */
class AutoStart(private val activity: Activity) {
    /** Counts the activity's onStop calls (MainActivity reports them). */
    var stops = 0

    private class Try(val intent: Intent, val kind: String)

    /**
     * Answers with "kind" ("autostart", "battery" or "manager"; null if
     * nothing opened) and "log", what was tried, for problem reports.
     */
    fun open(done: (Map<String, Any?>) -> Unit) {
        val tries = mutableListOf<Try>()
        for ((pkg, cls) in AUTO_START_SCREENS) tries += Try(component(pkg, cls), "autostart")
        for ((action, pkg) in AUTO_START_ACTIONS) {
            tries += Try(Intent(action).setPackage(pkg).addCategory(Intent.CATEGORY_DEFAULT), "autostart")
        }
        for (pkg in PHONE_MANAGERS) {
            for (cls in autoStartScreensIn(pkg, AUTO_START_NAME)) tries += Try(component(pkg, cls), "autostart")
        }
        // The Settings app has many screens: only clear auto-start names.
        for (pkg in SETTINGS_APPS) {
            for (cls in autoStartScreensIn(pkg, SETTINGS_NAME)) tries += Try(component(pkg, cls), "autostart")
        }
        for ((pkg, cls) in BATTERY_SCREENS) tries += Try(component(pkg, cls), "battery")
        for (pkg in PHONE_MANAGERS) {
            val launch = activity.packageManager.getLaunchIntentForPackage(pkg) ?: continue
            tries += Try(launch, "manager")
        }
        val seen = mutableSetOf<String>()
        tryNext(tries.filter { seen.add(it.intent.toUri(0)) }, 0, mutableListOf(), done)
    }

    private fun component(pkg: String, cls: String) = Intent().setComponent(ComponentName(pkg, cls))

    private fun tryNext(tries: List<Try>, i: Int, log: MutableList<String>, done: (Map<String, Any?>) -> Unit) {
        if (i >= tries.size) {
            log += "nothing opened"
            return done(mapOf("kind" to null, "log" to log.joinToString("; ")))
        }
        val t = tries[i]
        val name = t.intent.component?.flattenToShortString() ?: t.intent.action ?: t.intent.`package` ?: "?"
        val before = stops
        try {
            activity.startActivity(t.intent)
        } catch (e: Exception) {
            // Not on this phone, or not open to other apps: next, at once.
            if (e is SecurityException) log += "$name not allowed"
            return tryNext(tries, i + 1, log, done)
        }
        Handler(Looper.getMainLooper()).postDelayed({
            if (stops > before || !activity.hasWindowFocus()) {
                log += "opened $name"
                done(mapOf("kind" to t.kind, "log" to log.joinToString("; ")))
            } else {
                log += "$name showed nothing"
                tryNext(tries, i + 1, log, done)
            }
        }, SHOW_WAIT_MS)
    }

    /** Screens of [pkg] other apps may open whose names suggest auto-start. */
    private fun autoStartScreensIn(pkg: String, name: Regex): List<String> = try {
        @Suppress("DEPRECATION")
        val activities = activity.packageManager
            .getPackageInfo(pkg, PackageManager.GET_ACTIVITIES).activities ?: emptyArray()
        activities
            .filter { it.exported && it.enabled && it.permission == null && name.containsMatchIn(it.name) }
            // Lists of apps first, then the rest.
            .sortedBy { if (Regex("(?i)list|manage|mgr").containsMatchIn(it.name)) 0 else 1 }
            .map { it.name }
    } catch (e: Exception) {
        emptyList()
    }

    /** What this phone has, for problem reports. */
    fun report(): String {
        val pm = activity.packageManager
        val lines = mutableListOf("${Build.MANUFACTURER} ${Build.MODEL}, Android ${Build.VERSION.RELEASE}")
        for (pkg in (PHONE_MANAGERS + SETTINGS_APPS).distinct()) {
            val installed = try {
                pm.getPackageInfo(pkg, 0)
                true
            } catch (e: Exception) {
                false
            }
            if (!installed) continue
            lines += "$pkg (icon: ${pm.getLaunchIntentForPackage(pkg) != null})"
            val name = if (pkg in SETTINGS_APPS) SETTINGS_NAME else AUTO_START_NAME
            for (cls in autoStartScreensIn(pkg, name)) lines += "  found: $cls"
        }
        for ((pkg, cls) in AUTO_START_SCREENS + BATTERY_SCREENS) {
            val exported = try {
                pm.getActivityInfo(ComponentName(pkg, cls), 0).exported
            } catch (e: Exception) {
                null
            }
            if (exported != null) lines += "known: $pkg/$cls open to apps: $exported"
        }
        if (lines.size == 1) lines += "No phone-manager app or auto-start screen found."
        return lines.joinToString("\n")
    }

    companion object {
        /** How long a screen gets to show before the next is tried. */
        private const val SHOW_WAIT_MS = 1_500L

        private val AUTO_START_NAME = Regex("(?i)auto.?start|autoboot|auto.?launch|startup|bootstart|chainlaunch")

        private val AUTO_START_SCREENS = listOf(
            // Tecno, Infinix (Phone Master) and itel
            "com.transsion.phonemaster" to "com.cyin.himgr.autostart.AutoStartActivity",
            "com.transsion.phonemanager" to "com.cyin.himgr.autostart.AutoStartActivity",
            "com.itel.autobootmanager" to "com.itel.autobootmanager.activity.AutoBootMgrActivity",
            // Xiaomi, Redmi, Poco
            "com.miui.securitycenter" to "com.miui.permcenter.autostart.AutoStartManagementActivity",
            // Oppo, Realme, OnePlus (ColorOS / OxygenOS)
            "com.oplus.safecenter" to "com.oplus.safecenter.startupapp.view.StartupAppListActivity",
            "com.oplus.safecenter" to "com.oplus.safecenter.permission.startup.StartupAppListActivity",
            "com.coloros.safecenter" to "com.coloros.safecenter.permission.startup.StartupAppListActivity",
            "com.coloros.safecenter" to "com.coloros.safecenter.startupapp.StartupAppListActivity",
            "com.coloros.safecenter" to "com.coloros.safecenter.permission.startupapp.StartupAppListActivity",
            "com.coloros.safecenter" to "com.coloros.safecenter.permission.startupmanager.StartupAppListActivity",
            "com.oppo.safe" to "com.oppo.safe.permission.startup.StartupAppListActivity",
            "com.oneplus.security" to "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity",
            // Vivo, iQOO
            "com.vivo.permissionmanager" to "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
            "com.iqoo.secure" to "com.iqoo.secure.ui.phoneoptimize.BgStartUpManager",
            "com.iqoo.secure" to "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity",
            // Huawei, Honor
            "com.huawei.systemmanager" to "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
            "com.huawei.systemmanager" to "com.huawei.systemmanager.appcontrol.activity.StartupAppControlActivity",
            "com.huawei.systemmanager" to "com.huawei.systemmanager.optimize.process.ProtectActivity",
            "com.hihonor.systemmanager" to "com.hihonor.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
            // Asus, Letv, Meizu
            "com.asus.mobilemanager" to "com.asus.mobilemanager.autostart.AutoStartActivity",
            "com.asus.mobilemanager" to "com.asus.mobilemanager.entry.FunctionActivity",
            "com.letv.android.letvsafe" to "com.letv.android.letvsafe.AutobootManageActivity",
            "com.meizu.safe" to "com.meizu.safe.permission.SmartBGActivity",
        )

        private val SETTINGS_NAME = Regex("(?i)auto.?start|autoboot|auto.?launch")

        /** Auto-start screens opened by action. */
        private val AUTO_START_ACTIONS = listOf(
            "miui.intent.action.OP_AUTO_START" to "com.miui.securitycenter",
        )

        /** Background limits, on brands with no auto-start list. */
        private val BATTERY_SCREENS = listOf(
            // Samsung: Battery, with Background usage limits.
            "com.samsung.android.lool" to "com.samsung.android.sm.battery.ui.BatteryActivity",
            "com.samsung.android.lool" to "com.samsung.android.sm.ui.battery.BatteryActivity",
            "com.samsung.android.sm" to "com.samsung.android.sm.ui.battery.BatteryActivity",
            // Nokia (HMD)
            "com.evenwell.powersaving.g3" to "com.evenwell.powersaving.g3.exception.PowerSaverExceptionActivity",
            // Asus
            "com.asus.mobilemanager" to "com.asus.mobilemanager.powersaver.PowerSaverSettings",
        )

        /** Some phones put auto-start in their Settings app. */
        private val SETTINGS_APPS = listOf("com.android.settings", "com.transsion.settings")

        private val PHONE_MANAGERS = listOf(
            "com.transsion.phonemaster",
            "com.transsion.phonemanager",
            "com.itel.autobootmanager",
            "com.miui.securitycenter",
            "com.oplus.safecenter",
            "com.coloros.safecenter",
            "com.oppo.safe",
            "com.oneplus.security",
            "com.vivo.permissionmanager",
            "com.iqoo.secure",
            "com.huawei.systemmanager",
            "com.hihonor.systemmanager",
            "com.asus.mobilemanager",
            "com.letv.android.letvsafe",
            "com.meizu.safe",
        )
    }
}
