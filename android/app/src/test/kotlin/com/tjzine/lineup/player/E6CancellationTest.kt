package com.tjzine.lineup.player

import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.media3.common.util.TimestampAdjuster
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import java.io.File
import java.io.IOException
import java.net.InetAddress
import java.net.SocketTimeoutException
import java.security.KeyStore
import java.time.Duration
import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import javax.net.ssl.KeyManagerFactory
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLServerSocket
import javax.net.ssl.SSLSocket
import javax.net.ssl.TrustManagerFactory
import javax.net.ssl.X509TrustManager
import okhttp3.Call
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

/** Actual E6 client/OkHttpDataSource against bounded synthetic localhost TLS. */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
class E6CancellationTest {
    @get:Rule val temporary = TemporaryFolder()

    private enum class Mode { HEADERS_HELD, BODY_HELD, DISCONNECT }

    private class Server(context: SSLContext, private val mode: Mode) : AutoCloseable {
        private val socket = (context.serverSocketFactory.createServerSocket(0, 8,
            InetAddress.getByName("127.0.0.1")) as SSLServerSocket).apply { soTimeout = 100 }
        val port = socket.localPort
        val mediaSeen = CountDownLatch(1)
        val release = CountDownLatch(1)
        val mediaGets = AtomicInteger()
        val gets = AtomicInteger()
        private val failure = AtomicReference<Throwable?>()
        private val peers = Collections.synchronizedList(mutableListOf<SSLSocket>())
        private val workers = Collections.synchronizedList(mutableListOf<Thread>())
        @Volatile private var closed = false
        private val acceptor = Thread {
            while (!closed) {
                val peer = try { socket.accept() as SSLSocket } catch (_: SocketTimeoutException) { continue }
                    catch (_: IOException) { break }
                peers += peer
                val worker = Thread {
                    try {
                        peer.use {
                            peer.soTimeout = 4000
                            val input = peer.inputStream
                            val header = StringBuilder()
                            while (!header.endsWith("\r\n\r\n")) {
                                val n = input.read()
                                check(n >= 0 && header.length < 8192)
                                header.append(n.toChar())
                            }
                            gets.incrementAndGet()
                            val media = header.lineSequence().first().contains("0.m4s")
                            val firstMedia = media && mediaGets.incrementAndGet() == 1
                            if (firstMedia && mode != Mode.BODY_HELD) {
                                mediaSeen.countDown()
                                if (mode == Mode.DISCONNECT) return@use
                                check(release.await(5, TimeUnit.SECONDS))
                            }
                            val body = if (header.lineSequence().first().contains("index.m3u8"))
                                e6Playlist().toByteArray() else ByteArray(32) { 7 }
                            val out = peer.outputStream
                            out.write(("HTTP/1.0 200 OK\r\nContent-Length: ${body.size}\r\n\r\n").toByteArray())
                            if (firstMedia && mode == Mode.BODY_HELD) {
                                out.write(body, 0, 4); out.flush(); mediaSeen.countDown()
                                check(release.await(5, TimeUnit.SECONDS))
                                out.write(body, 4, body.size - 4)
                            } else out.write(body)
                            out.flush()
                        }
                    } catch (_: IOException) {
                        // This fixture deliberately observes client cancellation.
                    } catch (error: Throwable) { failure.set(error) } finally { peers.remove(peer) }
                }.apply { isDaemon = true; name = "E6CancellationPeer"; start() }
                workers += worker
            }
        }.apply { isDaemon = true; name = "E6CancellationAccept"; start() }

        override fun close() {
            closed = true; release.countDown(); socket.close()
            synchronized(peers) { peers.toList() }.forEach { try { it.close() } catch (_: IOException) { } }
            acceptor.join(3000)
            synchronized(workers) { workers.toList() }.forEach { it.join(3000); assertFalse(it.isAlive) }
            assertFalse(acceptor.isAlive)
            assertNull("synthetic server failure", failure.get())
        }
    }

