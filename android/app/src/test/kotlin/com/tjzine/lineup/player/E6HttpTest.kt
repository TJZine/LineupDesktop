package com.tjzine.lineup.player

import android.net.Uri
import androidx.media3.common.C
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import java.io.IOException
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.ResponseBody
import okhttp3.ResponseBody.Companion.toResponseBody
import okio.Buffer
import okio.buffer
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** Actual OkHttpDataSource/Range generation with an in-process terminal interceptor, no sockets. */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
class E6HttpTest {
    private class Fixture(val input: Map<String, Any?> = e6Input()) {
        val observation = e6Observer(input)
        val guard = E6Http(observation)
        var dispatched = 0
        var status = 200
        var extraHeaders = emptyMap<String, String>()
        var body: ResponseBody? = null
        val client = OkHttpClient.Builder().retryOnConnectionFailure(false)
            .followRedirects(false).followSslRedirects(false).addInterceptor(guard).addInterceptor { chain ->
                dispatched++
                val response = Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(status).message("fixture")
                extraHeaders.forEach { (key, value) -> response.addHeader(key, value) }
                response.body(body ?: if (chain.request().url.encodedPath.endsWith("index.m3u8"))
                    e6Playlist((input["offsetSeconds"] as Number).toInt()).toResponseBody() else ByteArray(32).toResponseBody())
                    .build()
            }.build()
        val factory = guard.factory(client)
        fun read(name: String = "index.m3u8", position: Long = 0, length: Long = C.LENGTH_UNSET.toLong()): Long {
            val source = factory.createDataSource()
            val uri = observation.config.variant.resolve(name)!!.toString()
            return try {
                source.open(DataSpec.Builder().setUri(Uri.parse(uri)).setPosition(position).setLength(length).build())
                val buffer = ByteArray(4096)
                var total = 0L
                while (true) { val n = source.read(buffer, 0, buffer.size); if (n < 0) break; total += n }
                total
            } finally { source.close() }
        }
        fun facts(): List<Map<*, *>> = observation.drain()["events"] as List<Map<*, *>>
    }

    private fun rejected(action: () -> Unit) { try { action(); fail("must reject") } catch (_: IOException) { } }

    @Test fun exactPlaylistThenInitMediaRequestsAreCountedAndSanitized() {
        val f = Fixture()
        f.read(); f.read("init.mp4"); f.read("2.m4s")
        assertEquals(3, f.dispatched)
        assertEquals(0, f.guard.activeCalls())
        val facts = f.facts()
        val attempt = facts.single { it["event"] == "http_attempt" && it["kind"] == "media" }
        assertEquals(2, attempt["ordinal"])
        assertEquals(2L, attempt["filenameIndex"])
        assertEquals(true, attempt["firstMediaAttempt"])
        assertTrue(facts.any { it["firstMediaHttpSuccess"] == true && it["outcome"] == "headers" })
        assertFalse(facts.any { it["firstMediaCompleted"] == true })
        f.guard.loadCompleted(Uri.parse(f.observation.config.reference("2.m4s").toString()),
            android.os.SystemClock.elapsedRealtime(), android.os.SystemClock.elapsedRealtime())
        assertEquals(true, f.facts().single()["firstMediaCompleted"])
        val serialized = facts.toString()
        for (private in listOf("localhost", "https", "m3u8", "init.mp4", "m4s")) assertFalse(serialized.contains(private))
    }

    @Test fun sameOriginOtherNamespaceAndUnlistedLeafNeverReachTransport() {
        val f = Fixture()
        f.read()
        rejected { f.read("../e6-other/0.m4s") }
        assertEquals(1, f.dispatched)
        assertEquals("unsafe_reference", f.observation.drain()["failureCode"])
        val g = Fixture(); g.read()
        rejected { g.read("stop") }
        assertEquals(1, g.dispatched)
    }

    @Test fun childCannotPrecedeValidatedFinitePlaylist() {
        val f = Fixture()
        rejected { f.read("0.m4s") }
        assertEquals(0, f.dispatched)
    }

