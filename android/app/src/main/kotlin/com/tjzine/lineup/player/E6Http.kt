package com.tjzine.lineup.player

import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy
import androidx.media3.exoplayer.upstream.LoadErrorHandlingPolicy
import java.io.IOException
import java.util.IdentityHashMap
import java.util.Collections
import okhttp3.Call
import okhttp3.HttpUrl
import okhttp3.Interceptor
import okhttp3.Response
import okhttp3.ResponseBody
import okhttp3.ResponseBody.Companion.toResponseBody
import okio.BufferedSource
import okio.ForwardingSource
import okio.buffer

/** Private debug scope only. Production MediaHttp and Media3 retry policy are untouched. */
@UnstableApi
internal class E6NoRetry : DefaultLoadErrorHandlingPolicy(0) {
    override fun getRetryDelayMsFor(info: LoadErrorHandlingPolicy.LoadErrorInfo): Long = C.TIME_UNSET
    override fun getFallbackSelectionFor(
        options: LoadErrorHandlingPolicy.FallbackOptions,
        info: LoadErrorHandlingPolicy.LoadErrorInfo,
    ): LoadErrorHandlingPolicy.FallbackSelection? = null
}

@UnstableApi
internal class E6Http(private val observation: E6Observation) : Interceptor {
    private val config = observation.config
    private val references = linkedMapOf(config.variant to E6Reference("variant", null, null))
    private val failures = mutableSetOf<HttpUrl>()
    private val successfulEpoch = mutableMapOf<HttpUrl, Long>()
    private val calls = IdentityHashMap<Call, Boolean>()
    private val unconfirmedClose = Collections.newSetFromMap(IdentityHashMap<Call, Boolean>())
    private val attempts = mutableMapOf("variant" to 0, "init" to 0, "media" to 0)
    private var totalBytes = 0L
    private var reservedBytes = 0L
    private var count = 0
    private var open = true
    private var firstAttempt = false
    private var firstHttp = false
    private var firstCompleted = false
    private var firstSeekAttempt = false
    private var firstSeekHttp = false
    private var firstSeekCompleted = false
    private data class Completed(val uri: HttpUrl, val ticket: Ticket, val startMs: Long, val endMs: Long)
    private val completed = mutableListOf<Completed>()

    @Synchronized fun closeGate() { open = false }
    @Synchronized fun activeCalls(): Int = calls.size
    @Synchronized fun isOpen(): Boolean = open
    @Synchronized fun totals(): Map<String, Any?> = mapOf("totalBytes" to totalBytes, "activeCalls" to calls.size,
        "variantAttempts" to attempts.getValue("variant"), "initAttempts" to attempts.getValue("init"),
        "mediaAttempts" to attempts.getValue("media"))

    /** Cancel acceptance is insufficient: an HTTP body can outlive its dispatcher callback. */
    fun awaitDrained(client: okhttp3.OkHttpClient?, timeoutMs: Long = 5000): Boolean {
        val deadline = System.nanoTime() + timeoutMs * 1_000_000
        fun drained() = activeCalls() == 0 && (client?.dispatcher?.runningCallsCount() ?: 0) == 0 &&
            (client?.dispatcher?.queuedCallsCount() ?: 0) == 0
        while (!drained() && System.nanoTime() < deadline) Thread.sleep(5)
        return drained()
    }

    fun factory(client: okhttp3.OkHttpClient): DataSource.Factory {
        return DataSource.Factory {
            var openingSpec: RequestSpec? = null
            // OkHttpDataSource enqueues asynchronously. Bind the actual DataSpec
            // before enqueue; a ThreadLocal in intercept() would lose that origin.
            val delegate = OkHttpDataSource.Factory(Call.Factory { request ->
                observation.requireActive()
                val real = openingSpec ?: throw E6Failure("unsafe_reference")
                client.newCall(request.newBuilder().tag(RequestSpec::class.java, real).build()).also { call ->
                    if (observation.deadlineNs != Long.MAX_VALUE) call.timeout().deadlineNanoTime(observation.deadlineNs)
                }
            }).createDataSource()
            object : DataSource by delegate {
                override fun open(dataSpec: DataSpec): Long {
                    if (dataSpec.httpMethod != DataSpec.HTTP_METHOD_GET || dataSpec.httpBody != null)
                        throw E6Failure("unsafe_reference")
                    val epoch = observation.seekEpoch
                    observation.loaderOpened(epoch)
                    openingSpec = RequestSpec(dataSpec, epoch)
                    return try { delegate.open(dataSpec) } finally { openingSpec = null }
                }
            }
        }
    }

