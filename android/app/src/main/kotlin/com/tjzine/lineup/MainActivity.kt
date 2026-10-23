package com.tjzine.lineup

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var platformChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        platformChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "lineup/platform",
        ).also { it.setMethodCallHandler(PlatformChannel(this)) }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        platformChannel?.setMethodCallHandler(null)
        platformChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