    @Test fun malformedPlaylistCannotAuthorizeAnyChild() {
        val f = Fixture(); f.body = "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nother.m3u8\n".toResponseBody()
        rejected { f.read() }
        rejected { f.read("0.m4s") }
        assertEquals(1, f.dispatched)
        assertEquals("playlist_scope", f.observation.drain()["failureCode"])
    }

    @Test fun noErrorRetryAndNoRedirectDispatchAtAnyPhase() {
        for (status in listOf(301, 302, 401, 403, 404, 429, 500)) {
            val f = Fixture(); f.read(); f.status = status
            f.extraHeaders = mapOf("Location" to "https://other.invalid/private")
            rejected { f.read("0.m4s") }
            rejected { f.read("0.m4s") }
            assertEquals("one failed media attempt only", 2, f.dispatched)
            assertEquals(if (status == 404) "http_404" else "unexpected_status", f.observation.drain()["failureCode"])
        }
    }

    @Test fun realDataSpecRangeIsRecordedWithoutSynthesizingOne() {
        val f = Fixture(); f.read()
        f.status = 206; f.extraHeaders = mapOf("Content-Range" to "bytes 8-39/64")
        assertEquals(32L, f.read("0.m4s", 8, 32))
        val facts = f.facts()
        val attempt = facts.single { it["event"] == "http_attempt" && it["kind"] == "media" }
        assertEquals(8L, attempt["rangeStart"]); assertEquals(39L, attempt["rangeEnd"])
        assertTrue(facts.any { it["contentRangeStart"] == 8L && it["contentRangeTotal"] == 64L })
    }

    @Test fun malformedOrUnrequestedPartialResponseFailsClosed() {
        for (header in listOf("bytes 9-40/64", "bytes 8-100/64", "bytes */64", "bytes 8-39/*", "bytes 8-39/64,0-1/64")) {
            val f = Fixture(); f.read(); f.status = 206; f.extraHeaders = mapOf("Content-Range" to header)
            rejected { f.read("0.m4s", 8, 32) }
            assertEquals("invalid_range", f.observation.drain()["failureCode"])
        }
        val f = Fixture(); f.read(); f.status = 206; f.extraHeaders = mapOf("Content-Range" to "bytes 0-31/32")
        rejected { f.read("0.m4s") }
    }

    @Test fun perCategoryAttemptCapsAreLifetimeBounds() {
        val f = Fixture(); f.read(); f.read(); rejected { f.read() }
        assertEquals(2, f.dispatched)
        assertEquals("request_budget", f.observation.drain()["failureCode"])
        val g = Fixture(); g.read(); g.read("init.mp4"); g.read("init.mp4"); rejected { g.read("init.mp4") }
        assertEquals(3, g.dispatched)
    }

    @Test fun successfulMediaRereadWithoutExplicitSeekIsRefused() {
        val f = Fixture(); f.read(); f.read("0.m4s"); rejected { f.read("0.m4s") }
        assertEquals(2, f.dispatched)
        assertEquals("error_retry_refused", f.observation.drain()["failureCode"])
    }

    @Test fun declaredBodyOverCapFailsBeforeReadingMedia() {
        val f = Fixture(); f.read()
        f.body = object : ResponseBody() {
            override fun contentType() = null
            override fun contentLength() = 128L * 1024 * 1024 + 1
            override fun source() = Buffer().write(ByteArray(32))
        }
        rejected { f.read("0.m4s") }
        assertEquals("response_byte_cap", f.observation.drain()["failureCode"])
    }

    @Test fun gateCancellationBlocksNewPhysicalAttempts() {
        val f = Fixture(); f.read(); f.guard.closeGate(); rejected { f.read("0.m4s") }
        assertEquals(1, f.dispatched); assertEquals(0, f.guard.activeCalls())
    }

