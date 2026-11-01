package com.tjzine.lineup.player

import android.net.Uri
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.util.TimestampAdjuster
import androidx.media3.exoplayer.analytics.PlayerId
import androidx.media3.exoplayer.hls.DefaultHlsExtractorFactory
import androidx.media3.exoplayer.hls.HlsExtractorFactory
import androidx.media3.exoplayer.hls.TimestampAdjusterProvider
import androidx.media3.exoplayer.hls.playlist.HlsMediaPlaylist
import androidx.media3.exoplayer.hls.playlist.HlsPlaylistParser
import androidx.media3.extractor.DiscardingTrackOutput
import androidx.media3.extractor.ExtractorOutput
import androidx.media3.extractor.SeekMap
import androidx.media3.extractor.TrackOutput
import java.security.MessageDigest
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** Required local extraction evidence: no optional environment, network, process or media output. */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
class SessionHlsPublicCorpusTest {
    private data class Sample(val timeUs: Long, val flags: Int, val size: Int, val offset: Int)
    private fun sha(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

    @Test fun h264StockRawPacketClockAndWrappedSamplesAreEquivalent() = verify("h264", "video/avc")
    @Test fun hevcStockRawPacketClockAndWrappedSamplesAreEquivalent() = verify("hevc", "video/hevc")

    @Test fun initializationAndEmptyPrestartMediaDoNotQualifyTheClock() {
        val clock = SessionHlsClock(); val adjuster = TimestampAdjuster(20_000_000)
        clock.scope(clockTimeline(), 0, clockPlaylist())
        val initialization = extractorInput(publicHlsBytes("h264/init.mp4"))
        val extractor = SessionHlsExtractors(clock).createExtractor(
            Uri.parse("https://fixture.invalid/session/init.mp4"),
            Format.Builder().setSampleMimeType("video/avc").build(), null,
            adjuster, mutableMapOf(), initialization, PlayerId.UNSET)
        val videoTimes = mutableListOf<Long>()
        extractor.init(object : ExtractorOutput {
            override fun track(id: Int, type: Int): TrackOutput = object : TrackOutput by DiscardingTrackOutput() {
                override fun sampleMetadata(timeUs: Long, flags: Int, size: Int, offset: Int, crypto: TrackOutput.CryptoData?) {
                    if (type == C.TRACK_TYPE_VIDEO) videoTimes += timeUs
                }
            }
            override fun endTracks() { }
            override fun seekMap(map: SeekMap) { }
        })
        fun read(input: androidx.media3.extractor.ExtractorInput) {
            var count = 0
            while (extractor.read(input)) assertTrue(count++ < 20_000)
        }
        read(initialization)
        assertTrue(videoTimes.isEmpty()); assertEquals(SessionHlsClock.State.Pending, clock.snapshot())
        read(extractorInput(byteArrayOf()))
        assertTrue(videoTimes.isEmpty()); assertEquals(SessionHlsClock.State.Pending, clock.snapshot())
        // The first delivered media is segment2, not playlist index0. Its raw
        // first videoPTS31.25s is adjusted to the supplied20s timeline target.
        read(extractorInput(publicHlsBytes("h264/2.m4s")))
        assertEquals(20_000_000L, videoTimes.first())
        assertEquals(-11_250_000L, adjuster.timestampOffsetUs)
        assertEquals(SessionHlsClock.State.Ready(-11_250_000), clock.snapshot())
    }


    @Test fun realProviderResetCreatesFreshEqualAndChangedBasesWithoutGuessingA() {
        for (segment in listOf(0, 2)) {
            val clock = SessionHlsClock(); clock.scope(clockTimeline(), 0, clockPlaylist())
            val provider = TimestampAdjusterProvider()
            val first = provider.getAdjuster(0)
            first.sharedInitializeOrWait(true, 0, 0)
            val factory = SessionHlsExtractors(clock)
            val init = publicHlsBytes("h264/init.mp4")
            samples(factory, init + publicHlsBytes("h264/0.m4s"), first, "video/avc")
            assertEquals(SessionHlsClock.State.Ready(-10_500_000), clock.publication())
            clock.seeking(); provider.reset()
            val next = provider.getAdjuster(0)
            assertNotSame(first, next)
            assertEquals(C.TIME_UNSET, next.timestampOffsetUs)
            next.sharedInitializeOrWait(true, segment * 10_000_000L, 0)
            samples(factory, init + publicHlsBytes("h264/$segment.m4s"), next, "video/avc") {
                assertEquals(SessionHlsClock.State.Pending, clock.publication())
                assertEquals(C.TIME_UNSET, next.timestampOffsetUs)
            }
            val expected = if (segment == 0) -10_500_000L else -11_250_000L
            assertEquals(expected, next.timestampOffsetUs)
            assertEquals(SessionHlsClock.State.Ready(expected, segment == 2), clock.publication())
            clock.videoSample(first, Long.MAX_VALUE) // Retired source cannot poison A1.
            assertEquals(SessionHlsClock.State.Ready(expected, segment == 2), clock.snapshot())
            clock.retire(); provider.reset(); clock.seeking()
            assertNull(clock.bind(provider.getAdjuster(0), true))
            clock.videoSample(next, 0); assertNull(clock.publication())
        }
    }

    private fun verify(codec: String, mime: String) {
        val record = JSONObject(String(publicHlsBytes("corpus.json"), Charsets.UTF_8))
            .getJSONObject("classes").getJSONObject(codec)
        assertTrue(record.getBoolean("postshift_independent_ffprobe_verified"))
        val init = publicHlsBytes("$codec/init.mp4")
        assertEquals(record.getString("init_sha256"), sha(init))
        val hashes = record.getJSONArray("segment_sha256")
        val segments = (0 until hashes.length()).map { index ->
            publicHlsBytes("$codec/$index.m4s").also { assertEquals(hashes.getString(index), sha(it)) }
        }
        val expectedJson = record.getJSONArray("expected_video_pts_us")
        val expected = (0 until expectedJson.length()).map { expectedJson.getLong(it) }.sorted()
        val bytes = segments.fold(init) { all, segment -> all + segment }
        assertTrue(bytes.size < 2 * 1024 * 1024)
        val stock = samples(DefaultHlsExtractorFactory(), bytes, TimestampAdjuster(TimestampAdjuster.MODE_NO_OFFSET), mime)
        assertEquals(expected, stock.map { it.timeUs }.sorted())
        val clock = SessionHlsClock(); val adjuster = TimestampAdjuster(0)
        clock.scope(clockTimeline(), 0, clockPlaylist())
        val observed = samples(SessionHlsExtractors(clock), bytes, adjuster, mime)
        val offset = adjuster.timestampOffsetUs
        assertNotEquals(C.TIME_UNSET, offset)
        assertNotEquals(0L, offset)
        assertEquals(SessionHlsClock.State.Ready(offset), clock.snapshot())
        assertEquals(stock, observed.map { it.copy(timeUs = Math.subtractExact(it.timeUs, offset)) })
        // Composition/reordering is retained. A packet ledger is not a second application clock.
        assertEquals(expected, observed.map { it.timeUs - offset }.sorted())
        for ((index, segment) in segments.withIndex()) {
            val plain = samples(DefaultHlsExtractorFactory(), init + segment,
                TimestampAdjuster(TimestampAdjuster.MODE_NO_OFFSET), mime)
            val perSegment = SessionHlsClock(); val perAdjuster = TimestampAdjuster(0)
            perSegment.scope(clockTimeline(), 0, clockPlaylist())
            val wrapped = samples(SessionHlsExtractors(perSegment), init + segment, perAdjuster, mime)
            val fact = record.getJSONArray("fragment_facts").getJSONObject(index)
            assertEquals(fact.getLong("first_decode_sample_pts_us"), plain.first().timeUs)
            assertEquals(fact.getInt("sample_count"), plain.size)
            assertEquals(plain, wrapped.map { it.copy(timeUs = it.timeUs - perAdjuster.timestampOffsetUs) })
            assertEquals(SessionHlsClock.State.Ready(perAdjuster.timestampOffsetUs), perSegment.snapshot())
        }
    }

    private fun samples(factory: HlsExtractorFactory, bytes: ByteArray, adjuster: TimestampAdjuster,
        mime: String, beforeRead: () -> Unit = {}): List<Sample> {
        val input = extractorInput(bytes)
        val extractor = factory.createExtractor(Uri.parse("https://fixture.invalid/session/0.m4s"),
            Format.Builder().setSampleMimeType(mime).build(), null, adjuster, mutableMapOf(), input, PlayerId.UNSET)
        val samples = mutableListOf<Sample>()
        extractor.init(object : ExtractorOutput {
            override fun track(id: Int, type: Int): TrackOutput = object : TrackOutput by DiscardingTrackOutput() {
                override fun sampleMetadata(timeUs: Long, flags: Int, size: Int, offset: Int, crypto: TrackOutput.CryptoData?) {
                    if (type == C.TRACK_TYPE_VIDEO) samples += Sample(timeUs, flags, size, offset)
                }
            }
            override fun endTracks() { }
            override fun seekMap(map: SeekMap) { }
        })
        beforeRead()
        var count = 0
        while (extractor.read(input)) assertTrue("bounded generated corpus", count++ < 20_000)
        return samples
    }
}
