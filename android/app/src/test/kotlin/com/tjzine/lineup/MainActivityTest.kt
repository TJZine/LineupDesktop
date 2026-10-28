package com.tjzine.lineup

import android.app.UiModeManager
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
class MainActivityTest {
    // Attach the context without onCreate: argument construction needs no Flutter
    // engine/JNI. These tests do not claim real engine or presentation acceptance.
    private fun activity(
        mode: Int = Configuration.UI_MODE_TYPE_NORMAL,
        feature: String? = null,
        arguments: ArrayList<String>? = null,
    ): MainActivity {
        val intent = Intent()
        if (arguments != null) intent.putStringArrayListExtra("dart_entrypoint_args", arguments)
        val activity = Robolectric.buildActivity(MainActivity::class.java, intent).get()
        shadowOf(activity.getSystemService(UiModeManager::class.java)).setCurrentModeType(mode)
        shadowOf(activity.packageManager).apply {
            setSystemFeature(PackageManager.FEATURE_LEANBACK, false)
            setSystemFeature("amazon.hardware.fire_tv", false)
            if (feature != null) setSystemFeature(feature, true)
        }
        return activity
    }

    @Test
    fun entrypointArgumentsFollowUiMode() {
        for ((mode, expected) in listOf(
            Configuration.UI_MODE_TYPE_TELEVISION to "tv",
            Configuration.UI_MODE_TYPE_NORMAL to "handheld",
            Configuration.UI_MODE_TYPE_CAR to "handheld",
            Configuration.UI_MODE_TYPE_DESK to "handheld",
        )) {
            assertEquals(listOf("--form-factor=$expected"), activity(mode).getDartEntrypointArgs())
        }
    }

    @Test
    fun tvFeaturesProduceTvArgumentsWithoutTelevisionUiMode() {
        for (feature in listOf(PackageManager.FEATURE_LEANBACK, "amazon.hardware.fire_tv")) {
            assertEquals(
                listOf("--form-factor=tv"),
                activity(feature = feature).getDartEntrypointArgs(),
            )
        }
    }

    @Test
    fun nativeFactReplacesCallerFlagsAndPreservesOtherArguments() {
        val original = arrayListOf(
            "--media=lineup-test://synthetic",
            "--form-factor=tv",
            "--case=product",
            "--form-factor=handheld",
            "--form-factor",
            "--form-factor=invalid",
        )
        val saved = original.toList()
        val activity = activity(arguments = original)
        assertEquals(
            listOf("--media=lineup-test://synthetic", "--case=product", "--form-factor=handheld"),
            activity.getDartEntrypointArgs(),
        )
        assertEquals(saved, original)
    }

    @Test
    fun callerCannotOverrideTvWithHandheld() {
        assertEquals(
            listOf("--form-factor=tv"),
            activity(
                Configuration.UI_MODE_TYPE_TELEVISION,
                arguments = arrayListOf("--form-factor=handheld"),
            ).getDartEntrypointArgs(),
        )
    }

    @Test
    fun activityRetainsItsFirstFactAcrossUiModeChanges() {
        val activity = activity()
        assertEquals(listOf("--form-factor=handheld"), activity.getDartEntrypointArgs())
        shadowOf(activity.getSystemService(UiModeManager::class.java))
            .setCurrentModeType(Configuration.UI_MODE_TYPE_TELEVISION)
        shadowOf(activity.packageManager).setSystemFeature(PackageManager.FEATURE_LEANBACK, true)
        assertEquals(listOf("--form-factor=handheld"), activity.getDartEntrypointArgs())
    }
}
