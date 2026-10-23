package com.tjzine.lineup

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** The only lineup/platform dispatcher. Native code owns the linking URL. */
class PlatformChannel(private val activity: Activity) : MethodChannel.MethodCallHandler {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "moveTaskToBack" -> {
                activity.moveTaskToBack(true)
                result.success(true)
            }
            "openPlexLink" -> {
                if (call.arguments != null) {
                    result.error("invalid_arguments", "openPlexLink accepts no arguments.", null)
                    return
                }
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(PLEX_LINK))
                val opened = try {
                    activity.startActivity(intent)
                    true
                } catch (_: ActivityNotFoundException) {
                    false
                } catch (_: SecurityException) {
                    false
                }
                result.success(opened)
            }
            else -> result.notImplemented()
        }
    }

    companion object {
        private const val PLEX_LINK = "https://plex.tv/link"
    }
}
