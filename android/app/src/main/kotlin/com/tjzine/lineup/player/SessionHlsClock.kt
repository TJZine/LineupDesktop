package com.tjzine.lineup.player

import androidx.media3.common.C
import androidx.media3.common.Timeline
import androidx.media3.common.util.TimestampAdjuster
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.hls.playlist.HlsMediaPlaylist
import androidx.media3.exoplayer.hls.playlist.HlsMultivariantPlaylist

/** One load's HLS adjustment. Samples stay untouched; application policy belongs to Dart. */
@UnstableApi
internal class SessionHlsClock {
    enum class Reason(val wire: String) {
        DISCONTINUITY("discontinuity"),
        PERIOD_MISMATCH("period_mismatch"),
        AMBIGUOUS_ADJUSTER("ambiguous_adjuster"),
        INVALID_TIMESTAMP("invalid_timestamp"),
    }

    sealed interface State {
        data object Pending : State
        data class Ready(val adjustmentUs: Long, val rebased: Boolean = false) : State {
            init { require(adjustmentUs != C.TIME_UNSET && adjustmentUs != Long.MIN_VALUE) }
        }
        data class Unavailable(val reason: Reason) : State
    }

    /** Private association identity, never a wire revision or a player position. */
    class Binding internal constructor(internal val adjuster: TimestampAdjuster) {
        internal var reads = 0
        internal var videoSeen = false
        internal var qualifiedA: Long? = null
        internal var previousA: Long? = null
        internal var frameDurationUs: Double? = null
        internal var previousVideoUs: Long? = null
        internal var observedSpacingUs: Long? = null
    }

    private var open = true
    private var state: State = State.Pending
    private var binding: Binding? = null
    private var replacementPermitted = false
    private var lastAcceptedA: Long? = null
    private var rebased = false
    private var periodUid: Any? = null
    private var scopeReady = false
    private var supported = true
    private var pendingBarrier = false
    private var qualified: State.Ready? = null

    /** Arm before Player.seekTo. A buffered seek does not discard its already proven basis. */
    @Synchronized
    fun seeking() {
        if (open && state !is State.Unavailable) replacementPermitted = true
    }

    @Synchronized
    fun bind(value: TimestampAdjuster, fragmentedMp4: Boolean): Binding? {
        if (!open || state is State.Unavailable) return null
        if (!fragmentedMp4) { unsupportedScope(); return null }
        val previous = binding
        if (previous?.adjuster === value) return previous
        if (previous != null && (!replacementPermitted || previous.reads != 0)) {
            unavailable(Reason.AMBIGUOUS_ADJUSTER)
            return null
        }
        val next = Binding(value).also { it.previousA = lastAcceptedA }
        binding = next // Old wrapper tokens become inert, including their late callbacks.
        if (previous != null) {
            replacementPermitted = false
            requalify(next)
        }
        return next
    }

    @Synchronized
    fun beginRead(value: Binding?) {
        if (open && value != null && binding === value && state !is State.Unavailable) value.reads++
    }

    @Synchronized
    fun endRead(value: Binding?) {
        if (value != null && value.reads > 0) value.reads--
    }

    @Synchronized
    fun videoFormat(value: Binding?, frameRate: Float) {
        if (!current(value)) return
        value!!.frameDurationUs = frameRate.toDouble().takeIf { it.isFinite() && it > 0 }
            ?.let { 1_000_000.0 / it }?.takeIf { it.isFinite() && it > 0 }
    }

    /** Only called after the ordinary TrackOutput accepted this real video sample. */
    @Synchronized
    fun videoSample(value: Binding?, timeUs: Long) {
        if (!current(value)) return
        val active = value!!
        refresh()
        if (state is State.Unavailable) return
        if (timeUs == C.TIME_UNSET || timeUs == Long.MIN_VALUE) {
            unavailable(Reason.INVALID_TIMESTAMP); return
        }
        val offset = active.adjuster.timestampOffsetUs
        if (offset == Long.MIN_VALUE) { unavailable(Reason.INVALID_TIMESTAMP); return }
        if (offset == C.TIME_UNSET) return // The new basis still needs initialized video metadata.
        try { Math.subtractExact(timeUs, offset) }
        catch (_: ArithmeticException) { unavailable(Reason.INVALID_TIMESTAMP); return }
        active.previousVideoUs?.let { previous ->
            val spacing = try { Math.subtractExact(timeUs, previous).let {
                if (it == Long.MIN_VALUE) null else kotlin.math.abs(it)
            } } catch (_: ArithmeticException) { null }
            if (spacing != null && spacing > 0)
                active.observedSpacingUs = minOf(active.observedSpacingUs ?: spacing, spacing)
        }
        active.previousVideoUs = timeUs
        active.videoSeen = true
        refresh()
    }

    // Convenient direct state-test entry; extractor callbacks use their immutable binding token.
    @Synchronized
    fun videoSample(value: TimestampAdjuster, timeUs: Long) {
        videoSample(binding?.takeIf { it.adjuster === value }, timeUs)
    }

