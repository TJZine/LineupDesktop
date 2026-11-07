package com.tjzine.lineup.player

import java.util.concurrent.TimeUnit
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock
import okhttp3.Call
import okhttp3.Dispatcher
import okhttp3.EventListener
import okhttp3.HttpUrl
import okhttp3.OkHttpClient

/**
 * One application-scoped OkHttp base shares the connection pool and TLS socket
 * factory (session resumption) across loads. Each load derives its own client
 * with its own [Dispatcher], so retirement cancels only that load's calls.
 *
 * Pooled connections carry no credential: there is no client certificate, cookie
 * jar or authenticator, and the Plex token is a per-request header. A retired
 * load's in-flight calls are cancelled and fenced through body termination.
 * Idle connections remain reusable solely for the same TLS address.
 */
internal object MediaHttp {
    private val base: OkHttpClient by lazy { OkHttpClient() }

    fun forLoad(origin: HttpUrl? = null): Load = Load(origin)

    internal class Load(origin: HttpUrl?) {
        private val calls = LiveCalls()
        val client: OkHttpClient = base
            .newBuilder()
            .dispatcher(Dispatcher())
            .eventListener(calls)
            .followRedirects(false)
            .followSslRedirects(false)
            .apply { if (origin != null) addInterceptor(OriginPin(origin)) }
            .addInterceptor(OriginPolicy())
            .addNetworkInterceptor(CancelOnAbandon())
            .build()

        fun retire() = calls.retire()

        /** Runs on the cleanup executor. Keep this load for retry on failure. */
        fun cancelAndAwait(): Boolean = try {
            calls.snapshot().forEach(Call::cancel)
            client.dispatcher.cancelAll()
            calls.awaitEmpty()
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
            false
        } catch (_: Exception) {
            false
        }
    }

    // The dispatcher forgets asynchronous calls when onResponse returns. These
    // callbacks track the call through the Loader's subsequent body reads.
    private class LiveCalls : EventListener() {
        private val lock = ReentrantLock()
        private val drained = lock.newCondition()
        private val active = mutableSetOf<Call>()
        private var retired = false

        fun retire() = lock.withLock { retired = true }

        override fun callStart(call: Call) {
            val rejected = lock.withLock {
                if (retired) true else {
                    active.add(call)
                    false
                }
            }
            if (rejected) call.cancel()
        }

        override fun callEnd(call: Call) = finish(call)
        override fun callFailed(call: Call, ioe: java.io.IOException) = finish(call)

        private fun finish(call: Call) = lock.withLock {
            if (active.remove(call) && active.isEmpty()) drained.signalAll()
        }

        fun snapshot(): List<Call> = lock.withLock { active.toList() }

        fun awaitEmpty(): Boolean = lock.withLock {
            var remaining = TimeUnit.SECONDS.toNanos(1)
            while (active.isNotEmpty() && remaining > 0) {
                remaining = drained.awaitNanos(remaining)
            }
            active.isEmpty()
        }
    }
}
