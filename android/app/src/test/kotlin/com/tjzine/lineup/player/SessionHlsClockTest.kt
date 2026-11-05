package com.tjzine.lineup.player

import android.net.Uri
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.Timeline
import androidx.media3.common.util.TimestampAdjuster
import androidx.media3.exoplayer.hls.playlist.HlsMediaPlaylist
import androidx.media3.exoplayer.hls.playlist.HlsPlaylistParser
import androidx.media3.exoplayer.source.SinglePeriodTimeline
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

internal fun clockPlaylist(extra: String = "", map: Boolean = true): HlsMediaPlaylist {
    val text = """#EXTM3U
#EXT-X-VERSION:7
#EXT-X-PLAYLIST-TYPE:VOD
#EXT-X-TARGETDURATION:10
#EXT-X-MEDIA-SEQUENCE:0
${if (map) "#EXT-X-MAP:URI=\"init.mp4\"" else ""}
#EXTINF:10,
0.m4s
$extra
#EXTINF:10,
1.m4s
#EXT-X-ENDLIST
"""
    return HlsPlaylistParser().parse(Uri.parse("https://fixture.invalid/session/index.m3u8"), text.byteInputStream()) as HlsMediaPlaylist
}

internal fun clockTimeline(uid: Any = "period", periodOrigin: Long = 0,
    windowOrigin: Long = 0, periods: Int = 1, windows: Int = 1): Timeline {
    val base = SinglePeriodTimeline(20_000_000, true, false, false, null, MediaItem.EMPTY)
    return object : Timeline() {
        override fun getWindowCount() = windows
        override fun getPeriodCount() = periods
        override fun getWindow(index: Int, window: Window, projectionUs: Long): Window =
            base.getWindow(0, window, projectionUs).also { it.positionInFirstPeriodUs = windowOrigin }
        override fun getPeriod(index: Int, period: Period, ids: Boolean): Period =
            base.getPeriod(0, period, ids).also { it.uid = uid; it.positionInWindowUs = periodOrigin }
        override fun getUidOfPeriod(index: Int) = uid
        override fun getIndexOfPeriod(value: Any) = if (value == uid) 0 else C.INDEX_UNSET
    }
}

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
class SessionHlsClockTest {
    private fun initialized(firstUs: Long = 10_500_000) = TimestampAdjuster(0).also { it.adjustSampleTimestamp(firstUs) }
    private fun ready(clock: SessionHlsClock, adjuster: TimestampAdjuster) {
        clock.bind(adjuster, true)
        clock.scope(clockTimeline(), 0, clockPlaylist())
        clock.videoSample(adjuster, 0)
    }
    private fun reason(clock: SessionHlsClock) = (clock.snapshot() as SessionHlsClock.State.Unavailable).reason

    @Test fun pendingRequiresVideoInitializedAdjustmentAndScope() {
        val clock = SessionHlsClock()
        val adjuster = TimestampAdjuster(0)
        clock.bind(adjuster, true)
        clock.scope(clockTimeline(), 0, clockPlaylist())
        assertEquals(SessionHlsClock.State.Pending, clock.snapshot())
        clock.videoSample(adjuster, 0)
        assertEquals(SessionHlsClock.State.Pending, clock.snapshot())
        adjuster.adjustSampleTimestamp(10_500_000)
        assertEquals(SessionHlsClock.State.Pending, clock.snapshot())
        clock.videoSample(adjuster, 0)
        assertEquals(SessionHlsClock.State.Ready(-10_500_000), clock.snapshot())
        assertNotEquals(10_500_000L, (clock.snapshot() as SessionHlsClock.State.Ready).adjustmentUs)
    }

    @Test fun initializedZeroIsReadyAndInitOrAudioAloneDoesNotQualify() {
        val clock = SessionHlsClock()
        val adjuster = TimestampAdjuster(TimestampAdjuster.MODE_NO_OFFSET)
        clock.bind(adjuster, true)
        clock.scope(clockTimeline(), 0, clockPlaylist())
        assertEquals(SessionHlsClock.State.Pending, clock.snapshot())
        clock.videoSample(adjuster, 10_500_000)
        assertEquals(SessionHlsClock.State.Ready(0), clock.snapshot())
        assertEquals(mapOf("state" to "ready", "adjustmentUs" to 0L), SessionHlsClock.wire(clock.snapshot()!!))
    }

