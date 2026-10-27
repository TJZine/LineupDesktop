package com.tjzine.lineup.player

import android.app.Activity
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.ui.SubtitleView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

/** Activity composition root installs [view] below Flutter, keeping video default-z-order. */
@UnstableApi
class NativePlayerAdapter(private val activity: Activity, messenger: BinaryMessenger) {
    val view = FrameLayout(activity)
    private val video = SurfaceView(activity)
    private val subtitles = SubtitleView(activity)
    private val handler = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(messenger, "lineup/native_player")
    private var rectangle = VideoRect(0.0, 0.0, 0.0, 0.0, 1.0)
    private var videoSize = VideoSize.UNKNOWN
    private val controller =
        NativePlayerController(
            object : PlayerHost {
                override fun firstFrame(generation: Long, loadId: Long, positionMs: Long) {
                    if (
                        activity.applicationInfo.flags and
                            android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0
                    ) {
                        android.util.Log.i(
                            "LineupPlayer",
                            "first_frame generation=$generation loadId=$loadId positionMs=$positionMs",
                        )
                    }
                }

                override fun fragmentSeek(generation: Long, loadId: Long, position: Long) {
                    if (
                        activity.applicationInfo.flags and
                            android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0
                    ) {
                        android.util.Log.i(
                            "LineupPlayer",
                            "fragment_seek generation=$generation loadId=$loadId position=$position",
                        )
                    }
                }

                override fun frameTimestamp(
                    generation: Long,
                    loadId: Long,
                    presentationTimeUs: Long,
                ) {
                    if (
                        activity.applicationInfo.flags and
                            android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0
                    ) {
                        android.util.Log.i(
                            "LineupPlayer",
                            "frame_timestamp generation=$generation loadId=$loadId ptsUs=$presentationTimeUs",
                        )
                    }
                }

                override fun sourceInitialization(
                    generation: Long,
                    loadId: Long,
                    revision: Int,
                    accepted: Boolean,
                ) {
                    if (
                        activity.applicationInfo.flags and
                            android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0
                    ) {
                        android.util.Log.i(
                            "LineupPlayer",
                            "source_initialization generation=$generation loadId=$loadId revision=$revision accepted=$accepted",
                        )
                    }
                }

                override fun post(task: () -> Unit) {
                    handler.post(task)
                }

                override fun rect(rect: VideoRect) {
                    rectangle = rect
                    layoutVideo()
                }

                override fun keepScreenOn(keep: Boolean) {
                    if (keep)
                        activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    else activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                }

                override fun createEngine(): PlayerEngine =
                    Media3Engine(
                        activity,
                        handler,
                        video,
                        subtitles,
                        { size ->
                            videoSize = size
                            layoutVideo()
                        },
                        ::keepScreenOn,
                    )

                override fun event(value: Map<String, Any?>) {
                    channel.invokeMethod("event", value)
                }
            }
        )

    init {
        listOf(view, video, subtitles).forEach {
            it.isFocusable = false
            it.isFocusableInTouchMode = false
            it.isClickable = false
            it.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        }
        view.clipChildren = true
        view.addView(video)
        view.addView(subtitles)
        channel.setMethodCallHandler { call, result ->
            controller.call(
                call.method,
                call.arguments,
                object : NativePlayerController.Reply {
                    override fun success(value: Any?) {
                        result.success(value)
                    }

                    override fun error(code: String) {
                        result.error(code, "Native player command failed", null)
                    }

                    override fun notImplemented() {
                        result.notImplemented()
                    }
                },
            )
        }
        layoutVideo()
    }

    private fun layoutVideo() {
        val r = rectangle
        val width = pixels(r.width * r.scale)
        val height = pixels(r.height * r.scale)
        view.layoutParams =
            FrameLayout.LayoutParams(width, height, Gravity.TOP or Gravity.LEFT).apply {
                leftMargin = pixels(r.left * r.scale)
                topMargin = pixels(r.top * r.scale)
            }
        var fitWidth = width
        var fitHeight = height
        if (videoSize.width > 0 && videoSize.height > 0 && width > 0 && height > 0) {
            val aspect =
                videoSize.width.toDouble() * videoSize.pixelWidthHeightRatio / videoSize.height
            if (aspect.isFinite() && aspect > 0) {
                if (width.toDouble() / height > aspect) fitWidth = (height * aspect).roundToInt()
                else fitHeight = (width / aspect).roundToInt()
            }
        }
        // Hide the SurfaceView itself, not only its container. A VISIBLE SurfaceView
        // laid out at 0x0 skips its surface updates (Android 11/12), so a window
        // stop/start while the player is hidden would orphan its SurfaceControl;
        // later loads then render into an offscreen layer (black picture, audio
        // and subtitles intact). Hiding it releases the surface while it still has
        // a frame; Media3 detaches and reattaches through the SurfaceHolder.
        val shown = fitWidth > 0 && fitHeight > 0
        view.visibility = if (shown) View.VISIBLE else View.INVISIBLE
        video.visibility = if (shown) View.VISIBLE else View.INVISIBLE
        video.layoutParams = FrameLayout.LayoutParams(fitWidth, fitHeight, Gravity.CENTER)
        subtitles.layoutParams = FrameLayout.LayoutParams(fitWidth, fitHeight, Gravity.CENTER)
    }

    private fun pixels(value: Double) =
        value.coerceIn(Int.MIN_VALUE.toDouble(), Int.MAX_VALUE.toDouble()).roundToInt()

    fun releaseForBackground() {
        controller.releaseForBackground()
    }

    fun close() {
        channel.setMethodCallHandler(null)
        controller.close()
        (view.parent as? ViewGroup)?.removeView(view)
    }
}