    @Test fun cancellationWaitsForActualBodyCloseInsteadOfDispatcherAcceptance() {
        val f = Fixture(); f.read()
        val entered = java.util.concurrent.CountDownLatch(1)
        val finishClose = java.util.concurrent.CountDownLatch(1)
        f.body = object : ResponseBody() {
            private val stream = object : okio.ForwardingSource(Buffer().write(ByteArray(32))) {
                override fun close() {
                    entered.countDown()
                    assertTrue(finishClose.await(3, java.util.concurrent.TimeUnit.SECONDS))
                    super.close()
                }
            }.buffer()
            override fun contentType() = null
            override fun contentLength() = 32L
            override fun source() = stream
        }
        val source = f.factory.createDataSource()
        source.open(DataSpec(Uri.parse(f.observation.config.reference("0.m4s").toString())))
        val closing = Thread { source.close() }.apply { start() }
        assertTrue(entered.await(3, java.util.concurrent.TimeUnit.SECONDS))
        try {
            f.guard.closeGate(); f.client.dispatcher.cancelAll()
            assertEquals(1, f.guard.activeCalls())
            assertFalse("cancelAll return is not a body-close fence", f.guard.awaitDrained(f.client, 10))
        } finally { finishClose.countDown(); closing.join(3000) }
        assertFalse(closing.isAlive)
        assertTrue(f.guard.awaitDrained(f.client, 1000))
        assertTrue(f.guard.awaitDrained(null, 0))
    }

    @Test fun completionQueuedAcrossSeekKeepsOriginalHttpPhase() {
        val f = Fixture(e6Input(21, true)); f.read(); f.read("0.m4s"); f.facts()
        f.observation.attach(E6Player().player, f.guard) { }
        f.observation.ready(); assertTrue(f.observation.beforeSeek(21.0, true)); f.facts()
        f.guard.loadCompleted(Uri.parse(f.observation.config.reference("0.m4s").toString()),
            android.os.SystemClock.elapsedRealtime(), android.os.SystemClock.elapsedRealtime())
        val completion = f.facts().single()
        assertEquals(0L, completion["seekEpoch"])
        assertEquals(false, completion["firstPostSeekCompleted"])
        assertEquals(true, completion["bindingKnown"])
        f.observation.cancel()
    }

    @Test fun failedBeforeHeadersStillHasOneFinalAttemptReceipt() {
        val observation = e6Observer()
        val guard = E6Http(observation)
        val client = OkHttpClient.Builder().addInterceptor(guard).addInterceptor { throw IOException("private diagnostic") }.build()
        val source = guard.factory(client).createDataSource()
        rejected { source.open(DataSpec(Uri.parse(observation.config.variant.toString()))) }
        source.close()
        val facts = observation.drain()["events"] as List<Map<*, *>>
        val final = facts.single { it["event"] == "http_result" && it["outcome"] == "failed" }
        assertEquals(1, final["attempt"]); assertNull(final["status"]); assertEquals(0L, final["bytes"])
        assertFalse(facts.toString().contains("private diagnostic"))
    }

    @Test fun failedSourceCloseRetainsOwnershipAndCannotConfirmDrain() {
        val f = Fixture(); f.read()
        f.body = object : ResponseBody() {
            private val stream = object : okio.ForwardingSource(Buffer().write(ByteArray(32))) {
                override fun close() { throw IOException("private close diagnostic") }
            }.buffer()
            override fun contentType() = null
            override fun contentLength() = 32L
            override fun source() = stream
        }
        // OkHttpDataSource.close deliberately closes quietly. The observer's
        // retained ownership/failure must expose the unsuccessful close anyway.
        f.read("0.m4s")
        assertEquals(1, f.guard.activeCalls())
        assertFalse(f.guard.awaitDrained(f.client, 1))
        assertEquals("io_failure", f.observation.drain()["failureCode"])
    }