    private fun tls(): Pair<SSLContext, X509TrustManager> {
        val store = File(temporary.newFolder(), "synthetic.p12")
        val output = File(store.parentFile, "keytool-output.txt")
        val process = ProcessBuilder(File(System.getProperty("java.home"), "bin/keytool").absolutePath,
            "-genkeypair", "-alias", "synthetic", "-keyalg", "RSA", "-keysize", "2048", "-storetype", "PKCS12",
            "-keystore", store.absolutePath, "-storepass", "synthetic-only", "-keypass", "synthetic-only",
            "-dname", "CN=localhost", "-ext", "SAN=dns:localhost,ip:127.0.0.1", "-validity", "2", "-noprompt")
            .redirectErrorStream(true).redirectOutput(output).start()
        if (!process.waitFor(10, TimeUnit.SECONDS)) {
            process.destroyForcibly(); process.waitFor(3, TimeUnit.SECONDS); fail("bounded certificate generation")
        }
        assertEquals(0, process.exitValue()); assertTrue(output.length() <= 4096)
        val keys = KeyStore.getInstance("PKCS12").apply { store.inputStream().use { load(it, "synthetic-only".toCharArray()) } }
        val km = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm()).apply { init(keys, "synthetic-only".toCharArray()) }
        val tm = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm()).apply { init(keys) }
        val trust = tm.trustManagers.filterIsInstance<X509TrustManager>().single()
        return SSLContext.getInstance("TLS").apply { init(km.keyManagers, arrayOf(trust), null) } to trust
    }

    private class Fixture(val server: Server, context: SSLContext, trust: X509TrustManager,
        deadline: Long = Long.MAX_VALUE, seekMode: Boolean = true) : AutoCloseable {
        val variant = "https://localhost:${server.port}/video/:/transcode/universal/session/synthetic/base/index.m3u8"
        var clock = System.nanoTime()
        val observation = E6Observation(E6Config.parse(e6Input(seek = seekMode, uri = variant), false),
            Handler(Looper.getMainLooper()), 1, deadline) { clock }
        val guard = E6Http(observation)
        val mediaCall = AtomicReference<Call>()
        val client = guard.debugClient(MediaHttp.forLoad(variant.toHttpUrl()).newBuilder()
            .sslSocketFactory(context.socketFactory, trust).proxy(java.net.Proxy.NO_PROXY)
            .dns(object : okhttp3.Dns { override fun lookup(hostname: String) = listOf(InetAddress.getByName("127.0.0.1")) })
            .build()).newBuilder().addNetworkInterceptor { chain ->
                if (chain.request().url.encodedPath.endsWith("0.m4s")) mediaCall.set(chain.call())
                chain.proceed(chain.request())
            }.build()
        val player = E6Player().apply { positionMs = 1 }
        init { read("index.m3u8") }
        fun source(name: String): DataSource = guard.factory(client).createDataSource().also {
            it.open(DataSpec(Uri.parse(observation.config.reference(name).toString())))
        }
        fun read(name: String) {
            val source = guard.factory(client).createDataSource()
            try {
                source.open(DataSpec(Uri.parse(if (name == "index.m3u8") variant else observation.config.reference(name).toString())))
                val buffer = ByteArray(1024)
                while (source.read(buffer, 0, buffer.size) >= 0) { }
            } finally { source.close() }
        }
        fun seek() {
            observation.attach(player.player, guard) { client.dispatcher.cancelAll() }
            observation.ready(); assertTrue(observation.beforeSeek(0.0, true))
        }
        fun completeDefault() {
            player.positionMs = 0
            observation.attach(player.player, guard) { client.dispatcher.cancelAll() }
            observation.ready()
            val adjuster = TimestampAdjuster(0).also { it.adjustSampleTimestamp(10_000_000) }
            observation.bindAdjuster(adjuster)
            observation.outputChanged(5_000_000)
            observation.rendererReset()
            observation.frame(0, clock, 5_000_000, 5_000_000, 0, 0, true)
            val released = observation.beginRelease(0, clock)
            observation.endRelease(released, true)
            observation.renderedFirstFrame(1)
            shadowOf(Looper.getMainLooper()).idle()
            repeat(40) {
                clock += 250_000_000; player.positionMs += 250
                shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(250))
            }
            assertTrue(observation.terminal)
        }
        @Suppress("UNCHECKED_CAST") fun events() = observation.drain()["events"] as List<Map<String, Any?>>
        override fun close() {
            guard.closeGate(); client.dispatcher.cancelAll(); server.release.countDown()
            assertTrue(guard.awaitDrained(client, 2000))
            client.connectionPool.evictAll(); client.dispatcher.executorService.shutdown()
        }
    }

    private fun thread(action: () -> Unit): Pair<Thread, AtomicReference<Throwable?>> {
        val failure = AtomicReference<Throwable?>()
        return Thread { try { action() } catch (error: Throwable) { failure.set(error) } }
            .apply { isDaemon = true; name = "E6CancelledConsumer"; start() } to failure
    }

    @Test fun seekCancelsPreHeaderLoadAndOnlyNewEpochMayRequestAgain() {
        val (context, trust) = tls()
        Server(context, Mode.HEADERS_HELD).use { server -> Fixture(server, context, trust).use { f ->
            val (reader, error) = thread { f.read("0.m4s") }
            assertTrue(server.mediaSeen.await(3, TimeUnit.SECONDS))
            f.seek(); f.mediaCall.get().cancel(); reader.join(3000)
            assertFalse(reader.isAlive); assertTrue(error.get() is IOException); assertFalse(f.observation.terminal)
            val facts = f.events(); assertFalse(facts.any { it["event"] == "failure" })
            val cancelled = facts.single { it["event"] == "http_result" && it["outcome"] == "cancelled" }
            assertNull(cancelled["status"]); assertEquals(0L, cancelled["bytes"]); assertEquals(0L, cancelled["seekEpoch"])
            f.read("0.m4s")
            assertEquals(2, server.mediaGets.get()); assertEquals(2, f.guard.totals()["mediaAttempts"])
            assertFalse(f.events().any { it["event"] == "failure" })
        } }
    }

    @Test fun sameEpochCannotRepeatCancelledOrConsumerClosedUrl() {
        val (context, trust) = tls()
        for (consumerClose in listOf(false, true)) Server(context, if (consumerClose) Mode.BODY_HELD else Mode.HEADERS_HELD).use { server ->
            Fixture(server, context, trust).use { f ->
                if (consumerClose) {
                    val source = f.source("0.m4s")
                    assertEquals(4, source.read(ByteArray(4), 0, 4)); source.close()
                } else {
                    val (reader, _) = thread { f.read("0.m4s") }
                    assertTrue(server.mediaSeen.await(3, TimeUnit.SECONDS)); f.mediaCall.get().cancel(); reader.join(3000); assertFalse(reader.isAlive)
                }
                assertFalse(f.observation.terminal)
                val facts = f.events()
                assertEquals(if (consumerClose) "closed_early" else "cancelled", facts.last { it["event"] == "http_result" }["outcome"])
                try { f.read("0.m4s"); fail("same epoch must be refused") } catch (_: IOException) { }
                assertEquals("error_retry_refused", f.observation.drain()["failureCode"])
                assertEquals(1, server.mediaGets.get()); assertEquals(1, f.guard.totals()["mediaAttempts"])
            }
        }
    }

    @Test fun bodyReadCancellationCountsDeliveredBytesWithoutFailure() {
        val (context, trust) = tls()
        Server(context, Mode.BODY_HELD).use { server -> Fixture(server, context, trust).use { f ->
            val source = f.source("0.m4s")
            assertEquals(4, source.read(ByteArray(4), 0, 4))
            val (reader, error) = thread { source.read(ByteArray(32), 0, 32) }
            f.seek(); f.mediaCall.get().cancel(); reader.join(3000); source.close()
            assertFalse(reader.isAlive); assertTrue(error.get() is IOException); assertFalse(f.observation.terminal)
            val facts = f.events(); assertFalse(facts.any { it["event"] == "failure" })
            val end = facts.single { it["event"] == "http_result" && it["kind"] == "media" && it["outcome"] == "cancelled" }
            assertEquals(4L, end["bytes"]); assertEquals(0L, end["seekEpoch"])
            f.read("0.m4s"); assertEquals(2, server.mediaGets.get())
        } }
    }

    @Test fun cancellationObservedOnlyAtBodyCloseAndConsumerClosePermitNewEpoch() {
        val (context, trust) = tls()
        for (cancelled in listOf(false, true)) Server(context, Mode.BODY_HELD).use { server -> Fixture(server, context, trust).use { f ->
            val source = f.source("0.m4s")
            assertEquals(4, source.read(ByteArray(4), 0, 4))
            if (cancelled) f.mediaCall.get().cancel()
            source.close()
            assertFalse(f.observation.terminal)
            val end = f.events().last { it["event"] == "http_result" }
            assertEquals(if (cancelled) "cancelled" else "closed_early", end["outcome"])
            assertEquals(4L, end["bytes"])
            f.seek(); f.read("0.m4s")
            assertEquals(2, server.mediaGets.get()); assertFalse(f.events().any { it["event"] == "failure" })
        } }
    }

    @Test fun completedDefaultTeardownCancellationDoesNotCreateLateFailure() {
        val (context, trust) = tls()
        Server(context, Mode.HEADERS_HELD).use { server -> Fixture(server, context, trust, seekMode = false).use { f ->
            val (reader, _) = thread { f.read("0.m4s") }
            assertTrue(server.mediaSeen.await(3, TimeUnit.SECONDS))
            f.completeDefault(); f.mediaCall.get().cancel(); reader.join(3000)
            assertFalse(reader.isAlive)
            val drain = f.observation.drain()
            assertEquals("complete", drain["result"]); assertNull(drain["failureCode"])
            @Suppress("UNCHECKED_CAST")
            val facts = drain["events"] as List<Map<String, Any?>>
            assertFalse(facts.any { it["event"] == "failure" })
            assertEquals("cancelled", facts.last { it["event"] == "http_result" }["outcome"])
            assertTrue(f.guard.awaitDrained(f.client, 1000))
        } }
    }

    @Test fun realIoAndDeadlineAndUnfinishedRetirementRemainFatalAndDrain() {
        val (context, trust) = tls()
        for (mode in listOf("io", "deadline", "retire")) Server(context, if (mode == "io") Mode.DISCONNECT else Mode.HEADERS_HELD).use { server ->
            Fixture(server, context, trust, if (mode == "deadline") System.nanoTime() + TimeUnit.SECONDS.toNanos(3) else Long.MAX_VALUE).use { f ->
                val (reader, _) = thread { f.read("0.m4s") }
                assertTrue(server.mediaSeen.await(3, TimeUnit.SECONDS))
                if (mode == "retire") { f.guard.closeGate(); f.mediaCall.get().cancel() }
                reader.join(4000); assertFalse(reader.isAlive)
                assertTrue(f.observation.terminal)
                assertEquals(when (mode) { "io" -> "io_failure"; "deadline" -> "active_deadline"; else -> "cancelled" }, f.observation.drain()["failureCode"])
                assertTrue(f.guard.awaitDrained(f.client, 1000)); assertEquals(1, f.guard.totals()["mediaAttempts"])
            }
        }
    }
}
