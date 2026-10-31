package com.tjzine.lineup.player

import android.net.Uri
import androidx.media3.common.C
import androidx.media3.common.DataReader
import androidx.media3.common.Format
import androidx.media3.common.util.TimestampAdjuster
import androidx.media3.exoplayer.analytics.PlayerId
import androidx.media3.exoplayer.hls.DefaultHlsExtractorFactory
import androidx.media3.exoplayer.hls.HlsExtractorFactory
import androidx.media3.extractor.DefaultExtractorInput
import androidx.media3.extractor.DiscardingTrackOutput
import androidx.media3.extractor.ExtractorOutput
import androidx.media3.extractor.SeekMap
import androidx.media3.extractor.TrackOutput
import java.io.File
import java.security.MessageDigest
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeNotNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** Supplementary generated PUBLIC corpus proof. No socket, process, decoder or media output. */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
class E6PublicCorpusTest {
    @Test fun pinnedStockH264ExtractorMatchesIndependentPacketLedger() = verify("h264", "e6-clock")
    @Test fun pinnedStockHevcExtractorMatchesIndependentPacketLedger() = verify("hevc", "e6-hevc")

    private fun sha(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

    private fun verify(codec: String, directory: String) {
        val path = System.getenv("LINEUP_E6_PUBLIC_CORPUS")
        assumeNotNull("Set only to the generated public E6 corpus; never private media", path)
        val root = File(path!!)
        val manifest = File(root, "corpus.json").readBytes()
        val record = JSONObject(String(manifest, Charsets.UTF_8)).getJSONObject("classes").getJSONObject(codec)
        assertTrue(record.getBoolean("postshift_independent_ffprobe_verified"))
        assertTrue(record.getBoolean("strict_parser_verified"))
        val init = File(root, "$directory/init.mp4").readBytes()
        assertEquals(record.getString("init_sha256"), sha(init))
        val segmentHashes = record.getJSONArray("segment_sha256")
        val segments = (0 until segmentHashes.length()).map { index ->
            File(root, "$directory/$index.m4s").readBytes().also { assertEquals(segmentHashes.getString(index), sha(it)) }
        }
        val bytes = init + segments.fold(ByteArray(0)) { all, next -> all + next }
        assertTrue("bounded synthetic fixture", bytes.size < 16 * 1024 * 1024)
        val expectedJson = record.getJSONArray("expected_video_pts_us")
        val expected = (0 until expectedJson.length()).map { expectedJson.getLong(it) }.sorted()
        val plain = samples(DefaultHlsExtractorFactory(), bytes, TimestampAdjuster(TimestampAdjuster.MODE_NO_OFFSET), codec)
        assertEquals(expected, plain.sorted())
        val observation = e6Observer()
        observation.loaderOpened(0)
        val adjuster = TimestampAdjuster(0)
        val adjusted = samples(E6Extractors(observation), bytes, adjuster, codec)
        val actualOffset = adjuster.timestampOffsetUs
        assertNotEquals(C.TIME_UNSET, actualOffset)
        assertNotEquals("nonzero HLS offset control", 0L, actualOffset)
        assertEquals(expected, adjusted.map { it - actualOffset }.sorted())
        val stockFirst = mutableListOf<Long>()
        val wrappedFirst = mutableListOf<Long>()
        val offsets = mutableListOf<Long>()
        val recovered = mutableListOf<Long>()
        val counts = mutableListOf<Int>()
        for ((index, segment) in segments.withIndex()) {
            val stock = samples(DefaultHlsExtractorFactory(), init + segment,
                TimestampAdjuster(TimestampAdjuster.MODE_NO_OFFSET), codec)
            val wrapperObservation = e6Observer(); wrapperObservation.loaderOpened(0)
            val hls = TimestampAdjuster(0)
            val wrapped = samples(E6Extractors(wrapperObservation), init + segment, hls, codec)
            val fact = record.getJSONArray("fragment_facts").getJSONObject(index)
            assertEquals(fact.getInt("sample_count"), stock.size)
            assertEquals(fact.getLong("first_decode_sample_pts_us"), stock.first())
            assertEquals(stock, wrapped.map { it - hls.timestampOffsetUs })
            stockFirst += stock.first(); wrappedFirst += wrapped.first(); offsets += hls.timestampOffsetUs
            recovered += wrapped.first() - hls.timestampOffsetUs; counts += wrapped.size
        }
        println("E6_PUBLIC_REFERENCE=" + JSONObject(linkedMapOf<String, Any>("version" to 1,
            "corpus_sha256" to sha(manifest), "media3_version" to "1.11.1", "source_class" to codec,
            "result" to "matched", "init_sha256" to sha(init),
            "segment_sha256" to segments.map(::sha), "stock_extractor_first_pts_us_by_segment" to stockFirst,
            "adjusted_first_pts_us_by_segment" to wrappedFirst, "hls_offset_us_by_segment" to offsets,
            "recovered_extractor_first_pts_us_by_segment" to recovered, "sample_counts_by_segment" to counts,
            "observer_offsets_applied" to false, "default_hls_factory" to true)).toString())
        assertEquals("proof must not rewrite its reference ledger", sha(manifest), sha(File(root, "corpus.json").readBytes()))
        assertEquals(record.getString("init_sha256"), sha(File(root, "$directory/init.mp4").readBytes()))
    }

    private fun samples(factory: HlsExtractorFactory, bytes: ByteArray, adjuster: TimestampAdjuster, codec: String): List<Long> {
        val stream = bytes.inputStream()
        val input = DefaultExtractorInput(DataReader { buffer, offset, length -> stream.read(buffer, offset, length) }, 0, bytes.size.toLong())
        val extractor = factory.createExtractor(Uri.parse("https://localhost:21443/e6-clock/0.m4s"),
            Format.Builder().setSampleMimeType(if (codec == "h264") "video/avc" else "video/hevc").build(),
            null, adjuster, emptyMap(), input, PlayerId.UNSET)
        val samples = mutableListOf<Long>()
        extractor.init(object : ExtractorOutput {
            override fun track(id: Int, type: Int): TrackOutput = object : TrackOutput by DiscardingTrackOutput() {
                override fun sampleMetadata(timeUs: Long, flags: Int, size: Int, offset: Int, cryptoData: TrackOutput.CryptoData?) {
                    if (type == C.TRACK_TYPE_VIDEO) samples += timeUs
                }
            }
            override fun endTracks() { }
            override fun seekMap(map: SeekMap) { }
        })
        var reads = 0
        while (extractor.read(input)) { assertTrue("finite synthetic extraction", reads++ < 100_000) }
        return samples
    }
}