    @Test fun mediaAndTotalAttemptCeilingsRejectBeforePhysicalDispatch() {
        val input = e6Input() + mapOf("expectedDurationsSeconds" to List(20) { 10 }, "sourceDurationMs" to 200_000)
        val playlist = e6Playlist(media = (0..19).map { "$it.m4s" })
        val f = Fixture(input); f.body = playlist.toResponseBody(); f.read(); f.body = null
        repeat(16) { f.read("$it.m4s") }
        rejected { f.read("16.m4s") }
        assertEquals(17, f.dispatched); assertEquals(16, f.guard.totals()["mediaAttempts"])
        val g = Fixture(input)
        repeat(2) { g.body = playlist.toResponseBody(); g.read() }; g.body = null
        repeat(2) { g.read("init.mp4") }; repeat(16) { g.read("$it.m4s") }
        rejected { g.read("16.m4s") }
        assertEquals(20, g.dispatched)
    }

    @Test fun unknownLengthResponseIsStreamingCappedWithoutAllocatingItsBody() {
        val f = Fixture(); f.read()
        val cap = 128L * 1024 * 1024
        var transferred = 0L
        f.body = object : ResponseBody() {
            var remaining = cap + 1
            val zeroes = ByteArray(8192)
            private val stream = object : okio.Source {
                override fun read(sink: Buffer, byteCount: Long): Long {
                    if (remaining == 0L) return -1
                    val n = minOf(remaining, byteCount, zeroes.size.toLong()).toInt()
                    sink.write(zeroes, 0, n); remaining -= n; transferred += n; return n.toLong()
                }
                override fun timeout() = okio.Timeout.NONE
                override fun close() { }
            }.buffer()
            override fun contentType() = null
            override fun contentLength() = -1L
            override fun source() = stream
        }
        rejected { f.read("0.m4s") }
        assertEquals("response_byte_cap", f.observation.drain()["failureCode"])
        assertEquals(cap, transferred)
        // No cap+1 read: native never transfers beyond the approved streaming bound.
        assertTrue((f.guard.totals()["totalBytes"] as Long) in cap..(cap + 1024 * 1024))
    }

    @Test fun releaseFenceWaitsForFinalReceiptAfterBodyHasAlreadyClosed() {
        val entered = java.util.concurrent.CountDownLatch(1)
        val finish = java.util.concurrent.CountDownLatch(1)
        val block = java.util.concurrent.atomic.AtomicBoolean(false)
        val config = E6Config.parse(e6Input(), false)
        val observation = E6Observation(config, android.os.Handler(android.os.Looper.getMainLooper()), 1, now = {
            if (block.get() && Thread.currentThread().name == "E6ClosingTest") {
                entered.countDown()
                assertTrue(finish.await(3, java.util.concurrent.TimeUnit.SECONDS))
            }
            System.nanoTime()
        })
        val guard = E6Http(observation)
        val client = OkHttpClient.Builder().addInterceptor(guard).addInterceptor { chain ->
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200).message("fixture")
                .body(if (chain.request().url == config.variant) e6Playlist().toResponseBody()
                    else ByteArray(32).toResponseBody()).build()
        }.build()
        val factory = guard.factory(client)
        val playlist = factory.createDataSource()
        playlist.open(DataSpec(Uri.parse(config.variant.toString())))
        while (playlist.read(ByteArray(1024), 0, 1024) >= 0) { }
        playlist.close()
        val media = factory.createDataSource()
        media.open(DataSpec(Uri.parse(config.reference("0.m4s").toString())))
        assertEquals(32, media.read(ByteArray(32), 0, 32))
        block.set(true)
        val closing = Thread({ media.close() }, "E6ClosingTest").apply { start() }
        assertTrue(entered.await(3, java.util.concurrent.TimeUnit.SECONDS))
        try {
            guard.closeGate(); client.dispatcher.cancelAll()
            assertEquals("final fact callback still owns its call", 1, guard.activeCalls())
            assertFalse(guard.awaitDrained(client, 10))
        } finally { finish.countDown(); closing.join(3000) }
        assertFalse(closing.isAlive)
        assertTrue(guard.awaitDrained(client, 1000))
    }
}
