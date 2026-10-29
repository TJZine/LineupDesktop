package com.tjzine.lineup.player

import okhttp3.Authenticator
import okhttp3.CookieJar
import org.junit.Assert.*
import org.junit.Test

class PlaybackMemoryTest {
    private val gib = 1024L * 1024 * 1024

    @Test
    fun ordinaryDevicesKeepMedia3TrackBasedDefault() {
        assertNull(PlaybackMemory.targetBufferBytes(false, 4 * gib, 256))
        assertNull(PlaybackMemory.targetBufferBytes(false, 2 * gib, 192))
    }

    @Test
    fun lowRamDevicesAreCappedWithinTheirHeapClass() {
        // Fire TV Stick 4K Max: ~1.7 GB total memory, not flagged isLowRamDevice.
        val stick = (1.7 * 1_000_000_000).toLong()
        assertEquals(48 * 1024 * 1024, PlaybackMemory.targetBufferBytes(false, stick, 256))
        assertEquals(48 * 1024 * 1024, PlaybackMemory.targetBufferBytes(true, 4 * gib, 256))
        // A small heap class halves the cap rather than exceeding the heap.
        assertEquals(40 * 1024 * 1024, PlaybackMemory.targetBufferBytes(true, gib, 80))
        // Never below Media3's own minimum target.
        assertEquals(13_107_200, PlaybackMemory.targetBufferBytes(true, gib, 16))
    }

    @Test
    fun perLoadClientsShareTransportButNotPolicyOrCancellation() {
        val first = MediaHttp.forLoad()
        val second = MediaHttp.forLoad()
        for (client in listOf(first, second)) {
            assertFalse(client.followRedirects)
            assertFalse(client.followSslRedirects)
            assertEquals(1, client.interceptors.count { it is OriginPolicy })
            assertEquals(1, client.interceptors.size)
            assertTrue(client.networkInterceptors.isEmpty())
            assertSame(CookieJar.NO_COOKIES, client.cookieJar)
            assertSame(Authenticator.NONE, client.authenticator)
            assertSame(Authenticator.NONE, client.proxyAuthenticator)
        }
        // Each load owns its own interceptor instance and dispatcher (cancelAll scope).
        assertNotSame(first.interceptors.single(), second.interceptors.single())
        assertNotSame(first.dispatcher, second.dispatcher)
        // Connections and TLS sessions are shared.
        assertSame(first.connectionPool, second.connectionPool)
        assertSame(first.sslSocketFactory, second.sslSocketFactory)
    }
}
