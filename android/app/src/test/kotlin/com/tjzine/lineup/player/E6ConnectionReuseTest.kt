package com.tjzine.lineup.player

import android.net.Uri
import androidx.media3.datasource.DataSpec
import java.io.File
import java.net.InetAddress
import java.net.SocketTimeoutException
import java.security.KeyStore
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import javax.net.ssl.KeyManagerFactory
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLServerSocket
import javax.net.ssl.TrustManagerFactory
import javax.net.ssl.X509TrustManager
import okhttp3.ConnectionPool
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okio.buffer
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** Real localhost TLS: closing HTTP1.0 and persistent503 controls; synthetic material only. */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
class E6ConnectionReuseTest {
    @get:Rule val temporary = TemporaryFolder()

    private class Server(context: SSLContext, private val firstStatus: Int = 200,
        private val withholdErrorBody: Boolean = false) : AutoCloseable {
        private val socket = (context.serverSocketFactory.createServerSocket(0, 8,
            InetAddress.getByName("127.0.0.1")) as SSLServerSocket).apply { soTimeout = 100 }
        val port = socket.localPort
        val gets = AtomicInteger()
        val accepts = AtomicInteger()
        val firstClosed = CountDownLatch(1)
        val failure = AtomicReference<Throwable?>()
        @Volatile private var closed = false
        private val thread = Thread {
            try {
                while (!closed) {
                    val peer = try { socket.accept() } catch (_: SocketTimeoutException) { continue }
                    accepts.incrementAndGet()
                    peer.use {
                        it.soTimeout = 3000
                        val input = it.getInputStream()
                        requestLoop@ while (true) {
                            val header = StringBuilder()
                            while (!header.endsWith("\r\n\r\n")) {
                                val n = try { input.read() } catch (error: java.io.IOException) {
                                    // A rejected503 cancels the owned TLS call;
                                    // an abrupt close while awaiting another
                                    // request is expected, not a server fault.
                                    if (firstStatus == 503 && gets.get() == 1 && header.isEmpty() &&
                                        error !is SocketTimeoutException) break@requestLoop
                                    throw error
                                }
                                if (n < 0 && header.isEmpty()) break@requestLoop
                                check(n >= 0 && header.length < 8192)
                                header.append(n.toChar())
                            }
                            check(header.startsWith("GET "))
                            gets.incrementAndGet()
                            val status = if (gets.get() == 1) firstStatus else 200
                            val body = if (status != 200) ByteArray(0) else if (header.lineSequence().first().contains("index.m3u8"))
                                e6Playlist().toByteArray(Charsets.UTF_8) else ByteArray(32)
                            // Closing controls match Python's default HTTP1.0, fixed
                            // length and no Connection header. The503 control stays
                            // persistent to isolate follow-up counting from stale sockets.
                            val protocol = if (firstStatus == 503) "HTTP/1.1" else "HTTP/1.0"
                            val size = if (withholdErrorBody && status != 200) 65536 else body.size
                            val response = "$protocol $status Fixture\r\nContent-Type: application/octet-stream\r\n" +
                                (if (status == 503) "Retry-After: 0\r\n" else "") + "Content-Length: $size\r\n\r\n"
                            it.getOutputStream().write(response.toByteArray(Charsets.US_ASCII))
                            it.getOutputStream().write(body)
                            it.getOutputStream().flush()
                            if (firstStatus != 503 || status != 503) break
                        }
                    }
                    if (gets.get() == 1) firstClosed.countDown()
                }
            } catch (error: Throwable) { if (!closed) failure.set(error) }
        }.apply { isDaemon = true; name = "E6SyntheticClosingHttp"; start() }

        override fun close() {
            closed = true; socket.close(); thread.join(4000)
            assertFalse("owned loopback server thread must terminate", thread.isAlive)
            assertNull("synthetic server error", failure.get())
        }
    }

