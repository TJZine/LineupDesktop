package com.tjzine.lineup.player

import android.net.Uri
import androidx.media3.common.C
import androidx.media3.common.DataReader
import androidx.media3.common.Format
import androidx.media3.common.util.TimestampAdjuster
import androidx.media3.common.util.ParsableByteArray
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.analytics.PlayerId
import androidx.media3.exoplayer.hls.DefaultHlsExtractorFactory
import androidx.media3.exoplayer.hls.HlsExtractorFactory
import androidx.media3.exoplayer.hls.HlsMediaChunkExtractor
import androidx.media3.extractor.ExtractorInput
import androidx.media3.extractor.ExtractorOutput
import androidx.media3.extractor.TrackOutput
import androidx.media3.extractor.mp4.Sniffer
import androidx.media3.extractor.text.SubtitleParser
import java.io.IOException

/** Decorates the pinned stock factory; it never changes sample data or timestamp adjustment. */
@UnstableApi
internal class SessionHlsExtractors(
    private val clock: SessionHlsClock,
    private var delegate: HlsExtractorFactory = DefaultHlsExtractorFactory(),
) : HlsExtractorFactory {
    override fun setSubtitleParserFactory(factory: SubtitleParser.Factory): HlsExtractorFactory {
        delegate = delegate.setSubtitleParserFactory(factory)
        return this
    }

    override fun experimentalParseSubtitlesDuringExtraction(parse: Boolean): HlsExtractorFactory {
        delegate = delegate.experimentalParseSubtitlesDuringExtraction(parse)
        return this
    }

    override fun experimentalSetCodecsToParseWithinGopSampleDependencies(codecs: Int): HlsExtractorFactory {
        delegate = delegate.experimentalSetCodecsToParseWithinGopSampleDependencies(codecs)
        return this
    }

    override fun getOutputTextFormat(format: Format): Format = delegate.getOutputTextFormat(format)

    override fun createExtractor(
        uri: Uri,
        format: Format,
        muxedCaptionFormats: MutableList<Format>?,
        timestampAdjuster: TimestampAdjuster,
        responseHeaders: MutableMap<String, MutableList<String>>,
        sniffingExtractorInput: ExtractorInput,
        playerId: PlayerId,
    ): HlsMediaChunkExtractor {
        // The bundled extractor's implementation field is not public. Use Media3's
        // own bounded fMP4 sniffer instead of guessing from a URI or using reflection.
        val originalPeek = sniffingExtractorInput.peekPosition - sniffingExtractorInput.position
        val fragmented = if (originalPeek in 0..Int.MAX_VALUE.toLong()) {
            try {
                sniffingExtractorInput.resetPeekPosition()
                Sniffer.sniffFragmented(sniffingExtractorInput) == null
            } catch (_: IOException) {
                false
            } catch (_: RuntimeException) {
                false
            } finally {
                sniffingExtractorInput.resetPeekPosition()
                if (originalPeek > 0) sniffingExtractorInput.advancePeekPosition(originalPeek.toInt())
            }
        } else false // Do not alter an unrepresentable caller-owned peek cursor.
        val binding = clock.bind(timestampAdjuster, fragmented)
        val extractor = delegate.createExtractor(uri, format, muxedCaptionFormats, timestampAdjuster,
            responseHeaders, sniffingExtractorInput, playerId)
        return ObservedExtractor(extractor, binding, clock)
    }

    private class ObservedExtractor(
        private val delegate: HlsMediaChunkExtractor,
        private val binding: SessionHlsClock.Binding?,
        private val clock: SessionHlsClock,
    ) : HlsMediaChunkExtractor by delegate {
        override fun init(output: ExtractorOutput) = delegate.init(object : ExtractorOutput by output {
            override fun track(id: Int, type: Int): TrackOutput {
                val target = output.track(id, type)
                if (type != C.TRACK_TYPE_VIDEO) return target
                return object : TrackOutput by target {
                    // Kotlin delegation does not forward Java default methods.
                    override fun format(format: Format) {
                        target.format(format)
                        clock.videoFormat(binding, format.frameRate)
                    }
                    override fun durationUs(durationUs: Long) = target.durationUs(durationUs)
                    override fun sampleData(input: DataReader, length: Int, allowEnd: Boolean): Int =
                        target.sampleData(input, length, allowEnd)
                    override fun sampleData(data: ParsableByteArray, length: Int) =
                        target.sampleData(data, length)

                    override fun sampleMetadata(timeUs: Long, flags: Int, size: Int, offset: Int,
                        cryptoData: TrackOutput.CryptoData?) {
                        target.sampleMetadata(timeUs, flags, size, offset, cryptoData)
                        clock.videoSample(binding, timeUs)
                    }
                }
            }
        })

        override fun read(input: ExtractorInput): Boolean {
            clock.beginRead(binding)
            try { return delegate.read(input) } finally { clock.endRead(binding) }
        }

        override fun recreate(): HlsMediaChunkExtractor = ObservedExtractor(delegate.recreate(), binding, clock)
    }
}
