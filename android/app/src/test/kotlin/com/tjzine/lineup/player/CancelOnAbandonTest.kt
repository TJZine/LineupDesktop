package com.tjzine.lineup.player

import java.io.Closeable
import java.io.IOException
import java.net.InetAddress
import java.util.concurrent.CountDownLatch
import java.util.concurrent.CompletableFuture
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import okhttp3.Call
import okhttp3.Callback
import okhttp3.ConnectionPool
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody
import okhttp3.mockwebserver.Dispatcher as ServerDispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import okio.Buffer
import okio.ForwardingSource
import okio.buffer
import org.junit.Assert.*
import org.junit.Test

/** Real HTTP/1.1 TLS exchanges; no Android/device, external server, or private media. */
class CancelOnAbandonTest {
    @Test(timeout = 20000)
    fun slowLargeAbandonSavesMedian50msAgainstPairedDrainControls() {
        Fixture().use { fixture ->
            val baseline = mutableListOf<Double>()
            val candidate = mutableListOf<Double>()
            // Fixed budget, alternating paired order. Handshake, headers and the
            // successful first read are outside the close-only timed interval.
            repeat(5) { pair ->
                val order = if (pair % 2 == 0) listOf(false, true) else listOf(true, false)
                for (isCandidate in order) {
                    fixture.server.enqueue(slow206(LARGE.size))
                    val call = fixture.client(isCandidate).newCall(fixture.request("/slow"))
                    val elapsed = call.execute().use { response ->
                        assertEquals(206, response.code)
                        assertEquals(LARGE.size.toLong(), response.body!!.contentLength())
                        assertEquals(PAYLOAD_BYTE, response.body!!.source().readByte().toInt())
                        val start = System.nanoTime()
                        response.close()
                        (System.nanoTime() - start) / 1_000_000.0
                    }
                    assertEquals("Only candidate large-body abandonment cancels its call", isCandidate, call.isCanceled())
                    (if (isCandidate) candidate else baseline).add(elapsed)
                }
            }
            println("cancel_close_ms baseline=$baseline candidate=$candidate " +
                "baseline_median=${median(baseline)} baseline_min=${baseline.min()} baseline_max=${baseline.max()} " +
                "candidate_median=${median(candidate)} candidate_min=${candidate.min()} candidate_max=${candidate.max()}")
            assertEquals(5, baseline.size)
            assertEquals(5, candidate.size)
            // A JVM scheduling or GC pause can delay an individual close. Keep
            // the regression gate relative and tolerate outlying pairs.
            val pairedSavings = baseline.zip(candidate).map { (baselineMs, candidateMs) ->
                baselineMs - candidateMs
            }
            assertTrue(
                "The median paired candidate saving must be at least 50ms: $pairedSavings",
                median(pairedSavings) >= 50.0,
            )
        }
    }

    @Test(timeout = 10000)
    fun smallPartiallyReadResponseStillReusesConnection() {
        Fixture().use { fixture ->
            fixture.server.enqueue(response206(32 * 1024))
            fixture.server.enqueue(MockResponse().setBody("next"))
            val client = fixture.client()
            val call = client.newCall(fixture.request("/small"))
            call.execute().use { response ->
                assertEquals(PAYLOAD_BYTE, response.body!!.source().readByte().toInt())
            }
            assertFalse(call.isCanceled())
            assertEquals(0, fixture.takeRequest().sequenceNumber)
            client.newCall(fixture.request("/next")).execute().use { response -> assertEquals("next", response.body!!.string()) }
            assertEquals("Small close must preserve the reusable TLS connection", 1, fixture.takeRequest().sequenceNumber)
        }
    }

    @Test(timeout = 10000)
    fun fullyReadLargeResponseStillReusesConnection() {
        Fixture().use { fixture ->
            fixture.server.enqueue(response206(LARGE.size))
            fixture.server.enqueue(MockResponse().setBody("next"))
            val client = fixture.client()
            val call = client.newCall(fixture.request("/complete"))
            call.execute().use { response -> assertArrayEquals(LARGE, response.body!!.bytes()) }
            assertFalse(call.isCanceled())
            assertEquals(0, fixture.takeRequest().sequenceNumber)
            client.newCall(fixture.request("/next")).execute().use { response -> assertEquals("next", response.body!!.string()) }
            assertEquals("Full consumption must preserve the reusable TLS connection", 1, fixture.takeRequest().sequenceNumber)
        }
    }

