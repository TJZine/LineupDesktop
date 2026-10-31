package com.tjzine.lineup.player

import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.content.Context
import android.os.Build
import android.os.Handler
import com.tjzine.lineup.BuildConfig
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Opt-in fixture seam; never installed as an alternative production load protocol. */
internal class E6Bridge(context: Context, messenger: BinaryMessenger, private val handler: Handler, arguments: List<String>) {
    private val transportSelectors = arguments.filter { it.startsWith("--e6-transport") }
    private val transportRequested = BuildConfig.DEBUG && transportSelectors.isNotEmpty()
    private val transportMode = transportSelectors.singleOrNull()?.let {
        when (it) { "--e6-transport=eof" -> "eof"; "--e6-transport=line" -> "line"; else -> null }
    }
    val enabled = BuildConfig.DEBUG && "--case=session-live" in arguments &&
        (("--e6-observe" in arguments) xor ("--e6-public-baseline" in arguments)) &&
        (!transportRequested || transportMode != null && "--e6-observe" in arguments)
    private val baseline = "--e6-public-baseline" in arguments
    private val channel = if (enabled) MethodChannel(messenger, "lineup/e6") else null
    private var current: E6Observation? = null
    private var claimed = false
    private var cancelled = false
    private var inputReadyNs: Long? = null
    private val readyFile by lazy { java.io.File(context.cacheDir, "e6-ready") }
    private val pid = android.os.Process.myPid()
    private var transportInitializationFailed = false
    private val transportStatus = if (enabled && transportMode != null) try {
        E6TransportStatus(context.cacheDir, transportMode, pid)
    } catch (_: Exception) { transportInitializationFailed = true; null } else null

    init {
        if (enabled) {
            if (transportMode == null) readyFile.delete()
            else try {
                java.nio.file.Files.deleteIfExists(readyFile.toPath())
                java.nio.file.Files.deleteIfExists(java.io.File(context.cacheDir, "e6-ready.tmp").toPath())
            } catch (_: Exception) { transportInitializationFailed = true }
        }
        channel?.setMethodCallHandler { call, result ->
            if (!enabled) result.error("observer_disabled", "E6 observer unavailable", null)
            else try {
                if (transportRequested && call.method in setOf("configure", "drain", "capabilities"))
                    throw E6Failure("invalid_probe")
                when (call.method) {
                    "transportStatus" -> {
                        if (cancelled) throw E6Failure("invalid_probe")
                        if (transportInitializationFailed) throw E6Failure("io_failure")
                        val status = transportStatus ?: throw E6Failure("invalid_probe")
                        status.store(call.arguments)
                        result.success(mapOf("stored" to true))
                    }
                    "markInputReady" -> {
                        if (call.arguments != null || current != null || inputReadyNs != null || cancelled)
                            throw E6Failure("invalid_config")
                        if (transportInitializationFailed) throw E6Failure("io_failure")
                        // Public coordination only: no capability, metadata or diagnostics.
                        inputReadyNs = System.nanoTime()
                        val publicReady = "{\"protocol\":1,\"pid\":$pid,\"ready\":true}"
                        if (transportMode == null) readyFile.writeText(publicReady, Charsets.UTF_8)
                        else E6TransportStatus.publish(readyFile, publicReady.toByteArray(Charsets.UTF_8), 128)
                        result.success(mapOf("ready" to true))
                    }
                    "configure" -> {
                        if (current != null || cancelled) throw E6Failure("unexpected_load")
                        val origin = inputReadyNs ?: throw E6Failure("invalid_config")
                        val config = E6Config.parse(call.arguments, baseline)
                        current = E6Observation(config, handler, 1,
                            origin + if (config.public) 60_000_000_000L else 90_000_000_000L)
                        result.success(mapOf("configured" to true))
                    }
                    "drain" -> {
                        if (call.arguments != null) throw E6Failure("invalid_config")
                        result.success(current?.drain() ?: throw E6Failure("invalid_config"))
                    }
                    "cancel" -> {
                        if (call.arguments != null) throw E6Failure("invalid_config")
                        current?.cancel()
                        cancelled = true
                        clearOwnMarker()
                        result.success(mapOf("cancelled" to true))
                    }
                    "capabilities" -> {
                        if (call.arguments != null) throw E6Failure("invalid_config")
                        result.success(capabilities(enabled))
                    }
                    else -> result.notImplemented()
                }
            } catch (error: E6Failure) { result.error(error.code, "E6 command rejected", null) }
            catch (_: Exception) { result.error("invalid_config", "E6 command rejected", null) }
        }
    }

    fun claim(): E6Observation? {
        if (transportRequested) throw E6Failure("invalid_probe")
        if (!enabled) return null
        if (claimed) throw E6Failure("unexpected_load")
        val observation = current ?: throw E6Failure("invalid_config")
        claimed = true
        return observation
    }

    private fun clearOwnMarker() {
        try {
            if (readyFile.isFile && readyFile.length() <= 128 &&
                org.json.JSONObject(readyFile.readText(Charsets.UTF_8)).optInt("pid", -1) == pid) readyFile.delete()
        } catch (_: Exception) { /* Never delete a replacement/unknown owner. */ }
    }

    fun close() { cancelled = true; current?.cancel(); if (enabled) clearOwnMarker(); channel?.setMethodCallHandler(null) }

    companion object {
        internal fun capabilities(enabled: Boolean): Map<String, Any> {
            var h264 = false; var aac = false; var hevc10 = false; var hevcSize = false
            try {
                for (codec in MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.filterNot { it.isEncoder }) {
                    for (mime in codec.supportedTypes) {
                        val caps = try { codec.getCapabilitiesForType(mime) } catch (_: Exception) { continue }
                        when (mime) {
                            "video/avc" -> if (caps.profileLevels.any { it.profile == MediaCodecInfo.CodecProfileLevel.AVCProfileHigh } &&
                                caps.videoCapabilities?.isSizeSupported(1920, 1080) == true) h264 = true
                            "audio/mp4a-latm" -> if (caps.audioCapabilities?.let {
                                it.maxInputChannelCount >= 2 && it.isSampleRateSupported(48000)
                            } == true) aac = true
                            "video/hevc" -> {
                                val main10 = caps.profileLevels.any { it.profile in listOf(
                                    MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10,
                                    MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10HDR10,
                                    MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10HDR10Plus) }
                                if (main10) hevc10 = true
                                if (main10 && caps.videoCapabilities?.isSizeSupported(3840, 1600) == true) hevcSize = true
                            }
                        }
                    }
                }
            } catch (_: Exception) { /* Unknown remains false; no decoder names or diagnostics leave. */ }
            return mapOf("debugEnabled" to enabled, "apiLevel" to Build.VERSION.SDK_INT,
                "arm64" to ("arm64-v8a" in Build.SUPPORTED_ABIS), "h2641080" to h264,
                "aac" to aac, "hevcMain10" to hevc10, "hevc3840x1600" to hevcSize)
        }
    }
}
