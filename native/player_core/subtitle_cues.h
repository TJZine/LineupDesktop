#ifndef LINEUP_PLAYER_CORE_SUBTITLE_CUES_H_
#define LINEUP_PLAYER_CORE_SUBTITLE_CUES_H_

#include <string_view>
#include "player_core/value.h"

namespace lineup::player {

// Mirrors sd_ass/sd_lavc at mpv 3186d369. No user decoder options are
// accepted by the player, so teletext/ARIB use their bitmap defaults.
enum class SubtitleCodec { none, text, ass, image };
SubtitleCodec ClassifySubtitleCodec(std::string_view codec);

// Bounded media-content conversion, never diagnostic text. The input is the
// current sub-text/ass value (one real newline per event), not an ASS file.
// Native ASS opt-in excludes positioned signs and drawing events entirely.
constexpr size_t kMaxSubtitleInputBytes = 64 * 1024;
ValueList ParseSubtitleCues(std::string_view text, bool native_ass);

}  // namespace lineup::player
#endif