    @Test(timeout = 10000)
    fun exactly64KiBRemainingUsesNormalClose() {
        Fixture().use { fixture ->
            fixture.server.enqueue(slow206(LIMIT + FIRST_READ))
            val call = fixture.client().newCall(fixture.request("/boundary"))
            call.execute().use { response ->
                assertArrayEquals(ByteArray(FIRST_READ) { PAYLOAD_BYTE.toByte() }, response.body!!.source().readByteArray(FIRST_READ.toLong()))
                response.close()
                assertFalse("Exactly64KiB remaining must not cancel", call.isCanceled())
            }
        }
    }

    @Test(timeout = 10000)
    fun moreThan64KiBRemainingCancelsAfterPartialRead() {
        Fixture().use { fixture ->
            fixture.server.enqueue(slow206(LIMIT + FIRST_READ + 1))
            val call = fixture.client().newCall(fixture.request("/above-boundary"))
            call.execute().use { response ->
                assertEquals(FIRST_READ, response.body!!.source().readByteArray(FIRST_READ.toLong()).size)
                response.close()
                assertTrue("64KiB+1 remaining must cancel this call", call.isCanceled())
            }
        }
    }

    @Test(timeout = 10000)
    fun unknownLengthResponseKeepsNormalClose() {
        Fixture().use { fixture ->
            fixture.server.enqueue(MockResponse().setResponseCode(206)
                .setChunkedBody(Buffer().write(LARGE), FIRST_READ)
                .throttleBody(FIRST_READ.toLong(), 1, TimeUnit.SECONDS))
            val call = fixture.client().newCall(fixture.request("/unknown"))
            call.execute().use { response ->
                assertEquals(-1L, response.body!!.contentLength())
                assertEquals(PAYLOAD_BYTE, response.body!!.source().readByte().toInt())
                response.close()
                assertFalse("Unknown length must not invent an unread-byte estimate", call.isCanceled())
            }
        }
    }

    @Test(timeout = 10000)
    fun abandoningOneResponseDoesNotCancelAnotherCall() {
        Fixture().use { fixture ->
            fixture.server.enqueue(slow206(LARGE.size))
            fixture.server.enqueue(response206(FIRST_READ * 2)
                .throttleBody(FIRST_READ.toLong(), 250, TimeUnit.MILLISECONDS))
            val client = fixture.client()
            val abandoned = client.newCall(fixture.request("/abandoned"))
            val survivor = client.newCall(fixture.request("/survivor"))
            abandoned.execute().use { first ->
                assertEquals(PAYLOAD_BYTE, first.body!!.source().readByte().toInt())
                survivor.execute().use { second ->
                    assertEquals(PAYLOAD_BYTE, second.body!!.source().readByte().toInt())
                    first.close()
                    assertTrue(abandoned.isCanceled())
                    assertFalse(survivor.isCanceled())
                    assertArrayEquals(ByteArray(FIRST_READ * 2 - 1) { PAYLOAD_BYTE.toByte() }, second.body!!.source().readByteArray())
                }
            }
            assertFalse("The independent call must complete without cancellation", survivor.isCanceled())
        }
    }

    @Test(timeout = 15000)
    fun retiringOneLoadCancelsItsAsyncCallsWhileOtherLoadCompletes() {
        Fixture().use { fixture ->
            val arrived = CountDownLatch(3)
            val releaseHeaders = CountDownLatch(1)
            fixture.server.dispatcher = object : ServerDispatcher() {
                override fun dispatch(request: RecordedRequest): MockResponse {
                    arrived.countDown()
                    check(releaseHeaders.await(8, TimeUnit.SECONDS)) { "Header release was not signalled" }
                    return MockResponse().setBody("complete")
                }
            }
            val retiringLoad = MediaHttp.forLoad()
            val retiring = fixture.client(load = retiringLoad)
            val active = fixture.client()
            assertNotSame(retiring.dispatcher, active.dispatcher)
            assertSame(retiring.connectionPool, active.connectionPool)
            val results = List(3) { Outcome() }
            val calls = listOf(
                retiring.newCall(fixture.request("/wait/one")),
                retiring.newCall(fixture.request("/wait/two")),
                active.newCall(fixture.request("/wait/other-load")),
            )
            try {
                calls.zip(results).forEach { (call, result) -> call.enqueue(result) }
                assertTrue("All three asynchronous calls must be waiting for headers", arrived.await(5, TimeUnit.SECONDS))
                assertEquals(2, retiring.dispatcher.runningCallsCount())
                assertEquals(1, active.dispatcher.runningCallsCount())
                retiringLoad.retire()
                assertTrue(retiringLoad.cancelAndAwait())
                for (i in 0..1) {
                    assertTrue(results[i].done.await(3, TimeUnit.SECONDS))
                    assertTrue(results[i].failed)
                    assertTrue(calls[i].isCanceled())
                }
                assertFalse(calls[2].isCanceled())
                assertEquals("Other load must still be waiting, not failed/cancelled", 1L, results[2].done.count)
                releaseHeaders.countDown()
                assertTrue(results[2].done.await(3, TimeUnit.SECONDS))
                assertFalse(results[2].failed)
                assertEquals("complete", results[2].body)
                assertFalse(calls[2].isCanceled())
            } finally {
                releaseHeaders.countDown()
            }
        }
    }

