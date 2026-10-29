package com.tjzine.lineup.player

import android.text.Annotation
import android.text.SpannableString
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.StyleSpan
import android.text.style.UnderlineSpan
import androidx.media3.common.Format
import androidx.media3.common.text.Cue
import androidx.media3.common.util.Consumer
import androidx.media3.common.util.ParsableByteArray
import androidx.media3.common.util.UnstableApi
import androidx.media3.extractor.text.CuesWithTiming
import androidx.media3.extractor.text.DefaultSubtitleParserFactory
import androidx.media3.extractor.text.SubtitleParser
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.util.concurrent.CopyOnWriteArrayList

/** Direct Play SSA only. No second parser, buffered timeline or retained raw-event cache. */
@UnstableApi
internal object SsaDialogueParser {
    private const val TRACK = "com.tjzine.lineup.ssa.track.v1"
    private const val KIND = "com.tjzine.lineup.ssa.kind.v1"
    private const val STYLE = "com.tjzine.lineup.ssa.style.v1"
    private const val PREFIX = "\uE000LN:"
    private const val END = '\uE001'
    private const val MAX_BYTES = 65536
    private const val MAX_EVENTS = 64
    private const val MAX_STYLES = 256
    private val blocks = Regex("\\{.*?\\}")
    private val commands = Regex("\\\\([A-Za-z]+)\\s*([+-]?\\d+)?")
    private class DecorationFailure : Exception()
    private class Track(val id: Int, val source: Format) {
        @Volatile var failed = false
    }

    fun isSsa(format: Format?): Boolean =
        (if (format?.sampleMimeType == "application/x-media3-cues") format.codecs else format?.sampleMimeType) == "text/x-ssa"

    private fun annotations(cue: Cue): List<Annotation> {
        val text = cue.text as? Spanned ?: return emptyList()
        return text.getSpans(0, text.length, Annotation::class.java).toList()
    }

    /** Strip only our nonvisual metadata, retaining every stock character/span/geometry field. */
    fun nativeCue(cue: Cue): Cue {
        val markers = annotations(cue).filter { it.key in listOf(TRACK, KIND, STYLE) }
        if (markers.isEmpty()) return cue
        val text = SpannableString(cue.text)
        markers.forEach(text::removeSpan)
        return cue.buildUpon().setText(text).build()
    }

    fun lineupCues(cues: List<Cue>): List<Cue> = cues.mapNotNull { cue ->
        if (annotations(cue).none { it.key == KIND && it.value == "dialogue" }) return@mapNotNull null
        val original = cue.text as? Spanned ?: return@mapNotNull cue
        val text = SpannableString(original.toString())
        var offset = 0
        while (offset < text.length) {
            val end = minOf(
                original.nextSpanTransition(offset, text.length, StyleSpan::class.java),
                original.nextSpanTransition(offset, text.length, UnderlineSpan::class.java),
                original.nextSpanTransition(offset, text.length, Annotation::class.java),
            )
            var flags = 0
            original.getSpans(offset, end, StyleSpan::class.java).forEach { flags = flags or it.style }
            if (original.getSpans(offset, end, UnderlineSpan::class.java).isNotEmpty()) flags = flags or 4
            original.getSpans(offset, end, Annotation::class.java).filter { it.key == STYLE }.forEach {
                val parts = it.value.split(':')
                val mask = parts[0].toInt()
                flags = (flags and mask.inv()) or parts[1].toInt()
            }
            if (flags and 3 != 0) text.setSpan(StyleSpan(flags and 3), offset, end, 33)
            if (flags and 4 != 0) text.setSpan(UnderlineSpan(), offset, end, 33)
            offset = end
        }
        cue.buildUpon().setText(text).build()
    }

