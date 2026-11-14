package com.tjzine.lineup.player

import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.okhttp.OkHttpDataSource
import java.io.IOException
import java.io.InterruptedIOException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.FutureTask
import java.util.concurrent.TimeUnit
import okhttp3.Call
import okhttp3.Callback
import okhttp3.Response
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
class Media3HttpCancellationTest {
    @Test(timeout = 10000)
    fun interruptingOpenClosesAResponseDeliveredAfterCancellation() = verifyInterruptedOpen(false)

    @Test(timeout = 10000)
    fun interruptingOpenClosesAResponseDeliveredBeforeCancellation() = verifyInterruptedOpen(true)

    private fun verifyInterruptedOpen(deliverFirst: Boolean) {
        val certificate = HeldCertificate.Builder().addSubjectAlternativeName("localhost").build()
        val serverTls = HandshakeCertificates.Builder().heldCertificate(certificate).build()
        val clientTls = HandshakeCertificates.Builder().addTrustedCertificate(certificate.certificate).build()
        MockWebServer().use { server ->
            server.useHttps(serverTls.sslSocketFactory(), false)
            server.enqueue(MockResponse().setBody("x".repeat(128 * 1024)))
            val load = MediaHttp.forLoad()
            val client = load.client.newBuilder()
                .sslSocketFactory(clientTls.sslSocketFactory(), clientTls.trustManager)
                .build()
            val headers = CountDownLatch(1)
            val deliver = CountDownLatch(if (deliverFirst) 0 else 1)
            val delivered = CountDownLatch(1)
            val delayed = Call.Factory { request ->
                val call = client.newCall(request)
                object : Call by call {
                    override fun enqueue(responseCallback: Callback) {
                        call.enqueue(object : Callback {
                            override fun onResponse(call: Call, response: Response) {
                                headers.countDown()
                                try {
                                    check(deliver.await(5, TimeUnit.SECONDS))
                                    responseCallback.onResponse(call, response)
                                } finally {
                                    delivered.countDown()
                                }
                            }

                            override fun onFailure(call: Call, e: IOException) =
                                responseCallback.onFailure(call, e)
                        })
                        if (deliverFirst) {
                            // Interrupt before Media3 checks its now-ready future.
                            check(delivered.await(3, TimeUnit.SECONDS))
                            Thread.currentThread().interrupt()
                        }
                    }
                }
            }
            val source = OkHttpDataSource.Factory(Media3CallFactory(delayed)).createDataSource()
            val open = FutureTask {
                try {
                    source.open(DataSpec(android.net.Uri.parse(server.url("/media").toString())))
                    null
                } catch (error: IOException) {
                    error.cause
                } finally {
                    source.close()
                }
            }
            val loader = Thread(open).apply { start() }
            try {
                assertTrue("The response must already be in the callback", headers.await(3, TimeUnit.SECONDS))
                if (!deliverFirst) loader.interrupt()
                assertTrue(open.get(3, TimeUnit.SECONDS) is InterruptedIOException)
                deliver.countDown()
                assertTrue(delivered.await(2, TimeUnit.SECONDS))
                load.retire()
                assertTrue("The abandoned response must leave the retirement fence", load.cancelAndAwait())
            } finally {
                deliver.countDown()
                loader.interrupt()
                loader.join(2000)
            }
        }
    }
}
