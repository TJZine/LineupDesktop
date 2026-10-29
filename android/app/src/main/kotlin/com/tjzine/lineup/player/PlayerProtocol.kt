package com.tjzine.lineup.player

import java.net.URI

/** Values cross the Flutter codec only here; engine and callbacks receive validated values. */
internal class ProtocolError(val code: String) : Exception(code)

internal data class MediaLoad(
    val uri: String,
    val loadId: Long,
    val token: String?,
    val paused: Boolean,
    val startSeconds: Double,
) {
    val credentialBytes
        get() =
            uri.toByteArray(Charsets.UTF_8).size +
                (token?.let { it.length + "X-Plex-Token: ".length } ?: 0)

    // Never expose the generated data-class toString (which would contain credentials).
    override fun toString() = "MediaLoad(loadId=$loadId)"
}

internal data class VideoRect(
    val left: Double,
    val top: Double,
    val width: Double,
    val height: Double,
    val scale: Double,
)

internal sealed interface PlayerCommand {
    data class Load(val media: MediaLoad) : PlayerCommand

    data object Play : PlayerCommand

    data object Pause : PlayerCommand

    data class Seek(val seconds: Double, val exact: Boolean) : PlayerCommand

    data class Stop(val id: Long) : PlayerCommand

    data class Select(val type: String, val id: Long?, val loadId: Long, val requestId: Long) :
        PlayerCommand

    data class Volume(val value: Double) : PlayerCommand
}

internal object PlayerProtocol {
    private fun invalid(): Nothing = throw ProtocolError("invalid_argument")

    fun map(value: Any?): Map<*, *> = value as? Map<*, *> ?: invalid()

    fun integer(value: Any?, minimum: Long): Long {
        val n =
            when (value) {
                is Int -> value.toLong()
                is Long -> value
                else -> invalid()
            }
        return n.takeIf { it >= minimum } ?: invalid()
    }

    fun number(value: Any?, minimum: Double = 0.0): Double {
        val n = (value as? Number)?.toDouble() ?: invalid()
        return n.takeIf { it.isFinite() && it >= minimum } ?: invalid()
    }

    fun boolean(value: Any?) = value as? Boolean ?: invalid()

    fun string(value: Any?) = value as? String ?: invalid()

    fun load(value: Any?): PlayerCommand.Load {
        val a = map(value)
        val uri = string(a["uri"])
        if (uri.toByteArray(Charsets.UTF_8).size !in 1..32768) invalid()
        val token = a["plexToken"]?.let { string(it) }
        if (token != null && (token.length !in 1..8192 || token.any { it.code !in 0x21..0x7e }))
            invalid()
        val parsed =
            try {
                URI(uri)
            } catch (_: Exception) {
                invalid()
            }
        if (
            token != null &&
                (!parsed.scheme.equals("https", true) || parsed.rawAuthority.isNullOrEmpty())
        ) {
            throw ProtocolError("insecure_media_uri")
        }
        // Embedded credentials and query credentials can never enter networking or diagnostics.
        if (
            parsed.rawUserInfo != null ||
                parsed.rawQuery?.split('&')?.any {
                    java.net.URLDecoder.decode(it.substringBefore('='), "UTF-8")
                        .equals("X-Plex-Token", true)
                } == true
        )
            invalid()
        val start = if (a.containsKey("startSeconds")) number(a["startSeconds"]) else 0.0
        val paused = if (a.containsKey("startPaused")) boolean(a["startPaused"]) else false
        return PlayerCommand.Load(MediaLoad(uri, integer(a["loadId"], 0), token, paused, start))
    }

    fun command(method: String, value: Any?): PlayerCommand =
        when (method) {
            "load" -> load(value)
            "play" -> PlayerCommand.Play
            "pause" -> PlayerCommand.Pause
            "seek" -> {
                val a = map(value)
                val mode = if (a.containsKey("mode")) a["mode"] else "exact"
                if (mode !in listOf("exact", "keyframes")) invalid()
                PlayerCommand.Seek(number(a["seconds"]), mode == "exact")
            }
            "stop" -> PlayerCommand.Stop(integer(map(value)["stopId"], 1))
            "selectTrack" -> {
                val a = map(value)
                val type = string(a["type"])
                if (type !in listOf("video", "audio", "subtitle")) invalid()
                PlayerCommand.Select(
                    type,
                    a["id"]?.let { integer(it, 1) },
                    integer(a["loadId"], 1),
                    integer(a["requestId"], 1),
                )
            }
            "setVolume" -> {
                val volume = number(map(value)["volume"])
                if (volume > 100) invalid()
                PlayerCommand.Volume(volume)
            }
            else -> invalid()
        }

