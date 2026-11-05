package com.tjzine.lineup.player

import android.media.MediaCodecInfo
import android.media.MediaCodecInfo.CodecProfileLevel as Profile
import android.media.MediaFormat
import android.view.Display
import androidx.media3.common.C
import androidx.media3.exoplayer.audio.AudioCapabilities
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.shadows.MediaCodecInfoBuilder
import org.robolectric.shadows.MediaCodecInfoBuilder.CodecCapabilitiesBuilder

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [30])
class MediaCapabilitiesProbeTest {
    private val context = RuntimeEnvironment.getApplication()

    private fun decoder(
        mime: String,
        profiles: List<Int> = emptyList(),
        level: Int = 1,
        name: String = "vendor.$mime",
        hardware: Boolean = true,
        secure: Boolean = false,
        encoder: Boolean = false,
    ): MediaCodecInfo {
        val format = if (mime.startsWith("video/")) MediaFormat.createVideoFormat(mime, 3840, 2160)
            else MediaFormat.createAudioFormat(mime, 48000, 8)
        val caps = CodecCapabilitiesBuilder.newBuilder().setMediaFormat(format)
            .setIsEncoder(encoder)
            .apply { if (mime.startsWith("video/")) setColorFormats(intArrayOf(MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible)) }
            .setProfileLevels(profiles.map { p -> Profile().apply { profile = p; this.level = level } }.toTypedArray())
            .apply { if (secure) setRequiredFeatures(arrayOf(MediaCodecInfo.CodecCapabilities.FEATURE_SecurePlayback)) }
            .build()
        return MediaCodecInfoBuilder.newBuilder().setName(name).setIsEncoder(encoder)
            .setIsHardwareAccelerated(hardware).setIsSoftwareOnly(!hardware)
            .setCapabilities(caps).build()
    }

    private fun probe(codecs: List<MediaCodecInfo>, encodings: IntArray = intArrayOf(C.ENCODING_PCM_16BIT), hdr: IntArray = intArrayOf()) =
        MediaCapabilitiesProbe(context, { codecs }, { AudioCapabilities(encodings, 8) }, { hdr }).read()

    @Suppress("UNCHECKED_CAST")
    private fun video(result: Map<String, Any>) = result["videoDecoders"] as List<Map<String, Any>>

    private fun fireTv() = listOf(
        decoder("video/avc", listOf(Profile.AVCProfileBaseline, Profile.AVCProfileMain, Profile.AVCProfileHigh, Profile.AVCProfileHigh10), Profile.AVCLevel52),
        decoder("video/hevc", listOf(Profile.HEVCProfileMain, Profile.HEVCProfileMain10HDR10, Profile.HEVCProfileMain10HDR10Plus), Profile.HEVCMainTierLevel51),
        decoder("video/x-vnd.on2.vp9", listOf(Profile.VP9Profile0, Profile.VP9Profile2)),
        decoder("video/av01", listOf(Profile.AV1ProfileMain8, Profile.AV1ProfileMain10), Profile.AV1Level51),
        decoder("video/mpeg2"), decoder("video/mp4v-es"), decoder("video/x-vnd.on2.vp8"),
        decoder("video/dolby-vision", listOf(Profile.DolbyVisionProfileDvheDtr, Profile.DolbyVisionProfileDvheStn,
            Profile.DolbyVisionProfileDvheSt, Profile.DolbyVisionProfileDvavSe, Profile.DolbyVisionProfileDvav110)),
    ) + listOf("audio/ac3", "audio/eac3", "audio/ac4", "audio/mp4a-latm", "audio/flac", "audio/opus", "audio/vorbis", "audio/raw").map { decoder(it) }