    class Factory(private val debug: Boolean = false, private val changed: () -> Unit = {}) : SubtitleParser.Factory {
        private val stock = DefaultSubtitleParserFactory()
        private val tracks = CopyOnWriteArrayList<Track>()
        @Volatile private var closed = false
        override fun supportsFormat(format: Format) = stock.supportsFormat(format)
        override fun getCueReplacementBehavior(format: Format) = stock.getCueReplacementBehavior(format)
        override fun create(format: Format): SubtitleParser {
            val parser = stock.create(format)
            if (format.sampleMimeType != "text/x-ssa") return parser
            // Only typed track state survives parse. No text, event times or cue timeline is cached here.
            val track = synchronized(tracks) {
                if (closed || tracks.size >= 256) null
                else Track(tracks.size, format).also(tracks::add)
            } ?: return parser
            return Decorator(parser, format, track, ::fail)
        }

        fun clear() = synchronized(tracks) { closed = true; tracks.clear() }

        private fun fail(track: Track) {
            if (!track.failed) {
                track.failed = true
                if (!closed) {
                    if (debug) android.util.Log.d("LineupPlayer", "SSA decoration failed; native captions retained")
                    changed()
                }
            }
        }

        /** Called on the application looper, also for cues decoded before a later track failure. */
        fun nativeFallback(format: Format?, cues: List<Cue>): Boolean {
            if (!isSsa(format)) return false
            val matching = tracks.filter { format?.id == null || it.source.id == format.id }
            if (matching.any { it.failed }) return true
            for (cue in cues) {
                if (cue.bitmap != null || cue.text.isNullOrEmpty()) continue
                val metadata = annotations(cue)
                val id = metadata.singleOrNull { it.key == TRACK }?.value?.toIntOrNull()
                val track = id?.let { tracks.getOrNull(it) }
                val kind = metadata.singleOrNull { it.key == KIND }?.value
                val invalidStyle = metadata.filter { it.key == STYLE }.any {
                    val values = it.value.split(':').map(String::toIntOrNull)
                    values.size != 2 || values.any { n -> n !in 0..7 } ||
                        (values[1]!! and values[0]!!.inv()) != 0
                }
                if (track == null || kind !in listOf("dialogue", "sign") || track.failed || invalidStyle) {
                    // Track delivery and cue delivery race. An unmarked cue may
                    // still belong to the previous plain-text track. Draw that cue
                    // natively without poisoning the new parser's track state.
                    // If a known SSA carrier itself is malformed, failure is sticky.
                    if (track != null && (kind !in listOf("dialogue", "sign") || invalidStyle)) fail(track)
                    return true
                }
            }
            return false
        }
    }

    private class Decorator(
        private val stock: SubtitleParser,
        private val format: Format,
        private val track: Track,
        private val fail: (Track) -> Unit,
    ) : SubtitleParser {
        override fun getCueReplacementBehavior() = stock.cueReplacementBehavior
        override fun reset() = stock.reset()

        override fun parse(data: ByteArray, offset: Int, length: Int, options: SubtitleParser.OutputOptions, output: Consumer<CuesWithTiming>) {
            if (track.failed) {
                stock(data, offset, length, options, output, 0)
                releaseInput()
                return
            }
            var delivered = 0
            try {
                val rewritten = rewrite(data, offset, length, format)
                stock.parse(rewritten, 0, rewritten.size, options) { group ->
                    // Only the current callback is copied; no callback/timeline collection is held.
                    val cues = group.cues.map { restore(it, track.id) }
                    output.accept(CuesWithTiming(cues, group.startTimeUs, group.durationUs))
                    delivered++
                }
            } catch (_: Exception) {
                fail(track)
                // Unwind the decorated parse before replaying ORIGINAL bytes. Skip callbacks
                // already emitted, so merge-style subtitle timelines never receive duplicates.
                stock(data, offset, length, options, output, delivered)
            } finally {
                releaseInput()
            }
        }

        private fun releaseInput() {
            // SsaParser retains the last input array. An empty parse releases our
            // rewritten scratch without another timeline or changing its header state.
            try {
                stock.parse(byteArrayOf(), 0, 0, SubtitleParser.OutputOptions.allCues()) {}
            } catch (_: Exception) { fail(track) }
        }

        private fun stock(data: ByteArray, offset: Int, length: Int, options: SubtitleParser.OutputOptions, output: Consumer<CuesWithTiming>, skip: Int) {
            var index = 0
            try {
                stock.parse(data, offset, length, options) { group ->
                    if (index++ >= skip) {
                        output.accept(CuesWithTiming(group.cues.map { markTrack(it, track.id) }, group.startTimeUs, group.durationUs))
                    }
                }
            } catch (_: Exception) {
                // Stock cannot produce cues for malformed input either. Keep playback and
                // already-current stock cues alive; future samples remain on the stock path.
                fail(track)
            }
        }
    }

