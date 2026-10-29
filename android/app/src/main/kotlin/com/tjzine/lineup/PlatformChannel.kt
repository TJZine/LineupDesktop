package com.tjzine.lineup

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean

/** The only lineup/platform dispatcher. Native code owns the linking URL. */
class PlatformChannel(
    private val activity: Activity,
    private val keyboardVisibility: KeyboardVisibilityObserver,
    private val licenseResources: LicenseResources = LicenseResources(activity.assets),
    private val licenseExecutor: ExecutorService = Executors.newSingleThreadExecutor(),
) : MethodChannel.MethodCallHandler, AutoCloseable {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val closed = AtomicBoolean(false)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "listLicenseDocuments" -> {
                if (call.arguments != null) {
                    result.error("invalid_arguments", "listLicenseDocuments accepts no arguments.", null)
                    return
                }
                enqueueLicenseOperation(result) { licenseResources.list() }
            }
            "readLicenseDocument" -> {
                val arguments = call.arguments as? Map<*, *>
                val id = arguments?.get("id") as? String
                if (arguments == null || arguments.size != 1 || id == null) {
                    result.error("invalid_arguments", "readLicenseDocument requires an id.", null)
                    return
                }
                enqueueLicenseOperation(result) { licenseResources.read(id) }
            }
            "watchKeyboardVisibility", "unwatchKeyboardVisibility" -> {
                if (call.arguments != null) {
                    result.error("invalid_arguments", "${call.method} accepts no arguments.", null)
                    return
                }
                if (call.method == "watchKeyboardVisibility") {
                    result.success(keyboardVisibility.watch())
                } else {
                    keyboardVisibility.unwatch()
                    result.success(null)
                }
            }
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

    private fun enqueueLicenseOperation(
        result: MethodChannel.Result,
        operation: () -> Any?,
    ) {
        if (closed.get()) {
            result.error(
                "license_resources_unavailable",
                "License resources could not be loaded.",
                null,
            )
            return
        }
        try {
            licenseExecutor.execute {
                try {
                    val value = operation()
                    mainHandler.post {
                        if (!closed.get()) result.success(value)
                    }
                } catch (_: Exception) {
                    mainHandler.post {
                        if (!closed.get()) {
                            result.error(
                                "license_resources_unavailable",
                                "License resources could not be loaded.",
                                null,
                            )
                        }
                    }
                }
            }
        } catch (_: RejectedExecutionException) {
            result.error(
                "license_resources_unavailable",
                "License resources could not be loaded.",
                null,
            )
        }
    }

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        licenseExecutor.shutdownNow()
    }

    companion object {
        private const val PLEX_LINK = "https://plex.tv/link"
    }
}
