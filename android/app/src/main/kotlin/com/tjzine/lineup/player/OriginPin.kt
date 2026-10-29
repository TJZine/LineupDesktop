package com.tjzine.lineup.player

import java.io.IOException
import okhttp3.HttpUrl
import okhttp3.Interceptor
import okhttp3.Response

/** Every HLS playlist, key, initialization and segment shares the validated load origin. */
internal class OriginPin(private val origin: HttpUrl) : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        if (!OriginPolicy.sameOrigin(origin, chain.request().url))
            throw IOException("unsafe_session_origin")
        return chain.proceed(chain.request())
    }
}
