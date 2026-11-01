package com.tjzine.lineup.player

import android.os.Handler
import android.os.Looper
import androidx.media3.common.MediaItem
import androidx.media3.common.util.TimestampAdjuster
import androidx.media3.exoplayer.source.SinglePeriodTimeline
import java.time.Duration
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

/** Offline-only correction proposal; no production positioning policy. */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
class E6CorrectedSeekTest {
    private class Fixture(val x: Int = 21, deadlineNs: Long = Long.MAX_VALUE, durationMs: Long = 40_000) {
        var clock = 1_000_000_000L
        val input = e6Input(x, true) + mapOf("mode" to "corrected_copy_seek", "sourceDurationMs" to durationMs,
            "expectedDurationsSeconds" to List((durationMs / 10000).toInt()) { 10 })
        val player = E6Player().apply {
            positionMs = 20_000; this.durationMs = durationMs
            timeline = SinglePeriodTimeline(durationMs * 1000, true, false, false, null, MediaItem.fromUri(android.net.Uri.EMPTY))
        }
        val observation = E6Observation(E6Config.parse(input, false), Handler(Looper.getMainLooper()), 1, deadlineNs) { clock }
        val guard = E6Http(observation)
        var cancellations = 0
        init { observation.attach(player.player, guard) { cancellations++ } }
        fun setupOutput() { observation.outputChanged(5_000_000); observation.rendererReset() }
        fun adjuster(a: Long, c: Long = 20_000_000, epoch: Long = 0): TimestampAdjuster =
            TimestampAdjuster(c).also { it.adjustSampleTimestamp(c - a); observation.bindAdjuster(it, epoch) }
        fun frame(c: Long = 20_000_000, firstRender: Boolean = true, binding: Boolean = true, buffer: Boolean = true) {
            observation.frame(c, clock, if (buffer) c + 5_000_000 else null, 5_000_000, 0, 0, binding)
            if (firstRender) {
                val candidate = observation.beginRelease(c, clock)
                observation.endRelease(candidate, true)
                observation.renderedFirstFrame(1)
            }
            idle()
        }
        fun idle(ms: Long = 0) {
            clock += ms * 1_000_000
            if (ms == 0L) shadowOf(Looper.getMainLooper()).idle()
            else shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(ms))
        }
        fun qualified(a: Long = -2_000_000, c: Long = 20_000_000) {
            setupOutput(); adjuster(a, c); observation.ready(); frame(c)
        }
        fun finish() { repeat(40) { player.positionMs += 250; idle(250) } }
        @Suppress("UNCHECKED_CAST") fun events(): List<Map<String, Any?>> = observation.drain()["events"] as List<Map<String, Any?>>
    }

    @Test fun newModePreservesPmsOffsetAndRejectsBaselineOrUnqualifiedCodec() {
        val input = e6Input(21, true) + ("mode" to "corrected_copy_seek")
        val config = E6Config.parse(input, false)
        assertEquals(21_000_000L, config.offsetUs)
        assertTrue(config.seek); assertTrue(config.correctedCopySeek); assertEquals("corrected_copy_seek", config.mode)
        assertEquals(5, config.playlist(e6Playlist(21).toByteArray()).size)
        for ((candidate, baseline) in listOf(input to true, (input + ("expectedVideoCodec" to "hevc")) to false)) {
            try { E6Config.parse(candidate, baseline); fail("must reject") } catch (_: E6Failure) { }
        }
    }

    @Test fun signedA0ProducesOneQuantizedProposalAndCommandFactsUseIt() {
        for (a0 in listOf(-2_053_708L, 3_123_456L)) {
            val f = Fixture(); f.qualified(a0)
            val proposal = f.events().single { it["event"] == "seek_ready" }
            val target = (21_000_000L + a0 + 10_000_000L) / 1000 * 1000
            assertEquals(a0, proposal["hlsOffsetUs"]); assertEquals(target, proposal["seekTargetUs"])
            assertEquals(target, proposal["seekEffectiveTargetUs"])
            assertEquals(21_000_000L, proposal["requestedOffsetUs"])
            for (key in listOf("clockKnown", "bindingKnown", "renderedAssociated", "rendererRelationValid", "hlsOffsetInitialized"))
                assertEquals(key, true, proposal[key])
            assertTrue(E6Facts.valid(proposal))
            assertTrue(f.observation.beforeSeek(target / 1_000_000.0, true))
            f.observation.seekAck(); f.observation.discontinuity()
            val commands = f.events().filter { it["event"] in listOf("seek_request", "seek_ack", "seek_discontinuity") }
            assertEquals(3, commands.size); assertTrue(commands.all { it["seekTargetUs"] == target && it["seekEffectiveTargetUs"] == target })
            f.observation.cancel()
        }
    }

    @Test fun frameBeforeReadyAndDelayedAdjusterCannotProposePrematurely() {
        val f = Fixture(); f.setupOutput()
        val delayed = TimestampAdjuster(20_000_000)
        f.observation.bindAdjuster(delayed); f.frame()
        assertFalse(f.events().any { it["event"] == "seek_ready" })
        f.observation.ready(); f.idle(100)
        assertFalse(f.events().any { it["event"] == "seek_ready" })
        delayed.adjustSampleTimestamp(22_000_000)
        f.idle(100)
        assertFalse(f.events().any { it["event"] == "seek_ready" })
        f.frame(20_040_000, firstRender = false)
        val proposal = f.events().single { it["event"] == "seek_ready" }
        assertEquals(-2_000_000L, proposal["hlsOffsetUs"]); assertEquals(29_000_000L, proposal["seekTargetUs"])
        f.observation.cancel()
    }

    @Test fun readyAlwaysPrecedesProposalWithAnAlreadyRenderedFrame() {
        val f = Fixture(); f.setupOutput(); f.adjuster(-2_000_000); f.frame()
        f.events(); f.observation.ready()
        assertEquals(listOf("ready", "seek_ready"), f.events().map { it["event"] })
        f.observation.cancel()
    }

    @Test fun missingAmbiguousOrDeadlineClocksFailWithoutFallback() {
        val missing = Fixture(); missing.setupOutput()
        missing.observation.bindAdjuster(TimestampAdjuster(20_000_000))
        missing.observation.ready(); missing.frame(); missing.events(); missing.idle(15_000)
        assertEquals("first_frame_deadline", missing.observation.drain()["failureCode"])
        val ambiguous = Fixture(); ambiguous.setupOutput(); ambiguous.adjuster(-2_000_000); ambiguous.adjuster(-3_000_000)
        ambiguous.observation.ready(); ambiguous.frame()
        assertEquals("clock_bridge_unavailable", ambiguous.observation.drain()["failureCode"])
        val deadline = Fixture(deadlineNs = 2_000_000_000L)
        deadline.qualified(); deadline.events(); deadline.clock = 2_000_000_000L
        assertFalse(deadline.observation.beforeSeek(29.0, true))
        assertEquals("active_deadline", deadline.observation.drain()["failureCode"])
    }

    @Test fun invalidBindingOrMissingIndependentBufferCannotPropose() {
        for (binding in listOf(false, true)) {
            val f = Fixture(); f.setupOutput(); f.adjuster(-2_000_000); f.observation.ready()
            f.frame(binding = binding, buffer = false)
            assertFalse(f.events().any { it["event"] == "seek_ready" })
            f.idle(15_000); assertEquals("first_frame_deadline", f.observation.drain()["failureCode"])
        }
    }

    @Test fun negativeOutOfWindowAndOverflowTargetsFailBeforeQuantization() {
        for (a0 in listOf(-31_000_001L, 9_000_000L, 10_000_000L, Long.MAX_VALUE)) {
            val f = Fixture(); f.qualified(a0)
            assertEquals("seek_contract", f.observation.drain()["failureCode"])
        }
    }

    @Test fun zeroTargetIsAllowedAndPositiveSubmillisecondTargetTruncates() {
        for (a0 in listOf(-31_000_000L, -30_999_500L)) {
            val f = Fixture(); f.qualified(a0)
            val proposal = f.events().single { it["event"] == "seek_ready" }
            assertEquals(0L, proposal["seekTargetUs"])
            assertTrue(f.observation.beforeSeek(0.0, true))
            f.observation.cancel()
        }
    }

    @Test fun wrongTargetNonexactOrSecondCommandCannotRecomputeProposal() {
        for ((seconds, exact) in listOf(21.0 to true, 29.0 to false)) {
            val f = Fixture(); f.qualified(); f.events()
            assertFalse(f.observation.beforeSeek(seconds, exact))
            assertEquals("seek_contract", f.observation.drain()["failureCode"])
        }
        val f = Fixture(); f.qualified(); f.events()
        assertTrue(f.observation.beforeSeek(29.0, true))
        assertFalse(f.observation.beforeSeek(29.0, true))
        val commands = f.events().filter { it["event"] == "seek_request" }
        assertEquals(1, commands.size); assertEquals(29_000_000L, commands.single()["seekTargetUs"])
    }

    @Test fun outputResetAdjusterOrTimelineChangeMakesFrozenBasisStale() {
        for (change in listOf("output", "reset", "adjuster", "duration", "timeline")) {
            val f = Fixture(); f.qualified(); f.events()
            when (change) {
                "output" -> f.observation.outputChanged(5_000_000)
                "reset" -> f.observation.rendererReset()
                "adjuster" -> f.adjuster(-3_000_000)
                "duration" -> f.player.durationMs = 39_999
                "timeline" -> f.player.timeline = SinglePeriodTimeline(40_000_000L, true, false, false, null,
                    MediaItem.fromUri(android.net.Uri.EMPTY))
            }
            assertFalse(f.observation.beforeSeek(29.0, true))
            assertEquals("seek_contract", f.observation.drain()["failureCode"])
        }
    }

    @Test fun correctedNoopUsesEffectiveTargetRatherThanRequestedOffset() {
        val f = Fixture(); f.player.positionMs = 29_000; f.qualified(c = 29_000_000); f.events()
        assertTrue(f.observation.beforeSeek(29.0, true)); f.observation.seekAck(); f.idle(); f.finish()
        val end = f.events().single { it["event"] == "seek_result" }
        assertEquals("seek_no_distance_no_new_epoch", end["seekResult"])
        assertEquals(29_000_000L, end["seekTargetUs"]); assertEquals(21_000_000L, end["requestedOffsetUs"])
        assertEquals("complete", f.observation.drain()["result"])
    }

    @Test fun additionalFloatMillisecondDropIsRecordedAndNoopUsesEffectiveTarget() {
        val f = Fixture(); f.player.positionMs = 1_000
        f.qualified(-29_999_000, 1_000_000)
        val proposal = f.events().single { it["event"] == "seek_ready" }
        assertEquals(1_001_000L, proposal["seekTargetUs"])
        assertEquals(1_000_000L, proposal["seekEffectiveTargetUs"])
        assertTrue(f.observation.beforeSeek(1.001, true)); f.observation.seekAck(); f.idle(); f.finish()
        val events = f.events()
        assertTrue(events.filter { it["event"] in listOf("seek_request", "seek_ack", "seek_result") }
            .all { it["seekTargetUs"] == 1_001_000L && it["seekEffectiveTargetUs"] == 1_000_000L })
        assertEquals("seek_no_distance_no_new_epoch", events.single { it["event"] == "seek_result" }["seekResult"])
        assertEquals("complete", f.observation.drain()["result"])
    }

    @Test fun normalMillisecondTargetsKeepRequestedAndEffectiveValuesEqual() {
        for ((x, targetMs) in listOf(21 to 17914L, 21 to 28946L, 605 to 608278L)) {
            val f = Fixture(x, durationMs = 700_000)
            val target = targetMs * 1000
            f.qualified(target - x * 1_000_000L - 10_000_000L)
            val proposal = f.events().single { it["event"] == "seek_ready" }
            assertEquals(target, proposal["seekTargetUs"]); assertEquals(target, proposal["seekEffectiveTargetUs"])
            assertTrue(f.observation.beforeSeek(target / 1_000_000.0, true))
            f.observation.cancel()
        }
    }

    @Test fun postSeekA1StaysIndependentWithNoSecondCorrection() {
        val f = Fixture(); f.qualified(); val first = f.events().single { it["event"] == "seek_ready" }
        assertTrue(f.observation.beforeSeek(29.0, true)); f.observation.seekAck()
        f.observation.rendererReset(); f.adjuster(-7_000_000, 29_000_000, 1)
        f.frame(29_000_000); f.player.positionMs = 29_000; f.finish()
        val events = f.events(); assertFalse(events.any { it["event"] == "seek_ready" })
        val end = events.single { it["event"] == "seek_result" }
        assertEquals(-2_000_000L, first["hlsOffsetUs"])
        assertEquals(-7_000_000L, end["hlsOffsetUs"]); assertEquals(29_000_000L, end["seekTargetUs"])
        assertEquals(21_000_000L, end["requestedOffsetUs"])
        assertEquals("post_seek_frame_observed", end["seekResult"])
    }

    @Test fun cancellationClosesGuardAndRetainsReleaseDrainReceipt() {
        val f = Fixture(); f.qualified(); f.events()
        f.observation.cancel(); f.observation.release(true, false, true)
        assertFalse(f.guard.isOpen())
        val drain = f.observation.drain()
        assertEquals("cancelled", drain["failureCode"])
        @Suppress("UNCHECKED_CAST")
        val events = drain["events"] as List<Map<String, Any?>>
        assertEquals(0, events.count { it["event"] == "seek_request" || it["event"] == "seek_ready" })
        val released = events.single { it["event"] == "release" }
        assertEquals(true, released["networkDrained"]); assertEquals(0, released["activeCalls"])
    }
}