    private data class RequestSpec(val data: DataSpec, val epoch: Long)

    private data class Ticket(
        val reference: E6Reference,
        val epoch: Long,
        val attempt: Int,
        val rangeStart: Long?,
        val rangeEnd: Long?,
        val first: Boolean,
        val firstSeek: Boolean,
        val startMs: Long,
    ) { var finalized = false }

    @Synchronized private fun authorize(chain: Interceptor.Chain): Ticket {
        observation.requireActive()
        if (!open || observation.terminal) throw E6Failure("cancelled")
        val request = chain.request()
        val tagged = request.tag(RequestSpec::class.java) ?: throw E6Failure("unsafe_reference")
        val data = tagged.data
        val raw = data.uri.toString()
        if (raw != request.url.toString() || raw.any { it <= ' ' || it == '\\' || it == '%' } ||
            request.method != "GET" || request.headers.names().any {
                it.equals("authorization", true) || it.equals("cookie", true) || it.equals("X-Plex-Token", true)
            }) throw E6Failure("unsafe_reference")
        val reference = references[request.url] ?: throw E6Failure("unsafe_reference")
        if (reference.kind == "variant" && (data.position != 0L || data.length != C.LENGTH_UNSET.toLong()))
            throw E6Failure("invalid_range")
        if (request.url in failures) throw E6Failure("error_retry_refused")
        val epoch = tagged.epoch
        if (reference.kind == "media" && successfulEpoch[request.url]?.let { it >= epoch } == true)
            throw E6Failure("error_retry_refused")
        val limit = when (reference.kind) { "media" -> 16; else -> 2 }
        if (count >= 20 || attempts.getValue(reference.kind) >= limit) throw E6Failure("request_budget")
        val start = data.position
        val end = if (data.length == C.LENGTH_UNSET.toLong()) null else try {
            Math.addExact(start, data.length - 1)
        } catch (_: ArithmeticException) { throw E6Failure("invalid_range") }
        if (start < 0 || data.length == 0L || end != null && end < start) throw E6Failure("invalid_range")
        val range = if (start == 0L && end == null) null else "bytes=$start-${end ?: ""}"
        if (request.header("Range") != range) throw E6Failure("invalid_range")
        val first = reference.kind == "media" && !firstAttempt
        val firstSeek = reference.kind == "media" && epoch > 0 && !firstSeekAttempt
        if (reference.kind == "media") firstAttempt = true
        if (firstSeek) firstSeekAttempt = true
        count++
        attempts[reference.kind] = attempts.getValue(reference.kind) + 1
        calls[chain.call()] = true
        return Ticket(reference, epoch, count, if (range == null) null else start, end, first, firstSeek,
            android.os.SystemClock.elapsedRealtime())
    }

    private fun facts(ticket: Ticket) = linkedMapOf<String, Any?>(
        "kind" to ticket.reference.kind, "attempt" to ticket.attempt,
        "ordinal" to ticket.reference.ordinal, "filenameIndex" to ticket.reference.filenameIndex,
        "mediaSequence" to ticket.reference.ordinal, "seekEpoch" to ticket.epoch,
        "rangePresent" to (ticket.rangeStart != null), "rangeStart" to ticket.rangeStart,
        "rangeEnd" to ticket.rangeEnd,
    )

    private fun receipt(ticket: Ticket, status: Int?, outcome: String, bytes: Long, eof: Boolean = false) {
        val counts = synchronized(this) {
            if (ticket.finalized) return
            ticket.finalized = true
            totals()
        }
        observation.emit("http_result", facts(ticket) + counts + mapOf("status" to status,
            "outcome" to outcome, "bytes" to bytes, "eof" to eof))
    }