    @Test fun sampleCanPrecedeManifestAndInitialEmptyTimelineStaysPending() {
        val clock = SessionHlsClock(); val adjuster = initialized()
        clock.bind(adjuster, true); clock.videoSample(adjuster, 0)
        clock.scope(Timeline.EMPTY, 0, null)
        assertEquals(SessionHlsClock.State.Pending, clock.snapshot())
        clock.scope(clockTimeline(), 0, clockPlaylist())
        assertEquals(SessionHlsClock.State.Ready(-10_500_000), clock.snapshot())
    }

    @Test fun resetOrChangedSameAdjusterNeedsNewInitializedVideoAndPendingPublication() {
        for (newRawUs in listOf(10_500_000L, 20_000_000L)) {
            val clock = SessionHlsClock(); val adjuster = initialized(); ready(clock, adjuster)
            clock.seeking(); adjuster.reset(0)
            assertEquals(SessionHlsClock.State.Pending, clock.snapshot())
            adjuster.adjustSampleTimestamp(newRawUs)
            assertEquals(SessionHlsClock.State.Pending, clock.snapshot())
            clock.videoSample(adjuster, 0)
            assertEquals(SessionHlsClock.State.Pending, clock.snapshot())
            assertEquals(SessionHlsClock.State.Pending, clock.publication())
            assertEquals(SessionHlsClock.State.Ready(-newRawUs), clock.publication())
        }
    }

    @Test fun samePeriodSeekAndRepeatedCallbacksKeepTheOneBasis() {
        val clock = SessionHlsClock(); val adjuster = initialized(); ready(clock, adjuster)
        repeat(4) {
            clock.scope(clockTimeline(), 0, clockPlaylist())
            clock.bind(adjuster, true)
            clock.videoSample(adjuster, 17_000_000)
            assertEquals(SessionHlsClock.State.Ready(-10_500_000), clock.snapshot())
        }
    }

    @Test fun anUnpermittedSecondAdjusterIsAmbiguousEvenWhenItsValueMatches() {
        val clock = SessionHlsClock(); ready(clock, initialized())
        clock.bind(initialized(), true)
        assertEquals(SessionHlsClock.Reason.AMBIGUOUS_ADJUSTER, reason(clock))
    }

    @Test fun periodUidCountOriginAndCurrentPeriodAreFenced() {
        for ((timeline,index) in listOf(clockTimeline(uid = "other") to 0,
            clockTimeline(periodOrigin = 1) to 0, clockTimeline(windowOrigin = 1) to 0,
            clockTimeline(periods = 2) to 0, clockTimeline(windows = 2) to 0, clockTimeline() to 1)) {
            val clock = SessionHlsClock(); ready(clock, initialized())
            clock.scope(timeline, index, clockPlaylist())
            assertEquals(SessionHlsClock.Reason.PERIOD_MISMATCH, reason(clock))
        }
    }

    @Test fun hlsDiscontinuityIsTerminalWhileMissingMapRemainsUnqualified() {
        val clock = SessionHlsClock(); ready(clock, initialized())
        clock.scope(clockTimeline(), 0, clockPlaylist("#EXT-X-DISCONTINUITY"))
        assertEquals(SessionHlsClock.Reason.DISCONTINUITY, reason(clock))
        val noMap = SessionHlsClock(); noMap.bind(initialized(), true)
        noMap.scope(clockTimeline(), 0, clockPlaylist(map = false))
        assertEquals(SessionHlsClock.State.Pending, noMap.snapshot())
    }

    @Test fun unsupportedContainerAndNoVideoNeverQualifyAnAdjustment() {
        val clock = SessionHlsClock(); val adjuster = initialized()
        clock.bind(adjuster, false)
        ready(clock, adjuster)
        assertEquals(SessionHlsClock.State.Pending, clock.snapshot())
        val audio = SessionHlsClock(); audio.bind(adjuster, true); audio.unsupportedScope()
        ready(audio, adjuster)
        assertEquals(SessionHlsClock.State.Pending, audio.snapshot())
    }

    @Test fun invalidSampleAndRecoveryOverflowNeverPublishReady() {
        for (sample in listOf(C.TIME_UNSET, Long.MIN_VALUE, Long.MAX_VALUE)) {
            val clock = SessionHlsClock(); val adjuster = initialized()
            clock.bind(adjuster, true); clock.scope(clockTimeline(), 0, clockPlaylist())
            clock.videoSample(adjuster, sample)
            assertEquals(SessionHlsClock.Reason.INVALID_TIMESTAMP, reason(clock))
        }
        for (value in listOf(C.TIME_UNSET, Long.MIN_VALUE)) {
            try { SessionHlsClock.State.Ready(value); fail("uninitialized values cannot be represented as ready") }
            catch (_: IllegalArgumentException) { }
        }
    }

