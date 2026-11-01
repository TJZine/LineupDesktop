package com.tjzine.lineup.player

import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.SeekParameters
import androidx.media3.exoplayer.source.MediaPeriod
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.SampleStream
import androidx.media3.exoplayer.source.WrappingMediaSource
import androidx.media3.exoplayer.trackselection.ExoTrackSelection
import androidx.media3.exoplayer.upstream.Allocator
import java.util.concurrent.atomic.AtomicBoolean

/** Applies the scheduled join tolerance once, without relaxing later user seeks. */
@UnstableApi
internal class InitialJoinMediaSource(source: MediaSource) : WrappingMediaSource(source) {
    private val initialSeekParameters = SeekParameters(5_000_000, 0)
    private val initialSelection = AtomicBoolean(true)

    // Explicit seeks may arrive on the application looper before the playback
    // thread has selected tracks. Such a target must not inherit the join policy.
    fun cancelInitialJoin() { initialSelection.set(false) }

    override fun createPeriod(
        id: MediaSource.MediaPeriodId,
        allocator: Allocator,
        startPositionUs: Long,
    ): MediaPeriod = InitialJoinPeriod(mediaSource.createPeriod(id, allocator, startPositionUs))

    override fun releasePeriod(mediaPeriod: MediaPeriod) {
        mediaSource.releasePeriod((mediaPeriod as InitialJoinPeriod).delegate)
    }

    private inner class InitialJoinPeriod(val delegate: MediaPeriod) : MediaPeriod by delegate {
        override fun prepare(callback: MediaPeriod.Callback, positionUs: Long) {
            delegate.prepare(object : MediaPeriod.Callback {
                override fun onPrepared(mediaPeriod: MediaPeriod) {
                    callback.onPrepared(this@InitialJoinPeriod)
                }

                override fun onContinueLoadingRequested(source: MediaPeriod) {
                    callback.onContinueLoadingRequested(this@InitialJoinPeriod)
                }
            }, positionUs)
        }

        override fun selectTracks(
            selections: Array<out ExoTrackSelection?>,
            mayRetainStreamFlags: BooleanArray,
            streams: Array<SampleStream?>,
            streamResetFlags: BooleanArray,
            positionUs: Long,
        ): Long {
            var joinUs = positionUs
            if (initialSelection.getAndSet(false) && positionUs > 0) {
                // Media3 1.11 initial selection bypasses the player's seek parameters.
                // Its bounded resolver falls back to target - tolerance when no sync
                // fits. PD-1 instead preserves the exact target in that case.
                val previousUs = delegate.getAdjustedSeekPositionUs(positionUs, SeekParameters.PREVIOUS_SYNC)
                if (previousUs in maxOf(0L, positionUs - initialSeekParameters.toleranceBeforeUs)..positionUs) {
                    joinUs = delegate.getAdjustedSeekPositionUs(positionUs, initialSeekParameters)
                }
            }
            return delegate.selectTracks(selections, mayRetainStreamFlags, streams, streamResetFlags, joinUs)
        }
    }
}
