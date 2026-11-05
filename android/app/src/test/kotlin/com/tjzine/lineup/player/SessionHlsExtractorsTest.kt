package com.tjzine.lineup.player

import android.net.Uri
import androidx.media3.common.C
import androidx.media3.common.DataReader
import androidx.media3.common.Format
import androidx.media3.common.util.ParsableByteArray
import androidx.media3.common.util.TimestampAdjuster
import androidx.media3.exoplayer.analytics.PlayerId
import androidx.media3.exoplayer.hls.DefaultHlsExtractorFactory
import androidx.media3.exoplayer.hls.HlsExtractorFactory
import androidx.media3.exoplayer.hls.HlsMediaChunkExtractor
import androidx.media3.exoplayer.hls.TimestampAdjusterProvider
import androidx.media3.extractor.DefaultExtractorInput
import androidx.media3.extractor.DiscardingTrackOutput
import androidx.media3.extractor.ExtractorInput
import androidx.media3.extractor.ExtractorOutput
import androidx.media3.extractor.SeekMap
import androidx.media3.extractor.TrackOutput
import androidx.media3.extractor.text.DefaultSubtitleParserFactory
import androidx.media3.extractor.text.SubtitleParser
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

internal fun publicHlsBytes(path: String): ByteArray =
    SessionHlsExtractorsTest::class.java.getResourceAsStream("/session-hls/$path")
        ?.use { it.readBytes() } ?: error("required public corpus missing: $path")

internal fun extractorInput(bytes: ByteArray): DefaultExtractorInput {
    val stream = bytes.inputStream()
    return DefaultExtractorInput(DataReader { buffer, offset, length -> stream.read(buffer, offset, length) }, 0, bytes.size.toLong())
}

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
class SessionHlsExtractorsTest {
    private class Chunk : HlsMediaChunkExtractor {
        lateinit var output: ExtractorOutput
        var recreated = 0
        var truncated = 0
        var reads = 0
        var onRead: (() -> Unit)? = null
        override fun init(output: ExtractorOutput) { this.output = output }
        override fun read(input: ExtractorInput): Boolean { reads++; onRead?.invoke(); return false }
        override fun isPackedAudioExtractor() = false
        override fun isReusable() = true
        override fun recreate(): HlsMediaChunkExtractor { recreated++; return this }
        override fun onTruncatedSegmentParsed() { truncated++ }
    }

    private class Factory(val chunk: Chunk = Chunk()) : HlsExtractorFactory by DefaultHlsExtractorFactory() {
        var next: Factory? = null
        var subtitle: SubtitleParser.Factory? = null
        var parse: Boolean? = null
        var codecs: Int? = null
        var inputPeek: Long? = null
        var creates = 0
        var outputFormat: Format? = null
        override fun setSubtitleParserFactory(value: SubtitleParser.Factory): HlsExtractorFactory {
            subtitle = value; return next ?: this
        }
        override fun experimentalParseSubtitlesDuringExtraction(value: Boolean): HlsExtractorFactory {
            parse = value; return this
        }
        override fun experimentalSetCodecsToParseWithinGopSampleDependencies(value: Int): HlsExtractorFactory {
            codecs = value; return this
        }
        override fun getOutputTextFormat(format: Format): Format = outputFormat ?: format
        override fun createExtractor(uri: Uri, format: Format, captions: MutableList<Format>?,
            adjuster: TimestampAdjuster, headers: MutableMap<String, MutableList<String>>,
            input: ExtractorInput, player: PlayerId): HlsMediaChunkExtractor {
            inputPeek = input.peekPosition; creates++; return chunk
        }
    }