    override fun intercept(chain: Interceptor.Chain): Response {
        val ticket = try { authorize(chain) } catch (error: E6Failure) {
            observation.fail(error.code); throw error
        }
        observation.emit("http_attempt", facts(ticket) + mapOf(
            "firstMediaAttempt" to ticket.first, "firstPostSeekAttempt" to ticket.firstSeek,
        ))
        var response: Response? = null
        try {
            if (!isOpen() || observation.terminal) throw E6Failure("cancelled")
            response = chain.proceed(chain.request())
            val headers = facts(ticket) + mapOf("status" to response.code, "outcome" to "headers")
            if (response.code !in listOf(200, 206)) {
                throw E6Failure(if (response.code == 404) "http_404" else "unexpected_status")
            }
            val rangeFacts = validateResponseRange(response, ticket)
            val httpFirst: Boolean
            val seekHttpFirst: Boolean
            synchronized(this) {
                httpFirst = ticket.reference.kind == "media" && !firstHttp
                seekHttpFirst = ticket.reference.kind == "media" && ticket.epoch > 0 && !firstSeekHttp
                if (ticket.reference.kind == "media") firstHttp = true
                if (seekHttpFirst) firstSeekHttp = true
            }
            observation.emit("http_result", headers + rangeFacts + mapOf(
                "firstMediaHttpSuccess" to httpFirst, "firstPostSeekHttpSuccess" to seekHttpFirst,
            ))
            val body = response.body ?: throw E6Failure("io_failure")
            val cap = when (ticket.reference.kind) { "variant" -> 1024L * 1024; "init" -> 16L * 1024 * 1024; else -> 128L * 1024 * 1024 }
            if (body.contentLength() > cap) throw E6Failure("response_byte_cap")
            val wrapped = boundedBody(body, cap, ticket, chain.call(), chain.request().url, response.code)
            if (ticket.reference.kind == "variant") {
                val bytes = wrapped.use { it.bytes() }
                val parsed = config.playlist(bytes)
                synchronized(this) {
                    if (references.size > 1 && references.filterValues { it.kind != "variant" } != parsed)
                        throw E6Failure("playlist_scope")
                    references.putAll(parsed)
                }
                observation.emit("load", mapOf("returnedStartUs" to config.offsetUs,
                    "playlistDurationUs" to config.durationsUs.sum(), "targetDurationSeconds" to config.target))
                return response.newBuilder().body(bytes.toResponseBody(body.contentType())).build()
            }
            return response.newBuilder().body(wrapped).build()
        } catch (error: Exception) {
            try { response?.close() } catch (_: Exception) { synchronized(this) { unconfirmedClose += chain.call() } }
            synchronized(this) {
                failures += chain.request().url
            }
            val code = (error as? E6Failure)?.code ?: "io_failure"
            try {
                receipt(ticket, response?.code, if (response?.code == 404) "http_404" else "failed", 0)
            } finally {
                synchronized(this) { if (chain.call() !in unconfirmedClose) calls.remove(chain.call()) }
            }
            observation.fail(code)
            throw E6Failure(code)
        }
    }

    private fun validateResponseRange(response: Response, ticket: Ticket): Map<String, Any?> {
        if (response.code == 200) {
            if (response.header("Content-Range") != null) throw E6Failure("invalid_range")
            return emptyMap()
        }
        if (ticket.rangeStart == null) throw E6Failure("invalid_range")
        val m = Regex("bytes ([0-9]{1,18})-([0-9]{1,18})/([0-9]{1,18})")
            .matchEntire(response.header("Content-Range") ?: "") ?: throw E6Failure("invalid_range")
        val start = m.groupValues[1].toLong()
        val end = m.groupValues[2].toLong()
        val total = m.groupValues[3].toLong()
        if (start != ticket.rangeStart || end < start || end >= total ||
            ticket.rangeEnd != null && end > ticket.rangeEnd ||
            response.body?.contentLength()?.let { it >= 0 && it != end - start + 1 } == true)
            throw E6Failure("invalid_range")
        return mapOf("contentRangeStart" to start, "contentRangeEnd" to end, "contentRangeTotal" to total)
    }