    @Test(timeout = 10000)
    fun retirementWaitsForDeliveredResponseBodyOutsideTheDispatcher() {
        Fixture().use { fixture ->
            val load = MediaHttp.forLoad()
            val reading = CountDownLatch(1)
            val resumeRead = CountDownLatch(1)
            val client = fixture.client(load = load) {
                addNetworkInterceptor { chain ->
                    val response = chain.proceed(chain.request())
                    val upstream = checkNotNull(response.body)
                    response.newBuilder().body(object : ResponseBody() {
                        private val input = object : ForwardingSource(upstream.source()) {
                            override fun read(sink: Buffer, byteCount: Long): Long {
                                reading.countDown()
                                check(resumeRead.await(5, TimeUnit.SECONDS))
                                return super.read(sink, byteCount)
                            }
                        }.buffer()
                        override fun contentType() = upstream.contentType()
                        override fun contentLength() = upstream.contentLength()
                        override fun source() = input
                    }).build()
                }
            }
            fixture.server.enqueue(response206(LARGE.size).setBodyDelay(2, TimeUnit.SECONDS))
            val idle = CountDownLatch(1)
            client.dispatcher.idleCallback = Runnable { idle.countDown() }
            val delivered = CompletableFuture<Response>()
            val call = client.newCall(fixture.request("/body"))
            val workers = Executors.newFixedThreadPool(2)
            try {
                call.enqueue(object : Callback {
                    override fun onFailure(call: Call, e: IOException) { delivered.completeExceptionally(e) }
                    override fun onResponse(call: Call, response: Response) { delivered.complete(response) }
                })
                val response = delivered.get(3, TimeUnit.SECONDS)
                val reader = workers.submit<Boolean> {
                    try {
                        response.use { it.body!!.source().readByte() }
                        false
                    } catch (_: IOException) { true }
                }
                assertTrue(idle.await(2, TimeUnit.SECONDS))
                assertEquals(0, client.dispatcher.runningCallsCount())
                assertTrue(reading.await(2, TimeUnit.SECONDS))

                load.retire()
                val cleanup = workers.submit<Boolean> { load.cancelAndAwait() }
                val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(2)
                while (!call.isCanceled() && !cleanup.isDone && System.nanoTime() < deadline) Thread.sleep(1)
                assertTrue("Retirement must cancel the delivered call", call.isCanceled())
                assertThrows(TimeoutException::class.java) { cleanup.get(100, TimeUnit.MILLISECONDS) }
                assertFalse("The wait bound preserves incomplete cleanup for retry", cleanup.get(2, TimeUnit.SECONDS))
                val retry = workers.submit<Boolean> { load.cancelAndAwait() }
                resumeRead.countDown()
                assertTrue("Cancellation interrupts the body read", reader.get(2, TimeUnit.SECONDS))
                assertTrue("The retry completes after the body terminates", retry.get(2, TimeUnit.SECONDS))

                val late = client.newCall(fixture.request("/late"))
                assertThrows(IOException::class.java) { late.execute().close() }
                assertTrue("Calls started after retirement cancel immediately", late.isCanceled())
            } finally {
                resumeRead.countDown()
                workers.shutdownNow()
            }
        }
    }

