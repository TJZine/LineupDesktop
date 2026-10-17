#include "player_core/track_list_encoder.h"

#include <algorithm>
#include <cctype>
#include <cstring>
#include <utility>

namespace lineup::player {

namespace {

constexpr size_t kMaxMetadataBytes = 64 * 1024;
constexpr size_t kMaxMetadataStringBytes = 4096;

}  // namespace

std::string AsciiLower(std::string value) {
  std::transform(value.begin(), value.end(), value.begin(), [](unsigned char byte) {
    return static_cast<char>(std::tolower(byte));
  });
  return value;
}

std::string BoundedUtf8(const char* input, size_t limit, bool* valid_utf8) {
  if (valid_utf8) *valid_utf8 = true;
  std::string value;
  for (size_t offset = 0; input && input[offset] && value.size() < limit;) {
    const auto lead = static_cast<unsigned char>(input[offset]);
    size_t length = lead < 0x80                    ? 1
                    : lead >= 0xC2 && lead <= 0xDF ? 2
                    : lead >= 0xE0 && lead <= 0xEF ? 3
                    : lead >= 0xF0 && lead <= 0xF4 ? 4
                                                   : 0;
    bool valid = length != 0;
    for (size_t index = 1; valid && index < length; ++index) {
      const auto byte = static_cast<unsigned char>(input[offset + index]);
      valid = input[offset + index] && (byte & 0xC0) == 0x80;
    }
    if (valid && length == 3) {
      const auto second = static_cast<unsigned char>(input[offset + 1]);
      valid =
          !(lead == 0xE0 && second < 0xA0) && !(lead == 0xED && second >= 0xA0);
    } else if (valid && length == 4) {
      const auto second = static_cast<unsigned char>(input[offset + 1]);
      valid =
          !(lead == 0xF0 && second < 0x90) && !(lead == 0xF4 && second >= 0x90);
    }
    if (!valid && valid_utf8) {
      *valid_utf8 = false;
      return {};
    }
    if (valid && value.size() + length <= limit) {
      value.append(input + offset, length);
      offset += length;
    } else if (!valid && value.size() + 3 <= limit) {
      value.append("\xEF\xBF\xBD", 3);
      ++offset;
    } else {
      break;
    }
  }
  return value;
}

const mpv_node* FindTrackNode(const mpv_node_list& map, const char* key) {
  for (int index = 0; index < map.num; ++index) {
    if (map.keys[index] && std::strcmp(map.keys[index], key) == 0) {
      return &map.values[index];
    }
  }
  return nullptr;
}

namespace {

const char* TrackType(const mpv_node* node) {
  if (node && node->format == MPV_FORMAT_STRING && node->u.string) {
    for (const char* type : {"video", "audio", "sub"}) {
      if (std::strcmp(node->u.string, type) == 0) return type;
    }
  }
  return nullptr;
}

const mpv_node* FindNode(const mpv_node& map, const char* key) {
  if (map.format != MPV_FORMAT_NODE_MAP || !map.u.list) {
    return nullptr;
  }
  return FindTrackNode(*map.u.list, key);
}

Value EncodeWhitelistedNode(const mpv_node* node, size_t& remaining_bytes) {
  if (!node) {
    return Value();
  }
  switch (node->format) {
    case MPV_FORMAT_STRING:
      if (node->u.string) {
        const size_t limit = std::min(kMaxMetadataStringBytes, remaining_bytes);
        std::string value = BoundedUtf8(node->u.string, limit);
        remaining_bytes -= value.size();
        return Value(std::move(value));
      }
      return Value("");
    case MPV_FORMAT_FLAG:
      return Value(node->u.flag != 0);
    case MPV_FORMAT_INT64:
      return Value(node->u.int64);
    case MPV_FORMAT_DOUBLE:
      return Value(node->u.double_);
    default:
      return Value();
  }
}

}  // namespace

Value EncodeTrackList(const mpv_node& node) {
  ValueList tracks;
  size_t remaining_optional_string_bytes = 64 * 1024;
  constexpr size_t kMaxStringBytes = 4096;
  constexpr int kMaxTracks = 256;
  if (node.format != MPV_FORMAT_NODE_ARRAY || !node.u.list ||
      !node.u.list->values) {
    return Value(tracks);
  }
  const int count = std::min(node.u.list->num, kMaxTracks);
  for (int index = 0; index < count; ++index) {
    const mpv_node& track = node.u.list->values[index];
    if (track.format != MPV_FORMAT_NODE_MAP || !track.u.list ||
        track.u.list->num <= 0 || !track.u.list->keys ||
        !track.u.list->values) {
      continue;
    }
    const auto& map = *track.u.list;
    const auto* id = FindTrackNode(map, "id");
    const char* type = TrackType(FindTrackNode(map, "type"));
    const auto* selected = FindTrackNode(map, "selected");
    if (!id || id->format != MPV_FORMAT_INT64 || id->u.int64 <= 0 || !type ||
        !selected || selected->format != MPV_FORMAT_FLAG) {
      continue;
    }
    ValueMap value = {
        {"id", Value(id->u.int64)},
        {"type", Value(type)},
        {"selected", Value(selected->u.flag != 0)},
    };
    for (const char* key : {"title", "lang", "codec", "demux-channels"}) {
      const auto* fact = FindTrackNode(map, key);
      if (!fact || fact->format != MPV_FORMAT_STRING || !fact->u.string ||
          remaining_optional_string_bytes == 0) {
        continue;
      }
      bool valid_utf8 = false;
      std::string text =
          BoundedUtf8(fact->u.string,
                      std::min(kMaxStringBytes, remaining_optional_string_bytes), &valid_utf8);
      if (!valid_utf8 || (text.empty() && fact->u.string[0] != '\0')) {
        continue;
      }
      remaining_optional_string_bytes -= text.size();
      value.emplace(key, Value(std::move(text)));
    }
    const auto* channels = FindTrackNode(map, "demux-channel-count");
    if (channels && channels->format == MPV_FORMAT_INT64 &&
        channels->u.int64 > 0) {
      value.emplace("demux-channel-count", Value(channels->u.int64));
    }
    for (const char* key : {"forced", "external", "hearing-impaired",
                            "visual-impaired", "commentary"}) {
      const auto* fact = FindTrackNode(map, key);
      if (fact && fact->format == MPV_FORMAT_FLAG) {
        value.emplace(key, Value(fact->u.flag != 0));
      }
    }
    tracks.emplace_back(std::move(value));
  }
  return Value(std::move(tracks));
}

Value EncodeVideoParameters(const mpv_node& node) {
  ValueMap parameters;
  size_t remaining_bytes = kMaxMetadataBytes;
  for (const char* key : {"w", "h", "pixelformat", "hw-pixelformat",
                          "primaries", "gamma", "colormatrix", "sig-peak"}) {
    parameters[key] = EncodeWhitelistedNode(FindNode(node, key), remaining_bytes);
  }
  return Value(parameters);
}

Value EncodeVideoTargetParameters(const mpv_node& node) {
  ValueMap parameters;
  for (const char* key : {"gamma", "primaries", "pixelformat"}) {
    const mpv_node* value = FindNode(node, key);
    std::string normalized;
    if (value && value->format == MPV_FORMAT_STRING && value->u.string) {
      normalized = AsciiLower(BoundedUtf8(value->u.string, 64));
      if (normalized.empty() || !std::all_of(normalized.begin(), normalized.end(),
          [](unsigned char byte) {
            return (byte >= 'a' && byte <= 'z') || (byte >= '0' && byte <= '9') ||
                   byte == '-' || byte == '_' || byte == '.';
          })) normalized.clear();
    }
    parameters[key] = normalized.empty() ? Value() : Value(normalized);
  }
  return Value(parameters);
}

}  // namespace lineup::player
