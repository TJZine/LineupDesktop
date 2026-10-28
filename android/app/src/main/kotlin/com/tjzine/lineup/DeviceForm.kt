package com.tjzine.lineup

import android.app.UiModeManager
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration

/** Android's form-factor fact; window size and orientation are separate concerns. */
enum class DeviceForm(val wireValue: String) {
    TV("tv"),
    HANDHELD("handheld");

    companion object {
        fun detect(context: Context): DeviceForm {
            val mode = context.getSystemService(UiModeManager::class.java)?.currentModeType
            val packages = context.packageManager
            return if (
                mode == Configuration.UI_MODE_TYPE_TELEVISION ||
                packages.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
                packages.hasSystemFeature("amazon.hardware.fire_tv")
            ) TV else HANDHELD
        }
    }
}
