package com.tjzine.lineup.player

import androidx.media3.common.C
import androidx.media3.common.DataReader
import androidx.media3.extractor.*
import java.nio.ByteBuffer
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
class GuardedFragmentedMp4Test {
    // A 12-second, 16x16 black H264 video with six fragments, MFRA, and no SIDX:
    // ffmpeg -f lavfi -i color=c=black:s=16x16:r=1 -t 12 -an -c:v libx264
    //   -preset ultrafast -g 2 -keyint_min 2 -sc_threshold 0 -pix_fmt yuv420p
    //   -movflags frag_keyframe+empty_moov+default_base_moof
    //   -metadata creation_time=1970-01-01T00:00:00Z mfra-seek.mp4
    private fun fixture() =
        javaClass.getResourceAsStream("/mfra-seek.mp4")!!.use { it.readBytes() }

    private fun int(bytes: ByteArray, offset: Int) = ByteBuffer.wrap(bytes, offset, 4).int

    private fun mfraStart(bytes: ByteArray) = bytes.size - int(bytes, bytes.size - 4)

    private fun moov(bytes: ByteArray): ByteArray {
        val start = int(bytes, 0) // The fixture's first box is ftyp.
        assertEquals("moov", String(bytes, start + 4, 4, Charsets.US_ASCII))
        return bytes.copyOfRange(start, start + int(bytes, start))
    }

    private class Extraction(private val bytes: ByteArray) {
        val events = mutableListOf<Map<String, Any?>>()
        val samples = mutableListOf<Long>()
        var seekMap: SeekMap? = null
        private var currentInput = input(0)
        private val extractor =
            GuardedExtractorsFactory { events.add(it) }.createExtractors().first {
                it.sniff(input(0))
            }

        init {
            assertTrue(extractor is GuardedMp4)
            extractor.init(
                object : ExtractorOutput {
                    override fun track(id: Int, type: Int): TrackOutput =
                        object : TrackOutput by DiscardingTrackOutput() {
                            override fun sampleMetadata(
                                timeUs: Long,
                                flags: Int,
                                size: Int,
                                offset: Int,
                                cryptoData: TrackOutput.CryptoData?,
                            ) {
                                if (type == C.TRACK_TYPE_VIDEO) samples.add(timeUs)
                            }
                        }

                    override fun endTracks() {}

                    override fun seekMap(map: SeekMap) {
                        seekMap = map
                    }
                }
            )
        }

        private fun input(position: Long): ExtractorInput {
            require(position in 0..bytes.size.toLong())
            var cursor = position.toInt()
            return DefaultExtractorInput(
                DataReader { target, offset, length ->
                    if (length == 0) 0
                    else if (cursor == bytes.size) C.RESULT_END_OF_INPUT
                    else {
                        val count = minOf(length, bytes.size - cursor)
                        bytes.copyInto(target, offset, cursor, cursor + count)
                        cursor += count
                        count
                    }
                },
                position,
                bytes.size.toLong(),
            )
        }

        fun readUntil(done: () -> Boolean = { false }) {
            val holder = PositionHolder()
            repeat(10000) {
                if (done()) return
                when (extractor.read(currentInput, holder)) {
                    Extractor.RESULT_CONTINUE -> {}
                    // Extractor-internal seeks reopen input without calling seek().
                    Extractor.RESULT_SEEK -> currentInput = input(holder.position)
                    Extractor.RESULT_END_OF_INPUT -> return
                    else -> error("unexpected_extractor_result")
                }
            }
            error("extractor_did_not_finish")
        }

        fun seek(point: SeekPoint) {
            samples.clear()
            extractor.seek(point.position, point.timeUs)
            currentInput = input(point.position)
        }
    }

    @Test
    fun mfraOnlyIndexSupportsNonzeroSeekBeforePlaybackAdvances() {
        val extraction = Extraction(fixture())
        extraction.readUntil { extraction.samples.isNotEmpty() }
        val map = checkNotNull(extraction.seekMap)
        assertTrue("MFRA must retain DefaultExtractorsFactory seek support", map.isSeekable)
        val point = map.getSeekPoints(8_000_000).first
        assertEquals(8_000_000L, point.timeUs)
        assertTrue(point.position > 0)
        extraction.seek(point)
        extraction.readUntil { extraction.samples.isNotEmpty() }
        // The very next extracted sample proves the seek; elapsed playback cannot satisfy this.
        assertEquals(8_000_000L, extraction.samples.first())
    }

    @Test
    fun absentMfraTreatsFinalSampleBytesAsOpaqueAndPlaysSequentially() {
        val bytes = fixture()
        val extraction = Extraction(bytes.copyOf(mfraStart(bytes)))
        extraction.readUntil()
        assertFalse(checkNotNull(extraction.seekMap).isSeekable)
        assertEquals((0L..11L).map { it * 1_000_000 }, extraction.samples)
    }

    @Test
    fun mfraProbeReturnStillValidatesLaterMoovWithReusedTrackOutput() {
        val bytes = fixture()
        val start = mfraStart(bytes)
        val extraction =
            Extraction(bytes.copyOf(start) + moov(bytes) + bytes.copyOfRange(start, bytes.size))
        extraction.readUntil()
        assertTrue(checkNotNull(extraction.seekMap).isSeekable)
        assertEquals(
            listOf(1, 2),
            extraction.events.filter { it["phase"] == "validate" }.map { it["revision"] },
        )
        assertEquals(12, extraction.samples.size)
    }

    @Test
    fun mfraProbeReturnCannotHideLaterVideoOmission() {
        val bytes = fixture()
        val laterMoov = moov(bytes)
        val sampleEntry = laterMoov.toString(Charsets.ISO_8859_1).indexOf("avc1")
        assertTrue(sampleEntry >= 0)
        "zzzz".toByteArray(Charsets.US_ASCII).copyInto(laterMoov, sampleEntry)
        val start = mfraStart(bytes)
        val extraction =
            Extraction(bytes.copyOf(start) + laterMoov + bytes.copyOfRange(start, bytes.size))
        val failure = assertThrows(OmittedMediaType::class.java) { extraction.readUntil() }
        assertEquals(C.TRACK_TYPE_VIDEO, failure.mediaType)
        assertTrue(checkNotNull(extraction.seekMap).isSeekable)
        assertTrue(extraction.events.any { it["phase"] == "moov-start" && it["revision"] == 2 })
    }
}
