package com.worldai.world_ai

import android.content.ComponentName
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ICON_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "setIcon") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val icon = call.arguments as? String
                if (icon == null) {
                    result.error("invalid_icon", "Icône inconnue", null)
                    return@setMethodCallHandler
                }

                val target = iconComponents[icon]
                if (target == null) {
                    result.error("invalid_icon", "Icône inconnue", null)
                    return@setMethodCallHandler
                }

                try {
                    val manager = packageManager
                    for ((name, component) in iconComponents) {
                        manager.setComponentEnabledSetting(
                            ComponentName(this, component),
                            if (name == icon) {
                                PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                            } else {
                                PackageManager.COMPONENT_ENABLED_STATE_DISABLED
                            },
                            PackageManager.DONT_KILL_APP,
                        )
                    }
                    result.success(null)
                } catch (error: Exception) {
                    result.error("icon_change_failed", error.message, null)
                }
            }
    }

    companion object {
        private const val ICON_CHANNEL = "com.worldai.world_ai/app_icon"
        private val iconComponents = mapOf(
            "default" to "com.worldai.world_ai.MainActivityDefault",
            "image2" to "com.worldai.world_ai.MainActivityImage2",
            "image3" to "com.worldai.world_ai.MainActivityImage3",
        )
    }
}