    @Test
    fun fireTvFactsUseCodecProfilesDisplayHdrAndCurrentPassthrough() {
        val codecs = fireTv()
        var encodings = intArrayOf(C.ENCODING_PCM_16BIT)
        var reads = 0
        val probe = MediaCapabilitiesProbe(context, { codecs }, {
            reads++; AudioCapabilities(encodings, 8)
        }, { intArrayOf(Display.HdrCapabilities.HDR_TYPE_HDR10, Display.HdrCapabilities.HDR_TYPE_HDR10_PLUS, Display.HdrCapabilities.HDR_TYPE_HLG) })
        val first = probe.read()
        val hevc = video(first).single { it["codec"] == "hevc" }
        assertEquals(listOf("main", "main 10"), hevc["profiles"])
        assertEquals("5.1", hevc["maxLevel"])
        assertEquals(listOf(4, 5, 8), hevc["dolbyVisionProfiles"])
        assertEquals(listOf(9), video(first).single { it["codec"] == "h264" }["dolbyVisionProfiles"])
        assertEquals(listOf(10), video(first).single { it["codec"] == "av1" }["dolbyVisionProfiles"])
        assertEquals(listOf("hdr10", "hdr10plus", "hlg"), hevc["hdr"])
        assertEquals("5.2", video(first).single { it["codec"] == "h264" }["maxLevel"])
        assertEquals(setOf("h264", "hevc", "vp9", "av1", "mpeg2video", "mpeg4", "vp8"), video(first).map { it["codec"] }.toSet())
        assertEquals(listOf("aac", "ac3", "ac4", "eac3", "flac", "opus", "pcm", "vorbis"), first["audioDecoders"])
        assertEquals(emptyList<String>(), first["audioPassthrough"])
        encodings = intArrayOf(C.ENCODING_PCM_16BIT, C.ENCODING_AC3, C.ENCODING_E_AC3, C.ENCODING_DOLBY_TRUEHD, C.ENCODING_DTS, C.ENCODING_DTS_HD)
        assertEquals(listOf("ac3", "eac3", "truehd", "dca", "dtshd"), probe.read()["audioPassthrough"])
        assertEquals(2, reads)
    }

    @Test
    fun phoneWithoutHevcSecureOnlyOrEncoderDoesNotClaimThemOrDolbyVision() {
        val result = probe(listOf(
            decoder("video/avc", listOf(Profile.AVCProfileBaseline, Profile.AVCProfileHigh)),
            decoder("audio/mp4a-latm"), decoder("video/hevc", listOf(Profile.HEVCProfileMain10), secure = true),
            decoder("video/hevc", listOf(Profile.HEVCProfileMain10), encoder = true),
        ))
        assertEquals(listOf("h264"), video(result).map { it["codec"] })
        assertEquals(listOf("aac", "pcm"), result["audioDecoders"])
        assertEquals(emptyList<String>(), video(result).single()["hdr"])
        assertTrue((result["containers"] as List<*>).containsAll(listOf("mp4", "mkv", "webm", "mpegts")))
    }

    @Test
    fun hdrRequiresBothDecoderProfileAndDisplaySupport() {
        val hdrCodec = decoder("video/hevc", listOf(Profile.HEVCProfileMain10HDR10Plus))
        assertEquals(emptyList<String>(), video(probe(listOf(hdrCodec))).single()["hdr"])
        val main8 = decoder("video/hevc", listOf(Profile.HEVCProfileMain))
        assertEquals(emptyList<String>(), video(probe(listOf(main8), hdr = intArrayOf(Display.HdrCapabilities.HDR_TYPE_HDR10))).single()["hdr"])
    }

    @Test
    fun boundsAndHardwarePreferenceAreDeterministicAcrossCodecEnumerationOrder() {
        val profiles = listOf(Profile.AVCProfileBaseline, Profile.AVCProfileMain, Profile.AVCProfileHigh,
            Profile.AVCProfileHigh10, Profile.AVCProfileHigh422, Profile.AVCProfileHigh444)
        val many = (1..150).map { index ->
            decoder("video/avc", profiles.filterIndexed { bit, _ -> index and (1 shl bit) != 0 },
                level = 1 shl (index % 17), name = "vendor.${index.toString().padStart(3, '0')}")
        }
        val software = decoder("video/avc", listOf(Profile.AVCProfileHigh10), name = "aaa.software", hardware = false)
        val first = probe(many + software)
        assertEquals(1, video(first).size)
        assertEquals(first, probe((many + software).reversed()))
        assertEquals(listOf("baseline"), video(first).first()["profiles"])
        assertEquals("h264", video(first).first()["codec"])
        assertTrue(video(first).size <= 64)
        assertTrue((first["audioDecoders"] as List<*>).size <= 64)
        assertTrue((first["audioPassthrough"] as List<*>).size <= 16)
        assertTrue((first["containers"] as List<*>).size <= 32)
    }
}
