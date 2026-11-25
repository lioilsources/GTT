package com.ol1n.metropole

import android.content.ComponentName
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * App icon colour mode (specs/appicon.md "F na Androidu"): the launcher entry is one
 * activity-alias per mode (`.Icon<Mode>` in AndroidManifest.xml). Dart sends the chosen mode over
 * `metropole/app_icon`; the aliases are switched when the activity stops, because a launcher may
 * close the running task when its alias changes.
 */
class MainActivity : FlutterActivity() {
    private var pendingIcon: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ICON_CHANNEL).setMethodCallHandler { call, result ->
            val mode = call.arguments as? String
            when {
                call.method != "set" -> result.notImplemented()
                mode == null || mode !in ICON_MODES -> result.error("unknown_mode", "Unknown app icon mode: $mode", null)
                else -> {
                    pendingIcon = mode
                    result.success(true)
                }
            }
        }
    }

    override fun onStop() {
        super.onStop()
        pendingIcon?.let(::applyIcon)
        pendingIcon = null
    }

    /** Aliases are declared relative to the manifest namespace, which is this class's package. */
    private fun alias(mode: String) =
        ComponentName(this, "${MainActivity::class.java.`package`!!.name}.Icon${mode.replaceFirstChar(Char::uppercaseChar)}")

    private fun isOn(mode: String): Boolean = when (packageManager.getComponentEnabledSetting(alias(mode))) {
        PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
        PackageManager.COMPONENT_ENABLED_STATE_DEFAULT -> mode == ICON_DEFAULT
        else -> false
    }

    /** Enables the alias of [mode] first, then disables the others, so there is always an entry. */
    private fun applyIcon(mode: String) {
        if (!isOn(mode)) {
            packageManager.setComponentEnabledSetting(
                alias(mode), PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP,
            )
        }
        for (other in ICON_MODES) {
            if (other != mode && isOn(other)) {
                packageManager.setComponentEnabledSetting(
                    alias(other), PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP,
                )
            }
        }
    }

    private companion object {
        const val ICON_CHANNEL = "metropole/app_icon"
        const val ICON_DEFAULT = "sunset"
        val ICON_MODES = listOf("day", "night", "sunset", "teal", "japan")
    }
}
