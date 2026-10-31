package com.tjzine.lineup.player

import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.source.SinglePeriodTimeline
import java.lang.reflect.Proxy

internal fun e6Input(offset: Int = 0, seek: Boolean = false, uri: String = "https://localhost:21443/e6-clock/index.m3u8") =
    linkedMapOf<String, Any?>("variant" to uri, "offsetSeconds" to offset, "observeSeconds" to 10,
        "mode" to if (seek) "seek_after_ready" else "default", "sourceDurationMs" to 40_000,
        "expectedVideoCodec" to "h264", "expectedAudioCodec" to "aac", "expectedTargetDurationSeconds" to 10,
        "expectedMediaSequence" to 0, "expectedDurationsSeconds" to listOf(10, 10, 10, 10))

internal fun e6Playlist(offset: Int = 0, init: String = "init.mp4", media: List<String> = (0..3).map { "$it.m4s" }): String =
    "#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-TARGETDURATION:10\n#EXT-X-MEDIA-SEQUENCE:0\n" +
        (if (offset == 0) "" else "#EXT-X-START:TIME-OFFSET=$offset\n") +
        "#EXT-X-MAP:URI=\"$init\"\n" + media.joinToString("") { "#EXTINF:10.000000,\n$it\n" } + "#EXT-X-ENDLIST\n"

internal class E6Player {
    var positionMs = 0L
    var state = Player.STATE_READY
    var durationMs = 40_000L
    var timeline = SinglePeriodTimeline(40_000_000L, true, false, false, null, MediaItem.fromUri(Uri.EMPTY))
    val player = Proxy.newProxyInstance(Player::class.java.classLoader, arrayOf(Player::class.java)) { _, method, _ ->
        when (method.name) {
            "getCurrentPosition" -> positionMs
            "getDuration" -> durationMs
            "getBufferedPosition" -> 30_000L
            "getCurrentTimeline" -> timeline
            "getCurrentPeriodIndex", "getCurrentMediaItemIndex" -> 0
            "getPlaybackState" -> state
            "isPlaying" -> state == Player.STATE_READY
            "getApplicationLooper" -> Looper.getMainLooper()
            "toString" -> "E6Player"
            else -> when (method.returnType) { java.lang.Boolean.TYPE -> false; java.lang.Integer.TYPE -> 0;
                java.lang.Long.TYPE -> 0L; else -> null }
        }
    } as Player
}

internal fun e6Observer(input: Map<String, Any?> = e6Input(), baseline: Boolean = false) =
    E6Observation(E6Config.parse(input, baseline), Handler(Looper.getMainLooper()), 1)
