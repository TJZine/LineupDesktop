package com.tjzine.lineup.player

import android.content.Context
import android.os.Handler
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.Renderer
import androidx.media3.exoplayer.mediacodec.MediaCodecAdapter
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.video.MediaCodecVideoRenderer
import androidx.media3.exoplayer.video.VideoRendererEventListener

/** Runs on Media3's playback looper, in the same order as the seek and frame release. */
internal class SessionSeekLanding(private val landed: (Long) -> Unit) {
    private var seekId: Long? = null
    private var reset = false

    fun arm(id: Long) {
        seekId = id
        reset = false
    }

    fun positionReset() {
        if (seekId != null) reset = true
    }

    fun frameReleased() {
        if (!reset) return
        val id = seekId ?: return
        seekId = null
        reset = false
        landed(id)
    }
}

/** The session uses the stock codec renderer with two observation points. */
@UnstableApi
internal class SessionRenderers(
    context: Context,
    private val landing: SessionSeekLanding,
) : DefaultRenderersFactory(context) {
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
        // Match DefaultRenderersFactory's default MediaCodecVideoRenderer builder.
        // Session engines use the default factory settings and no extension renderer.
        val builder = MediaCodecVideoRenderer.Builder(context)
            .setCodecAdapterFactory(codecAdapterFactory)
            .setMediaCodecSelector(mediaCodecSelector)
            .setAllowedJoiningTimeMs(allowedVideoJoiningTimeMs)
            .setEnableDecoderFallback(enableDecoderFallback)
            .setEventHandler(eventHandler)
            .setEventListener(eventListener)
            .setMaxDroppedFramesToNotify(MAX_DROPPED_VIDEO_FRAME_COUNT_TO_NOTIFY)
        out.add(SessionVideoRenderer(builder, landing))
    }
}

@UnstableApi
private class SessionVideoRenderer(
    builder: MediaCodecVideoRenderer.Builder,
    private val landing: SessionSeekLanding,
) : MediaCodecVideoRenderer(builder) {
    override fun onPositionReset(positionUs: Long, joining: Boolean, sampleStreamIsResetToKeyFrame: Boolean) {
        super.onPositionReset(positionUs, joining, sampleStreamIsResetToKeyFrame)
        if (!joining) landing.positionReset()
    }

    override fun renderOutputBufferV21(
        codec: MediaCodecAdapter,
        index: Int,
        presentationTimeUs: Long,
        releaseTimeNs: Long,
    ) {
        super.renderOutputBufferV21(codec, index, presentationTimeUs, releaseTimeNs)
        landing.frameReleased()
    }
}