    @Test fun alternateRenditionsOrVariantsAreUnsupportedClockScope() {
        for (text in listOf("""#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=1000
one.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2000
two.m3u8
""", """#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="Audio",URI="audio.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=1000,AUDIO="audio"
one.m3u8
""")) {
            val master = HlsPlaylistParser().parse(Uri.parse("https://fixture.invalid/master.m3u8"), text.byteInputStream())
                as androidx.media3.exoplayer.hls.playlist.HlsMultivariantPlaylist
            val clock = SessionHlsClock(); ready(clock, initialized()); clock.renditions(master)
            assertEquals(SessionHlsClock.State.Pending, clock.snapshot())
        }
    }

    @Test fun aLaterOverflowRevokesAnAlreadyReadyClock() {
        val clock = SessionHlsClock(); val adjuster = initialized(); ready(clock, adjuster)
        clock.videoSample(adjuster, Long.MAX_VALUE)
        assertEquals(SessionHlsClock.Reason.INVALID_TIMESTAMP, reason(clock))
    }

    @Test fun permittedReplacementIgnoresLateRetiredSamplesButConcurrentReadIsAmbiguous() {
        val clock = SessionHlsClock(); val first = initialized()
        val old = clock.bind(first, true)!!
        clock.scope(clockTimeline(), 0, clockPlaylist()); clock.videoSample(old, 0)
        clock.seeking()
        val fresh = initialized(); val next = clock.bind(fresh, true)!!
        clock.videoSample(old, Long.MAX_VALUE) // Retired: cannot invalidate the replacement.
        assertEquals(SessionHlsClock.State.Pending, clock.snapshot())
        clock.videoSample(next, 0); clock.publication()
        assertEquals(SessionHlsClock.State.Ready(-10_500_000), clock.publication())
        val overlap = SessionHlsClock(); val active = overlap.bind(first, true)!!
        overlap.beginRead(active); overlap.seeking(); overlap.bind(fresh, true)
        overlap.endRead(active)
        assertEquals(SessionHlsClock.Reason.AMBIGUOUS_ADJUSTER, reason(overlap))
    }

    @Test fun rebasedDiagnosticUsesFormatOrObservedVideoSpacingAndNeverGuessesFps() {
        for (knownRate in listOf(true, false)) {
            val clock = SessionHlsClock(); val first = initialized(); ready(clock, first)
            clock.seeking(); val nextAdjuster = initialized(10_650_000)
            val next = clock.bind(nextAdjuster, true)!!
            if (knownRate) clock.videoFormat(next, 10f)
            clock.videoSample(next, 0); clock.publication()
            assertEquals(SessionHlsClock.State.Ready(-10_650_000, knownRate), clock.publication())
            if (!knownRate) {
                clock.videoSample(next, 100_000)
                assertEquals(SessionHlsClock.State.Ready(-10_650_000, true), clock.publication())
            }
            assertEquals("clock_rebased", SessionHlsClock.wire(clock.snapshot()!!)["diagnosticCode"])
        }
    }

    @Test fun exactlyOneFrameDoesNotClassifyAsRebasedAndBufferedSeekKeepsBasis() {
        val clock = SessionHlsClock(); val first = initialized(); ready(clock, first)
        clock.seeking()
        assertEquals(SessionHlsClock.State.Ready(-10_500_000), clock.publication())
        val next = clock.bind(initialized(10_600_000), true)!!
        clock.videoFormat(next, 10f); clock.videoSample(next, 0); clock.publication()
        assertEquals(SessionHlsClock.State.Ready(-10_600_000), clock.publication())
    }

    @Test fun queuedPublicationReadsCurrentStateAndRetirementRejectsLateSamples() {
        val clock = SessionHlsClock(); val adjuster = initialized(); ready(clock, adjuster)
        val delivered = mutableListOf<SessionHlsClock.State>()
        val queued = { clock.snapshot()?.let { delivered += it } }
        clock.scope(clockTimeline(uid = "replacement"), 0, clockPlaylist()); queued(); queued()
        assertTrue(delivered.all { it is SessionHlsClock.State.Unavailable })
        clock.retire(); clock.bind(adjuster, true); clock.videoSample(adjuster, 0); queued()
        assertEquals(2, delivered.size); assertNull(clock.snapshot())
    }
}
