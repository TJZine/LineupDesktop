package com.tjzine.lineup.player

import java.io.IOException

class Mp4ObservationError : IOException("incomplete_mp4_type_observation")

/** Observes only box framing and moov/trak/mdia/hdlr type declarations. */
class Mp4TypeObserver(private val onMoovStart: () -> Unit = {}) {
    data class Types(val video: Boolean, val audio: Boolean)

    private data class Parent(val type: String, val end: Long)

    private val parents = ArrayDeque<Parent>() // Relevant ancestry has at most three entries.
    private val header = ByteArray(16)
    private val handler = ByteArray(12)
    private var headerBytes = 0
    private var headerLength = 8
    private var handlerBytes = 0
    private var bodyEnd: Long? = null
    private var bodyStart = 0L
    private var bodyIsHandler = false
    private var position = 0L
    private var pendingVideo = false
    private var pendingAudio = false
    private var inMoov = false
    private var suspended = false
    private var mediaBoxStart: Long? = null
    private var suspendedReturnPosition: Long? = null
    private var validated = false
    var revision = 0
        private set

    var types = Types(false, false)
        private set

    fun reset() {
        parents.clear()
        headerBytes = 0
        headerLength = 8
        handlerBytes = 0
        bodyEnd = null
        bodyStart = 0
        bodyIsHandler = false
        position = 0
        pendingVideo = false
        pendingAudio = false
        inMoov = false
        suspended = false
        mediaBoxStart = null
        suspendedReturnPosition = null
        validated = false
        revision = 0
        types = Types(false, false)
    }

    fun markValidated() {
        requireSnapshot()
        validated = true
    }

    fun requireSnapshot(): Types {
        if (revision == 0 || inMoov || suspended) throw Mp4ObservationError()
        return types
    }

    fun seek(target: Long) {
        if (validated) {
            // Sample seeks keep the already validated immutable media-type facts.
            // If the parser starts at byte zero again, observe its header reparse.
            if (target == 0L) {
                restartAtZeroPreservingTypes()
            } else {
                suspended = true
                suspendedReturnPosition = null
            }
        } else if (target == 0L) reset() else reposition(target)
    }

    /**
     * FragmentedMp4Extractor.seek always restarts at an atom header (Media3 1.11.1). Keep validated
     * declarations until a new moov, while observing future initializations. Ordinary Mp4Extractor
     * sample seeks must continue using seek(), since samples are unframed.
     */
    fun seekToBox(target: Long) {
        if (!validated) {
            seek(target)
            return
        }
        restartAtZeroPreservingTypes()
        position = target
    }

    private fun restartAtZeroPreservingTypes() {
        val previous = types
        val previousRevision = revision
        reset()
        types = previous
        revision = previousRevision
        validated = true
    }

    fun reposition(target: Long) {
        if (suspended) {
            // Media3's MFRA probe reads the last 16 bytes (which need not be a
            // box), then returns to the first moof/mdat header it already read.
            // Ignore only that detour. Resume at this known header so a later
            // moov still has to prove its own declared audio/video exposure.
            if (target == suspendedReturnPosition) {
                restartAtZeroPreservingTypes()
                position = target
            }
            return
        }
        if (target == position) return
        val end = bodyEnd
        if (end != null && target in bodyStart..end && !bodyIsHandler) {
            position = target
            finishBody()
            closeParents()
            return
        }
        if (validated && !inMoov) {
            suspended = true
            suspendedReturnPosition = mediaBoxStart
            return
        }
        throw Mp4ObservationError()
    }

    fun eof() {
        if (inMoov || (!validated && revision == 0)) throw Mp4ObservationError()
    }