    private fun markTrack(cue: Cue, id: Int): Cue {
        val value = cue.text ?: return cue
        val text = SpannableString(value)
        text.setSpan(Annotation(TRACK, id.toString()), 0, text.length, Spanned.SPAN_MARK_MARK)
        return cue.buildUpon().setText(text).build()
    }

    private fun rewrite(data: ByteArray, offset: Int, length: Int, format: Format): ByteArray {
        if (length > MAX_BYTES) throw DecorationFailure()
        val input = ParsableByteArray(data, offset + length)
        input.position = offset
        val charset = input.readUtfCharsetFromBom() ?: Charsets.UTF_8
        val start = input.position
        val text = charset.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(data, start, offset + length - start)).toString()
        // Collision means stock fallback; never reinterpret literal media characters as metadata.
        if (text.contains(PREFIX)) throw DecorationFailure()
        val initialFormat = format.initializationData.firstOrNull()
        if (initialFormat != null && initialFormat.size > MAX_BYTES) throw DecorationFailure()
        var columns: Pair<Int, Int>? = initialFormat?.let { eventFormat(it.toString(Charsets.UTF_8)) }
        var events = columns != null
        var ordinal = 0
        var styles = 0
        val result = StringBuilder()
        val lines = Regex("[^\\r\\n]*(?:\\r\\n|\\r|\\n|$)").findAll(text)
        for (match in lines) {
            val line = match.value.trimEnd('\r', '\n')
            val ending = match.value.substring(line.length)
            if (line.startsWith('[')) events = line.equals("[Events]", true)
            if (events && line.startsWith("Format:")) columns = eventFormat(line)
            if (line.startsWith("Dialogue:")) {
                val spec = columns ?: throw DecorationFailure()
                if (++ordinal > MAX_EVENTS) throw DecorationFailure()
                val fields = line.substring(9).split(',', limit = spec.first).toMutableList()
                if (fields.size != spec.first) throw DecorationFailure()
                val raw = fields[spec.second]
                var sign = false
                blocks.findAll(raw).forEach { block ->
                    commands.findAll(block.value).forEach { command ->
                        val tag = command.groupValues[1]
                        if (tag in listOf("pos", "move", "org", "clip", "iclip") ||
                            (tag == "p" && positive(command.groupValues[2]))) sign = true
                    }
                }
                var mask = 0
                var flags = 0
                var previous = 0
                val body = StringBuilder()
                blocks.findAll(raw).forEach { block ->
                    body.append(raw, previous, block.range.last + 1)
                    var changed = false
                    val content = block.value
                    // Match the desktop emphasis grammar exactly. Unknown tag
                    // names/values do not alter emphasis; bare tags reset off.
                    var tagStart = if (content.substring(1).contains('{')) -1 else content.indexOf('\\')
                    while (tagStart >= 0) {
                        val next = content.indexOf('\\', tagStart + 1).let { if (it < 0) content.lastIndex else it }
                        val tag = content.substring(tagStart + 1, next)
                        if (tag == "r") {
                            mask = 7
                            flags = 0
                            changed = true
                        } else if (tag in listOf("b", "b0", "b1", "i", "i0", "i1", "u", "u0", "u1")) {
                            val bit = when (tag[0]) { 'b' -> 1; 'i' -> 2; else -> 4 }
                            mask = mask or bit
                            flags = if (tag.endsWith('1')) flags or bit else flags and bit.inv()
                            changed = true
                        }
                        tagStart = if (next < content.lastIndex) next else -1
                    }
                    if (changed) {
                        if (++styles > MAX_STYLES) throw DecorationFailure()
                        body.append(PREFIX).append('S').append(mask).append(':').append(flags).append(END)
                    }
                    previous = block.range.last + 1
                }
                body.append(raw, previous, raw.length)
                fields[spec.second] = "$PREFIX" + "E${ordinal - 1}:${if (sign) 1 else 0}$END" + body
                result.append("Dialogue:").append(fields.joinToString(",")).append(ending)
            } else result.append(match.value)
            if (result.length > MAX_BYTES) throw DecorationFailure()
        }
        val encoded = result.toString().toByteArray(charset)
        val bom = data.copyOfRange(offset, start)
        if (encoded.size + bom.size > MAX_BYTES) throw DecorationFailure()
        return bom + encoded
    }

    private fun positive(value: String): Boolean = !value.startsWith('-') &&
        value.removePrefix("+").any { it in '1'..'9' }

    private fun eventFormat(line: String): Pair<Int, Int>? {
        if (!line.startsWith("Format:")) return null
        val fields = line.substring(7).split(',').map { it.trim().lowercase() }
        val index = fields.indexOf("text")
        return if (fields.size <= 64 && index >= 0 && fields.count { it == "text" } == 1) fields.size to index else null
    }

    private fun restore(cue: Cue, id: Int): Cue {
        val value = cue.text ?: throw DecorationFailure()
        val text = SpannableStringBuilder(value)
        if (!text.startsWith(PREFIX + "E")) throw DecorationFailure()
        var offset = 0
        var kind: String? = null
        var region = 0
        var style = "0:0"
        var changes = 0
        while (offset < text.length) {
            if (!text.startsWith(PREFIX, offset)) { offset++; continue }
            val end = text.indexOf(END.toString(), offset + PREFIX.length)
            if (end < 0) throw DecorationFailure()
            val marker = text.substring(offset + PREFIX.length, end)
            if (marker.startsWith('E') && offset == 0 && kind == null) {
                val fields = marker.substring(1).split(':')
                if (fields.size != 2 || fields[0].toIntOrNull() !in 0 until MAX_EVENTS || fields[1] !in listOf("0", "1")) throw DecorationFailure()
                kind = if (fields[1] == "1") "sign" else "dialogue"
            } else if (marker.startsWith('S')) {
                val fields = marker.substring(1).split(':')
                if (fields.size != 2 || fields.any { it.toIntOrNull() !in 0..7 } || ++changes > MAX_STYLES) throw DecorationFailure()
                if (offset > region) text.setSpan(Annotation(STYLE, style), region, offset, 33)
                style = marker.substring(1)
                region = offset
            } else throw DecorationFailure()
            text.delete(offset, end + 1)
        }
        if (kind == null) throw DecorationFailure()
        if (text.length > region) text.setSpan(Annotation(STYLE, style), region, text.length, 33)
        // Editable deletion removes zero-length EXCLUSIVE spans. Stock SsaParser
        // retains them on empty text; rebuild those spans on an immutable-string copy.
        val restored = SpannableString(text)
        if (text.isEmpty() && value is Spanned) {
            value.getSpans(0, value.length, Any::class.java).forEach {
                restored.setSpan(it, 0, 0, value.getSpanFlags(it))
            }
        }
        restored.setSpan(Annotation(KIND, kind), 0, restored.length, Spanned.SPAN_MARK_MARK)
        restored.setSpan(Annotation(TRACK, id.toString()), 0, restored.length, Spanned.SPAN_MARK_MARK)
        return cue.buildUpon().setText(restored).build()
    }
}
