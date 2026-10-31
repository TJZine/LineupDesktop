package com.tjzine.lineup.player

import java.io.File
import java.util.concurrent.atomic.AtomicReference
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
class E6TransportStatusTest {
    @get:Rule val temporary = TemporaryFolder()

    private fun facts(mode: String = "eof", phase: String = "starting", received: Any = 0,
        attempted: Any = false, flushed: Any = 0, failure: Any? = null): Map<String, Any?> =
        linkedMapOf("mode" to mode, "phase" to phase, "receivedBytes" to received,
            "responseAttempted" to attempted, "flushedBytes" to flushed, "failureCode" to failure)

    private fun rejected(code: String = "invalid_probe", action: () -> Unit) {
        try { action(); fail("must reject") } catch (error: E6Failure) { assertEquals(code, error.code) }
    }

    @Test fun nativeInjectsIdentityAndWritesOnlyTheEightBoundedPublicFields() {
        val root = temporary.newFolder()
        val status = E6TransportStatus(root, "eof", 4312)
        status.store(facts(phase = "input_incomplete", received = 7))
        val file = File(root, "e6-transport-status")
        assertTrue(file.length() <= 512)
        val record = JSONObject(file.readText(Charsets.UTF_8))
        assertEquals(E6TransportStatus.keys + setOf("protocol", "pid"), record.keys().asSequence().toSet())
        assertEquals(1, record.getInt("protocol")); assertEquals(4312, record.getInt("pid"))
        assertEquals("eof", record.getString("mode")); assertEquals(7, record.getInt("receivedBytes"))
        assertFalse(record.getBoolean("responseAttempted")); assertTrue(record.isNull("failureCode"))
        assertEquals(listOf("e6-transport-status"), root.list()!!.toList())
    }

    @Test fun freshTransportOwnerClearsOnlyItsFixedStalePublicFiles() {
        val root = temporary.newFolder()
        File(root, "e6-transport-status").writeText("stale public status")
        File(root, "e6-transport-status.tmp").writeText("stale public temporary")
        File(root, "unrelated").writeText("keep")
        E6TransportStatus(root, "line", 4312)
        assertEquals(listOf("unrelated"), root.list()!!.toList())
    }

    @Test fun allDeclaredPhasesAndFailureEnumsRoundTripWithoutArbitraryStrings() {
        val root = temporary.newFolder(); val status = E6TransportStatus(root, "line", 1)
        for (phase in E6TransportStatus.phases) {
            status.store(facts(mode = "line", phase = phase))
            assertEquals(phase, JSONObject(File(root, "e6-transport-status").readText()).getString("phase"))
        }
        for (failure in E6TransportStatus.failures) {
            status.store(facts(mode = "line", phase = "failed", failure = failure))
            assertEquals(failure, JSONObject(File(root, "e6-transport-status").readText()).getString("failureCode"))
        }
    }

    @Test fun exactKeysModeAndTypesRejectBeforeChangingTheLastValidFile() {
        val root = temporary.newFolder(); val status = E6TransportStatus(root, "eof", 1)
        status.store(facts())
        val file = File(root, "e6-transport-status"); val original = file.readBytes()
        val invalid = listOf(null, listOf(1), facts() - "failureCode", facts() + ("pid" to 99),
            facts() + ("uri" to "PRIVATE_SENTINEL"), facts(mode = "line"), facts(phase = "PRIVATE_SENTINEL"),
            facts(failure = "PRIVATE_SENTINEL"), facts(received = "11"), facts(received = 11.0),
            facts(received = true), facts(attempted = 0), facts(flushed = 1.0), facts(failure = 1))
        for (input in invalid) {
            rejected { status.store(input) }
            assertArrayEquals(original, file.readBytes())
            assertFalse(File(root, "e6-transport-status.tmp").exists())
        }
    }

    @Test fun byteBoundsAndMonotonicAttemptCountersAreEnforced() {
        val root = temporary.newFolder(); val status = E6TransportStatus(root, "eof", 1)
        for (input in listOf(facts(received = -1), facts(received = 32769), facts(flushed = -1),
            facts(flushed = 1025, attempted = true), facts(flushed = 1))) rejected { status.store(input) }
        status.store(facts(received = 32768L, flushed = 1024L, attempted = true))
        rejected { status.store(facts(received = 32767, flushed = 1024, attempted = true)) }
        rejected { status.store(facts(received = 32768, flushed = 1023, attempted = true)) }
        rejected { status.store(facts(received = 32768, flushed = 1024, attempted = false)) }
        assertEquals(32768, JSONObject(File(root, "e6-transport-status").readText()).getInt("receivedBytes"))
    }

    @Test fun failedAtomicRenameCleansTemporaryAndRetainsThePreviousDestination() {
        val root = temporary.newFolder(); val status = E6TransportStatus(root, "eof", 1)
        val blocking = File(root, "e6-transport-status").apply { mkdir() }
        File(blocking, "keep").writeText("public fixture")
        rejected("io_failure") { status.store(facts()) }
        assertEquals("public fixture", File(blocking, "keep").readText())
        assertFalse(File(root, "e6-transport-status.tmp").exists())
    }

    @Test fun atomicPublicationNeverExposesPartialJsonDuringRepeatedReplacement() {
        val root = temporary.newFolder(); val status = E6TransportStatus(root, "line", 1)
        val file = File(root, "e6-transport-status")
        status.store(facts(mode = "line"))
        val error = AtomicReference<Throwable?>()
        val writer = Thread {
            try { repeat(100) { status.store(facts(mode = "line", phase = "peer_accepted", received = it + 1)) } }
            catch (failure: Throwable) { error.set(failure) }
        }.apply { start() }
        val deadline = System.nanoTime() + 3_000_000_000L
        do {
            val record = JSONObject(file.readText(Charsets.UTF_8))
            assertEquals(1, record.getInt("protocol")); assertEquals(1, record.getInt("pid"))
            assertEquals("line", record.getString("mode"))
            assertTrue(record.getInt("receivedBytes") in 0..100)
        } while (writer.isAlive && System.nanoTime() < deadline)
        writer.join(3000)
        assertFalse("bounded public file replacement", writer.isAlive)
        assertNull(error.get())
        assertEquals(100, JSONObject(file.readText()).getInt("receivedBytes"))
        assertFalse(File(root, "e6-transport-status.tmp").exists())
    }

    @Test fun readinessPublicationIsAtomicBoundedAndLeavesNoTemporary() {
        val root = temporary.newFolder(); val ready = File(root, "e6-ready")
        val bytes = "{\"protocol\":1,\"pid\":4312,\"ready\":true}".toByteArray(Charsets.UTF_8)
        E6TransportStatus.publish(ready, bytes, 128)
        assertArrayEquals(bytes, ready.readBytes())
        rejected("output_cap") { E6TransportStatus.publish(ready, ByteArray(129), 128) }
        assertArrayEquals(bytes, ready.readBytes())
        assertFalse(File(root, "e6-ready.tmp").exists())
    }
}
