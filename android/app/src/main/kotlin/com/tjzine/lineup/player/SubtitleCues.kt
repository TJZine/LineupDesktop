package com.tjzine.lineup.player

import android.graphics.Typeface
import android.text.Layout
import android.text.Spanned
import android.text.style.StyleSpan
import android.text.style.UnderlineSpan
import androidx.media3.common.Format
import androidx.media3.common.text.Cue
import androidx.media3.common.util.UnstableApi

internal data class SubtitlePresentation(
    val scale: Float = 1f,
    val imageRaise: Float = 0f,
    val lineupDrawsStyled: Boolean = false,
)

/** Decoder classification, geometry and bounded content encoding. Never retain or log cue text. */
@UnstableApi
internal object SubtitleCues {
    fun engineDraws(format: Format?, presentation: SubtitlePresentation): Boolean {
        val mime = if (format?.sampleMimeType == "application/x-media3-cues")
            format.codecs else format?.sampleMimeType
        return mime in setOf("application/pgs", "application/vobsub", "application/dvbsubs") ||
            (mime == "text/x-ssa" && !presentation.lineupDrawsStyled)
    }

    fun transform(cue: Cue, presentation: SubtitlePresentation): Cue {
        if (cue.bitmap != null) {
            if (cue.positionAnchor != Cue.ANCHOR_TYPE_START ||
                cue.lineAnchor != Cue.ANCHOR_TYPE_START || cue.lineType != Cue.LINE_TYPE_FRACTION ||
                cue.size == Cue.DIMEN_UNSET || cue.bitmapHeight == Cue.DIMEN_UNSET ||
                cue.position == Cue.DIMEN_UNSET || cue.line == Cue.DIMEN_UNSET) return cue
            val width = (cue.size * presentation.scale).coerceIn(0f, 1f)
            val height = (cue.bitmapHeight * presentation.scale).coerceIn(0f, 1f)
            return cue.buildUpon().setSize(width).setBitmapHeight(height)
                .setPosition((cue.position + cue.size / 2 - width / 2).coerceIn(0f, 1f - width))
                .setLine((cue.line + cue.bitmapHeight - height - presentation.imageRaise)
                    .coerceIn(0f, 1f - height), Cue.LINE_TYPE_FRACTION).build()
        }
        return if (cue.textSize != Cue.DIMEN_UNSET && cue.textSizeType in
            listOf(Cue.TEXT_SIZE_TYPE_FRACTIONAL, Cue.TEXT_SIZE_TYPE_FRACTIONAL_IGNORE_PADDING))
            cue.buildUpon().setTextSize(cue.textSize * presentation.scale, cue.textSizeType).build()
        else cue
    }

    fun alignment(cue: Cue): Int {
        val column = when (cue.textAlignment) {
            Layout.Alignment.ALIGN_NORMAL -> 1
            Layout.Alignment.ALIGN_OPPOSITE -> 3
            else -> when {
                cue.position == Cue.DIMEN_UNSET -> 2
                cue.position < 1f / 3 -> 1
                cue.position >= 2f / 3 -> 3
                else -> 2
            }
        }
        val row = when {
            cue.line == Cue.DIMEN_UNSET -> 0
            cue.lineType == Cue.LINE_TYPE_NUMBER -> if (cue.line >= 0 && cue.line < 5) 2 else 0
            cue.line < 1f / 3 -> 2
            cue.line >= 2f / 3 -> 0
            else -> 1
        }
        return row * 3 + column
    }

    fun encode(cues: List<Cue>): List<Map<String, Any>> {
        var remaining = 4096
        val result = mutableListOf<Map<String, Any>>()
        for (cue in cues) {
            if (result.size == 8 || remaining == 0) break
            val text = cue.text ?: continue
            if (cue.bitmap != null) continue
            val lines = mutableListOf<List<Map<String, Any>>>()
            var start = 0
            while (start <= text.length && lines.size < 8 && remaining > 0) {
                val newline = text.indexOf('\n', start).let { if (it < 0) text.length else it }
                val segments = mutableListOf<Map<String, Any>>()
                var offset = start
                while (offset < newline && segments.size < 32 && remaining > 0) {
                    val spans = text as? Spanned
                    var end = if (spans == null) newline else minOf(
                        spans.nextSpanTransition(offset, newline, StyleSpan::class.java),
                        spans.nextSpanTransition(offset, newline, UnderlineSpan::class.java),
                    )
                    // A span boundary must not split a surrogate pair.
                    if (end < newline && end > offset && Character.isHighSurrogate(text[end - 1]) &&
                        Character.isLowSurrogate(text[end])) end++
                    val value = StringBuilder()
                    var cursor = offset
                    while (cursor < end) {
                        val cp = Character.codePointAt(text, cursor)
                        val piece = String(Character.toChars(cp))
                        val bytes = piece.toByteArray(Charsets.UTF_8).size
                        if (bytes > remaining) break
                        value.append(piece)
                        remaining -= bytes
                        cursor += Character.charCount(cp)
                    }
                    if (value.isNotEmpty()) {
                        var style = 0
                        spans?.getSpans(offset, end, StyleSpan::class.java)?.forEach { style = style or it.style }
                        val segment = mutableMapOf<String, Any>("text" to value.toString())
                        if (style and Typeface.ITALIC != 0) segment["italic"] = true
                        if (style and Typeface.BOLD != 0) segment["bold"] = true
                        if (spans?.getSpans(offset, end, UnderlineSpan::class.java)?.isNotEmpty() == true)
                            segment["underline"] = true
                        segments.add(segment)
                    }
                    if (cursor < end) { remaining = 0; break }
                    offset = end
                }
                lines.add(segments)
                if (newline == text.length) break
                start = newline + 1
            }
            result.add(mapOf("align" to alignment(cue), "lines" to lines))
        }
        return result
    }
}
