package com.tjzine.lineup

import android.app.Activity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
// The repository pins Java 17; Robolectric's API 36 image needs Java 21.
// Actual API 36 window/lifecycle behavior remains an emulator acceptance gate.
@Config(manifest = Config.NONE, sdk = [28, 30])
class WindowFactsTest {
    @Test
    fun observationUsesActualActivityModeAndRetiresOnUnwatchAndClose() {
        val controller = Robolectric.buildActivity(Activity::class.java).setup()
        val activity = controller.get()
        val observer = KeyboardVisibilityObserver(activity) {}
        val events = mutableListOf<Pair<String, Any?>>()
        val dispatcher = PlatformChannel(activity, observer, publish = { name, value ->
            events.add(name to value)
        })
        try {
            dispatcher.publishWindowFacts()
            assertTrue(events.isEmpty())
            dispatcher.onMethodCall(MethodCall("watchWindowFacts", null), Result())
            assertEquals(listOf("multiWindowChanged" to false), events)
            shadowOf(activity).setInMultiWindowMode(true)
            dispatcher.publishWindowFacts()
            assertEquals("multiWindowChanged" to true, events.last())
            dispatcher.onMethodCall(MethodCall("unwatchWindowFacts", null), Result())
            val count = events.size
            shadowOf(activity).setInMultiWindowMode(false)
            dispatcher.publishWindowFacts()
            assertEquals(count, events.size)
            dispatcher.onMethodCall(MethodCall("watchWindowFacts", null), Result())
            assertEquals("multiWindowChanged" to false, events.last())
            dispatcher.close()
            val closedCount = events.size
            dispatcher.publishWindowFacts()
            dispatcher.onMethodCall(MethodCall("watchWindowFacts", null), Result())
            assertEquals(closedCount, events.size)
        } finally {
            dispatcher.close()
            observer.close()
            controller.pause().stop().destroy()
        }
    }

    @Test
    fun invalidArgumentsNeverStartAnObservation() {
        val controller = Robolectric.buildActivity(Activity::class.java).setup()
        val activity = controller.get()
        val observer = KeyboardVisibilityObserver(activity) {}
        val dispatcher = PlatformChannel(activity, observer, publish = { _, _ -> fail("No observation expected") })
        try {
            for (method in listOf("watchWindowFacts", "unwatchWindowFacts")) {
                val reply = Result()
                dispatcher.onMethodCall(MethodCall(method, false), reply)
                assertEquals("invalid_arguments", reply.errorCode)
            }
            dispatcher.publishWindowFacts()
        } finally {
            dispatcher.close()
            observer.close()
            controller.pause().stop().destroy()
        }
    }

    private class Result : MethodChannel.Result {
        var errorCode: String? = null
        override fun success(result: Any?) { assertEquals(true, result) }
        override fun error(code: String, message: String?, details: Any?) { errorCode = code }
        override fun notImplemented() { fail("Unexpected method") }
    }
}
