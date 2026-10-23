package com.tjzine.lineup

import android.os.Build
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var platformChannel: MethodChannel? = null
    private val backInput by lazy {
        AndroidBackInput(systemBackCallbacks = Build.VERSION.SDK_INT >= 33) {
            flutterEngine?.navigationChannel?.popRoute()
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (flutterEngine != null && backInput.handle(event)) return true
        return super.dispatchKeyEvent(event)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus) backInput.cancelPendingPress()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        platformChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "lineup/platform",
        ).also { it.setMethodCallHandler(PlatformChannel(this)) }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        backInput.cancelPendingPress()
        platformChannel?.setMethodCallHandler(null)
        platformChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
