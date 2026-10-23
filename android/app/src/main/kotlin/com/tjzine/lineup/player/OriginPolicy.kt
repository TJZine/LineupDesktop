package com.tjzine.lineup.player

import java.io.IOException
import okhttp3.HttpUrl
import okhttp3.Interceptor
import okhttp3.Response

/** No automatic redirects, cookies, authenticators, or secondary scheme handlers. */
class OriginPolicy : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val original = chain.request()
        val origin = original.url
        if (
            !origin.isHttps ||
                origin.username.isNotEmpty() ||
                origin.password.isNotEmpty() ||
                origin.queryParameterNames.any { it.equals("X-Plex-Token", true) }
        ) {
            throw IOException("unsafe_media_origin")
        }
        var request = original
        repeat(6) { hop ->
            val response = chain.proceed(request)
            if (response.code !in listOf(301, 302, 303, 307, 308)) return response
            val target = response.header("Location")?.let { request.url.resolve(it) }
            response.close()
            if (target == null || !sameOrigin(origin, target) || hop == 5) {
                throw IOException("unsafe_media_redirect")
            }
            request = original.newBuilder().url(target).build()
        }
        throw IOException("redirect_limit")
    }

    companion object {
        fun sameOrigin(a: HttpUrl, b: HttpUrl): Boolean =
            b.isHttps &&
                a.scheme == b.scheme &&
                a.host == b.host &&
                a.port == b.port &&
                b.username.isEmpty() &&
                b.password.isEmpty() &&
                b.queryParameterNames.none { it.equals("X-Plex-Token", true) }
    }
}
