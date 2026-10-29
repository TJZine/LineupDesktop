#include "player_core/subtitle_cues.h"

#include <algorithm>
#include <cstdint>
#include <string>

namespace lineup::player {
namespace {
constexpr size_t kMaxTextBytes = 4096;
constexpr size_t kMaxCues = 8;
constexpr size_t kMaxLines = 8;
constexpr size_t kMaxSegments = 32;

struct Style {
  bool italic = false;
  bool bold = false;
  bool underline = false;
  bool operator==(const Style& other) const {
    return italic == other.italic && bold == other.bold && underline == other.underline;
  }
};

bool TagLetter(char c) {
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
}

bool PositiveDrawingMode(std::string_view argument) {
  // ASS drawing mode is an integer. Inspect its sign and digits without
  // accumulating a value, so even oversized untrusted arguments cannot overflow.
  size_t i = 0;
  while (i < argument.size() && (argument[i] == ' ' || argument[i] == '\t')) ++i;
  if (i < argument.size() && argument[i] == '-') return false;
  if (i < argument.size() && argument[i] == '+') ++i;
  bool positive = false;
  while (i < argument.size() && argument[i] >= '0' && argument[i] <= '9') {
    positive = positive || argument[i] != '0';
    ++i;
  }
  return positive;
}

bool IsSign(std::string_view event) {
  // Tags only have meaning inside an override block. Avoid rejecting literal
  // dialogue that happens to contain a backslash outside a block.
  int depth = 0;
  for (size_t i = 0; i < event.size(); ++i) {
    if (event[i] == '{') ++depth;
    if (event[i] == '}' && depth > 0) --depth;
    if (!depth || event[i] != '\\') continue;
    const size_t start = i + 1;
    size_t end = start;
    while (end < event.size() && TagLetter(event[end])) ++end;
    const auto name = event.substr(start, end - start);
    // Match complete tag names: pbo, position and style/font names are not
    // drawing or positioning tags. A p0 reset alone is ordinary dialogue.
    if (name == "pos" || name == "move" || name == "org" ||
        name == "clip" || name == "iclip" ||
        (name == "p" && PositiveDrawingMode(event.substr(end)))) return true;
  }
  return false;
}

// Returns a valid UTF-8 scalar width; invalid bytes are discarded. Never emit
// half a character at either the input or output boundary.
size_t ScalarBytes(std::string_view s) {
  const auto first = static_cast<unsigned char>(s[0]);
  if (first < 0x80) return first >= 0x20 || first == '\t' ? 1 : 0;
  const size_t n = first >= 0xc2 && first <= 0xdf ? 2 :
                   first >= 0xe0 && first <= 0xef ? 3 :
                   first >= 0xf0 && first <= 0xf4 ? 4 : 0;
  if (!n || s.size() < n) return 0;
  uint32_t scalar = first & (0x7f >> n);
  for (size_t i = 1; i < n; ++i) {
    const auto c = static_cast<unsigned char>(s[i]);
    if ((c & 0xc0) != 0x80) return 0;
    scalar = (scalar << 6) | (c & 0x3f);
  }
  if ((n == 2 && scalar < 0x80) || (n == 3 && scalar < 0x800) ||
      (n == 4 && scalar < 0x10000) || scalar > 0x10ffff ||
      (scalar >= 0xd800 && scalar <= 0xdfff)) return 0;
  return n;
}

Value ParseEvent(std::string_view event, size_t& bytes) {
  Style style, segment_style;
  int align = 2;
  ValueList lines, segments;
  std::string text;
  bool has_text = false;
  auto flush = [&] {
    if (text.empty()) return;
    ValueMap segment{{"text", Value(std::move(text))}};
    if (segment_style.italic) segment["italic"] = Value(true);
    if (segment_style.bold) segment["bold"] = Value(true);
    if (segment_style.underline) segment["underline"] = Value(true);
    segments.emplace_back(std::move(segment));
    text.clear();
  };
  auto line = [&] {
    flush();
    lines.emplace_back(std::move(segments));
    segments.clear();
  };
  for (size_t i = 0; i < event.size() && bytes < kMaxTextBytes;) {
    if (event[i] == '{') {
      int depth = 1;
      const size_t start = ++i;
      while (i < event.size() && depth) {
        if (event[i] == '{') ++depth;
        if (event[i] == '}') --depth;
        if (depth) ++i;
      }
      // An unfinished or nested block is discarded in its entirety.
      if (depth) break;
      auto block = event.substr(start, i - start);
      ++i;
      if (block.find('{') != std::string_view::npos) continue;
      for (size_t j = 0; j < block.size(); ++j) {
        if (block[j] != '\\') continue;
        const size_t end = block.find('\\', j + 1);
        const auto tag = block.substr(j + 1, end == std::string_view::npos ? end : end - j - 1);
        if (tag.size() == 3 && tag.substr(0, 2) == "an" && tag[2] >= '1' && tag[2] <= '9') {
          align = tag[2] - '0';
        } else if (!tag.empty() && (tag[0] == 'i' || tag[0] == 'b' || tag[0] == 'u') &&
                   (tag.size() == 1 || (tag.size() == 2 && (tag[1] == '0' || tag[1] == '1')))) {
          const bool enabled = tag.size() == 2 && tag[1] == '1';
          if (tag[0] == 'i') style.italic = enabled;
          if (tag[0] == 'b') style.bold = enabled;
          if (tag[0] == 'u') style.underline = enabled;
        } else if (tag == "r") {
          style = {};
        }
      }
      continue;
    }
    if (event[i] == '\\' && i + 1 < event.size()) {
      const char escaped = event[i + 1];
      if (escaped == 'N' || escaped == 'n') {
        i += 2;
        line();
        if (lines.size() >= kMaxLines) break;
        continue;
      }
      if (escaped == 'h') {
        if (!(style == segment_style)) flush();
        if (segments.size() >= kMaxSegments) break;
        segment_style = style;
        text += ' ';
        ++bytes;
        has_text = true;
        i += 2;
        continue;
      }
    }
    const size_t n = ScalarBytes(event.substr(i));
    if (!n) { ++i; continue; }
    if (n > kMaxTextBytes - bytes) break;
    if (!(style == segment_style)) flush();
    if (segments.size() >= kMaxSegments) break;
    segment_style = style;
    text.append(event.substr(i, n));
    bytes += n;
    has_text = true;
    i += n;
  }
  if (lines.size() < kMaxLines) line();
  if (!has_text) return {};
  return Value(ValueMap{{"align", Value(align)}, {"lines", Value(std::move(lines))}});
}
}  // namespace

SubtitleCodec ClassifySubtitleCodec(std::string_view codec) {
  if (codec.empty()) return SubtitleCodec::none;
  if (codec == "ass") return SubtitleCodec::ass;
  for (auto image : {"hdmv_pgs_subtitle", "dvd_subtitle", "dvb_subtitle", "xsub", "dvb_teletext", "arib_caption"}) {
    if (codec == image) return SubtitleCodec::image;
  }
  return SubtitleCodec::text;
}

ValueList ParseSubtitleCues(std::string_view text, bool native_ass) {
  text = text.substr(0, kMaxSubtitleInputBytes);
  ValueList result;
  size_t bytes = 0;
  while (!text.empty() && result.size() < kMaxCues && bytes < kMaxTextBytes) {
    const size_t end = text.find('\n');
    const auto event = text.substr(0, end);
    if (!native_ass || !IsSign(event)) {
      auto cue = ParseEvent(event, bytes);
      if (!std::holds_alternative<std::monostate>(cue)) result.push_back(std::move(cue));
    }
    if (end == std::string_view::npos) break;
    text.remove_prefix(end + 1);
  }
  return result;
}
}  // namespace lineup::player
