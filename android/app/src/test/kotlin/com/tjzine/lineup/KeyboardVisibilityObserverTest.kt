package com.tjzine.lineup

import android.app.Activity
import android.view.ViewGroup
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
class KeyboardVisibilityObserverTest {
    @Test
    fun unavailableApiNeverManufacturesHiddenOrAddsAView() {
        val controller = Robolectric.buildActivity(Activity::class.java).setup()
        val activity = controller.get()
        val root = activity.window.decorView as ViewGroup
        val children = root.childCount
        val events = mutableListOf<Boolean>()
        val observer = KeyboardVisibilityObserver(activity, events::add)
        assertFalse(observer.watch())
        assertFalse(observer.watch())
        observer.unwatch()
        observer.unwatch()
        observer.close()
        observer.close()
        assertFalse(observer.watch())
        assertEquals(children, root.childCount)
        assertTrue(events.isEmpty())
        controller.pause().stop().destroy()
    }

    @Test
    fun dispatcherValidatesNoArgumentWireAndReturnsUnavailableSeparately() {
        val controller = Robolectric.buildActivity(Activity::class.java).setup()
        val activity = controller.get()
        val observer = KeyboardVisibilityObserver(activity) { fail("No API28 observation") }
        val dispatcher = PlatformChannel(activity, observer)
        for (method in listOf("watchKeyboardVisibility", "unwatchKeyboardVisibility")) {
            val invalid = Result()
            dispatcher.onMethodCall(MethodCall(method, mapOf("visible" to false)), invalid)
            assertEquals("invalid_arguments", invalid.errorCode)
        }
        val watch = Result()
        dispatcher.onMethodCall(MethodCall("watchKeyboardVisibility", null), watch)
        assertEquals(false, watch.value)
        val unwatch = Result()
        dispatcher.onMethodCall(MethodCall("unwatchKeyboardVisibility", null), unwatch)
        assertTrue(unwatch.succeeded)
        assertNull(unwatch.value)
        observer.close()
        controller.pause().stop().destroy()
    }

    private class Result : MethodChannel.Result {
        var value: Any? = null
        var succeeded = false
        var errorCode: String? = null
        override fun success(result: Any?) { value = result; succeeded = true }
        override fun error(code: String, message: String?, details: Any?) { errorCode = code }
        override fun notImplemented() { fail("Unexpected method") }
    }
}