    /** Parsed Media3 manifest/timeline only; never a second parser or an HTTP request. */
    @Synchronized
    fun scope(timeline: Timeline, currentPeriod: Int, playlist: HlsMediaPlaylist?) {
        if (!open || state is State.Unavailable) return
        if (timeline.isEmpty || playlist == null) {
            if (state is State.Ready) unavailable(Reason.PERIOD_MISMATCH)
            return
        }
        if (timeline.windowCount != 1 || timeline.periodCount != 1 || currentPeriod != 0) {
            unavailable(Reason.PERIOD_MISMATCH); return
        }
        val period = timeline.getPeriod(0, Timeline.Period(), true)
        val window = timeline.getWindow(0, Timeline.Window())
        if (period.positionInWindowUs != 0L || window.positionInFirstPeriodUs != 0L ||
            period.uid == null || periodUid != null && periodUid != period.uid) {
            unavailable(Reason.PERIOD_MISMATCH); return
        }
        if (playlist.discontinuitySequence != 0 ||
            playlist.segments.any { it.relativeDiscontinuitySequence != 0 }) {
            unavailable(Reason.DISCONTINUITY); return
        }
        if (playlist.mediaSequence != 0L || playlist.trailingParts.isNotEmpty() ||
            playlist.interstitials.isNotEmpty() || playlist.segments.any { it.hasGapTag }) {
            unavailable(Reason.PERIOD_MISMATCH); return
        }
        if (window.isDynamic || !playlist.hasEndTag || playlist.segments.isEmpty() ||
            playlist.segments.any { it.initializationSegment == null }) {
            unsupportedScope(); return
        }
        periodUid = period.uid
        scopeReady = true
        refresh()
    }

    @Synchronized
    fun renditions(playlist: HlsMultivariantPlaylist) {
        if (!open || state is State.Unavailable) return
        if (playlist.variants.size != 1 || playlist.videos.isNotEmpty() ||
            playlist.audios.isNotEmpty() || playlist.subtitles.isNotEmpty() ||
            playlist.closedCaptions.isNotEmpty() || playlist.contentSteeringInfo != null) unsupportedScope()
    }

    /** Outside the fMP4/video precondition: no guessed A and no extra terminal reason. */
    @Synchronized
    fun unsupportedScope() {
        if (!open || state is State.Unavailable) return
        supported = false
        if (state is State.Ready) pendingBarrier = true
        state = State.Pending
        qualified = null
    }

    @Synchronized
    fun snapshot(): State? {
        if (!open) return null
        refresh()
        return state
    }

    /** App-looper publication acknowledges pending before a qualified replacement can be ready. */
    @Synchronized
    fun publication(): State? {
        val result = snapshot() ?: return null
        if (result == State.Pending && pendingBarrier) {
            pendingBarrier = false
            qualified?.let { state = it }
        }
        return result
    }

    @Synchronized
    fun retire() {
        open = false
        binding = null
        qualified = null
        periodUid = null
    }

    private fun current(value: Binding?) =
        open && value != null && value === binding && state !is State.Unavailable

    private fun unavailable(reason: Reason) {
        if (open && state !is State.Unavailable) {
            state = State.Unavailable(reason)
            binding = null
            qualified = null
        }
    }

    private fun requalify(value: Binding) {
        value.previousA = lastAcceptedA
        value.qualifiedA = null
        value.videoSeen = false
        value.previousVideoUs = null
        value.observedSpacingUs = null
        qualified = null
        state = State.Pending
        pendingBarrier = true
    }

    private fun refresh() {
        if (!open || state is State.Unavailable || !supported) return
        val active = binding ?: return
        val offset = active.adjuster.timestampOffsetUs
        if (offset == Long.MIN_VALUE) { unavailable(Reason.INVALID_TIMESTAMP); return }
        if (offset == C.TIME_UNSET) {
            if (active.qualifiedA != null) requalify(active)
            return
        }
        if (active.qualifiedA != null && active.qualifiedA != offset) requalify(active)
        if (!active.videoSeen || !scopeReady) return
        active.qualifiedA = offset
        lastAcceptedA = offset
        val frameUs = active.frameDurationUs ?: active.observedSpacingUs?.toDouble()
        val previous = active.previousA
        if (previous != null && frameUs != null && exceedsFrame(offset, previous, frameUs)) rebased = true
        val ready = State.Ready(offset, rebased)
        if (pendingBarrier) qualified = ready else state = ready
    }

    private fun exceedsFrame(value: Long, previous: Long, frameUs: Double): Boolean {
        val delta = try { Math.subtractExact(value, previous) }
            catch (_: ArithmeticException) { return true }
        return delta == Long.MIN_VALUE || kotlin.math.abs(delta).toDouble() > frameUs
    }

    companion object {
        fun wire(value: State): Map<String, Any> = when (value) {
            State.Pending -> mapOf("state" to "pending")
            is State.Ready -> mapOf("state" to "ready", "adjustmentUs" to value.adjustmentUs) +
                if (value.rebased) mapOf("diagnosticCode" to "clock_rebased") else emptyMap()
            is State.Unavailable -> mapOf("state" to "unavailable", "reason" to value.reason.wire,
                "diagnosticCode" to "clock_unavailable")
        }
    }
}