    fun consume(at: Long, data: ByteArray, offset: Int, count: Int, inputLength: Long) {
        if (suspended) return
        reposition(at)
        if (suspended) return
        var index = offset
        val limit = offset + count
        while (index < limit) {
            closeParents()
            val end = bodyEnd
            if (end != null) {
                val n = minOf((end - position).coerceAtLeast(0), (limit - index).toLong()).toInt()
                if (n == 0) {
                    finishBody()
                    continue
                }
                if (bodyIsHandler && handlerBytes < 12) {
                    val copy = minOf(n, 12 - handlerBytes)
                    data.copyInto(handler, handlerBytes, index, index + copy)
                    handlerBytes += copy
                    if (handlerBytes == 12) {
                        when (String(handler, 8, 4, Charsets.US_ASCII)) {
                            "vide" -> pendingVideo = true
                            "soun" -> pendingAudio = true
                        }
                    }
                }
                index += n
                position += n
                finishBody()
                continue
            }
            if (headerBytes == 0) {
                val remaining = parents.lastOrNull()?.let { it.end - position }
                if (remaining != null && remaining < 8) throw Mp4ObservationError()
            }
            val n = minOf(headerLength - headerBytes, limit - index)
            data.copyInto(header, headerBytes, index, index + n)
            headerBytes += n
            index += n
            position += n
            if (headerBytes == 8 && unsigned32(header, 0) == 1L) headerLength = 16
            if (headerBytes == headerLength) openBox(inputLength)
        }
        closeParents()
    }

    fun skip(at: Long, count: Long) {
        if (count == 0L) return
        if (suspended) return
        reposition(at)
        if (suspended) return
        val end = bodyEnd ?: throw Mp4ObservationError()
        val target = add(position, count)
        if (count < 0 || target > end || (bodyIsHandler && handlerBytes < 12))
            throw Mp4ObservationError()
        position = target
        finishBody()
        closeParents()
    }

    private fun openBox(inputLength: Long) {
        val start = position - headerLength
        val type = String(header, 4, 4, Charsets.US_ASCII)
        val raw = unsigned32(header, 0)
        val size =
            when (raw) {
                0L ->
                    (parents.lastOrNull()?.end ?: inputLength).let {
                        if (it < 0) throw Mp4ObservationError()
                        it - start
                    }
                1L -> {
                    if ((header[8].toInt() and 0x80) != 0) throw Mp4ObservationError()
                    (unsigned32(header, 8) shl 32) or unsigned32(header, 12)
                }
                else -> raw
            }
        if (size < headerLength) throw Mp4ObservationError()
        val end = add(start, size)
        if (
            parents.lastOrNull()?.let { end > it.end } == true ||
                (inputLength >= 0 && end > inputLength)
        )
            throw Mp4ObservationError()
        val path = parents.map { it.type }
        if (path.isEmpty()) {
            mediaBoxStart = if (type == "moof" || type == "mdat") start else null
        }
        val enter =
            (path.isEmpty() && type == "moov") ||
                (path == listOf("moov") && type == "trak") ||
                (path == listOf("moov", "trak") && type == "mdia")
        headerBytes = 0
        headerLength = 8
        if (enter) {
            if (type == "moov") {
                pendingVideo = false
                pendingAudio = false
                inMoov = true
                onMoovStart()
            }
            parents.addLast(Parent(type, end))
        } else {
            bodyStart = position
            bodyEnd = end
            bodyIsHandler = path == listOf("moov", "trak", "mdia") && type == "hdlr"
            handlerBytes = 0
            if (bodyIsHandler && end - position < 12) throw Mp4ObservationError()
            finishBody()
        }
        closeParents()
    }

    private fun finishBody() {
        if (bodyEnd == position) {
            if (bodyIsHandler && handlerBytes < 12) throw Mp4ObservationError()
            bodyEnd = null
            bodyIsHandler = false
            handlerBytes = 0
        }
    }

    private fun closeParents() {
        if (bodyEnd != null || headerBytes != 0) return
        while (parents.isNotEmpty() && position == parents.last().end) {
            if (parents.removeLast().type == "moov") {
                types = Types(pendingVideo, pendingAudio)
                revision++
                inMoov = false
            }
        }
        if (parents.lastOrNull()?.let { position > it.end } == true) throw Mp4ObservationError()
    }

    private fun add(a: Long, b: Long): Long =
        try {
            Math.addExact(a, b)
        } catch (_: ArithmeticException) {
            throw Mp4ObservationError()
        }

    private fun unsigned32(data: ByteArray, offset: Int): Long =
        (0..3).fold(0L) { n, i -> (n shl 8) or (data[offset + i].toLong() and 255) }
}
