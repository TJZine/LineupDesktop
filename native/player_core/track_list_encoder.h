#ifndef LINEUP_PLAYER_CORE_TRACK_LIST_ENCODER_H_
#define LINEUP_PLAYER_CORE_TRACK_LIST_ENCODER_H_

#include <mpv/client.h>

#include <cstddef>
#include <string>

#include "player_core/value.h"

namespace lineup::player {

// Looks up a key in an already validated MPV_FORMAT_NODE_MAP list.
const mpv_node* FindTrackNode(const mpv_node_list& map, const char* key);

Value EncodeTrackList(const mpv_node& node);
Value EncodeVideoParameters(const mpv_node& node);
Value EncodeVideoTargetParameters(const mpv_node& node);

// Telemetry retains replacement-character handling. Track metadata supplies
// valid_utf8 to reject malformed strings instead.
std::string BoundedUtf8(const char* input, size_t limit,
                        bool* valid_utf8 = nullptr);

std::string AsciiLower(std::string value);

}  // namespace lineup::player

#endif
