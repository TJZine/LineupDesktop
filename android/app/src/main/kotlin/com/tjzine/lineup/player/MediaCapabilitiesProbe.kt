package com.tjzine.lineup.player

import android.content.Context
import android.hardware.display.DisplayManager
import android.media.MediaCodecInfo
import android.media.MediaCodecInfo.CodecProfileLevel as Profile
import android.media.MediaCodecList
import android.os.Build
import android.os.Looper
import android.view.Display
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.audio.AudioCapabilities

/** Current decoder and output facts only; Plex eligibility and conversion policy belong to Dart. */
@UnstableApi
internal class MediaCapabilitiesProbe(
    private val context: Context,
    private val codecs: () -> List<MediaCodecInfo> = {
        MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.toList()
    },
    private val audio: () -> AudioCapabilities = {
        AudioCapabilities.getCapabilities(
            context,
            AudioAttributes.Builder().setUsage(C.USAGE_MEDIA)
                .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(),
            null,
        )
    },
    private val displayHdr: () -> IntArray = {
        (context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager)
            .getDisplay(Display.DEFAULT_DISPLAY)?.hdrCapabilities?.supportedHdrTypes ?: intArrayOf()
    },
) {
    fun read(): Map<String, Any> {
        check(Looper.myLooper() == Looper.getMainLooper())
        val entries = codecs().filterNot { it.isEncoder }.sortedWith(
            compareBy<MediaCodecInfo> { !hardware(it) }.thenBy { it.name },
        )
        val hdr = displayHdr().toSet()
        val video = mutableListOf<Map<String, Any>>()
        val audioCodecs = sortedSetOf("pcm")
        val dolbyVision = entries.flatMap { info ->
            info.supportedTypes.filter { it.equals("video/dolby-vision", true) }.flatMap { type ->
                capabilities(info, type)?.profileLevels?.mapNotNull {
                    dolbyVisionProfile(it.profile)
                } ?: emptyList()
            }
        }.distinct().sorted()
        for (info in entries) {
            for (mime in info.supportedTypes.sorted()) {
                val caps = capabilities(info, mime) ?: continue
                val codec = videoCodecs[mime]
                if (codec == null) {
                    audioCodecsByMime[mime]?.let { audioCodecs += it }
                    continue
                }
                // Keep one decoder's coherent limits rather than combining incompatible maxima.
                if (video.any { it["codec"] == codec }) continue
                val levels = caps.profileLevels.toList()
                val value = linkedMapOf<String, Any>("codec" to codec)
                val profiles = levels.mapNotNull { profile(codec, it.profile) }.distinct().sorted()
                if (profiles.isNotEmpty()) value["profiles"] = profiles.take(64)
                levels.mapNotNull { level(codec, it.level) }.maxByOrNull { it.toDouble() }?.let {
                    value["maxLevel"] = it
                }
                caps.videoCapabilities?.let {
                    value["maxWidth"] = it.supportedWidths.upper.coerceIn(1, 32768)
                    value["maxHeight"] = it.supportedHeights.upper.coerceIn(1, 32768)
                    value["maxBitrateKbps"] = (it.bitrateRange.upper / 1000).coerceAtLeast(1)
                }
                val transfers = sortedSetOf<String>()
                val supports10 = profiles.any { it == "main 10" || it == "2" || it == "3" }
                val supportsHdr10 = levels.any {
                    when (codec) {
                        "hevc" -> it.profile in listOf(Profile.HEVCProfileMain10HDR10, Profile.HEVCProfileMain10HDR10Plus)
                        "vp9" -> it.profile in listOf(Profile.VP9Profile2HDR, Profile.VP9Profile3HDR, Profile.VP9Profile2HDR10Plus, Profile.VP9Profile3HDR10Plus)
                        "av1" -> it.profile in listOf(Profile.AV1ProfileMain10HDR10, Profile.AV1ProfileMain10HDR10Plus)
                        else -> false
                    }
                }
                val supportsHdr10Plus = levels.any {
                    when (codec) {
                        "hevc" -> it.profile == Profile.HEVCProfileMain10HDR10Plus
                        "vp9" -> it.profile in listOf(Profile.VP9Profile2HDR10Plus, Profile.VP9Profile3HDR10Plus)
                        "av1" -> it.profile == Profile.AV1ProfileMain10HDR10Plus
                        else -> false
                    }
                }
                if (supportsHdr10 && Display.HdrCapabilities.HDR_TYPE_HDR10 in hdr) transfers += "hdr10"
                if (supportsHdr10Plus && Display.HdrCapabilities.HDR_TYPE_HDR10_PLUS in hdr) transfers += "hdr10plus"
                if (supports10 && Display.HdrCapabilities.HDR_TYPE_HLG in hdr) transfers += "hlg"
                value["hdr"] = transfers.toList()
                value["dolbyVisionProfiles"] = dolbyVision.filter {
                    when (codec) {
                        "h264" -> it in listOf(0, 1, 9)
                        "hevc" -> it in 2..8
                        "av1" -> it == 10
                        else -> false
                    }
                }.take(64)
                video += value
            }
        }
        val output = audio()
        return mapOf(
            "videoDecoders" to video.distinct().take(64),
            "audioDecoders" to audioCodecs.take(64),
            "audioPassthrough" to passthrough.filter { output.supportsEncoding(it.first) }
                .map { it.second }.distinct().take(16),
            "containers" to containers,
        )
    }

    private fun capabilities(info: MediaCodecInfo, mime: String): MediaCodecInfo.CodecCapabilities? =
        try {
            info.getCapabilitiesForType(mime).takeUnless {
                it.isFeatureRequired(MediaCodecInfo.CodecCapabilities.FEATURE_SecurePlayback)
            }
        } catch (_: IllegalArgumentException) {
            null
        }

    companion object {
        val empty: Map<String, Any> = mapOf(
            "videoDecoders" to emptyList<Any>(), "audioDecoders" to emptyList<String>(),
            "audioPassthrough" to emptyList<String>(), "containers" to emptyList<String>(),
        )
        // Installed progressive extractors; HLS is a separate, explicit load kind.
        private val containers = listOf("aac", "avi", "flac", "mkv", "mov", "mp3", "mp4", "mpeg", "mpegts", "ogg", "wav", "webm")
        private val videoCodecs = mapOf(
            "video/avc" to "h264", "video/hevc" to "hevc", "video/x-vnd.on2.vp9" to "vp9",
            "video/x-vnd.on2.vp8" to "vp8", "video/av01" to "av1", "video/mpeg2" to "mpeg2video",
            "video/mp4v-es" to "mpeg4", "video/wvc1" to "vc1",
        )
        private val audioCodecsByMime = mapOf(
            "audio/mp4a-latm" to "aac", "audio/ac3" to "ac3", "audio/eac3" to "eac3",
            "audio/eac3-joc" to "eac3", "audio/true-hd" to "truehd", "audio/vnd.dts" to "dca",
            "audio/vnd.dts.hd" to "dtshd", "audio/flac" to "flac", "audio/opus" to "opus",
            "audio/vorbis" to "vorbis", "audio/mpeg" to "mp3", "audio/raw" to "pcm", "audio/ac4" to "ac4",
        )
        private val passthrough = listOf(
            C.ENCODING_AC3 to "ac3", C.ENCODING_E_AC3 to "eac3", C.ENCODING_DOLBY_TRUEHD to "truehd",
            C.ENCODING_DTS to "dca", C.ENCODING_DTS_HD to "dtshd",
        )
        private fun hardware(info: MediaCodecInfo): Boolean =
            if (Build.VERSION.SDK_INT >= 29) info.isHardwareAccelerated
            else !info.name.startsWith("OMX.google.") && !info.name.startsWith("c2.android.")

        private fun dolbyVisionProfile(value: Int): Int? =
            if (value > 0 && value.countOneBits() == 1 && value <= Profile.DolbyVisionProfileDvav110)
                value.countTrailingZeroBits() else null

        private fun profile(codec: String, value: Int): String? =
            when (codec) {
                "h264" -> when (value) {
                    Profile.AVCProfileBaseline, Profile.AVCProfileConstrainedBaseline -> "baseline"
                    Profile.AVCProfileMain -> "main"
                    Profile.AVCProfileHigh, Profile.AVCProfileConstrainedHigh -> "high"
                    Profile.AVCProfileHigh10 -> "high 10"
                    Profile.AVCProfileHigh422 -> "high 4:2:2"
                    Profile.AVCProfileHigh444 -> "high 4:4:4 predictive"
                    else -> null
                }
                "hevc" -> when (value) {
                    Profile.HEVCProfileMain -> "main"
                    Profile.HEVCProfileMain10, Profile.HEVCProfileMain10HDR10, Profile.HEVCProfileMain10HDR10Plus -> "main 10"
                    else -> null
                }
                "vp9" -> when (value) {
                    Profile.VP9Profile0 -> "0"
                    Profile.VP9Profile1 -> "1"
                    Profile.VP9Profile2, Profile.VP9Profile2HDR, Profile.VP9Profile2HDR10Plus -> "2"
                    Profile.VP9Profile3, Profile.VP9Profile3HDR, Profile.VP9Profile3HDR10Plus -> "3"
                    else -> null
                }
                "av1" -> when (value) {
                    Profile.AV1ProfileMain8 -> "main"
                    Profile.AV1ProfileMain10, Profile.AV1ProfileMain10HDR10, Profile.AV1ProfileMain10HDR10Plus -> "main 10"
                    else -> null
                }
                else -> null
            }

        private fun level(codec: String, value: Int): String? {
            val names = when (codec) {
                "h264" -> listOf("1", "1.1", "1.2", "1.3", "2", "2.1", "2.2", "3", "3.1", "3.2", "4", "4.1", "4.2", "5", "5.1", "5.2", "6", "6.1", "6.2")
                "hevc" -> listOf("1", "2", "2.1", "3", "3.1", "4", "4.1", "5", "5.1", "5.2", "6", "6.1", "6.2")
                "vp9" -> listOf("1", "1.1", "2", "2.1", "3", "3.1", "4", "4.1", "5", "5.1", "5.2", "6", "6.1", "6.2")
                "av1" -> listOf("2", "2.1", "2.2", "2.3", "3", "3.1", "3.2", "3.3", "4", "4.1", "4.2", "4.3", "5", "5.1", "5.2", "5.3", "6", "6.1", "6.2", "6.3", "7", "7.1", "7.2", "7.3")
                else -> return null
            }
            if (value <= 0 || value.countOneBits() != 1) return null
            val bit = value.countTrailingZeroBits()
            val index = when (codec) {
                "hevc" -> bit / 2 // Main/high tiers share a level.
                "h264" -> if (bit == 1) return null else if (bit > 1) bit - 1 else bit
                else -> bit
            }
            return names.getOrNull(index)
        }
    }
}
