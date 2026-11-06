package com.tjzine.lineup.player

import java.io.IOException
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.*
import org.junit.Test

class OriginPinTest {
    private val origin = "https://session.invalid:18443/base/index.m3u8".toHttpUrl()

    @Test
    fun everyPlaylistInitializationAndSegmentIsPinnedWithoutCredentials() {
        val requests = mutableListOf<Request>()
        val client = MediaHttp.forLoad(origin).client.newBuilder().addInterceptor { chain ->
            requests += chain.request()
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1)
                .code(200).message("OK").body("synthetic".toResponseBody()).build()
        }.build()
        assertTrue(client.interceptors[0] is OriginPin)
        assertTrue(client.interceptors[1] is OriginPolicy)
        for (path in listOf("index.m3u8", "init.mp4", "segment-0.m4s")) {
            client.newCall(Request.Builder().url(origin.resolve(path)!!).build()).execute().close()
        }
        assertEquals(3, requests.size)
        assertTrue(requests.all { it.header("X-Plex-Token") == null })
        for (uri in listOf(
            "https://other.invalid:18443/a.m4s", "https://session.invalid:18444/a.m4s",
            "http://session.invalid:18443/a.m4s", "https://u:p@session.invalid:18443/a.m4s",
            "https://session.invalid:18443/a.m4s?%58-pLeX-tOkEn=synthetic",
        )) {
            try {
                client.newCall(Request.Builder().url(uri).build()).execute().close()
                fail("unsafe origin reached terminal interceptor")
            } catch (error: IOException) {
                assertEquals("unsafe_session_origin", error.message)
            }
        }
        assertEquals(3, requests.size)
    }

    @Test
    fun sameOriginRedirectPassesAndCrossOriginHopIsRefusedBeforeRequest() {
        val requests = mutableListOf<Request>()
        var target = "https://session.invalid:18443/base/segment.m4s"
        val client = MediaHttp.forLoad(origin).client.newBuilder().addInterceptor { chain ->
            val request = chain.request()
            requests += request
            Response.Builder().request(request).protocol(Protocol.HTTP_1_1)
                .code(if (request.url == origin) 302 else 200).message("synthetic")
                .apply { if (request.url == origin) header("Location", target) }
                .body("".toResponseBody()).build()
        }.build()
        client.newCall(Request.Builder().url(origin).build()).execute().close()
        assertEquals(2, requests.size)
        target = "https://other.invalid:18443/segment.m4s"
        try {
            client.newCall(Request.Builder().url(origin).build()).execute().close()
            fail("off-origin redirect accepted")
        } catch (error: IOException) {
            assertEquals("unsafe_media_redirect", error.message)
        }
        assertEquals(3, requests.size)
        assertTrue(requests.all { it.url.host == origin.host && it.header("X-Plex-Token") == null })
    }
}
