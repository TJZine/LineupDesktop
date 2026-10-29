package com.tjzine.lineup.player

import androidx.media3.common.util.UnstableApi
import androidx.media3.extractor.mp4.FragmentedMp4Extractor
import androidx.media3.extractor.mp4.Track
import androidx.media3.extractor.text.SubtitleParser

/** Fragmented extractor hook; implementations restart seek() at a box header. */
interface ParsedTrackReporter {
    var reportParsedTrack: (Int?) -> Unit
}

/** Media3 exposes this hook for current initialization tracks, even when outputs are reused. */
@UnstableApi
class ReportingFragmentedMp4(subtitles: SubtitleParser.Factory) :
    FragmentedMp4Extractor(subtitles, FragmentedMp4Extractor.FLAG_READ_MFRA_FOR_SEEK_MAP),
    ParsedTrackReporter {
    override var reportParsedTrack: (Int?) -> Unit = {}

    override fun modifyTrack(track: Track?): Track? {
        val parsed = super.modifyTrack(track)
        if (parsed == null) reportParsedTrack(null)
        else if (parsed.shouldBeExposed) reportParsedTrack(parsed.type)
        return parsed
    }
}