    private fun tls(): Pair<SSLContext, X509TrustManager> {
        // JDK17 is already a repository prerequisite. Generate a fresh localhost
        // certificate; no user key, shared trust store or external service is used.
        val store = File(temporary.newFolder(), "synthetic.p12")
        val keytool = File(System.getProperty("java.home"), "bin/keytool").absolutePath
        val output = File(store.parentFile, "keytool-output.txt")
        val process = ProcessBuilder(keytool, "-genkeypair", "-alias", "synthetic", "-keyalg", "RSA",
            "-keysize", "2048", "-storetype", "PKCS12", "-keystore", store.absolutePath,
            "-storepass", "synthetic-only", "-keypass", "synthetic-only", "-dname", "CN=localhost",
            "-ext", "SAN=dns:localhost,ip:127.0.0.1", "-validity", "2", "-noprompt")
            .redirectErrorStream(true).redirectOutput(output).start()
        if (!process.waitFor(10, TimeUnit.SECONDS)) {
            process.destroyForcibly(); process.waitFor(3, TimeUnit.SECONDS)
            fail("bounded synthetic certificate generation")
        }
        assertEquals(0, process.exitValue())
        assertTrue("bounded public keytool diagnostics", output.length() <= 4096)
        val keys = KeyStore.getInstance("PKCS12").apply {
            store.inputStream().use { load(it, "synthetic-only".toCharArray()) }
        }
        val km = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm()).apply {
            init(keys, "synthetic-only".toCharArray())
        }
        val tm = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm()).apply { init(keys) }
        val trust = tm.trustManagers.filterIsInstance<X509TrustManager>().single()
        return SSLContext.getInstance("TLS").apply { init(km.keyManagers, arrayOf(trust), null) } to trust
    }

    private fun read(guard: E6Http, client: OkHttpClient, uri: String) {
        val source = guard.factory(client).createDataSource()
        try {
            source.open(DataSpec(Uri.parse(uri)))
            val bytes = ByteArray(4096)
            while (source.read(bytes, 0, bytes.size) >= 0) { }
        } finally { source.close() }
    }

    @Test fun pooledNoRetryClientCanFailBeforeHeadersAfterHttp10PeerCloses() = scenario(false)

    @Test fun actualE6DebugClientUsesFreshConnectionWithoutRetryAndCountsBothGets() = scenario(true)

    @Test fun applicationGuardAloneMissesTheInternal503FollowupEvenWithRetryFalse() {
        val (context, trust) = tls()
        Server(context, 503).use { server ->
            val variant = "https://localhost:${server.port}/video/:/transcode/universal/session/synthetic/base/index.m3u8"
            val observation = e6Observer(e6Input(uri = variant)); val guard = E6Http(observation)
            val ordinary = MediaHttp.forLoad(variant.toHttpUrl()).newBuilder()
                .sslSocketFactory(context.socketFactory, trust).proxy(java.net.Proxy.NO_PROXY)
                .dns(object : okhttp3.Dns { override fun lookup(hostname: String) = listOf(InetAddress.getByName("127.0.0.1")) })
                .connectionPool(ConnectionPool()).build()
            // Pre-hardening zero-idle/application-only policy. A persistent
            // peer isolates the internal503 follow-up from the stale-close fault.
            val client = ordinary.newBuilder().connectionPool(ConnectionPool(0, 5, TimeUnit.MINUTES))
                .retryOnConnectionFailure(false).addInterceptor(guard).build()
            try {
                assertFalse(client.retryOnConnectionFailure)
                read(guard, client, variant)
                assertEquals(2, server.gets.get())
                assertEquals(1, guard.totals()["variantAttempts"])
                println("E6_FOLLOWUP_CONTROL retry=false serverGets=2 variantAttempts=1 hidden503Followup=true")
            } finally {
                guard.closeGate(); client.dispatcher.cancelAll(); client.connectionPool.evictAll()
                assertTrue(guard.awaitDrained(client, 1000)); client.dispatcher.executorService.shutdown()
            }
        }
    }

    @Test fun actualDebugClientRejectsFollowupAndRetains503And404Status() {
        val (context, trust) = tls()
        for (status in listOf(503, 404)) Server(context, status).use { server ->
            val variant = "https://localhost:${server.port}/video/:/transcode/universal/session/synthetic/base/index.m3u8"
            val observation = e6Observer(e6Input(uri = variant)); val guard = E6Http(observation)
            val ordinary = MediaHttp.forLoad(variant.toHttpUrl()).newBuilder()
                .sslSocketFactory(context.socketFactory, trust).proxy(java.net.Proxy.NO_PROXY)
                .dns(object : okhttp3.Dns { override fun lookup(hostname: String) = listOf(InetAddress.getByName("127.0.0.1")) })
                .connectionPool(ConnectionPool()).build()
            val client = guard.debugClient(ordinary)
            try {
                var failed = false
                try { read(guard, client, variant) } catch (_: java.io.IOException) { failed = true }
                assertTrue(failed); assertFalse(client.retryOnConnectionFailure)
                assertEquals(1, server.gets.get()); assertEquals(1, server.accepts.get())
                assertEquals(1, guard.totals()["variantAttempts"])
                val result = observation.drain()
                assertEquals(if (status == 404) "http_404" else "unexpected_status", result["failureCode"])
                val receipts = (result["events"] as List<Map<*, *>>).filter {
                    it["event"] == "http_result" && it["outcome"] == if (status == 404) "http_404" else "failed" }
                assertEquals(1, receipts.size); assertEquals(status, receipts.single()["status"])
                println("E6_FOLLOWUP_CONTROL policy=network_status_guard retry=false serverGets=1 variantAttempts=1 status=$status hiddenFollowup=false")
            } finally {
                guard.closeGate(); client.dispatcher.cancelAll(); client.connectionPool.evictAll()
                assertTrue(guard.awaitDrained(client, 1000)); client.dispatcher.executorService.shutdown()
            }
        }
    }

    @Test fun rejectedNonemptyResponseIsCancelledBeforeItsBodyCloseCanDiscard() {
        val (context, trust) = tls()
        Server(context, 503, withholdErrorBody = true).use { server ->
            val variant = "https://localhost:${server.port}/video/:/transcode/universal/session/synthetic/base/index.m3u8"
            val observation = e6Observer(e6Input(uri = variant)); val guard = E6Http(observation)
            val ordinary = MediaHttp.forLoad(variant.toHttpUrl()).newBuilder()
                .sslSocketFactory(context.socketFactory, trust).proxy(java.net.Proxy.NO_PROXY)
                .dns(object : okhttp3.Dns { override fun lookup(hostname: String) = listOf(InetAddress.getByName("127.0.0.1")) })
                .connectionPool(ConnectionPool()).build()
            val observedClose = java.util.concurrent.atomic.AtomicBoolean()
            val cancelledAtClose = java.util.concurrent.atomic.AtomicBoolean()
            // This inner test observer returns the real response/body and sees
            // the exact close called by the actual outer debug status guard.
            val client = guard.debugClient(ordinary).newBuilder().addNetworkInterceptor { chain ->
                val response = chain.proceed(chain.request())
                val body = response.body!!
                val source = object : okio.ForwardingSource(body.source()) {
                    override fun close() {
                        observedClose.set(true)
                        cancelledAtClose.set(chain.call().isCanceled())
                        super.close()
                    }
                }.let { it.buffer() }
                response.newBuilder().body(object : okhttp3.ResponseBody() {
                    override fun contentLength() = body.contentLength()
                    override fun contentType() = body.contentType()
                    override fun source() = source
                }).build()
            }.build()
            try {
                var failed = false
                try { read(guard, client, variant) } catch (_: java.io.IOException) { failed = true }
                assertTrue(failed); assertTrue(observedClose.get()); assertTrue(cancelledAtClose.get())
                assertEquals(1, server.gets.get()); assertEquals(1, guard.totals()["variantAttempts"])
                val result = observation.drain()
                assertEquals("unexpected_status", result["failureCode"])
                assertTrue((result["events"] as List<Map<*, *>>).any { it["event"] == "http_result" && it["status"] == 503 })
                println("E6_REJECT_CLOSE status=503 advertisedErrorBytes=65536 cancelledBeforeClose=true serverGets=1 variantAttempts=1")
            } finally {
                guard.closeGate(); client.dispatcher.cancelAll(); client.connectionPool.evictAll()
                assertTrue(guard.awaitDrained(client, 1000)); client.dispatcher.executorService.shutdown()
            }
        }
    }

    private fun scenario(noReuse: Boolean) {
        val (context, trust) = tls()
        Server(context).use { server ->
            val variant = "https://localhost:${server.port}/video/:/transcode/universal/session/synthetic/base/index.m3u8"
            val observation = e6Observer(e6Input(uri = variant))
            val guard = E6Http(observation)
            val ordinary = MediaHttp.forLoad(variant.toHttpUrl()).newBuilder()
                .sslSocketFactory(context.socketFactory, trust)
                .proxy(java.net.Proxy.NO_PROXY)
                .dns(object : okhttp3.Dns {
                    override fun lookup(hostname: String): List<InetAddress> {
                        check(hostname == "localhost")
                        return listOf(InetAddress.getByName("127.0.0.1"))
                    }
                })
                .connectionPool(ConnectionPool()).build()
            // Historical construction is a deliberate negative control, frozen
            // separately before the fix. The positive uses the engine's actual
            // E6 factory, including unchanged security guards and retry policy.
            val client = if (noReuse) guard.debugClient(ordinary) else ordinary.newBuilder()
                .retryOnConnectionFailure(false).addInterceptor(guard).build()
            try {
                assertFalse(client.retryOnConnectionFailure)
                assertEquals(ordinary.connectTimeoutMillis, client.connectTimeoutMillis)
                assertEquals(ordinary.readTimeoutMillis, client.readTimeoutMillis)
                assertEquals(ordinary.writeTimeoutMillis, client.writeTimeoutMillis)
                assertEquals(ordinary.callTimeoutMillis, client.callTimeoutMillis)
                assertEquals(ordinary.followRedirects, client.followRedirects)
                assertEquals(ordinary.followSslRedirects, client.followSslRedirects)
                assertEquals(ordinary.protocols, client.protocols)
                assertSame(ordinary.dispatcher, client.dispatcher)
                if (noReuse) assertNotSame(ordinary.connectionPool, client.connectionPool)
                read(guard, client, variant)
                assertTrue(server.firstClosed.await(3, TimeUnit.SECONDS))
                assertEquals(if (noReuse) 0 else 1, client.connectionPool.idleConnectionCount())
                var failed = false
                try { read(guard, client, variant.replace("index.m3u8", "init.mp4")) }
                catch (_: java.io.IOException) { failed = true }
                assertEquals("record actual peer-close behavior rather than manufacturing failure", !noReuse, failed)
                assertEquals(if (noReuse) 2 else 1, server.gets.get())
                assertEquals(if (noReuse) 2 else 1, server.accepts.get())
                assertEquals(1, guard.totals()["variantAttempts"]); assertEquals(1, guard.totals()["initAttempts"])
                val facts = observation.drain()["events"] as List<Map<*, *>>
                if (noReuse) {
                    assertTrue(facts.any { it["event"] == "http_result" && it["kind"] == "init" &&
                        it["outcome"] == "complete" && it["status"] == 200 && it["bytes"] == 32L })
                    assertFalse(facts.any { it["outcome"] == "failed" })
                    guard.closeGate()
                    var blocked = false
                    try { read(guard, client, variant.replace("index.m3u8", "0.m4s")) }
                    catch (_: java.io.IOException) { blocked = true }
                    assertTrue(blocked)
                    assertEquals(2, server.gets.get())
                    assertEquals(0, guard.totals()["mediaAttempts"])
                    println("E6_POOL_CONTROL policy=no_idle_reuse protocol=HTTP1.0 retry=false variantAttempts=1 initAttempts=1 serverGets=2 accepts=2 initPreHeadersFailed=false")
                } else {
                    assertTrue(facts.any { it["event"] == "http_result" && it["kind"] == "init" &&
                        it["outcome"] == "failed" && it["status"] == null && it["bytes"] == 0L })
                    println("E6_POOL_CONTROL policy=historical_pooled protocol=HTTP1.0 retry=false variantAttempts=1 initAttempts=1 serverGets=1 accepts=1 initPreHeadersFailed=true")
                }
            } finally {
                guard.closeGate(); client.dispatcher.cancelAll(); client.connectionPool.evictAll()
                assertTrue(guard.awaitDrained(client, 1000))
                client.dispatcher.executorService.shutdown()
            }
        }
    }
}