    fun subtitlePresentation(value: Any?): SubtitlePresentation {
        val a = map(value)
        val scale = number(a["scale"], 0.25)
        val raise = number(a["imageRaise"])
        if (scale > 4.0 || raise > 0.25) invalid()
        return SubtitlePresentation(scale.toFloat(), raise.toFloat(), boolean(a["lineupDrawsStyled"]))
    }

    fun rect(value: Any?): VideoRect {
        val a = map(value)
        fun coordinate(key: String): Double {
            val v = (a[key] as? Number)?.toDouble() ?: invalid()
            return v.takeIf { it.isFinite() } ?: invalid()
        }
        val r =
            VideoRect(
                coordinate("left"),
                coordinate("top"),
                number(a["width"]),
                number(a["height"]),
                number(a["scale"]),
            )
        if (r.scale <= 0) invalid()
        return r
    }
}

/** Owned by the application looper. No task, callback, or queue crosses an engine lifetime. */
internal interface PlayerEngine {
    interface Listener {
        fun firstFrame(positionMs: Long) {}

        fun frameTimestamp(presentationTimeUs: Long) {}

        fun fragmentSeek(position: Long) {}

        fun sourceInitialization(revision: Int, accepted: Boolean) {}

        fun ready(paused: Boolean)

        fun ended()

        fun failure(code: String, httpStatus: Int? = null)

        fun property(name: String, value: Any?)
    }

    fun load(media: MediaLoad, listener: Listener)

    fun play()

    fun pause()

    fun seek(seconds: Double, exact: Boolean)

    fun select(type: String, id: Long?): Boolean

    fun volume(value: Double)

    fun release(complete: (Boolean) -> Unit)
}

internal interface PlayerHost {
    fun firstFrame(generation: Long, loadId: Long, positionMs: Long) {}

    fun frameTimestamp(generation: Long, loadId: Long, presentationTimeUs: Long) {}

    fun fragmentSeek(generation: Long, loadId: Long, position: Long) {}

    fun sourceInitialization(generation: Long, loadId: Long, revision: Int, accepted: Boolean) {}

    fun post(task: () -> Unit)

    fun rect(rect: VideoRect)

    fun keepScreenOn(keep: Boolean)

    fun subtitlePresentation(value: SubtitlePresentation?) {}

    fun createEngine(): PlayerEngine

    fun event(value: Map<String, Any?>)
}

internal data class QueuedEvent(
    val generation: Long,
    val epoch: Long?,
    val value: Map<String, Any?>,
)

internal class PlayerEventQueue {
    private val queue = ArrayDeque<QueuedEvent>()
    var overflowed = false
        private set

    val size
        get() = queue.size

    fun add(event: QueuedEvent) {
        fun cues(e: QueuedEvent) = e.value["type"] == "property" && e.value["name"] == "subtitle-cues"
        if (cues(event)) {
            val index = queue.indexOfFirst { cues(it) }
            if (index >= 0) {
                queue[index] = event
                return
            }
        }
        if (queue.size == 256) {
            val property = queue.indexOfFirst { it.value["type"] == "property" && !cues(it) }
            if (property >= 0) {
                val iterator = queue.iterator()
                repeat(property + 1) { iterator.next() }
                iterator.remove()
            } else if (event.value["type"] == "property" && !cues(event)) return
            else {
                val iterator = queue.iterator()
                while (iterator.hasNext()) {
                    if (!cues(iterator.next())) { iterator.remove(); break }
                }
                overflowed = true
            }
        }
        queue.addLast(event)
    }

    fun take(): QueuedEvent? = if (queue.isEmpty()) null else queue.removeFirst()

    fun clear() {
        queue.clear()
        overflowed = false
    }

    fun consumeOverflow(): Boolean = overflowed.also { overflowed = false }
}
