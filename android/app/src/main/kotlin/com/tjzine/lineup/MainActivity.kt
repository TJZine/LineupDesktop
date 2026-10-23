package com.tjzine.lineup

import android.os.Build
import android.os.Bundle
import android.view.KeyEvent
import android.widget.FrameLayout
import com.tjzine.lineup.player.NativePlayerAdapter
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var nativePlayer: NativePlayerAdapter? = null
    private var platformChannel: MethodChannel? = null
    private var keyboardVisibility: KeyboardVisibilityObserver? = null
    private val backInput by lazy {
        AndroidBackInput(systemBackCallbacks = Build.VERSION.SDK_INT >= 33) {
            flutterEngine?.navigationChannel?.popRoute()
        }
    }

    override fun getBackgroundMode() = BackgroundMode.transparent

    override fun getRenderMode() = RenderMode.surface

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Video keeps default SurfaceView z-order; subtitles are window content,
        // and Flutter's transparent SurfaceView is on top of both.
        nativePlayer?.let { findViewById<FrameLayout>(android.R.id.content).addView(it.view, 0) }
    }

    override fun onStop() {
        nativePlayer?.releaseForBackground()
        super.onStop()
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
        nativePlayer = NativePlayerAdapter(this, flutterEngine.dartExecutor.binaryMessenger)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lineup/platform")
        val visibility = KeyboardVisibilityObserver(this) { visible ->
            channel.invokeMethod("keyboardVisibilityChanged", visible)
        }
        keyboardVisibility = visibility
        platformChannel = channel.also {
            it.setMethodCallHandler(PlatformChannel(this, visibility))
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        backInput.cancelPendingPress()
        keyboardVisibility?.close()
        keyboardVisibility = null
        nativePlayer?.close()
        nativePlayer = null
        platformChannel?.setMethodCallHandler(null)
        platformChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
