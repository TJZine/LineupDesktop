package com.tjzine.lineup.player

import org.json.JSONObject

/** Closed wire vocabulary shared with the debug collector. Never accept external strings here. */
internal object E6Facts {
    val enums = mapOf(
        "playlistScopeReason" to E6PlaylistScope.reasons,
        "playlistScopeTag" to (E6PlaylistScope.tags + "other_tag"),
        "event" to setOf("configured", "load", "ready", "frame_first", "rendered_first_frame",
            "position", "seek_request", "seek_ack", "seek_discontinuity", "renderer_reset",
            "output_change", "seek_result", "http_attempt", "http_result", "media_completed",
            "format", "release", "failure", "capabilities"),
        "mode" to setOf("default", "seek_after_ready"),
        "sourceClass" to setOf("h264", "hevc"),
        "playbackState" to setOf("idle", "buffering", "ready", "ended"),
        "kind" to setOf("variant", "init", "media"),
        "outcome" to setOf("headers", "complete", "closed_early", "http_404", "failed"),
        "videoCodec" to setOf("h264", "hevc", "unknown"),
        "audioCodec" to setOf("aac", "unknown"),
        "transfer" to setOf("sdr", "pq", "hlg", "unknown"),
        "decoderSupport" to setOf("supported", "unsupported", "unknown"),
        "abi" to setOf("arm64", "arm32", "x86_64", "x86", "unknown"),
        "clockDomain" to setOf("system_nano_time"),
        "seekResult" to setOf("seek_no_distance_no_new_epoch", "seek_landing_unconfirmed", "post_seek_frame_observed"),
        "failureCode" to setOf("invalid_config", "observer_disabled", "baseline_private_refused",
            "unexpected_load", "unsafe_reference", "playlist_scope", "request_budget", "response_byte_cap",
            "unexpected_status", "invalid_range", "error_retry_refused", "io_failure", "http_404",
            "cancelled", "active_deadline", "startup_deadline", "first_frame_deadline", "clock_bridge_unavailable",
            "clock_relation_invalid", "seek_contract", "event_overflow", "fact_schema", "output_mismatch",
            "video_decode_error", "audio_decode_error", "source_open_error", "playback_error", "release_failed"),
    )
    val booleans = setOf("sourceOriginProven", "playing", "bindingKnown", "clockKnown", "buffering",
        "rendererRelationValid", "renderedAssociated", "seekExact", "released", "playbackThreadAlive",
        "networkDrained", "firstMediaAttempt", "firstMediaHttpSuccess", "firstMediaCompleted",
        "firstPostSeekAttempt", "firstPostSeekHttpSuccess", "firstPostSeekCompleted", "rangePresent",
        "eof", "debugEnabled", "arm64", "h2641080", "aac", "hevcMain10", "hevc3840x1600",
        "baseline", "noErrorRetry", "hlsOffsetInitialized", "late", "decoderHardware")
    val numbers = setOf("playlistScopeIndex", "monoNs", "runOrdinal", "requestedOffsetUs", "seekEpoch", "commandSeekEpoch", "outputEpoch", "frameEpoch",
        "callbackPtsUs", "releaseTimeNs", "callbackMonoNs", "rendererOffsetUs", "hlsOffsetUs", "decoderBufferUs",
        "extractorPtsUs", "extractorRequestedDeltaUs", "hypothesisSourceUs", "hypothesisRequestedDeltaUs",
        "frameWindowUs", "frameWindowPositionDeltaUs", "extractorPositionDeltaUs", "hypothesisPositionDeltaUs",
        "frameAgeNs", "snapshotLagNs", "positionMs", "durationMs", "bufferedPositionMs", "windowIndex", "periodIndex",
        "periodPositionInWindowUs", "periodPositionUs", "windowDefaultPositionUs", "windowPositionInFirstPeriodUs",
        "windowDurationUs", "sampleIndex", "sampleDueNs", "renderedCallbackNs", "seekTargetUs", "seekPositionMs",
        "seekRequestNs", "attempt", "ordinal", "filenameIndex", "mediaSequence", "status", "bytes", "totalBytes",
        "rangeStart", "rangeEnd", "contentRangeStart", "contentRangeEnd", "contentRangeTotal", "activeCalls",
        "variantAttempts", "initAttempts", "mediaAttempts", "width", "height", "apiLevel", "decoderInitDurationMs",
        "returnedStartUs", "playlistDurationUs", "targetDurationSeconds", "callbacks", "releaseElapsedRealtimeMs")

    fun valid(value: Map<String, Any?>): Boolean = value["event"] in enums.getValue("event") &&
        value.all { (key, item) ->
            when {
                key in enums -> item == null || item is String && item in enums.getValue(key)
                key in booleans -> item == null || item is Boolean
                key in numbers -> item == null || item is Byte || item is Short || item is Int || item is Long
                else -> false
            }
        }
}

/** Lifetime accounting survives drain; draining cannot reset either output budget. */
internal class E6FactQueue {
    private val pending = mutableListOf<Map<String, Any?>>()
    private var count = 0
    private var bytes = 0

    @Synchronized fun add(value: Map<String, Any?>) {
        if (!E6Facts.valid(value)) throw E6Failure("fact_schema")
        val size = JSONObject(value).toString().toByteArray(Charsets.UTF_8).size
        // Leave room in the socket's 1MiB bound for ACK/envelope/terminal records.
        val eventLimit = if (value["event"] == "release") 299 else 298
        if (size > 15 * 1024 || count >= eventLimit || bytes + size > 960 * 1024)
            throw E6Failure("event_overflow")
        pending += value.toMap()
        count++
        bytes += size
    }

    @Synchronized fun drain(): List<Map<String, Any?>> = pending.toList().also { pending.clear() }
}
