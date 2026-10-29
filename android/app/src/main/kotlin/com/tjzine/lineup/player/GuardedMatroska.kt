package com.tjzine.lineup.player

import android.net.Uri
import androidx.media3.common.C
import androidx.media3.common.ParserException
import androidx.media3.common.util.UnstableApi
import androidx.media3.extractor.*
import androidx.media3.extractor.mkv.MatroskaExtractor
import androidx.media3.extractor.mp4.FragmentedMp4Extractor
import androidx.media3.extractor.mp4.Mp4Extractor
import androidx.media3.extractor.text.DefaultSubtitleParserFactory
import androidx.media3.extractor.text.SubtitleParser

/** A typed, credential-free source failure; adapter maps this before generic parser errors. */
@UnstableApi
class OmittedMediaType(val mediaType: Int) :
    ParserException(
        if (mediaType == C.TRACK_TYPE_VIDEO) "unsupported_video_track"
        else "unsupported_audio_track",
        null,
        false,
        C.DATA_TYPE_MEDIA,
    )

/** Uses Media3's EBML parser. No codec list or second parser is maintained here. */
@UnstableApi
class GuardedMatroska private constructor(private val parser: Parser) : Extractor by parser {
    constructor(
        subtitles: SubtitleParser.Factory = DefaultSubtitleParserFactory()
    ) : this(Parser(subtitles))

    override fun init(output: ExtractorOutput) {
        parser.resetPresence()
        parser.init(
            object : ExtractorOutput by output {
                override fun track(id: Int, type: Int): TrackOutput {
                    if (type == C.TRACK_TYPE_VIDEO) parser.exposedVideo = true
                    if (type == C.TRACK_TYPE_AUDIO) parser.exposedAudio = true
                    return output.track(id, type)
                }
            }
        )
    }

    private class Parser(subtitles: SubtitleParser.Factory) : MatroskaExtractor(subtitles) {
        private var declaredVideo = false
        private var declaredAudio = false
        var exposedVideo = false
        var exposedAudio = false

        fun resetPresence() {
            declaredVideo = false
            declaredAudio = false
            exposedVideo = false
            exposedAudio = false
        }

        override fun startMasterElement(id: Int, position: Long, size: Long) {
            // A seek can reparse Tracks; begin a fresh comparison only for a new Tracks element.
            if (id == 0x1654AE6B) resetPresence()
            super.startMasterElement(id, position, size)
        }

        override fun integerElement(id: Int, value: Long) {
            if (id == 0x83) {
                // EBML TrackType: 1=video, 2=audio. These are NOT Media3's constants.
                if (value == 1L) declaredVideo = true
                if (value == 2L) declaredAudio = true
            }
            super.integerElement(id, value)
        }

        override fun endMasterElement(id: Int) {
            // Check before super: otherwise all-omitted files throw its generic 'No valid tracks'.
            if (id == 0x1654AE6B) {
                if (declaredVideo && !exposedVideo) throw OmittedMediaType(C.TRACK_TYPE_VIDEO)
                if (declaredAudio && !exposedAudio) throw OmittedMediaType(C.TRACK_TYPE_AUDIO)
            }
            super.endMasterElement(id)
        }
        // Ordinary cluster seeks retain track declarations just as the parent retains tracks.
        // A newly parsed Tracks element resets all four facts above; each load gets a new parser.
    }
}

@UnstableApi
class GuardedExtractorsFactory(private val report: (Map<String, Any?>) -> Unit = {}) :
    ExtractorsFactory {
    private val defaults = DefaultExtractorsFactory()
    private var subtitles: SubtitleParser.Factory = DefaultSubtitleParserFactory()

    override fun setSubtitleParserFactory(factory: SubtitleParser.Factory): ExtractorsFactory {
        subtitles = factory
        defaults.setSubtitleParserFactory(factory)
        return this
    }

    override fun createExtractors(): Array<Extractor> = wrap(defaults.createExtractors())

    override fun createExtractors(uri: Uri, headers: Map<String, List<String>>): Array<Extractor> =
        wrap(defaults.createExtractors(uri, headers))

    private fun wrap(extractors: Array<Extractor>) =
        extractors
            .map {
                when (it) {
                    is MatroskaExtractor -> GuardedMatroska(subtitles)
                    is FragmentedMp4Extractor ->
                        GuardedMp4(ReportingFragmentedMp4(subtitles), report)
                    is Mp4Extractor -> GuardedMp4(it, report)
                    else -> it
                }
            }
            .toTypedArray()
}
