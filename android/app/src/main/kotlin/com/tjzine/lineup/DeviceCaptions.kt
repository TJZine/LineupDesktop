package com.tjzine.lineup

import android.content.Context
import android.content.pm.ApplicationInfo
import android.graphics.Typeface
import android.view.accessibility.CaptioningManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** OS-scoped channel. A listener is owned only between Dart's listen and cancel. */
internal class DeviceCaptions(
    context: Context,
    messenger: BinaryMessenger,
    private val manager: CaptioningManager = context.getSystemService(CaptioningManager::class.java),
) : MethodChannel.MethodCallHandler, AutoCloseable {
    private val channel = MethodChannel(messenger, "lineup/device_captions")
    private val debug = context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
    private var listening = false
    private val listener = object : CaptioningManager.CaptioningChangeListener() {
        override fun onEnabledChanged(enabled: Boolean) = changed()
        override fun onFontScaleChanged(fontScale: Float) = changed()
        override fun onUserStyleChanged(userStyle: CaptioningManager.CaptionStyle) = changed()
        override fun onLocaleChanged(locale: java.util.Locale?) = changed()
    }
    init { channel.setMethodCallHandler(this) }

    internal fun read(): Map<String, Any?> {
        val style = manager.userStyle
        return mapOf(
            "enabled" to manager.isEnabled,
            "fontScale" to manager.fontScale.toDouble(),
            "foreground" to if (style.hasForegroundColor()) style.foregroundColor.toLong() and 0xffffffffL else null,
            "background" to if (style.hasBackgroundColor()) style.backgroundColor.toLong() and 0xffffffffL else null,
            "window" to if (style.hasWindowColor()) style.windowColor.toLong() and 0xffffffffL else null,
            "edgeColor" to if (style.hasEdgeColor()) style.edgeColor.toLong() and 0xffffffffL else null,
            "edgeType" to if (style.hasEdgeType()) edge(style.edgeType) else null,
            "typeface" to typeface(style.typeface),
        )
    }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "read" -> result.success(read())
                "listen" -> {
                    if (!listening) { manager.addCaptioningChangeListener(listener); listening = true }
                    result.success(null)
                }
                "cancel" -> { cancel(); result.success(null) }
                else -> result.notImplemented()
            }
        } catch (_: Exception) {
            skipped()
            result.error("native_command_error", "Device captions unavailable", null)
        }
    }
    private fun changed() {
        if (listening) try { channel.invokeMethod("changed", read()) } catch (_: Exception) { skipped() }
    }
    private fun skipped() {
        if (debug) android.util.Log.d("LineupPlayer", "Device caption update skipped")
    }
    private fun cancel() {
        if (listening) { manager.removeCaptioningChangeListener(listener); listening = false }
    }
    override fun close() {
        channel.setMethodCallHandler(null)
        try { cancel() } catch (_: Exception) { skipped() }
    }
    companion object {
        internal fun edge(value: Int): String? = when (value) {
            CaptioningManager.CaptionStyle.EDGE_TYPE_NONE -> "none"
            CaptioningManager.CaptionStyle.EDGE_TYPE_OUTLINE -> "outline"
            CaptioningManager.CaptionStyle.EDGE_TYPE_DROP_SHADOW -> "dropShadow"
            CaptioningManager.CaptionStyle.EDGE_TYPE_RAISED -> "raised"
            CaptioningManager.CaptionStyle.EDGE_TYPE_DEPRESSED -> "depressed"
            else -> null
        }
        internal fun typeface(value: Typeface?): String? {
            if (value == null) return null
            return listOf(
                Typeface.SANS_SERIF to "standard", Typeface.MONOSPACE to "monoSans", Typeface.SERIF to "serif",
                Typeface.create("serif-monospace", Typeface.NORMAL) to "monoSerif",
                Typeface.create("casual", Typeface.NORMAL) to "casual",
                Typeface.create("cursive", Typeface.NORMAL) to "cursive",
                Typeface.create("sans-serif-smallcaps", Typeface.NORMAL) to "smallCaps",
            ).firstOrNull { it.first == value }?.second
        }
    }
}
