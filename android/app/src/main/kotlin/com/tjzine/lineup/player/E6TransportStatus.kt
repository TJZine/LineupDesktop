package com.tjzine.lineup.player

import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.nio.file.StandardOpenOption
import org.json.JSONObject

/** Public diagnostic facts only. This owner never receives the socket's input bytes. */
internal class E6TransportStatus(cache: File, private val mode: String, private val pid: Int) {
    private val destination = File(cache, "e6-transport-status")
    private val temporary = File(cache, "e6-transport-status.tmp")
    private var received = 0L
    private var flushed = 0L
    private var attempted = false

    init {
        if (mode !in modes) throw E6Failure("invalid_probe")
        try {
            Files.deleteIfExists(destination.toPath())
            Files.deleteIfExists(temporary.toPath())
        } catch (_: Exception) { throw E6Failure("io_failure") }
    }

    @Synchronized fun store(raw: Any?) {
        val input = raw as? Map<*, *> ?: throw E6Failure("invalid_probe")
        if (input.keys != keys || input["mode"] != mode || input["phase"] !in phases)
            throw E6Failure("invalid_probe")
        val count = integer(input["receivedBytes"], 32768)
        val output = integer(input["flushedBytes"], 1024)
        val response = input["responseAttempted"] as? Boolean ?: throw E6Failure("invalid_probe")
        val failure = input["failureCode"]
        if (failure != null && failure !in failures || count < received || output < flushed ||
            attempted && !response || output > 0 && !response)
            throw E6Failure("invalid_probe")
        val record = JSONObject(linkedMapOf<String, Any>("protocol" to 1, "pid" to pid, "mode" to mode,
            "phase" to (input["phase"] as String), "receivedBytes" to count, "responseAttempted" to response,
            "flushedBytes" to output, "failureCode" to (failure ?: JSONObject.NULL)))
            .toString().toByteArray(Charsets.UTF_8)
        publish(destination, record, 512)
        received = count; flushed = output; attempted = response
    }

    companion object {
        val modes = setOf("eof", "line")
        val phases = setOf("starting", "waiting_resumed", "listening", "peer_accepted", "input_eof",
            "input_complete", "input_incomplete", "reply_attempt", "reply_flushed", "closed", "failed", "cancelled")
        val failures = setOf("invalid_probe", "input_cap", "extra_input", "peer_closed", "io_failure", "cancelled",
            "startup_deadline", "exchange_deadline", "output_cap")
        val keys = setOf("mode", "phase", "receivedBytes", "responseAttempted", "flushedBytes", "failureCode")

        /** Fixed native-owned public paths only; no path or bytes come from a socket. */
        internal fun publish(destination: File, bytes: ByteArray, maximum: Int) {
            if (bytes.size > maximum) throw E6Failure("output_cap")
            val temporary = File(destination.parentFile, destination.name + ".tmp")
            try {
                Files.deleteIfExists(temporary.toPath())
                // Sibling rename is atomic or the command fails; never rewrite
                // the observed file in place or use a non-atomic fallback.
                Files.write(temporary.toPath(), bytes, StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE)
                Files.move(temporary.toPath(), destination.toPath(), StandardCopyOption.ATOMIC_MOVE,
                    StandardCopyOption.REPLACE_EXISTING)
            } catch (_: Exception) { throw E6Failure("io_failure") }
            finally {
                try { Files.deleteIfExists(temporary.toPath()) } catch (_: Exception) { }
            }
        }

        private fun integer(value: Any?, maximum: Long): Long {
            val result = when (value) { is Int -> value.toLong(); is Long -> value; else -> throw E6Failure("invalid_probe") }
            if (result !in 0..maximum) throw E6Failure("invalid_probe")
            return result
        }
    }
}
