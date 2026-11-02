package com.tjzine.lineup.player

import okhttp3.Call
import okhttp3.Interceptor
import okhttp3.MediaType
import okhttp3.Response
import okhttp3.ResponseBody
import okio.Buffer
import okio.BufferedSource
import okio.ForwardingSource
import okio.buffer

/** Avoids HTTP/1's bounded drain when a large response cannot usefully be retained. */
internal class CancelOnAbandon : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val response = chain.proceed(chain.request())
        val body = response.body ?: return response
        val length = body.contentLength()
        // These bodies can be closed internally before a follow-up on the same
        // Call. Cancelling that Call would prevent redirects, authentication or
        // retries, so leave their existing close behavior intact.
        if (response.isRedirect || response.code in FOLLOW_UP_CODES || length <= MAX_REMAINDER) {
            return response
        }
        return response.newBuilder().body(AbandonableBody(body, length, chain.call())).build()
    }

    private class AbandonableBody(
        private val upstream: ResponseBody,
        private val length: Long,
        call: Call,
    ) : ResponseBody() {
        private val input = object : ForwardingSource(upstream.source()) {
            private var fetched = 0L

            override fun read(sink: Buffer, byteCount: Long): Long {
                val count = super.read(sink, byteCount)
                if (count > 0) fetched += count
                return count
            }

            override fun close() {
                // Count source bytes, including prefetch, rather than only bytes
                // delivered to the extractor. Already fetched bytes need no drain.
                if (length - fetched > MAX_REMAINDER) call.cancel()
                super.close()
            }
        }.buffer()

        override fun contentType(): MediaType? = upstream.contentType()
        override fun contentLength(): Long = length
        override fun source(): BufferedSource = input
    }

    companion object {
        private const val MAX_REMAINDER = 64L * 1024
        private val FOLLOW_UP_CODES = setOf(401, 407, 408, 421, 503)
    }
}
