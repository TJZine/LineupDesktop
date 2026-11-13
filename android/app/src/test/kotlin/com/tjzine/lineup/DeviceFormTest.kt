package com.tjzine.lineup

import android.app.Activity
import android.app.UiModeManager
import android.content.pm.PackageManager
import android.content.res.Configuration
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
}
