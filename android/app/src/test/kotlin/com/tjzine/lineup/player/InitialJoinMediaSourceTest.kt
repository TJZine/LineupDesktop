package com.tjzine.lineup.player

import androidx.media3.common.MediaItem
import androidx.media3.exoplayer.SeekParameters
import androidx.media3.exoplayer.source.MediaPeriod
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.SampleStream
import androidx.media3.exoplayer.trackselection.ExoTrackSelection
import androidx.media3.exoplayer.upstream.Allocator
import androidx.media3.exoplayer.upstream.DefaultAllocator
import java.lang.reflect.Proxy
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
class InitialJoinMediaSourceTest {
    private inline fun <reified T> unused(): T = Proxy.newProxyInstance(
        T::class.java.classLoader, arrayOf(T::class.java),
    ) { _, method, _ -> error("Unexpected ${method.name}") } as T

    private inner class Fixture(val previousUs: Long, val nextUs: Long) {
        val adjustments = mutableListOf<SeekParameters>()
        val selections = mutableListOf<Long>()
        var callback: MediaPeriod.Callback? = null
        var released: MediaPeriod? = null
        var preparedUs: Long? = null
        var explicitUs: Long? = null
        val period = object : MediaPeriod by unused<MediaPeriod>() {
            override fun prepare(callback: MediaPeriod.Callback, positionUs: Long) {
                this@Fixture.callback = callback
                preparedUs = positionUs
            }

            override fun getAdjustedSeekPositionUs(positionUs: Long, parameters: SeekParameters): Long {
                adjustments += parameters
                return parameters.resolveSeekPositionUs(positionUs, previousUs, nextUs)
            }

            override fun selectTracks(
                selections: Array<out ExoTrackSelection?>,
                mayRetainStreamFlags: BooleanArray,
                streams: Array<SampleStream?>,
                streamResetFlags: BooleanArray,
                positionUs: Long,
            ): Long {
                this@Fixture.selections += positionUs
                return positionUs
            }

            override fun seekToUs(positionUs: Long): Long {
                explicitUs = positionUs
                return positionUs
            }
        }
        val source = InitialJoinMediaSource(object : MediaSource by unused<MediaSource>() {
            override fun getMediaItem() = MediaItem.EMPTY
            override fun createPeriod(id: MediaSource.MediaPeriodId, allocator: Allocator, startPositionUs: Long) = period
            override fun releasePeriod(mediaPeriod: MediaPeriod) { released = mediaPeriod }
        })

        fun create() = source.createPeriod(MediaSource.MediaPeriodId(Any()), DefaultAllocator(false, 1024), 10_000_000)
        fun select(period: MediaPeriod, positionUs: Long) = period.selectTracks(
            emptyArray(), booleanArrayOf(), emptyArray(), booleanArrayOf(), positionUs,
        )
    }

    @Test
    fun initialJoinSelectsOnlyKeyframesWithinThreeSecondsBeforeTarget() {
        for ((previous, expected) in listOf(
            9_000_000L to 9_000_000L,
            7_000_000L to 7_000_000L,
            6_999_999L to 10_000_000L,
        )) {
            val f = Fixture(previous, 10_100_000)
            assertEquals(expected, f.select(f.create(), 10_000_000))
            assertEquals(expected, f.selections.single())
            if (expected != 10_000_000L) {
                assertEquals(SeekParameters(3_000_000, 0), f.adjustments.last())
            }
        }
        val zero = Fixture(0, 4_000_000)
        assertEquals(0, zero.select(zero.create(), 0))
        assertTrue(zero.adjustments.isEmpty())
        val nearStart = Fixture(0, 4_000_000)
        assertEquals(0, nearStart.select(nearStart.create(), 2_000_000))
    }

    @Test
    fun reselectionAndRecreatedPeriodsDoNotRelaxSubsequentPositions() {
        val f = Fixture(8_000_000, 12_000_000)
        val period = f.create()
        assertEquals(8_000_000, f.select(period, 10_000_000))
        f.adjustments.clear()
        assertEquals(10_000_000, f.select(period, 10_000_000))
        assertEquals(10_000_000, f.select(f.create(), 10_000_000))
        assertTrue(f.adjustments.isEmpty())
        assertEquals(11_000_000, period.seekToUs(11_000_000))
        assertEquals(11_000_000L, f.explicitUs)
        assertEquals(10_000_000, period.getAdjustedSeekPositionUs(10_000_000, SeekParameters.EXACT))
        assertEquals(SeekParameters.EXACT, f.adjustments.last())
        assertEquals(8_000_000, period.getAdjustedSeekPositionUs(10_000_000, SeekParameters.PREVIOUS_SYNC))
    }

    @Test
    fun explicitSeekBeforePreparationPreservesItsTargetIncludingOriginalJoinPosition() {
        for (targetUs in listOf(10_000_000L, 11_000_000L)) {
            val f = Fixture(8_000_000, 12_000_000)
            val period = f.create()
            var prepared = false
            period.prepare(object : MediaPeriod.Callback {
                override fun onPrepared(mediaPeriod: MediaPeriod) { prepared = true }
                override fun onContinueLoadingRequested(source: MediaPeriod) {}
            }, 10_000_000)
            f.source.cancelInitialJoin()
            f.callback!!.onPrepared(f.period)
            assertTrue(prepared)
            assertEquals(targetUs, f.select(period, targetUs))
            assertTrue(f.adjustments.isEmpty())
        }
    }

    @Test
    fun callbacksIdentifyWrapperAndReleaseReturnsOriginalPeriod() {
        val f = Fixture(8_000_000, 12_000_000)
        val wrapped = f.create()
        var prepared: MediaPeriod? = null
        var loading: MediaPeriod? = null
        wrapped.prepare(object : MediaPeriod.Callback {
            override fun onPrepared(mediaPeriod: MediaPeriod) { prepared = mediaPeriod }
            override fun onContinueLoadingRequested(source: MediaPeriod) { loading = source }
        }, 10_000_000)
        f.callback!!.onPrepared(f.period)
        f.callback!!.onContinueLoadingRequested(f.period)
        assertSame(wrapped, prepared)
        assertSame(wrapped, loading)
        assertEquals(10_000_000L, f.preparedUs)
        f.source.releasePeriod(wrapped)
        assertSame(f.period, f.released)
    }
}
