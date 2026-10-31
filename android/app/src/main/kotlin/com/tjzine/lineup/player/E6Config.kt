package com.tjzine.lineup.player

import java.io.IOException
import java.math.BigDecimal
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import org.json.JSONObject

/** In-memory capability. No URI, identifier or exception text is a fact. */
internal class E6Failure(val code: String) : IOException(code)

internal data class E6Config(
    val variant: HttpUrl,
    val offsetUs: Long,
    val seek: Boolean,
    val durationMs: Long,
    val video: String,
    val target: Int,
    val durationsUs: List<Long>,
    val baseline: Boolean,
) {
    val namespace: String = variant.encodedPath.substringBeforeLast('/') + "/"
    val public: Boolean = variant.host == "localhost" && variant.port == 21443
    override fun toString() = "E6Config()"

    fun reference(raw: String): HttpUrl {
        // Validate before HttpUrl can normalize dot segments or encoded separators.
        if (raw.isEmpty() || raw.length > 4096 || raw.any { it <= ' ' || it == '\\' || it == '%' } ||
            raw.contains('#') || raw.contains('?') || raw.split('/').any { it == "." || it == ".." })
            throw E6Failure("unsafe_reference")
        val resolved = variant.resolve(raw) ?: throw E6Failure("unsafe_reference")
        if (resolved.scheme != "https" || resolved.host != variant.host || resolved.port != variant.port ||
            resolved.username.isNotEmpty() || resolved.password.isNotEmpty() ||
            !resolved.encodedPath.startsWith(namespace) ||
            resolved.encodedPath.removePrefix(namespace).contains('/') ||
            resolved.encodedPath == variant.encodedPath)
            throw E6Failure("unsafe_reference")
        return resolved
    }

    companion object {
        val keys = setOf("variant", "offsetSeconds", "observeSeconds", "mode", "sourceDurationMs",
            "expectedVideoCodec", "expectedAudioCodec", "expectedTargetDurationSeconds",
            "expectedMediaSequence", "expectedDurationsSeconds")

        fun parse(raw: Any?, baseline: Boolean): E6Config {
            val map = raw as? Map<*, *> ?: throw E6Failure("invalid_config")
            if (map.keys != keys || JSONObject(map).toString().toByteArray(Charsets.UTF_8).size > 32768)
                throw E6Failure("invalid_config")
            val text = map["variant"] as? String ?: throw E6Failure("invalid_config")
            if (text.length > 4096 || text.any { it <= ' ' || it == '\\' || it == '%' } ||
                text.contains('?') || text.contains('#') || text.split('/').any { it == "." || it == ".." })
                throw E6Failure("unsafe_reference")
            val uri = text.toHttpUrlOrNull() ?: throw E6Failure("unsafe_reference")
            if (!uri.isHttps || uri.username.isNotEmpty() || uri.password.isNotEmpty())
                throw E6Failure("unsafe_reference")
            val local = uri.host == "localhost" && uri.port == 21443 &&
                uri.encodedPath in listOf("/e6-clock/index.m3u8", "/e6-hevc/index.m3u8")
            val privatePath = Regex("^/video/:/transcode/universal/session/[A-Za-z0-9_-]{1,256}/base/index\\.m3u8$")
                .matches(uri.encodedPath)
            if (!local && !privatePath) throw E6Failure("unsafe_reference")
            val mode = map["mode"] as? String ?: throw E6Failure("invalid_config")
            if (mode !in listOf("default", "seek_after_ready")) throw E6Failure("invalid_config")
            if (baseline && (text != "https://localhost:21443/e6-clock/index.m3u8" || mode != "default"))
                throw E6Failure("baseline_private_refused")
            val offset = micros(map["offsetSeconds"])
            if (offset !in listOf(0L, 9L, 10L, 19L, 21L, 605L).map { it * 1_000_000 })
                throw E6Failure("invalid_config")
            if (micros(map["observeSeconds"]) != 10_000_000L ||
                micros(map["expectedMediaSequence"]) != 0L || map["expectedAudioCodec"] != "aac")
                throw E6Failure("invalid_config")
            val duration = integer(map["sourceDurationMs"], 1, 43_200_000)
            val target = integer(map["expectedTargetDurationSeconds"], 1, 120).toInt()
            val video = map["expectedVideoCodec"] as? String ?: throw E6Failure("invalid_config")
            if (video !in listOf("h264", "hevc")) throw E6Failure("invalid_config")
            val rawDurations = map["expectedDurationsSeconds"] as? List<*> ?: throw E6Failure("invalid_config")
            if (rawDurations.isEmpty() || rawDurations.size > 10_000) throw E6Failure("invalid_config")
            val durations = rawDurations.map { micros(it).also { n ->
                if (n <= 0 || n > 120_000_000) throw E6Failure("invalid_config")
            } }
            if (kotlin.math.abs(durations.sum() - duration * 1000) > 1_000_000)
                throw E6Failure("invalid_config")
            return E6Config(uri, offset, mode == "seek_after_ready", duration, video, target, durations, baseline)
        }

        private fun integer(value: Any?, min: Long, max: Long): Long {
            val n = decimal(value)
            return try { n.longValueExact().also { if (it !in min..max) throw E6Failure("invalid_config") } }
            catch (_: ArithmeticException) { throw E6Failure("invalid_config") }
        }

        internal fun micros(value: Any?): Long = try {
            decimal(value).movePointRight(6).longValueExact()
        } catch (_: ArithmeticException) { throw E6Failure("invalid_config") }

        private fun decimal(value: Any?): BigDecimal {
            if (value !is Number || value.toString().length > 32) throw E6Failure("invalid_config")
            return try { BigDecimal(value.toString()) }
            catch (_: NumberFormatException) { throw E6Failure("invalid_config") }
        }
    }
}

