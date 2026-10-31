package com.tjzine.lineup.player

import android.content.Context
import android.net.Uri
import android.os.Handler
import androidx.media3.common.Format
import androidx.media3.common.Timeline
import androidx.media3.common.util.TimestampAdjuster
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.Renderer
import androidx.media3.exoplayer.analytics.PlayerId
import androidx.media3.exoplayer.hls.DefaultHlsExtractorFactory
import androidx.media3.exoplayer.hls.HlsExtractorFactory
import androidx.media3.exoplayer.hls.HlsMediaChunkExtractor
import androidx.media3.exoplayer.mediacodec.MediaCodecAdapter
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.video.MediaCodecVideoRenderer
import androidx.media3.exoplayer.video.VideoRendererEventListener
import androidx.media3.extractor.ExtractorInput
import java.nio.ByteBuffer

/** Same pinned default extractors, including every mutable configuration method. */
@UnstableApi
internal class E6Extractors(
    private val observation: E6Observation,
    private val delegate: HlsExtractorFactory = DefaultHlsExtractorFactory(),
) : HlsExtractorFactory by delegate {
    override fun createExtractor(
        uri: Uri,
        format: Format,
        muxedCaptionFormats: MutableList<Format>?,
        timestampAdjuster: TimestampAdjuster,
        responseHeaders: MutableMap<String, MutableList<String>>,
        sniffingExtractorInput: ExtractorInput,
        playerId: PlayerId,
    ): HlsMediaChunkExtractor {
        observation.bindLoaderAdjuster(timestampAdjuster)
        return delegate.createExtractor(uri, format, muxedCaptionFormats, timestampAdjuster,
            responseHeaders, sniffingExtractorInput, playerId)
    }
}

/**
 * Debug-only ordinary MediaCodec path. The 1.11.1 Builder defaults match the
 * unmodified DefaultRenderersFactory defaults for AV1 parsing, decode-only flag,
 * drop threshold, scheduling and duration-to-progress. No effects/prewarming or
 * extension renderer is enabled. The factory still constructs its ordinary audio,
 * text and metadata renderers. Public baseline controls independently check parity.
 */
@UnstableApi
internal class E6Renderers(context: Context, private val observation: E6Observation) : DefaultRenderersFactory(context) {
    @Volatile private var video: E6VideoRenderer? = null

    override fun buildVideoRenderers(
        context: Context,
        extensionRendererMode: Int,
        mediaCodecSelector: MediaCodecSelector,
        enableDecoderFallback: Boolean,
        eventHandler: Handler,
        eventListener: VideoRendererEventListener,
        allowedVideoJoiningTimeMs: Long,
        out: ArrayList<Renderer>,
    ) {
        check(extensionRendererMode == EXTENSION_RENDERER_MODE_OFF)
        val observedEvents = object : VideoRendererEventListener by eventListener {
            override fun onRenderedFirstFrame(output: Any, renderTimeMs: Long) {
                observation.renderedFirstFrame(renderTimeMs)
                eventListener.onRenderedFirstFrame(output, renderTimeMs)
            }
        }
        val builder = MediaCodecVideoRenderer.Builder(context)
            .setCodecAdapterFactory(getCodecAdapterFactory())
            .setMediaCodecSelector(mediaCodecSelector)
            .setAllowedJoiningTimeMs(allowedVideoJoiningTimeMs)
            .setEnableDecoderFallback(enableDecoderFallback)
            .setEventHandler(eventHandler)
            .setEventListener(observedEvents)
            .setMaxDroppedFramesToNotify(MAX_DROPPED_VIDEO_FRAME_COUNT_TO_NOTIFY)
        val renderer = E6VideoRenderer(builder, observation)
        video = renderer
        out.add(renderer)
    }

    fun frame(pts: Long, release: Long) { video?.frame(pts, release) }
}

@UnstableApi
internal class E6VideoRenderer(builder: MediaCodecVideoRenderer.Builder, private val observation: E6Observation) :
    MediaCodecVideoRenderer(builder) {
    private var processingBuffer: Long? = null
    private var firstRelease = true

    override fun onOutputStreamOffsetUsChanged(outputStreamOffsetUs: Long) {
        super.onOutputStreamOffsetUsChanged(outputStreamOffsetUs)
        observation.outputChanged(outputStreamOffsetUs)
        firstRelease = true
    }

    override fun onPositionReset(positionUs: Long, joining: Boolean, sampleStreamIsResetToKeyFrame: Boolean) {
        super.onPositionReset(positionUs, joining, sampleStreamIsResetToKeyFrame)
        observation.rendererReset(sampleStreamIsResetToKeyFrame)
        firstRelease = true
    }

    override fun renderOutputBufferV21(codec: MediaCodecAdapter, index: Int, presentationTimeUs: Long, releaseTimeNs: Long) {
        val candidate = if (firstRelease) observation.beginRelease(presentationTimeUs, releaseTimeNs) else null
        firstRelease = false
        var succeeded = false
        try {
            super.renderOutputBufferV21(codec, index, presentationTimeUs, releaseTimeNs)
            succeeded = true
        } finally { if (candidate != null) observation.endRelease(candidate, succeeded) }
    }

    override fun processOutputBuffer(
        positionUs: Long,
        elapsedRealtimeUs: Long,
        codec: MediaCodecAdapter?,
        buffer: ByteBuffer?,
        bufferIndex: Int,
        bufferFlags: Int,
        sampleCount: Int,
        bufferPresentationTimeUs: Long,
        isDecodeOnlyBuffer: Boolean,
        isLastBuffer: Boolean,
        format: Format,
    ): Boolean {
        processingBuffer = bufferPresentationTimeUs
        return try {
            super.processOutputBuffer(positionUs, elapsedRealtimeUs, codec, buffer, bufferIndex,
                bufferFlags, sampleCount, bufferPresentationTimeUs, isDecodeOnlyBuffer, isLastBuffer, format)
        } finally { processingBuffer = null }
    }

    fun frame(pts: Long, release: Long) {
        val timeline = getTimeline()
        val id = getMediaPeriodId()
        val index = id?.let { timeline.getIndexOfPeriod(it.periodUid) }
            ?.takeIf { it >= 0 && timeline.periodCount == 1 }
        val period = index?.let { timeline.getPeriod(it, Timeline.Period()) }
        observation.frame(pts, release, processingBuffer, getOutputStreamOffsetUs(), index,
            period?.positionInWindowUs, period != null)
    }
}