    private class Sink : ExtractorOutput {
        val metadata = mutableListOf<List<Any?>>()
        val formats = mutableListOf<Format>()
        val durations = mutableListOf<Long>()
        val bytes = mutableListOf<Byte>()
        var endTracks = 0
        var seekMaps = 0
        var rejectMetadata = false
        override fun track(id: Int, type: Int): TrackOutput = object : TrackOutput {
            override fun format(format: Format) { formats += format }
            override fun durationUs(durationUs: Long) { durations += durationUs }
            override fun sampleData(input: DataReader, length: Int, allowEnd: Boolean, part: Int): Int {
                val buffer = ByteArray(length); val read = input.read(buffer, 0, length)
                if (read > 0) bytes += buffer.take(read)
                return read
            }
            override fun sampleData(data: ParsableByteArray, length: Int, part: Int) {
                val buffer = ByteArray(length); data.readBytes(buffer, 0, length); bytes += buffer.toList()
            }
            override fun sampleMetadata(timeUs: Long, flags: Int, size: Int, offset: Int, crypto: TrackOutput.CryptoData?) {
                if (rejectMetadata) throw IllegalStateException("synthetic sink rejection")
                metadata += listOf(type, timeUs, flags, size, offset, crypto)
            }
        }
        override fun endTracks() { endTracks++ }
        override fun seekMap(map: SeekMap) { seekMaps++ }
    }

    private fun create(factory: HlsExtractorFactory, adjuster: TimestampAdjuster,
        input: ExtractorInput = extractorInput(publicHlsBytes("h264/init.mp4"))) =
        factory.createExtractor(Uri.parse("https://fixture.invalid/session/part.mp4"),
            Format.Builder().setSampleMimeType("video/avc").build(), null, adjuster, mutableMapOf(), input, PlayerId.UNSET)

    @Test fun fluentMutatorsKeepWrapperAndRetargetReturnedDelegates() {
        val first = Factory(); val replacement = Factory(); first.next = replacement
        val clock = SessionHlsClock(); val wrapper = SessionHlsExtractors(clock, first)
        val subtitle = DefaultSubtitleParserFactory()
        assertSame(wrapper, wrapper.setSubtitleParserFactory(subtitle)); assertSame(subtitle, first.subtitle)
        assertSame(wrapper, wrapper.experimentalParseSubtitlesDuringExtraction(false)); assertEquals(false, replacement.parse)
        assertSame(wrapper, wrapper.experimentalSetCodecsToParseWithinGopSampleDependencies(2)); assertEquals(2, replacement.codecs)
        val format = Format.Builder().setSampleMimeType("text/vtt").build(); replacement.outputFormat = format
        assertSame(format, wrapper.getOutputTextFormat(Format.Builder().build()))
        create(wrapper, TimestampAdjuster(0))
        assertEquals(0, first.creates); assertEquals(1, replacement.creates)
    }

    @Test fun sniffRestoresNonzeroPeekAndDoesNotGuessContainerFromFilename() {
        for (bytes in listOf(publicHlsBytes("h264/init.mp4"), "short unrelated bytes".toByteArray())) {
            val factory = Factory(); val clock = SessionHlsClock(); val input = extractorInput(bytes)
            input.advancePeekPosition(3)
            create(SessionHlsExtractors(clock, factory), TimestampAdjuster(0), input)
            assertEquals(0L, input.position); assertEquals(3L, input.peekPosition); assertEquals(3L, factory.inputPeek)
            assertEquals(1, factory.creates)
            if (bytes.size < 100) assertEquals(SessionHlsClock.State.Pending, clock.snapshot())
            else assertEquals(SessionHlsClock.State.Pending, clock.snapshot())
        }
    }

    @Test fun emptyInputDoesNotQualifyClockOrPreventOrdinaryDelegateCreation() {
        val factory = Factory(); val clock = SessionHlsClock()
        create(SessionHlsExtractors(clock, factory), TimestampAdjuster(0), extractorInput(byteArrayOf()))
        assertEquals(1, factory.creates)
        assertEquals(SessionHlsClock.State.Pending, clock.snapshot())
    }

