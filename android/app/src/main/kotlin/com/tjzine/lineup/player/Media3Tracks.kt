package com.tjzine.lineup.player

import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.TrackGroup
import androidx.media3.common.Tracks
import androidx.media3.common.util.UnstableApi
import java.util.IdentityHashMap

@UnstableApi
internal class Media3Tracks {
    data class Target(val group: TrackGroup, val index: Int, val type: Int)

    private val identities = IdentityHashMap<TrackGroup, MutableMap<Int, Long>>()
    private var nextId = 1L
    private val targets = mutableMapOf<Long, Target>()

    fun target(id: Long) = targets[id]

    fun encode(tracks: Tracks): List<Map<String, Any?>> {
        targets.clear()
        val rows = mutableListOf<Map<String, Any?>>()
        var bytes = 0
        for (group in tracks.groups) {
            val type =
                when (group.type) {
                    C.TRACK_TYPE_VIDEO -> "video"
                    C.TRACK_TYPE_AUDIO -> "audio"
                    C.TRACK_TYPE_TEXT -> "sub"
                    else -> continue
                }
            for (index in 0 until group.length) {
                if (!group.isTrackSupported(index)) continue
                val id =
                    identities
                        .getOrPut(group.mediaTrackGroup) { mutableMapOf() }
                        .getOrPut(index) { nextId++ }
                val f = group.getTrackFormat(index)
                val row =
                    linkedMapOf<String, Any?>(
                        "id" to id,
                        "type" to type,
                        "selected" to group.isTrackSelected(index),
                    )
                bounded(f.label)?.let { row["title"] = it }
                bounded(f.language)?.let { row["lang"] = it }
                codec(f)?.let { row["codec"] = it }
                if (f.channelCount > 0) row["demux-channel-count"] = f.channelCount
                row["forced"] = f.selectionFlags and C.SELECTION_FLAG_FORCED != 0
                if (f.roleFlags != 0) {
                    row["hearing-impaired"] =
                        f.roleFlags and
                            (C.ROLE_FLAG_CAPTION or C.ROLE_FLAG_DESCRIBES_MUSIC_AND_SOUND) != 0
                    row["visual-impaired"] = f.roleFlags and C.ROLE_FLAG_DESCRIBES_VIDEO != 0
                    row["commentary"] = f.roleFlags and C.ROLE_FLAG_COMMENTARY != 0
                }
                // Include keys/scalar overhead conservatively in the aggregate 64-KiB bound.
                val cost =
                    row.entries.sumOf {
                        it.key.length +
                            (it.value as? String)?.toByteArray(Charsets.UTF_8)?.size.orZero() +
                            24
                    }
                if (rows.size >= 256 || bytes + cost > 64 * 1024) return rows
                rows.add(row)
                bytes += cost
                targets[id] = Target(group.mediaTrackGroup, index, group.type)
            }
        }
        return rows
    }

    private fun Int?.orZero() = this ?: 0

    companion object {
        fun bounded(value: String?): String? =
            value?.takeIf { it.toByteArray(Charsets.UTF_8).size <= 4096 }

        fun codec(format: Format): String? {
            val mime =
                if (format.sampleMimeType == "application/x-media3-cues") format.codecs
                else format.sampleMimeType
            // DV has multiple encoded families. Preserve its declared codec string,
            // rather than assuming HEVC or confusing a decoder fallback with source facts.
            if (mime == "video/dolby-vision") return bounded(format.codecs)
            return when (mime) {
                "video/avc" -> "h264"
                "video/hevc" -> "hevc"
                "video/av01" -> "av1"
                "video/mpeg2" -> "mpeg2video"
                "video/mp4v-es" -> "mpeg4"
                "video/x-vnd.on2.vp9" -> "vp9"
                "video/x-vnd.on2.vp8" -> "vp8"
                "audio/mp4a-latm" -> "aac"
                "audio/ac3" -> "ac3"
                "audio/eac3",
                "audio/eac3-joc" -> "eac3"
                "audio/true-hd" -> "truehd"
                "audio/vnd.dts",
                "audio/vnd.dts.hd",
                "audio/vnd.dts.hd;profile=lbr" -> "dts"
                "audio/flac" -> "flac"
                "audio/opus" -> "opus"
                "audio/vorbis" -> "vorbis"
                "audio/mpeg" -> "mp3"
                "application/x-subrip" -> "subrip"
                "text/x-ssa" -> "ass"
                "application/pgs" -> "hdmv_pgs_subtitle"
                "application/vobsub" -> "dvd_subtitle"
                "text/vtt" -> "webvtt"
                else -> bounded(mime)
            }
        }

        fun videoParams(f: Format): Map<String, Any?> =
            mapOf(
                "w" to f.width.takeIf { it > 0 },
                "h" to f.height.takeIf { it > 0 },
                "pixelformat" to null,
                "hw-pixelformat" to null,
                "primaries" to
                    when (f.colorInfo?.colorSpace) {
                        C.COLOR_SPACE_BT2020 -> "bt.2020"
                        C.COLOR_SPACE_BT709 -> "bt.709"
                        else -> null
                    },
                "gamma" to
                    when (f.colorInfo?.colorTransfer) {
                        C.COLOR_TRANSFER_ST2084 -> "pq"
                        C.COLOR_TRANSFER_HLG -> "hlg"
                        else -> null
                    },
                "colormatrix" to null,
                "sig-peak" to null,
            )
    }
}
