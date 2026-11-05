package com.tjzine.lineup

import android.content.Context
import android.graphics.Typeface
import android.os.Looper
import android.provider.Settings
import android.view.accessibility.CaptioningManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.nio.ByteBuffer
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [34])
class DeviceCaptionsTest {
    private class Messenger : BinaryMessenger {
        val changes = mutableListOf<MethodCall>()
        var handler: BinaryMessenger.BinaryMessageHandler? = null
        override fun send(channel: String, message: ByteBuffer?) {
            message?.rewind()
            changes.add(StandardMethodCodec.INSTANCE.decodeMethodCall(message!!))
        }
        override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) = send(channel, message)
        override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) { this.handler = handler }
    }
    private val result = object : MethodChannel.Result {
        override fun success(result: Any?) {}
        override fun error(code: String, message: String?, details: Any?) { fail(code) }
        override fun notImplemented() { fail() }
    }
    @Test fun readsRealManagerCustomFieldsAsUnsignedArgbAndNotifiesOnlyWhileListening() {
        val context = RuntimeEnvironment.getApplication()
        val settings = context.contentResolver
        Settings.Secure.putInt(settings, "accessibility_captioning_preset", -1)
        Settings.Secure.putInt(settings, "accessibility_captioning_foreground_color", 0x80ffffff.toInt())
        Settings.Secure.putInt(settings, "accessibility_captioning_background_color", 0)
        Settings.Secure.putInt(settings, "accessibility_captioning_window_color", 0)
        Settings.Secure.putInt(settings, "accessibility_captioning_edge_type", 2)
        Settings.Secure.putInt(settings, "accessibility_captioning_edge_color", 0xff000000.toInt())
        Settings.Secure.putFloat(settings, "accessibility_captioning_font_scale", 1.5f)
        Settings.Secure.putString(settings, "accessibility_captioning_typeface", "monospace")
        val messenger = Messenger()
        val captions = DeviceCaptions(context, messenger, context.getSystemService(CaptioningManager::class.java))
        val value = captions.read()
        assertEquals(0x80ffffffL, value["foreground"])
        assertEquals(0xff000000L, value["edgeColor"])
        assertEquals(1.5, value["fontScale"])
        assertEquals("dropShadow", value["edgeType"])
        assertEquals("monoSans", value["typeface"])
        captions.onMethodCall(MethodCall("listen", null), result)
        captions.onMethodCall(MethodCall("listen", null), result)
        Settings.Secure.putInt(settings, "accessibility_captioning_enabled", 1)
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue(messenger.changes.any { it.method == "changed" && (it.arguments as Map<*, *>)["enabled"] == true })
        captions.onMethodCall(MethodCall("cancel", null), result)
        val count = messenger.changes.size
        Settings.Secure.putInt(settings, "accessibility_captioning_enabled", 0)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(count, messenger.changes.size)
        captions.close()
        assertNull(messenger.handler)
    }
    @Test fun edgeAndTypefaceMappingsCoverAllPublishedValues() {
        assertEquals(listOf("none", "outline", "dropShadow", "raised", "depressed"), (0..4).map(DeviceCaptions::edge))
        assertNull(DeviceCaptions.edge(99))
        assertNull(DeviceCaptions.typeface(null))
        assertEquals("standard", DeviceCaptions.typeface(Typeface.SANS_SERIF))
        assertEquals("monoSans", DeviceCaptions.typeface(Typeface.MONOSPACE))
        assertEquals("serif", DeviceCaptions.typeface(Typeface.SERIF))
        for ((family, expected) in listOf("serif-monospace" to "monoSerif", "casual" to "casual",
            "cursive" to "cursive", "sans-serif-smallcaps" to "smallCaps"))
            assertEquals(expected, DeviceCaptions.typeface(Typeface.create(family, Typeface.NORMAL)))
    }
    @Test fun customUnsetFieldsRemainNull() {
        val context = RuntimeEnvironment.getApplication()
        val settings = context.contentResolver
        Settings.Secure.putInt(settings, "accessibility_captioning_preset", -1)
        for (key in listOf("foreground_color", "background_color", "window_color", "edge_color"))
            Settings.Secure.putInt(settings, "accessibility_captioning_$key", 0x00ffffff)
        Settings.Secure.putInt(settings, "accessibility_captioning_edge_type", -1)
        val captions = DeviceCaptions(context, Messenger())
        val value = captions.read()
        for (key in listOf("foreground", "background", "window", "edgeColor", "edgeType"))
            assertNull(key, value[key])
        captions.close()
    }

}