    @Test fun wrapperDelegatesFormatsBytesMetadataAndChunkLifecycle() {
        val factory = Factory(); val clock = SessionHlsClock(); val adjuster = TimestampAdjuster(0)
        adjuster.adjustSampleTimestamp(10_500_000)
        val wrapped = create(SessionHlsExtractors(clock, factory), adjuster)
        clock.scope(clockTimeline(), 0, clockPlaylist())
        val sink = Sink(); wrapped.init(sink)
        val audio = factory.chunk.output.track(1, C.TRACK_TYPE_AUDIO)
        audio.sampleMetadata(-21_333, 1, 4, 0, null)
        assertEquals(SessionHlsClock.State.Pending, clock.snapshot())
        val video = factory.chunk.output.track(2, C.TRACK_TYPE_VIDEO)
        val format = Format.Builder().setSampleMimeType("video/avc").build(); video.format(format)
        video.durationUs(100)
        video.sampleData(ParsableByteArray(byteArrayOf(1,2)), 2)
        video.sampleData(ParsableByteArray(byteArrayOf(3)), 1, TrackOutput.SAMPLE_DATA_PART_MAIN)
        val stream = byteArrayOf(4,5).inputStream()
        video.sampleData(DataReader { b,o,n -> stream.read(b,o,n) }, 2, false)
        val crypto = TrackOutput.CryptoData(C.CRYPTO_MODE_AES_CTR, byteArrayOf(7), 0, 0)
        video.sampleMetadata(0, 3, 5, 1, crypto)
        assertEquals(listOf(format), sink.formats); assertEquals(listOf(100L), sink.durations)
        assertEquals(byteArrayOf(1,2,3,4,5).toList(), sink.bytes)
        assertEquals(listOf(C.TRACK_TYPE_VIDEO,0L,3,5,1,crypto), sink.metadata.last())
        assertEquals(SessionHlsClock.State.Ready(-10_500_000), clock.snapshot())
        factory.chunk.output.endTracks(); factory.chunk.output.seekMap(SeekMap.Unseekable(C.TIME_UNSET))
        assertEquals(1, sink.endTracks); assertEquals(1, sink.seekMaps)
        assertTrue(wrapped.isReusable); assertFalse(wrapped.isPackedAudioExtractor)
        assertFalse(wrapped.read(extractorInput(byteArrayOf()))); assertEquals(1, factory.chunk.reads)
        wrapped.onTruncatedSegmentParsed(); assertEquals(1, factory.chunk.truncated)
        val recreated = wrapped.recreate(); recreated.init(sink)
        factory.chunk.output.track(2, C.TRACK_TYPE_VIDEO).sampleMetadata(1_000_000, 1, 0, 0, null)
        assertEquals(1, factory.chunk.recreated); assertEquals(SessionHlsClock.State.Ready(-10_500_000), clock.snapshot())
    }


    @Test fun realProviderResetDuringAnActiveWrapperReadIsAmbiguous() {
        val provider = TimestampAdjusterProvider()
        val first = provider.getAdjuster(0)
        val clock = SessionHlsClock(); val factory = Factory()
        val wrapper = SessionHlsExtractors(clock, factory)
        val old = create(wrapper, first)
        factory.chunk.onRead = {
            clock.seeking(); provider.reset()
            val fresh = provider.getAdjuster(0)
            assertNotSame(first, fresh)
            assertEquals(C.TIME_UNSET, fresh.timestampOffsetUs)
            create(wrapper, fresh)
        }
        assertFalse(old.read(extractorInput(byteArrayOf())))
        assertEquals(SessionHlsClock.State.Unavailable(SessionHlsClock.Reason.AMBIGUOUS_ADJUSTER),
            clock.publication())
        factory.chunk.onRead = null
        clock.retire()
        assertFalse(old.read(extractorInput(byteArrayOf())))
        assertNull(clock.publication())
    }

    @Test fun aRejectedSampleIsNotAClockReadinessObservation() {
        val factory = Factory(); val clock = SessionHlsClock(); val adjuster = TimestampAdjuster(0)
        adjuster.adjustSampleTimestamp(10_500_000)
        val wrapped = create(SessionHlsExtractors(clock, factory), adjuster); clock.scope(clockTimeline(), 0, clockPlaylist())
        val sink = Sink(); sink.rejectMetadata = true; wrapped.init(sink)
        try { factory.chunk.output.track(1, C.TRACK_TYPE_VIDEO).sampleMetadata(0,1,1,0,null); fail("sink rejection must propagate unchanged") }
        catch (_: IllegalStateException) { }
        assertEquals(SessionHlsClock.State.Pending, clock.snapshot())
    }
}
