package com.tjzine.lineup.player

import android.os.Handler
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.Player
import androidx.media3.common.PlaybackException
import androidx.media3.common.Timeline
import androidx.media3.common.util.TimestampAdjuster
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlaybackException
import androidx.media3.exoplayer.mediacodec.MediaCodecRenderer
import java.util.Collections
import java.util.IdentityHashMap

/** One configured debug load. Player reads are exclusively on its application Looper. */
@UnstableApi
internal class E6Observation(
    val config: E6Config,
    private val handler: Handler,
    private val runOrdinal: Long,
    val deadlineNs: Long = Long.MAX_VALUE,
    private val now: () -> Long = System::nanoTime,
) {
    private val queue = E6FactQueue()
    @Volatile var terminal = false; private set
    @Volatile var seekEpoch = 0L; private set
    @Volatile private var outputEpoch = 0L
    @Volatile private var frameEpoch = 0L
    private var result = "running"
    private var failure: String? = null
    private var ready = false
    private var player: Player? = null
    private var loaded = false
    private var cancelIo: (() -> Unit)? = null
    private val adjusters = mutableMapOf<Long, MutableSet<TimestampAdjuster>>()
    private val loaderEpochs = IdentityHashMap<Thread, Long>()
    private var rendererOffset: Long? = null
    private var resetSeekEpoch = 0L
    private var callbackCount = 0L
    private var frameDispatchPending = false
    private val pendingFirst = mutableListOf<Frame>()
    private var latest: Frame? = null
    private val frames = mutableListOf<Frame>()
    private var initial: Frame? = null
    private var postSeekFirst: Frame? = null
    private var rendered: Frame? = null
    private var postSeekRendered: Frame? = null
    private val releaseCandidates = ArrayDeque<Release>()
    private var unmatchedRendered = false
    private var renderedSeen = false
    private var seekRequestNs: Long? = null
    private var seekPositionMs: Long? = null
    private var seekReset = false
    private var sampleOrigin: Long? = null
    private var sampleIndex = 0
    private var renderedReceiptNs: Long? = null
    private var loadNs = 0L
    private var readyNs: Long? = null
    private var http: E6Http? = null
    private val tick = Runnable { collect() }

    internal data class Frame(
        val pts: Long, val release: Long?, val callback: Long, val offset: Long?, val hls: Long?,
        val buffer: Long?, val output: Long, val reset: Long, val seek: Long,
        val periodIndex: Int?, val periodInWindow: Long?, val binding: Boolean,
    )

    internal class Release(val frame: Frame?) {
        var succeeded = false
        var receiptNs: Long? = null
        var elapsedMs: Long? = null
        var published = false
    }

    init { emit("configured", mapOf("baseline" to config.baseline, "noErrorRetry" to true)) }

    fun requireActive() {
        if (now() >= deadlineNs) { fail("active_deadline"); throw E6Failure("active_deadline") }
    }

    @Synchronized fun emit(event: String, fields: Map<String, Any?> = emptyMap()) {
        try {
            queue.add(linkedMapOf<String, Any?>("event" to event, "monoNs" to now(), "runOrdinal" to runOrdinal,
                "requestedOffsetUs" to config.offsetUs, "mode" to if (config.seek) "seek_after_ready" else "default",
                "sourceClass" to config.video, "seekEpoch" to seekEpoch, "commandSeekEpoch" to seekEpoch, "outputEpoch" to outputEpoch,
                "frameEpoch" to frameEpoch, "sourceOriginProven" to false, "clockDomain" to "system_nano_time") + fields)
        } catch (error: E6Failure) {
            terminal = true; result = "failed"; failure = error.code
            handler.post { cancelIo?.invoke() }
        }
    }

    fun fail(error: E6Failure) = fail(error.code, error.scopeFacts())

    @Synchronized fun fail(code: String, fields: Map<String, Any?> = emptyMap()) {
        if (result == "failed" || result == "complete" && code == "cancelled") return
        val safe = code.takeIf { it in E6Facts.enums.getValue("failureCode") } ?: "playback_error"
        terminal = true; result = "failed"; failure = safe
        emit("failure", fields + mapOf("failureCode" to safe))
        handler.removeCallbacks(tick)
        handler.post { cancelIo?.invoke() }
    }

    fun attach(player: Player, http: E6Http, cancel: () -> Unit) {
        check(android.os.Looper.myLooper() == handler.looper)
        synchronized(this) {
            if (loaded || terminal) throw E6Failure("unexpected_load")
            loaded = true; this.player = player; this.http = http; cancelIo = cancel; loadNs = now()
        }
        emit("load")
        handler.post(tick)
    }

    fun accepts(media: MediaLoad): Boolean = media.kind == LoadKind.plexSession && media.token == null &&
        media.startSeconds == 0.0 && media.uri == config.variant.toString()

    @Synchronized fun loaderOpened(epoch: Long) { loaderEpochs[Thread.currentThread()] = epoch }
    @Synchronized fun bindLoaderAdjuster(adjuster: TimestampAdjuster) {
        val epoch = loaderEpochs[Thread.currentThread()] ?: return
        bindAdjuster(adjuster, epoch)
    }
    @Synchronized internal fun bindAdjuster(adjuster: TimestampAdjuster, epoch: Long = 0) {
        adjusters.getOrPut(epoch) { Collections.newSetFromMap(IdentityHashMap<TimestampAdjuster, Boolean>()) } += adjuster
    }

    @Synchronized fun outputChanged(offset: Long) {
        rendererOffset = offset.takeUnless { it == C.TIME_UNSET }
        outputEpoch++
        emit("output_change", mapOf("rendererOffsetUs" to rendererOffset))
    }

    @Synchronized fun rendererReset(@Suppress("UNUSED_PARAMETER") sampleStreamIsResetToKeyFrame: Boolean = false) {
        frameEpoch++
        resetSeekEpoch = seekEpoch
        if (seekEpoch > 0) seekReset = true
        latest = null
        frames.clear()
        emit("renderer_reset")
    }

    /** Called synchronously inside renderer.processOutputBuffer; buffer is independently observed. */
    @Synchronized fun frame(
        pts: Long, release: Long, buffer: Long?, offset: Long?, periodIndex: Int?, periodInWindow: Long?, binding: Boolean,
    ) {
        if (terminal) return
        callbackCount++
        // A renderer keyframe reset does not reveal whether HLS reset its
        // provider. Buffered/reused extraction retains its actual adjuster;
        // replacement extraction binds its real reference before emitting data.
        // The approved source is one period with no discontinuities/renditions.
        val matched = adjusters[resetSeekEpoch] ?: adjusters[0]
        val a = if (matched?.size == 1) matched.single().timestampOffsetUs.takeUnless { it == C.TIME_UNSET } else null
        val frame = Frame(pts, release.takeUnless { it == C.TIME_UNSET }, now(), offset?.takeUnless { it == C.TIME_UNSET } ?: rendererOffset, a,
            buffer, outputEpoch, frameEpoch, resetSeekEpoch, periodIndex, periodInWindow, binding)
        if (buffer != null && frame.offset != null && buffer - frame.offset != pts) {
            fail("clock_relation_invalid"); return
        }
        if (initial == null) {
            initial = frame
            if (frame !in pendingFirst) pendingFirst += frame
        }
        if (seekEpoch > 0 && seekReset && frame.seek == seekEpoch && postSeekFirst == null) {
            postSeekFirst = frame
            pendingFirst += frame
        }
        latest = frame
        // Retain the last intended-released frame and bounded future releases.
        // A callback may arrive well before its releaseTimeNs; it cannot replace
        // the frame attributed to the current application-thread position yet.
        val released = frames.asReversed().filter { it.release != null && it.release <= frame.callback }
            .maxWithOrNull(compareBy<Frame> { it.release }.thenBy { it.callback })
        frames.removeAll { it.release != null && it.release <= frame.callback && it !== released }
        if (frames.size >= 256) { fail("event_overflow"); return }
        frames += frame
        if (!frameDispatchPending) {
            frameDispatchPending = true
            handler.post {
                val firsts = synchronized(this) {
                    frameDispatchPending = false
                    pendingFirst.toList().also { pendingFirst.clear() }
                }
                if (!terminal) firsts.forEach { emit("frame_first", snapshot(it)) }
                maybeStart()
            }
        }
    }

    fun ready() {
        if (terminal) return
        if (!ready) {
            ready = true; readyNs = now()
            emit("ready", snapshot(sampleFrame(now())))
        }
        maybeStart()
    }

    /** Register before super.renderOutputBufferV21 can post its first-frame signal. */
    @Synchronized fun beginRelease(pts: Long, release: Long): Release {
        val matched = latest?.takeIf { it.pts == pts && it.release == release &&
            it.output == outputEpoch && it.reset == frameEpoch && it.seek == resetSeekEpoch }
        val candidate = Release(matched)
        if (releaseCandidates.size >= 4) { fail("event_overflow"); return candidate }
        releaseCandidates.addLast(candidate)
        return candidate
    }

    fun endRelease(candidate: Release, succeeded: Boolean) {
        synchronized(this) { candidate.succeeded = succeeded }
        if (!succeeded) { fail("clock_bridge_unavailable"); return }
        handler.post { publishRelease(candidate) }
    }

    private fun publishRelease(candidate: Release) {
        val frame = synchronized(this) {
            if (!candidate.succeeded || candidate.receiptNs == null || candidate.published) return
            candidate.published = true
            candidate.frame
        }
        if (terminal) return
        renderedSeen = true
        if (frame != null) {
            if (frame === initial) rendered = frame
            if (frame === postSeekFirst) postSeekRendered = frame
        } else unmatchedRendered = true
        renderedReceiptNs = candidate.receiptNs
        emit("rendered_first_frame", snapshot(frame) + mapOf("renderedCallbackNs" to candidate.receiptNs,
            "releaseElapsedRealtimeMs" to candidate.elapsedMs, "renderedAssociated" to (frame != null)))
        if (frame == null) { fail("clock_bridge_unavailable"); return }
        maybeStart()
    }

    fun renderedFirstFrame(renderElapsedMs: Long) {
        if (terminal) return
        if (config.baseline && !renderedSeen) {
            renderedSeen = true; renderedReceiptNs = now()
            emit("rendered_first_frame", snapshot(null) + mapOf("renderedCallbackNs" to renderedReceiptNs,
                "releaseElapsedRealtimeMs" to renderElapsedMs, "renderedAssociated" to false))
        } else if (!config.baseline) {
            val candidate = synchronized(this) {
                releaseCandidates.firstOrNull { it.receiptNs == null }?.also {
                    it.receiptNs = now(); it.elapsedMs = renderElapsedMs
                }
            }
            if (candidate == null) {
                unmatchedRendered = true
                emit("rendered_first_frame", snapshot(null) + mapOf("renderedAssociated" to false,
                    "releaseElapsedRealtimeMs" to renderElapsedMs, "renderedCallbackNs" to now()))
                fail("clock_bridge_unavailable")
            } else publishRelease(candidate)
        }
        maybeStart()
    }

    fun beforeSeek(seconds: Double, exact: Boolean): Boolean {
        val p = player ?: return false.also { fail("seek_contract") }
        if (!config.seek || !ready || seekEpoch != 0L || !exact || !seconds.isFinite() ||
            kotlin.math.abs(seconds * 1_000_000 - config.offsetUs) > 0.01 || terminal) {
            fail("seek_contract"); return false
        }
        seekPositionMs = p.currentPosition
        seekRequestNs = now()
        seekEpoch = 1L
        emit("seek_request", snapshot(synchronized(this) { latest }) + mapOf("seekTargetUs" to config.offsetUs,
            "seekPositionMs" to seekPositionMs, "seekExact" to exact, "seekRequestNs" to seekRequestNs))
        // A zero-distance command may legitimately preserve the renderer epoch and current frame.
        maybeStart()
        return true
    }

    fun seekAck() { emit("seek_ack", mapOf("seekTargetUs" to config.offsetUs, "seekExact" to true)) }
    fun discontinuity() { if (!terminal) emit("seek_discontinuity", snapshot(synchronized(this) { latest })) }

    private fun noDistance(): Boolean = seekPositionMs?.let { it * 1000 == config.offsetUs } == true

    private fun attributable(frame: Frame?): Boolean = frame != null &&
        (!config.seek || seekEpoch > 0 && (frame.seek == seekEpoch && seekReset || noDistance() && !seekReset))

    private fun maybeStart() {
        if (terminal || sampleOrigin != null || !renderedSeen) return
        val frame = synchronized(this) { if (config.seek && seekReset) postSeekFirst else initial }
        val confirmed = if (config.seek && seekReset) postSeekRendered === frame && frame != null else rendered === frame && frame != null
        if (config.baseline || attributable(frame) && confirmed) {
            if (config.seek && seekEpoch == 0L) return
            // The first render may precede READY. Keep its actual callback time and never relabel a later frame.
            sampleOrigin = frame?.release ?: if (config.baseline) renderedReceiptNs else null
            if (sampleOrigin == null) return
            collect()
        }
    }

    private fun collect() {
        handler.removeCallbacks(tick)
        if (terminal || !loaded) return
        val time = now()
        if (time >= deadlineNs) { fail("active_deadline"); return }
        if (!ready && time - loadNs >= 30_000_000_000L) { fail("startup_deadline"); return }
        val sinceReady = readyNs
        if (sinceReady != null && sampleOrigin == null && time - sinceReady >= 15_000_000_000L) {
            fail("first_frame_deadline"); return
        }
        val origin = sampleOrigin
        if (origin != null) {
            // Do not fabricate simultaneous samples if the application Looper was stalled.
            while (sampleIndex <= 40 && time >= origin + sampleIndex * 250_000_000L) {
                val frame = sampleFrame(time)
                val due = origin + sampleIndex * 250_000_000L
                emit("position", snapshot(frame) + mapOf("sampleIndex" to sampleIndex,
                    "sampleDueNs" to due, "late" to (time - due > 250_000_000L)))
                sampleIndex++
            }
            if (sampleIndex == 41) {
                val frame = sampleFrame(time)
                val first = if (config.seek && seekReset) postSeekFirst else initial
                if (config.seek) emit("seek_result", snapshot(first) + mapOf("seekResult" to when {
                    noDistance() && !seekReset -> "seek_no_distance_no_new_epoch"
                    first != null && first.hls != null && first.offset != null && first.binding &&
                        postSeekRendered === first && attributable(first) && seekReset -> "post_seek_frame_observed"
                    else -> "seek_landing_unconfirmed"
                }))
                if (!ready || !config.baseline && (frame == null || !frame.binding || frame.hls == null || frame.offset == null ||
                        first == null || !first.binding || first.hls == null || first.offset == null ||
                        unmatchedRendered || (if (config.seek && seekReset) postSeekRendered !== first else rendered !== first) ||
                        !attributable(frame))) fail("clock_bridge_unavailable")
                else {
                    terminal = true; result = "complete"
                    http?.closeGate()
                }
                return
            }
        }
        handler.postDelayed(tick, if (origin == null) 20 else
            ((origin + sampleIndex * 250_000_000L - now()) / 1_000_000).coerceIn(1, 250))
    }

    @Synchronized private fun sampleFrame(time: Long): Frame? = frames.asReversed().filter {
        it.release != null && it.release <= time && attributable(it)
    }.maxWithOrNull(compareBy<Frame> { it.release }.thenBy { it.callback })

    internal fun snapshot(frame: Frame?): Map<String, Any?> {
        check(android.os.Looper.myLooper() == handler.looper)
        val p = player ?: return emptyMap()
        val time = now()
        val timeline = p.currentTimeline
        val index = p.currentPeriodIndex
        val validPeriod = !timeline.isEmpty && index in 0 until timeline.periodCount
        val period = if (validPeriod) timeline.getPeriod(index, Timeline.Period()) else null
        val window = if (!timeline.isEmpty && p.currentMediaItemIndex in 0 until timeline.windowCount)
            timeline.getWindow(p.currentMediaItemIndex, Timeline.Window()) else null
        val position = p.currentPosition
        val binding = frame?.binding == true && frame.periodIndex == index && period != null &&
            frame.periodInWindow == period.positionInWindowUs
        val known = binding && frame?.hls != null && frame.offset != null
        val extractor = if (known) frame!!.pts - frame.hls!! else null
        val frameWindow = if (binding) frame!!.pts + period!!.positionInWindowUs else null
        val hypothesis = extractor?.minus(10_000_000)
        return linkedMapOf("monoNs" to time, "positionMs" to position, "durationMs" to p.duration.takeUnless { it == C.TIME_UNSET || it < 0 },
            "bufferedPositionMs" to p.bufferedPosition.takeUnless { it == C.TIME_UNSET || it < 0 },
            "windowIndex" to if (window == null) null else p.currentMediaItemIndex, "periodIndex" to if (validPeriod) index else null,
            "periodPositionInWindowUs" to period?.positionInWindowUs,
            "periodPositionUs" to period?.let { position * 1000 - it.positionInWindowUs },
            "windowDefaultPositionUs" to window?.defaultPositionUs,
            "windowPositionInFirstPeriodUs" to window?.positionInFirstPeriodUs,
            "windowDurationUs" to window?.durationUs?.takeUnless { it == C.TIME_UNSET },
            "playbackState" to when (p.playbackState) { Player.STATE_READY -> "ready"; Player.STATE_BUFFERING -> "buffering";
                Player.STATE_ENDED -> "ended"; else -> "idle" }, "playing" to p.isPlaying,
            "buffering" to (p.playbackState == Player.STATE_BUFFERING), "bindingKnown" to binding, "clockKnown" to known,
            "callbackPtsUs" to frame?.pts, "releaseTimeNs" to frame?.release, "callbackMonoNs" to frame?.callback,
            "rendererOffsetUs" to frame?.offset, "hlsOffsetUs" to frame?.hls, "hlsOffsetInitialized" to (frame?.hls != null),
            "decoderBufferUs" to frame?.buffer, "rendererRelationValid" to frame?.let { f ->
                if (f.buffer == null || f.offset == null) null else f.buffer - f.offset == f.pts },
            "extractorPtsUs" to extractor, "extractorRequestedDeltaUs" to extractor?.minus(config.offsetUs),
            "hypothesisSourceUs" to hypothesis, "hypothesisRequestedDeltaUs" to hypothesis?.minus(config.offsetUs),
            "frameWindowUs" to frameWindow, "frameWindowPositionDeltaUs" to frameWindow?.minus(position * 1000),
            "extractorPositionDeltaUs" to extractor?.minus(position * 1000),
            "hypothesisPositionDeltaUs" to hypothesis?.minus(position * 1000),
            "frameAgeNs" to frame?.release?.takeIf { it <= time }?.let { time - it },
            "snapshotLagNs" to frame?.let { time - it.callback },
            "outputEpoch" to (frame?.output ?: outputEpoch), "frameEpoch" to (frame?.reset ?: frameEpoch),
            "seekEpoch" to (frame?.seek ?: seekEpoch),
            "callbacks" to callbackCount, "renderedAssociated" to frame?.let { f ->
                listOfNotNull(rendered, postSeekRendered).any { confirmed ->
                    f.output == confirmed.output && f.reset == confirmed.reset && f.seek == confirmed.seek
                }
            }.orFalse())
    }

    private fun Boolean?.orFalse(): Boolean = this == true

    fun format(format: Format, video: Boolean) {
        val codec = when (format.sampleMimeType) { "video/avc" -> "h264"; "video/hevc" -> "hevc"; "audio/mp4a-latm" -> "aac"; else -> "unknown" }
        val transfer = when (format.colorInfo?.colorTransfer) { C.COLOR_TRANSFER_ST2084 -> "pq"; C.COLOR_TRANSFER_HLG -> "hlg";
            C.COLOR_TRANSFER_SDR -> "sdr"; else -> "unknown" }
        emit("format", if (video) mapOf("videoCodec" to codec, "width" to format.width.takeIf { it > 0 },
            "height" to format.height.takeIf { it > 0 }, "transfer" to transfer) else mapOf("audioCodec" to codec))
        if (codec != if (video) config.video else "aac") fail("output_mismatch")
    }

    fun playerFailure(error: PlaybackException, code: String) {
        if (config.video == "hevc" && explicitHevcRejection(error)) {
            emit("format", mapOf("videoCodec" to "hevc", "decoderSupport" to "unsupported"))
        }
        fail(code)
    }

    companion object {
        /** Actual typed renderer/decoder evidence, never an inference from source or IO failure. */
        internal fun explicitHevcRejection(error: PlaybackException): Boolean {
            if (error.errorCode !in setOf(PlaybackException.ERROR_CODE_DECODER_INIT_FAILED,
                    PlaybackException.ERROR_CODE_DECODING_FORMAT_UNSUPPORTED,
                    PlaybackException.ERROR_CODE_DECODING_FORMAT_EXCEEDS_CAPABILITIES) ||
                Media3Failure.classify(error).first != "video_decode_error") return false
            val mime = (error as? ExoPlaybackException)?.rendererFormat?.sampleMimeType
                ?: generateSequence(error.cause) { it.cause }.take(32)
                    .filterIsInstance<MediaCodecRenderer.DecoderInitializationException>().firstOrNull()?.mimeType
            return mime == "video/hevc"
        }
    }

    fun release(released: Boolean, threadAlive: Boolean, networkDrained: Boolean) {
        handler.removeCallbacks(tick)
        http?.closeGate()
        emit("release", mapOf("released" to released, "playbackThreadAlive" to threadAlive,
            "activeCalls" to (http?.activeCalls() ?: 0), "networkDrained" to networkDrained) + (http?.totals() ?: emptyMap()))
        if (!released || threadAlive || !networkDrained || (http?.activeCalls() ?: 0) != 0) fail("release_failed")
        synchronized(this) { adjusters.clear(); loaderEpochs.clear(); frames.clear(); releaseCandidates.clear();
            latest = null; initial = null; postSeekFirst = null; rendered = null; postSeekRendered = null; rendererOffset = null }
        player = null; cancelIo = null
    }

    fun cancel() {
        http?.closeGate()
        handler.removeCallbacks(tick)
        cancelIo?.invoke()
        if (!terminal) fail("cancelled")
    }

    @Synchronized fun drain(): Map<String, Any?> = mapOf("events" to queue.drain(), "hasReady" to ready,
        "terminal" to terminal, "result" to result, "failureCode" to failure)
}
