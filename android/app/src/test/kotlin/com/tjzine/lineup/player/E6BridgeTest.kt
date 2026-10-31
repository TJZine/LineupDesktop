package com.tjzine.lineup.player

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.FlutterException
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.StandardMethodCodec
import java.nio.ByteBuffer
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
class E6BridgeTest {
    private class Messenger : BinaryMessenger {
        val handlers = mutableMapOf<String, BinaryMessenger.BinaryMessageHandler>()
        override fun send(channel: String, message: ByteBuffer?) { }
        override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) { }
        override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) {
            if (handler == null) handlers.remove(channel) else handlers[channel] = handler
        }
        fun call(method: String, args: Any? = null): Any? {
            val message = StandardMethodCodec.INSTANCE.encodeMethodCall(MethodCall(method, args)).apply { rewind() }
            var response: ByteBuffer? = null
            handlers.getValue("lineup/e6").onMessage(message) { response = it }
            return StandardMethodCodec.INSTANCE.decodeEnvelope(response!!.apply { rewind() })
        }
    }

    private val context = RuntimeEnvironment.getApplication()
    private fun bridge(messenger: Messenger, args: List<String> = listOf("--case=session-live", "--e6-observe")) =
        E6Bridge(context, messenger, Handler(Looper.getMainLooper()), args)

    @Test fun ordinaryAndNonOptInDebugCasesInstallNoChannel() {
        for (args in listOf(emptyList(), listOf("--e6-observe"), listOf("--case=session-live"),
            listOf("--case=session-live", "--e6-observe", "--e6-public-baseline"))) {
            val messenger = Messenger(); val b = bridge(messenger, args)
            assertFalse(b.enabled); assertTrue(messenger.handlers.isEmpty()); assertNull(b.claim()); b.close()
        }
    }

    @Test fun configureClaimsExactlyOneLoadAndDrainRetainsItsState() {
        val messenger = Messenger(); val b = bridge(messenger)
        messenger.call("markInputReady")
        assertEquals(mapOf("configured" to true), messenger.call("configure", e6Input()))
        val observation = b.claim()!!
        assertFalse(observation.terminal)
        val drain = messenger.call("drain") as Map<*, *>
        assertEquals(setOf("events", "hasReady", "terminal", "result", "failureCode"), drain.keys)
        assertEquals(false, drain["hasReady"]); assertEquals("running", drain["result"])
        try { b.claim(); fail("one load") } catch (error: E6Failure) { assertEquals("unexpected_load", error.code) }
        assertEquals(mapOf("cancelled" to true), messenger.call("cancel"))
        assertEquals("failed", (messenger.call("drain") as Map<*, *>)["result"])
        b.close()
    }

    @Test fun baselineRejectsPrivateInputBeforeEngineClaimAndNoPrivateValueIsReturned() {
        val messenger = Messenger(); val b = bridge(messenger, listOf("--case=session-live", "--e6-public-baseline"))
        messenger.call("markInputReady")
        try {
            messenger.call("configure", e6Input(uri = "https://PRIVATE_HOST.invalid/video/:/transcode/universal/session/PRIVATE_ID/base/index.m3u8"))
            fail("baseline must refuse private input")
        } catch (error: FlutterException) {
            assertEquals("baseline_private_refused", error.code)
            assertFalse(error.message.orEmpty().contains("PRIVATE")); assertNull(error.details)
        }
        assertEquals(mapOf("configured" to true), messenger.call("configure", e6Input()))
        b.close()
    }

    @Test fun publicReadyMarkerHasOnlyPublicFieldsAndDeletesOnlyOwnPid() {
        val messenger = Messenger(); val b = bridge(messenger)
        val file = java.io.File(context.cacheDir, "e6-ready")
        assertFalse(file.exists())
        assertEquals(mapOf("ready" to true), messenger.call("markInputReady"))
        val record = org.json.JSONObject(file.readText())
        assertEquals(setOf("protocol", "pid", "ready"), record.keys().asSequence().toSet())
        assertEquals(android.os.Process.myPid(), record.getInt("pid"))
        messenger.call("cancel"); assertFalse(file.exists())
        // A second process/readiness origin cannot extend this process's deadline.
        try { messenger.call("markInputReady"); fail("nonresettable origin") } catch (_: FlutterException) { }
        file.writeText("{\"protocol\":1,\"pid\":2147483647,\"ready\":true}")
        b.close(); assertTrue("do not remove a replacement owner's marker", file.exists())
        file.delete()
    }

    @Test fun capabilitiesExposeOnlyTypedPublicDecoderFacts() {
        val messenger = Messenger(); val b = bridge(messenger)
        val caps = messenger.call("capabilities") as Map<*, *>
        assertEquals(setOf("debugEnabled", "apiLevel", "arm64", "h2641080", "aac", "hevcMain10", "hevc3840x1600"), caps.keys)
        assertTrue(caps["apiLevel"] is Int)
        assertTrue(caps.filterKeys { it != "apiLevel" }.values.all { it is Boolean })
        b.close()
    }

    private fun transportFacts(mode: String = "eof", phase: String = "starting", received: Int = 0) =
        mapOf("mode" to mode, "phase" to phase, "receivedBytes" to received,
            "responseAttempted" to false, "flushedBytes" to 0, "failureCode" to null)

    @Test fun transportRequiresExactlyOneValidModeAndNeverFallsBackToPlayback() {
        val common = listOf("--case=session-live", "--e6-observe")
        for (args in listOf(common + "--e6-transport", common + "--e6-transport=other",
            common + listOf("--e6-transport=eof", "--e6-transport=line"),
            common + listOf("--e6-transport=eof", "--e6-transport=eof"),
            listOf("--case=session-live", "--e6-public-baseline", "--e6-transport=eof"),
            listOf("--case=session-live", "--e6-transport=eof"))) {
            val messenger = Messenger(); val b = bridge(messenger, args)
            assertFalse(b.enabled); assertTrue(messenger.handlers.isEmpty())
            try { b.claim(); fail("transport must never claim a player") }
            catch (error: E6Failure) { assertEquals("invalid_probe", error.code) }
            b.close()
        }
    }

    @Test fun validTransportModesRejectEveryPlayerAndCodecBridgePath() {
        for (mode in listOf("eof", "line")) {
            val messenger = Messenger(); val b = bridge(messenger,
                listOf("--case=session-live", "--e6-observe", "--e6-transport=$mode"))
            assertTrue(b.enabled)
            for (method in listOf("configure", "drain", "capabilities")) {
                try { messenger.call(method, if (method == "configure") mapOf("unexpected" to true) else null); fail("blocked") }
                catch (error: FlutterException) { assertEquals("invalid_probe", error.code); assertNull(error.details) }
            }
            try { b.claim(); fail("blocked player claim") } catch (error: E6Failure) { assertEquals("invalid_probe", error.code) }
            assertEquals(mapOf("stored" to true), messenger.call("transportStatus", transportFacts(mode)))
            b.close()
        }
    }

    @Test fun transportStatusInjectsOwnPidAndPreservesFinalIncompleteFactsAfterCancel() {
        val messenger = Messenger(); val b = bridge(messenger,
            listOf("--case=session-live", "--e6-observe", "--e6-transport=eof"))
        assertEquals(mapOf("ready" to true), messenger.call("markInputReady"))
        val ready = java.io.File(context.cacheDir, "e6-ready")
        assertTrue(ready.exists()); assertFalse(java.io.File(context.cacheDir, "e6-ready.tmp").exists())
        assertEquals(mapOf("stored" to true), messenger.call("transportStatus",
            transportFacts(phase = "input_incomplete", received = 7)))
        val file = java.io.File(context.cacheDir, "e6-transport-status")
        val before = file.readBytes()
        val record = org.json.JSONObject(file.readText())
        assertEquals(android.os.Process.myPid(), record.getInt("pid")); assertEquals(1, record.getInt("protocol"))
        assertEquals("input_incomplete", record.getString("phase")); assertTrue(record.isNull("failureCode"))
        messenger.call("cancel"); assertFalse(ready.exists())
        try { messenger.call("transportStatus", transportFacts(phase = "closed", received = 7)); fail("cancel guard") }
        catch (error: FlutterException) { assertEquals("invalid_probe", error.code) }
        b.close(); assertArrayEquals(before, file.readBytes())
        assertFalse(java.io.File(context.cacheDir, "e6-transport-status.tmp").exists())
    }

    @Test fun statusModeMismatchAndOrdinaryE6CallsCannotWriteTransportFacts() {
        val messenger = Messenger(); val b = bridge(messenger,
            listOf("--case=session-live", "--e6-observe", "--e6-transport=line"))
        try { messenger.call("transportStatus", transportFacts()); fail("mode mismatch") }
        catch (error: FlutterException) { assertEquals("invalid_probe", error.code) }
        b.close()
        val normalMessenger = Messenger(); val normal = bridge(normalMessenger)
        try { normalMessenger.call("transportStatus", transportFacts()); fail("not transport mode") }
        catch (error: FlutterException) { assertEquals("invalid_probe", error.code) }
        normal.close()
    }
}