    private fun boundedBody(body: ResponseBody, cap: Long, ticket: Ticket, call: Call, uri: HttpUrl, status: Int): ResponseBody {
        var bytes = 0L
        var eof = false
        var finished = false
        var failed = false
        val expected = body.contentLength()
        val stream = object : ForwardingSource(body.source()) {
            override fun read(sink: okio.Buffer, byteCount: Long): Long {
                observation.requireActive()
                if (byteCount == 0L) return 0
                val allowed = try { synchronized(this@E6Http) {
                    if (!open || observation.terminal) throw E6Failure("cancelled")
                    minOf(byteCount, cap - bytes, 512L * 1024 * 1024 - totalBytes - reservedBytes)
                        .also { if (it <= 0 && expected != bytes) throw E6Failure("response_byte_cap"); reservedBytes += it }
                } } catch (error: E6Failure) { observation.fail(error.code); throw error }
                if (allowed == 0L && expected == bytes) { eof = true; return -1 }
                val n: Long
                try { n = super.read(sink, allowed) } catch (error: Exception) {
                    failed = true
                    synchronized(this@E6Http) { reservedBytes -= allowed; failures += uri }
                    observation.fail((error as? E6Failure)?.code ?: "io_failure")
                    throw E6Failure((error as? E6Failure)?.code ?: "io_failure")
                }
                synchronized(this@E6Http) {
                    reservedBytes -= allowed
                    if (n > 0) { totalBytes += n; bytes += n }
                    if (n < 0) eof = true
                }
                if (n < 0 && expected >= 0 && bytes != expected) {
                    failed = true
                    observation.fail("io_failure"); throw E6Failure("io_failure")
                }
                return n
            }

            override fun close() {
                if (finished) return
                finished = true
                var closed = false
                try { super.close(); closed = true } catch (_: Exception) {
                    failed = true
                    observation.fail("io_failure")
                    throw E6Failure("io_failure")
                } finally {
                    val complete = !failed && (eof || expected >= 0 && bytes == expected)
                    synchronized(this@E6Http) {
                        if (!closed) unconfirmedClose += call
                        if (complete) successfulEpoch[uri] = ticket.epoch else failures += uri
                        if (complete && ticket.reference.kind == "media") completed +=
                            Completed(uri, ticket, ticket.startMs, android.os.SystemClock.elapsedRealtime())
                    }
                    try {
                        receipt(ticket, status, if (failed) "failed" else if (complete) "complete" else "closed_early", bytes, eof)
                    } finally {
                        // Ownership fences the final fact callback as well as
                        // the socket/body close. Dispatcher completion alone
                        // cannot make a later receipt safe to omit from drain.
                        if (closed) synchronized(this@E6Http) { calls.remove(call) }
                    }
                }
            }
        }.buffer()
        return object : ResponseBody() {
            override fun contentType() = body.contentType()
            override fun contentLength() = expected
            override fun source(): BufferedSource = stream
        }
    }

    fun loadCompleted(uri: android.net.Uri, elapsedRealtimeMs: Long, loadDurationMs: Long) {
        val reference: E6Reference
        val first: Boolean
        val firstSeek: Boolean
        val phase: Long?
        synchronized(this) {
            reference = references.entries.firstOrNull { it.key.toString() == uri.toString() }?.value ?: return
            if (reference.kind != "media") return
            // Media3's callback can wait on the application Looper across seek.
            // Match its real load interval in the elapsedRealtime domain to an
            // immutable HTTP phase; never label it from the current seek epoch.
            val candidates = completed.filter { it.uri.toString() == uri.toString() &&
                it.startMs >= elapsedRealtimeMs - loadDurationMs && it.endMs <= elapsedRealtimeMs }
            val matched = candidates.singleOrNull()
            phase = matched?.ticket?.epoch
            if (matched != null) completed.remove(matched)
            first = !firstCompleted
            firstSeek = phase != null && phase > 0 && !firstSeekCompleted
            firstCompleted = true
            if (firstSeek) firstSeekCompleted = true
        }
        observation.emit("media_completed", mapOf("ordinal" to reference.ordinal,
            "filenameIndex" to reference.filenameIndex, "mediaSequence" to reference.ordinal,
            "firstMediaCompleted" to first, "firstPostSeekCompleted" to firstSeek,
            "seekEpoch" to phase, "bindingKnown" to (phase != null)))
    }
}
