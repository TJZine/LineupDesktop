package com.tjzine.lineup.player

import okhttp3.Dispatcher
import okhttp3.OkHttpClient

/**
 * One application-scoped OkHttp base shares the connection pool and TLS socket
 * factory (session resumption) across loads. Each load derives its own client
 * with its own [Dispatcher], so retirement cancels only that load's calls.
 *
 * Pooled connections carry no credential: there is no client certificate, cookie
 * jar or authenticator, and the Plex token is a per-request header. A retired
 * load's in-flight calls are cancelled (closing their sockets); only idle
 * connections remain, reusable solely for the same TLS address.
 */
internal object MediaHttp {
    private val base: OkHttpClient by lazy { OkHttpClient() }

    fun forLoad(): OkHttpClient =
        base
            .newBuilder()
            .dispatcher(Dispatcher())
            .followRedirects(false)
            .followSslRedirects(false)
            .addInterceptor(OriginPolicy())
            .build()
}
