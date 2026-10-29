package com.tjzine.lineup.player

import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.extractor.*

@UnstableApi
class GuardedMp4(
    private val delegate: Extractor,
    private val report: (Map<String, Any?>) -> Unit = {},
) : Extractor by delegate {
    private var observerRevisionForReport = 0
    private var omittedParsedTrack = false
    private val observer = Mp4TypeObserver {
        exposedVideo = false
        exposedAudio = false
        omittedParsedTrack = false
        report(mapOf("phase" to "moov-start", "revision" to (observerRevisionForReport + 1)))
    }
    private var exposedVideo = false
    private var exposedAudio = false
    private var validatedRevision = 0

    override fun init(output: ExtractorOutput) {
        observer.reset()
        exposedVideo = false
        exposedAudio = false
        validatedRevision = 0
        omittedParsedTrack = false
        (delegate as? ParsedTrackReporter)?.reportParsedTrack = { type ->
            report(mapOf("phase" to "parsed-track", "type" to type))
            when (type) {
                C.TRACK_TYPE_VIDEO -> exposedVideo = true
                C.TRACK_TYPE_AUDIO -> exposedAudio = true
                null -> omittedParsedTrack = true
            }
        }
        delegate.init(
            object : ExtractorOutput by output {
                override fun track(id: Int, type: Int): TrackOutput {
                    if (type == C.TRACK_TYPE_VIDEO) exposedVideo = true
                    if (type == C.TRACK_TYPE_AUDIO) exposedAudio = true
                    return output.track(id, type)
                }

                override fun endTracks() {
                    validate()
                    output.endTracks()
                }
            }
        )
    }

    private fun validate() {
        val types = observer.requireSnapshot()
        report(
            mapOf(
                "phase" to "validate",
                "revision" to observer.revision,
                "video" to exposedVideo,
                "audio" to exposedAudio,
                "declaredVideo" to types.video,
                "declaredAudio" to types.audio,
            )
        )
        if (types.video && !exposedVideo) throw OmittedMediaType(C.TRACK_TYPE_VIDEO)
        if (types.audio && !exposedAudio) throw OmittedMediaType(C.TRACK_TYPE_AUDIO)
        observer.markValidated()
        validatedRevision = observer.revision
        observerRevisionForReport = observer.revision
    }

    override fun seek(position: Long, timeUs: Long) {
        if (delegate is ParsedTrackReporter)
            report(mapOf("phase" to "fragment-seek", "position" to position))
        if (delegate is ParsedTrackReporter) observer.seekToBox(position)
        else observer.seek(position)
        delegate.seek(position, timeUs)
    }

    override fun read(input: ExtractorInput, seekPosition: PositionHolder): Int {
        observer.reposition(input.position)
        val forwarding =
            object : ForwardingExtractorInput(input) {
                override fun read(target: ByteArray, offset: Int, length: Int): Int {
                    val at = position
                    val n = super.read(target, offset, length)
                    if (n > 0) observer.consume(at, target, offset, n, this.length)
                    else if (n == -1) observer.eof()
                    return n
                }

                override fun readFully(
                    target: ByteArray,
                    offset: Int,
                    length: Int,
                    allowEndOfInput: Boolean,
                ): Boolean {
                    val at = position
                    val ok = super.readFully(target, offset, length, allowEndOfInput)
                    if (ok) observer.consume(at, target, offset, length, this.length)
                    else observer.eof()
                    return ok
                }

                override fun readFully(target: ByteArray, offset: Int, length: Int) {
                    val at = position
                    super.readFully(target, offset, length)
                    observer.consume(at, target, offset, length, this.length)
                }

                override fun skip(length: Int): Int {
                    val at = position
                    val n = super.skip(length)
                    if (n > 0) observer.skip(at, n.toLong()) else if (n == -1) observer.eof()
                    return n
                }

                override fun skipFully(length: Int, allowEndOfInput: Boolean): Boolean {
                    val at = position
                    val ok = super.skipFully(length, allowEndOfInput)
                    if (ok) observer.skip(at, length.toLong()) else observer.eof()
                    return ok
                }

                override fun skipFully(length: Int) {
                    val at = position
                    super.skipFully(length)
                    observer.skip(at, length.toLong())
                }
            }
        val result =
            try {
                delegate.read(forwarding, seekPosition)
            } catch (failure: IllegalStateException) {
                // Fragmented MP4 checks track-count reuse before endTracks. Its parse hook has
                // already reported this moov's recognized tracks; preserve a precise omission
                // failure.
                if (omittedParsedTrack && observer.revision > validatedRevision) validate()
                throw failure
            }
        if (observer.revision > validatedRevision) validate()
        if (result == Extractor.RESULT_SEEK) observer.reposition(seekPosition.position)
        if (result == Extractor.RESULT_END_OF_INPUT) observer.eof()
        return result
    }
}