internal data class E6Reference(val kind: String, val ordinal: Int?, val filenameIndex: Long?)

/** Parse only the approved finite single-variant scope, without changing the playlist. */
internal fun E6Config.playlist(bytes: ByteArray): Map<HttpUrl, E6Reference> {
    if (bytes.size > 1024 * 1024) throw E6Failure("response_byte_cap")
    val text = try {
        Charsets.UTF_8.newDecoder().onMalformedInput(java.nio.charset.CodingErrorAction.REPORT)
            .decode(java.nio.ByteBuffer.wrap(bytes)).toString()
    } catch (_: Exception) { throw E6Failure("playlist_scope") }
    val lines = text.lineSequence().map { it.trimEnd('\r') }.filter { it.isNotEmpty() }.toList()
    if (lines.firstOrNull() != "#EXTM3U") throw E6Failure("playlist_scope")
    var map: HttpUrl? = null
    var target: Int? = null
    var sequence: Long? = null
    var start: Long? = null
    var end = false
    var pending: Long? = null
    val durations = mutableListOf<Long>()
    val refs = linkedMapOf<HttpUrl, E6Reference>()
    for (line in lines.drop(1)) {
        when {
            line.startsWith("#EXT-X-TARGETDURATION:") -> {
                if (target != null) throw E6Failure("playlist_scope")
                target = line.substringAfter(':').toIntOrNull() ?: throw E6Failure("playlist_scope")
            }
            line.startsWith("#EXT-X-MEDIA-SEQUENCE:") -> {
                if (sequence != null) throw E6Failure("playlist_scope")
                sequence = line.substringAfter(':').toLongOrNull() ?: throw E6Failure("playlist_scope")
            }
            line.startsWith("#EXT-X-MAP:") -> {
                val match = Regex("#EXT-X-MAP:URI=\"([^\"]+)\"").matchEntire(line)
                    ?: throw E6Failure("playlist_scope")
                if (map != null) throw E6Failure("playlist_scope")
                map = reference(match.groupValues[1])
            }
            line.startsWith("#EXT-X-START:") -> {
                if (start != null) throw E6Failure("playlist_scope")
                val match = Regex("#EXT-X-START:TIME-OFFSET=([0-9]+(?:\\.[0-9]{1,6})?)")
                    .matchEntire(line) ?: throw E6Failure("playlist_scope")
                start = try { BigDecimal(match.groupValues[1]).movePointRight(6).longValueExact() }
                    catch (_: ArithmeticException) { throw E6Failure("playlist_scope") }
            }
            line.startsWith("#EXTINF:") -> {
                if (pending != null || end) throw E6Failure("playlist_scope")
                val match = Regex("#EXTINF:([0-9]+(?:\\.[0-9]{1,6})?),").matchEntire(line)
                    ?: throw E6Failure("playlist_scope")
                pending = try { BigDecimal(match.groupValues[1]).movePointRight(6).longValueExact() }
                    catch (_: ArithmeticException) { throw E6Failure("playlist_scope") }
            }
            line == "#EXT-X-ENDLIST" -> {
                if (end || pending != null) throw E6Failure("playlist_scope")
                end = true
            }
            line.startsWith("#EXT-X-VERSION:") -> {
                if (line.substringAfter(':').toIntOrNull() !in 1..10) throw E6Failure("playlist_scope")
            }
            line == "#EXT-X-PLAYLIST-TYPE:VOD" || line == "#EXT-X-INDEPENDENT-SEGMENTS" -> Unit
            line.startsWith('#') -> throw E6Failure("playlist_scope")
            else -> {
                val duration = pending ?: throw E6Failure("playlist_scope")
                if (map == null || duration <= 0 || duration > 120_000_000 || end || durations.size >= 10_000)
                    throw E6Failure("playlist_scope")
                val uri = reference(line)
                if (uri == map || refs.containsKey(uri)) throw E6Failure("playlist_scope")
                val basename = uri.pathSegments.last()
                val index = if (Regex("(?:0|[1-9][0-9]{0,17})\\.m4s").matches(basename))
                    basename.substringBefore('.').toLongOrNull() else null
                refs[uri] = E6Reference("media", durations.size, index)
                durations += duration
                pending = null
            }
        }
    }
    if (!end || map == null || pending != null || target != this.target || sequence != 0L ||
        (start ?: 0L) != offsetUs || durations != durationsUs)
        throw E6Failure("playlist_scope")
    refs[map] = E6Reference("init", null, null)
    return refs
}