    @Test(timeout = 10000)
    fun largeSameOriginRedirectDoesNotCancelManualFollowup() {
        Fixture().use { fixture ->
            fixture.server.enqueue(response206(LARGE.size).setResponseCode(302).setHeader("Location", "/redirected"))
            fixture.server.enqueue(MockResponse().setBody("redirected"))
            val call = fixture.client().newCall(fixture.request("/redirect"))
            call.execute().use { response ->
                assertEquals(200, response.code)
                assertEquals("redirected", response.body!!.string())
            }
            assertFalse("Manual same-origin followup must not inherit cancellation", call.isCanceled())
            assertEquals("/redirect", fixture.takeRequest().path)
            assertEquals("/redirected", fixture.takeRequest().path)
        }
    }

    @Test(timeout = 10000)
    fun largeRetryable503DoesNotCancelOkHttpFollowup() {
        Fixture().use { fixture ->
            fixture.server.enqueue(response206(LARGE.size).setResponseCode(503).setHeader("Retry-After", "0"))
            fixture.server.enqueue(MockResponse().setBody("retried"))
            val call = fixture.client().newCall(fixture.request("/retry"))
            call.execute().use { response ->
                assertEquals(200, response.code)
                assertEquals("retried", response.body!!.string())
            }
            assertFalse("OkHttp retry must not inherit cancellation", call.isCanceled())
            assertEquals("/retry", fixture.takeRequest().path)
            assertEquals("/retry", fixture.takeRequest().path)
        }
    }

    private class Outcome : Callback {
        val done = CountDownLatch(1)
        @Volatile var failed = false
        @Volatile var body: String? = null
        override fun onFailure(call: Call, e: IOException) { failed = true; done.countDown() }
        override fun onResponse(call: Call, response: Response) {
            try { response.use { body = it.body!!.string() } }
            catch (_: IOException) { failed = true }
            finally { done.countDown() }
        }
    }

    private class Fixture : Closeable {
        val server = MockWebServer()
        private val pool = ConnectionPool()
        private val clients = mutableListOf<OkHttpClient>()
        private val clientCertificates: HandshakeCertificates
        init {
            val certificate = HeldCertificate.Builder().addSubjectAlternativeName("localhost").build()
            val serverCertificates = HandshakeCertificates.Builder().heldCertificate(certificate).build()
            clientCertificates = HandshakeCertificates.Builder().addTrustedCertificate(certificate.certificate).build()
            server.useHttps(serverCertificates.sslSocketFactory(), false)
            server.protocols = listOf(Protocol.HTTP_1_1)
            server.start(InetAddress.getLoopbackAddress(), 0)
        }
        fun client(
            candidate: Boolean = true,
            load: MediaHttp.Load = MediaHttp.forLoad(),
            configure: OkHttpClient.Builder.() -> Unit = {},
        ): OkHttpClient = load.client.newBuilder()
            .sslSocketFactory(clientCertificates.sslSocketFactory(), clientCertificates.trustManager)
            .connectionPool(pool)
            .protocols(listOf(Protocol.HTTP_1_1))
            .apply { if (!candidate) networkInterceptors().removeAll { it is CancelOnAbandon } }
            .apply(configure)
            .build().also {
                assertEquals(if (candidate) 1 else 0, it.networkInterceptors.count { interceptor -> interceptor is CancelOnAbandon })
                clients.add(it)
            }
        fun request(path: String): Request = Request.Builder().url(server.url(path)).build()
        fun takeRequest(): RecordedRequest = server.takeRequest(3, TimeUnit.SECONDS)
            ?: throw AssertionError("Expected local fixture request did not arrive")
        override fun close() {
            clients.forEach { it.dispatcher.cancelAll() }
            pool.evictAll()
            server.shutdown()
            clients.forEach { it.dispatcher.executorService.shutdownNow() }
        }
    }

    companion object {
        private const val LIMIT = 64 * 1024
        private const val FIRST_READ = 8192
        private const val PAYLOAD_BYTE = 42
        private val LARGE = ByteArray(2 * 1024 * 1024) { PAYLOAD_BYTE.toByte() }
        private fun median(values: List<Double>) = values.sorted()[values.size / 2]
        private fun response206(size: Int): MockResponse = MockResponse().setResponseCode(206)
            .setHeader("Content-Range", "bytes 0-${size - 1}/$size")
            .setBody(Buffer().write(LARGE, 0, size))
        private fun slow206(size: Int) = response206(size).throttleBody(FIRST_READ.toLong(), 1, TimeUnit.SECONDS)
    }
}
