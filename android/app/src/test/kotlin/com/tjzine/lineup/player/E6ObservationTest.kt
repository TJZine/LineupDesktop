package com.tjzine.lineup.player

import android.os.Handler
import android.os.Looper
import androidx.media3.common.C
import androidx.media3.common.PlaybackException
import androidx.media3.common.util.TimestampAdjuster
import java.time.Duration
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
class E6ObservationTest {
    private class Fixture(offset: Int = 0, seek: Boolean = false, baseline: Boolean = false) {
        var clock = 1_000_000_000L
        val player = E6Player()
        val observation = E6Observation(E6Config.parse(e6Input(offset, seek), baseline), Handler(Looper.getMainLooper()), 1) { clock }
        val guard = E6Http(observation)
        var cancellations = 0
        init { observation.attach(player.player, guard) { cancellations++ } }
        fun frame(c: Long = 2_000_000, o: Long = 5_000_000, a: Long? = -10_000_000, bind: Boolean = true) {
            if (a != null) {
                val adjuster = TimestampAdjuster(c)
                adjuster.adjustSampleTimestamp(c - a)
                observation.bindAdjuster(adjuster)
            }
            observation.outputChanged(o)
            observation.rendererReset()
            observation.frame(c, clock, c + o, o, 0, 0, bind)
            release(c, clock)
        }
        fun release(c: Long, time: Long) {
            val release = observation.beginRelease(c, time)
            observation.endRelease(release, true)
        }
        fun idle(ms: Long = 0) {
            clock += ms * 1_000_000
            if (ms == 0L) shadowOf(Looper.getMainLooper()).idle()
            else shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(ms))
        }
        fun finish() { repeat(40) { player.positionMs += 250; idle(250) } }
        fun events(): List<Map<*, *>> = observation.drain()["events"] as List<Map<*, *>>
    }

    @Test fun callbackClockDoesNotSubtractRendererOffsetTwiceInEitherDirection() {
        for ((offset, hls) in listOf(5_000_000L to -10_000_000L, -5_000_000L to 10_000_000L)) {
            val f = Fixture()
            f.observation.ready(); f.frame(o = offset, a = hls); f.observation.renderedFirstFrame(12); f.idle()
            val frame = f.events().single { it["event"] == "frame_first" }
            assertEquals(2_000_000L, frame["callbackPtsUs"])
            assertEquals(2_000_000L + offset, frame["decoderBufferUs"])
            assertEquals(2_000_000L - hls, frame["extractorPtsUs"])
            assertEquals(true, frame["rendererRelationValid"])
            assertEquals(false, frame["sourceOriginProven"])
            f.observation.cancel()
        }
    }

    @Test fun samplesRetainPositionAndFrameClocksInsteadOfReplacingPlayerPosition() {
        val f = Fixture(21)
        f.player.positionMs = 1200
        f.observation.ready(); f.frame(); f.observation.renderedFirstFrame(10); f.idle()
        val sample = f.events().single { it["event"] == "position" }
        assertEquals(1200L, sample["positionMs"])
        assertEquals(2_000_000L, sample["frameWindowUs"])
        assertEquals(800_000L, sample["frameWindowPositionDeltaUs"])
        assertEquals(12_000_000L, sample["extractorPtsUs"])
        assertEquals(10_800_000L, sample["extractorPositionDeltaUs"])
        assertEquals(2_000_000L, sample["hypothesisSourceUs"])
        assertEquals(-19_000_000L, sample["hypothesisRequestedDeltaUs"])
        assertEquals(800_000L, sample["hypothesisPositionDeltaUs"])
        f.observation.cancel()
    }

    @Test fun firstFrameBeforeReadyIsPreservedAndCollectsExactlyFortyOneSamples() {
        val f = Fixture()
        f.frame(); f.observation.renderedFirstFrame(100); f.idle()
        f.idle(10); f.observation.ready()
        val first = f.events()
        assertEquals(1, first.count { it["event"] == "frame_first" })
        assertEquals(1, first.count { it["event"] == "rendered_first_frame" })
        assertEquals(1, first.count { it["event"] == "ready" })
        val firstSample = first.single { it["event"] == "position" }
        assertEquals(0, firstSample["sampleIndex"])
        f.finish()
        val rest = f.events().filter { it["event"] == "position" }
        assertEquals((1..40).toList(), rest.map { it["sampleIndex"] })
        assertTrue(rest.all { it["snapshotLagNs"] is Long && it["frameAgeNs"] is Long })
        assertEquals("complete", f.observation.drain()["result"])
        assertFalse(f.guard.isOpen())
    }

    @Test fun readyBeforeFrameDoesNotInventAFrameAndRetainsUnknownTimeUnset() {
        val f = Fixture(); f.observation.ready()
        val ready = f.events().single { it["event"] == "ready" }
        assertNull(ready["callbackPtsUs"]); assertEquals(false, ready["clockKnown"])
        f.observation.frame(1, C.TIME_UNSET, null, C.TIME_UNSET, null, null, false)
        f.release(1, C.TIME_UNSET)
        f.observation.renderedFirstFrame(100); f.idle(); f.finish()
        assertEquals("clock_bridge_unavailable", f.observation.drain()["failureCode"])
    }

    @Test fun multipleUnmatchedAdjustersRemainUnknownAndCannotPass() {
        val f = Fixture(); f.observation.ready(); f.frame()
        val second = TimestampAdjuster(0); second.adjustSampleTimestamp(10)
        f.observation.bindAdjuster(second)
        f.observation.frame(3_000_000, f.clock, 8_000_000, 5_000_000, 0, 0, true)
        f.observation.renderedFirstFrame(1); f.idle(); f.finish()
        val end = f.observation.drain()
        assertEquals("failed", end["result"]); assertEquals("clock_bridge_unavailable", end["failureCode"])
    }

    @Test fun independentlyObservedBufferContradictionStopsImmediately() {
        val f = Fixture()
        f.observation.frame(2, f.clock, 9, 3, 0, 0, true)
        assertEquals("clock_relation_invalid", f.observation.drain()["failureCode"])
        f.idle(); assertEquals(1, f.cancellations)
    }

    @Test fun exactSeekExcludesQueuedOldFramesUntilRendererReset() {
        val f = Fixture(21, seek = true)
        f.observation.ready(); f.frame(); f.observation.renderedFirstFrame(1); f.idle()
        assertFalse(f.events().any { it["event"] == "position" })
        assertTrue(f.observation.beforeSeek(21.0, true)); f.observation.seekAck()
        // A queued old output frame still carries the reset's pre-seek epoch.
        f.observation.frame(2_100_000, f.clock, 7_100_000, 5_000_000, 0, 0, true)
        f.idle()
        assertFalse(f.events().any { it["event"] == "position" })
        f.observation.discontinuity(); f.observation.rendererReset()
        f.observation.frame(21_000_000, f.clock, 26_000_000, 5_000_000, 0, 0, true)
        f.release(21_000_000, f.clock)
        f.observation.renderedFirstFrame(2)
        f.idle()
        val landed = f.events()
        assertEquals(1, landed.count { it["event"] == "frame_first" })
        assertEquals(21_000_000L, landed.single { it["event"] == "frame_first" }["callbackPtsUs"])
        assertEquals(1L, landed.single { it["event"] == "position" }["seekEpoch"])
        f.finish()
        assertEquals("post_seek_frame_observed", f.events().single { it["event"] == "seek_result" }["seekResult"])
        assertEquals("complete", f.observation.drain()["result"])
    }

    @Test fun zeroDistanceSeekPreservesEpochAndDoesNotFabricateLandedFrame() {
        val f = Fixture(seek = true)
        f.observation.ready(); f.frame(); f.observation.renderedFirstFrame(1); f.idle()
        f.events()
        assertTrue(f.observation.beforeSeek(0.0, true)); f.observation.seekAck(); f.idle(); f.finish()
        val events = f.events()
        assertEquals(0, events.count { it["event"] == "renderer_reset" || it["event"] == "frame_first" })
        assertEquals("seek_no_distance_no_new_epoch", events.single { it["event"] == "seek_result" }["seekResult"])
        assertEquals(0L, events.single { it["event"] == "seek_request" }["seekEpoch"])
        assertEquals(1L, events.single { it["event"] == "seek_request" }["commandSeekEpoch"])
        assertEquals(0L, events.single { it["event"] == "seek_result" }["seekEpoch"])
        assertEquals(1L, events.single { it["event"] == "seek_result" }["commandSeekEpoch"])
        assertTrue(events.filter { it["event"] == "position" }.all { it["seekEpoch"] == 0L && it["commandSeekEpoch"] == 1L })
        assertEquals("complete", f.observation.drain()["result"])
    }

    @Test fun secondWrongTargetNonexactAndDefaultSeeksAreRejected() {
        for ((seek, seconds, exact) in listOf(Triple(false, 0.0, true), Triple(true, 9.0, true), Triple(true, 0.0, false))) {
            val f = Fixture(seek = seek); f.observation.ready()
            assertFalse(f.observation.beforeSeek(seconds, exact))
            assertEquals("seek_contract", f.observation.drain()["failureCode"])
        }
        val f = Fixture(seek = true); f.observation.ready()
        assertTrue(f.observation.beforeSeek(0.0, true)); assertFalse(f.observation.beforeSeek(0.0, true))
    }

    @Test fun startupAndFirstFrameDeadlinesAreDistinctAndBounded() {
        val f = Fixture(); f.idle(30_000)
        assertEquals("startup_deadline", f.observation.drain()["failureCode"])
        val g = Fixture(); g.observation.ready(); g.idle(15_000)
        assertEquals("first_frame_deadline", g.observation.drain()["failureCode"])
    }

    @Test fun baselineUsesOrdinaryFirstFrameAndPositionWithoutManufacturingClockBridge() {
        val f = Fixture(baseline = true); f.observation.ready(); f.observation.renderedFirstFrame(12); f.idle(); f.finish()
        val samples = f.events().filter { it["event"] == "position" }
        assertEquals(41, samples.size); assertTrue(samples.all { it["clockKnown"] == false && it["callbackPtsUs"] == null })
        assertEquals("complete", f.observation.drain()["result"])
    }

    @Test fun cancellationAndFailedReleaseRetainFactsAndDoNotBecomeSuccess() {
        val f = Fixture(); f.observation.cancel(); f.observation.release(false, true, false)
        val drain = f.observation.drain()
        assertEquals("failed", drain["result"])
        val release = (drain["events"] as List<Map<*, *>>).single { it["event"] == "release" }
        assertEquals(false, release["released"]); assertEquals(true, release["playbackThreadAlive"])
        assertEquals(false, release["networkDrained"])
    }

    @Test fun futureReleaseDoesNotReplaceTheFrameAttributedToCurrentPosition() {
        val f = Fixture(); f.observation.ready(); f.frame(); f.observation.renderedFirstFrame(1); f.idle(); f.events()
        f.observation.frame(3_000_000, f.clock + 500_000_000, 8_000_000, 5_000_000, 0, 0, true)
        f.idle(250)
        val before = f.events().single { it["event"] == "position" }
        assertEquals(2_000_000L, before["callbackPtsUs"])
        assertEquals(250_000_000L, before["frameAgeNs"])
        f.idle(250)
        val after = f.events().single { it["event"] == "position" }
        assertEquals(3_000_000L, after["callbackPtsUs"])
        assertEquals(0L, after["frameAgeNs"])
        assertEquals(500_000_000L, after["snapshotLagNs"])
        f.observation.cancel()
    }

    @Test fun delayedOldRenderSignalCannotConfirmNewSeekEpochOrChangeFirstSeriesOrigin() {
        val f = Fixture(21, seek = true); f.observation.ready(); f.frame(); f.idle(); f.events()
        assertTrue(f.observation.beforeSeek(21.0, true))
        f.observation.rendererReset()
        val firstRelease = f.clock + 10_000_000
        f.observation.frame(21_000_000, firstRelease, 26_000_000, 5_000_000, 0, 0, true)
        f.release(21_000_000, firstRelease)
        // Later metadata is not the first post-seek frame or the sampling origin.
        f.observation.frame(21_040_000, firstRelease + 40_000_000, 26_040_000, 5_000_000, 0, 0, true)
        f.observation.renderedFirstFrame(1) // Delayed initial signal.
        f.idle(20)
        assertFalse(f.events().any { it["event"] == "position" })
        f.observation.renderedFirstFrame(2) // Matching post-seek signal.
        f.idle()
        val started = f.events()
        val sample = started.single { it["event"] == "position" }
        assertEquals(firstRelease, sample["sampleDueNs"])
        assertEquals(21_000_000L, sample["callbackPtsUs"])
        assertEquals(true, sample["renderedAssociated"])
        f.observation.cancel()
    }

    @Test fun newlyConstructedExtractorUsesItsMatchedAdjustmentAfterSeek() {
        val f = Fixture(21, seek = true); f.observation.ready(); f.frame(); f.observation.renderedFirstFrame(1); f.idle(); f.events()
        assertTrue(f.observation.beforeSeek(21.0, true))
        f.observation.rendererReset(true)
        val newAdjuster = TimestampAdjuster(21_000_000)
        newAdjuster.adjustSampleTimestamp(12_000_000)
        f.observation.bindAdjuster(newAdjuster, 1)
        f.observation.frame(21_000_000, f.clock, 26_000_000, 5_000_000, 0, 0, true)
        f.release(21_000_000, f.clock); f.observation.renderedFirstFrame(2); f.idle()
        val first = f.events().single { it["event"] == "frame_first" }
        assertEquals(9_000_000L, first["hlsOffsetUs"]); assertEquals(12_000_000L, first["extractorPtsUs"])
        f.observation.cancel()
    }

    @Test fun absoluteActiveDeadlineCannotBeExtendedByConfigureLoadOrSeek() {
        var now = 1_000_000_000L
        val observation = E6Observation(E6Config.parse(e6Input(), false), Handler(Looper.getMainLooper()), 1,
            now + 1000) { now }
        observation.requireActive()
        now += 1000
        try { observation.requireActive(); fail("absolute boundary") } catch (error: E6Failure) { assertEquals("active_deadline", error.code) }
        assertEquals("active_deadline", observation.drain()["failureCode"])
    }

    @Test fun nonzeroPeriodWindowMappingUsesItsSignedOffsetAndKeepsPlayerPosition() {
        val f = Fixture()
        f.player.timeline = androidx.media3.exoplayer.source.SinglePeriodTimeline(
            C.TIME_UNSET, C.TIME_UNSET, C.TIME_UNSET, 45_000_000L, 40_000_000L, 5_000_000L, 0L,
            true, false, true, null, androidx.media3.common.MediaItem.EMPTY, null)
        f.player.positionMs = 2000
        val adjuster = TimestampAdjuster(7_000_000); adjuster.adjustSampleTimestamp(17_000_000)
        f.observation.bindAdjuster(adjuster); f.observation.outputChanged(5_000_000); f.observation.rendererReset()
        f.observation.ready()
        f.observation.frame(7_000_000, f.clock, 12_000_000, 5_000_000, 0, -5_000_000, true)
        f.release(7_000_000, f.clock); f.observation.renderedFirstFrame(1); f.idle()
        val sample = f.events().single { it["event"] == "position" }
        assertEquals(-5_000_000L, sample["periodPositionInWindowUs"])
        assertEquals(7_000_000L, sample["periodPositionUs"])
        assertEquals(2_000_000L, sample["frameWindowUs"])
        assertEquals(0L, sample["frameWindowPositionDeltaUs"])
        assertEquals(2000L, sample["positionMs"])
        f.observation.cancel()
    }

    @Test fun bufferedKeyframeSeekRetainsTheActualExistingExtractorAdjustment() {
        val f = Fixture(21, seek = true); f.observation.ready(); f.frame(); f.observation.renderedFirstFrame(1); f.idle(); f.events()
        assertTrue(f.observation.beforeSeek(21.0, true))
        // This flag guarantees a keyframe reset, not a new HLS provider/extractor.
        f.observation.rendererReset(true)
        f.observation.frame(21_000_000, f.clock, 26_000_000, 5_000_000, 0, 0, true)
        f.release(21_000_000, f.clock); f.observation.renderedFirstFrame(2); f.idle()
        val first = f.events().single { it["event"] == "frame_first" }
        assertEquals(-10_000_000L, first["hlsOffsetUs"])
        assertEquals(31_000_000L, first["extractorPtsUs"])
        assertEquals(true, first["clockKnown"])
        f.finish()
        assertEquals("complete", f.observation.drain()["result"])
    }

    @Test fun onlyExplicitTypedHevcDecoderRejectionEmitsUnsupportedQualificationFact() {
        fun renderer(code: Int, mime: String) = androidx.media3.exoplayer.ExoPlaybackException.createForRenderer(
            IllegalStateException("PRIVATE_DIAGNOSTIC"), "PRIVATE_RENDERER", 0,
            androidx.media3.common.Format.Builder().setSampleMimeType(mime).build(), C.FORMAT_UNSUPPORTED_TYPE, false, code)
        val positives = listOf(PlaybackException.ERROR_CODE_DECODER_INIT_FAILED,
            PlaybackException.ERROR_CODE_DECODING_FORMAT_UNSUPPORTED, PlaybackException.ERROR_CODE_DECODING_FORMAT_EXCEEDS_CAPABILITIES)
        for (code in positives) {
            val observer = e6Observer(e6Input() + ("expectedVideoCodec" to "hevc"))
            val error = renderer(code, "video/hevc")
            observer.playerFailure(error, Media3Failure.classify(error).first)
            val drain = observer.drain()
            val facts = drain["events"] as List<Map<*, *>>
            assertEquals(1, facts.count { it["videoCodec"] == "hevc" && it["decoderSupport"] == "unsupported" })
            assertEquals("video_decode_error", drain["failureCode"])
            assertFalse(facts.toString().contains("PRIVATE"))
        }
        val negatives = listOf(renderer(PlaybackException.ERROR_CODE_DECODER_INIT_FAILED, "audio/mp4a-latm"),
            renderer(PlaybackException.ERROR_CODE_DECODER_INIT_FAILED, "video/avc"),
            renderer(PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT, "video/hevc"),
            renderer(PlaybackException.ERROR_CODE_DECODING_FAILED, "video/hevc"),
            renderer(PlaybackException.ERROR_CODE_DECODER_QUERY_FAILED, "video/hevc"),
            PlaybackException("PRIVATE", null, PlaybackException.ERROR_CODE_DECODER_INIT_FAILED))
        for (error in negatives) {
            val observer = e6Observer(e6Input() + ("expectedVideoCodec" to "hevc"))
            observer.playerFailure(error, Media3Failure.classify(error).first)
            assertFalse((observer.drain()["events"] as List<Map<*, *>>).any {
                it["videoCodec"] == "hevc" && it["decoderSupport"] == "unsupported" })
        }
    }
}
