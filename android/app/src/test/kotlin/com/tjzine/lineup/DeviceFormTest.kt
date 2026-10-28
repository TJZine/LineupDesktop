package com.tjzine.lineup

import android.app.Activity
import android.app.UiModeManager
import android.content.pm.PackageManager
import android.content.res.Configuration
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
@Config(manifest = Config.NONE, sdk = [28])
class DeviceFormTest {
    private fun withActivity(
        mode: Int = Configuration.UI_MODE_TYPE_NORMAL,
        feature: String? = null,
        check: (Activity) -> Unit,
    ) {
        val controller = Robolectric.buildActivity(Activity::class.java).setup()
        val activity = controller.get()
        shadowOf(activity.getSystemService(UiModeManager::class.java)).setCurrentModeType(mode)
        shadowOf(activity.packageManager).apply {
            setSystemFeature(PackageManager.FEATURE_LEANBACK, false)
            setSystemFeature("amazon.hardware.fire_tv", false)
            if (feature != null) setSystemFeature(feature, true)
        }
        try {
            check(activity)
        } finally {
            controller.pause().stop().destroy()
        }
    }

    @Test
    fun televisionUiModeIsTv() = withActivity(Configuration.UI_MODE_TYPE_TELEVISION) {
        assertEquals(DeviceForm.TV, DeviceForm.detect(it))
    }

    @Test
    fun leanbackFeatureIsTvInNormalMode() = withActivity(feature = PackageManager.FEATURE_LEANBACK) {
        assertEquals(DeviceForm.TV, DeviceForm.detect(it))
    }

    @Test
    fun fireTvFeatureIsTvInNormalMode() = withActivity(feature = "amazon.hardware.fire_tv") {
        assertEquals(DeviceForm.TV, DeviceForm.detect(it))
    }

    @Test
    fun normalPhoneIsHandheld() = withActivity {
        assertEquals(DeviceForm.HANDHELD, DeviceForm.detect(it))
    }

    @Test
    fun carAndDeskWithoutTvFeaturesAreHandheld() {
        for (mode in listOf(Configuration.UI_MODE_TYPE_CAR, Configuration.UI_MODE_TYPE_DESK)) {
            withActivity(mode) { assertEquals(DeviceForm.HANDHELD, DeviceForm.detect(it)) }
        }
    }

    @Test
    fun dispatcherReturnsDetectionAndRejectsEveryNonNullArgument() = withActivity {
        val observer = KeyboardVisibilityObserver(it) {}
        val dispatcher = PlatformChannel(it, observer)
        try {
            val reply = Result()
            dispatcher.onMethodCall(MethodCall("deviceProfile", null), reply)
            assertEquals(mapOf("formFactor" to "handheld"), reply.value)
            for (argument in listOf(emptyMap<String, Any>(), false, 0, "tv")) {
                val invalid = Result()
                dispatcher.onMethodCall(MethodCall("deviceProfile", argument), invalid)
                assertEquals("invalid_arguments", invalid.errorCode)
                assertNull(invalid.value)
            }
        } finally {
            dispatcher.close()
            observer.close()
        }
    }

    @Test
    fun dispatcherReturnsTvWireValue() = withActivity(Configuration.UI_MODE_TYPE_TELEVISION) {
        val observer = KeyboardVisibilityObserver(it) {}
        val dispatcher = PlatformChannel(it, observer)
        try {
            val reply = Result()
            dispatcher.onMethodCall(MethodCall("deviceProfile", null), reply)
            assertEquals(mapOf("formFactor" to "tv"), reply.value)
        } finally {
            dispatcher.close()
            observer.close()
        }
    }

    private class Result : MethodChannel.Result {
        var value: Any? = null
        var errorCode: String? = null
        override fun success(result: Any?) { value = result }
        override fun error(code: String, message: String?, details: Any?) { errorCode = code }
        override fun notImplemented() { fail("Unexpected method") }
    }
}
