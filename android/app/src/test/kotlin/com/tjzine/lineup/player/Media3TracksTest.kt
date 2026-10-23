package com.tjzine.lineup.player

import androidx.media3.common.*
import com.google.common.collect.ImmutableList
import org.junit.Assert.*
import org.junit.Test

@org.junit.runner.RunWith(org.robolectric.RobolectricTestRunner::class)
@org.robolectric.annotation.Config(manifest = org.robolectric.annotation.Config.NONE, sdk = [28])
class Media3TracksTest {
    private fun format(mime: String, label: String? = null) =
        Format.Builder().setSampleMimeType(mime).setLabel(label).build()

    private fun group(value: TrackGroup, selected: Int = -1, support: Int = C.FORMAT_HANDLED) =
        Tracks.Group(
            value,
            false,
            IntArray(value.length) { support },
            BooleanArray(value.length) { it == selected },
        )

    private fun tracks(vararg groups: Tracks.Group) = Tracks(ImmutableList.copyOf(groups.toList()))

    @Test
    fun idsStayPositiveAcrossSelectionAndReorderButResetPerLoad() {
        val audio = TrackGroup(format("audio/ac3"), format("audio/eac3"))
        val video = TrackGroup(format("video/avc"))
        val encoder = Media3Tracks()
        val first = encoder.encode(tracks(group(audio, 0), group(video, 0)))
        val second = encoder.encode(tracks(group(video, 0), group(audio, 1)))
        assertEquals(listOf(1L, 2L, 3L), first.map { it["id"] })
        assertEquals(listOf(3L, 1L, 2L), second.map { it["id"] })
        assertEquals(listOf(true, false, true), second.map { it["selected"] })
        assertSame(audio, encoder.target(2)!!.group)
        assertEquals(1, encoder.target(2)!!.index)
        assertEquals(1L, Media3Tracks().encode(tracks(group(video))).single()["id"])
    }

    @Test
    fun originalTextCodecAndTruthfulFlagsAndChannels() {
        val text =
            Format.Builder()
                .setSampleMimeType("application/x-media3-cues")
                .setCodecs("text/x-ssa")
                .setSelectionFlags(C.SELECTION_FLAG_FORCED)
                .setLanguage("eng")
                .build()
        val audio =
            Format.Builder()
                .setSampleMimeType("audio/eac3")
                .setChannelCount(6)
                .setRoleFlags(C.ROLE_FLAG_COMMENTARY or C.ROLE_FLAG_DESCRIBES_VIDEO)
                .build()
        val result =
            Media3Tracks().encode(tracks(group(TrackGroup(text)), group(TrackGroup(audio))))
        assertEquals("ass", result[0]["codec"])
        assertEquals("sub", result[0]["type"])
        assertEquals(true, result[0]["forced"])
        assertFalse(result[0].containsKey("hearing-impaired"))
        assertFalse(result[0].containsKey("default"))
        assertFalse(result[0].containsKey("external"))
        assertEquals(6, result[1]["demux-channel-count"])
        assertFalse(result[1].containsKey("demux-channels"))
        assertEquals(true, result[1]["commentary"])
        assertEquals(true, result[1]["visual-impaired"])
    }

    @Test
    fun unavailableAndOversizedFactsAreOmittedAndAggregateIsBounded() {
        val group = TrackGroup(*Array(300) { format("audio/aac", "x".repeat(4096)) })
        val rows = Media3Tracks().encode(tracks(group(group)))
        assertTrue(rows.size < 256)
        assertTrue(rows.isNotEmpty())
        val huge =
            Media3Tracks()
                .encode(tracks(group(TrackGroup(format("audio/aac", "é".repeat(2049))))))
                .single()
        assertFalse(huge.containsKey("title"))
        assertFalse(huge.containsKey("demux-channel-count"))
    }

    @Test
    fun unsupportedSubtitlesAreOmittedAndOldTargetsCannotBeSelected() {
        val encoder = Media3Tracks()
        val old = TrackGroup(format("text/x-ssa"))
        encoder.encode(tracks(group(old)))
        val rows = encoder.encode(tracks(group(old, support = C.FORMAT_UNSUPPORTED_TYPE)))
        assertTrue(rows.isEmpty())
        assertNull(encoder.target(1))
    }

    @Test
    fun sourceColorIsTruthfulAndUnknownTransferIsNotInvented() {
        val hdr =
            Format.Builder()
                .setWidth(1920)
                .setHeight(1080)
                .setColorInfo(
                    ColorInfo.Builder()
                        .setColorSpace(C.COLOR_SPACE_BT2020)
                        .setColorTransfer(C.COLOR_TRANSFER_ST2084)
                        .build()
                )
                .build()
        val params = Media3Tracks.videoParams(hdr)
        assertEquals("bt.2020", params["primaries"])
        assertEquals("pq", params["gamma"])
        assertNull(params["pixelformat"])
        assertNull(params["sig-peak"])
        val sdr =
            Format.Builder()
                .setColorInfo(
                    ColorInfo.Builder()
                        .setColorSpace(C.COLOR_SPACE_BT709)
                        .setColorTransfer(C.COLOR_TRANSFER_SDR)
                        .build()
                )
                .build()
        assertNull(Media3Tracks.videoParams(sdr)["gamma"])
    }

    @Test
    fun dolbyVisionPreservesActualCodecStringRatherThanAssumingHevc() {
        fun dv(codecs: String?) =
            Media3Tracks.codec(
                Format.Builder().setSampleMimeType("video/dolby-vision").setCodecs(codecs).build()
            )
        assertEquals("dvhe.05.06", dv("dvhe.05.06"))
        assertEquals("dva1.09.06", dv("dva1.09.06"))
        assertEquals("dav1.10.06", dv("dav1.10.06"))
        assertNull(dv(null))
    }
}
