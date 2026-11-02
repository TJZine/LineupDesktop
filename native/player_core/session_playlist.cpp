#include "player_core/session_playlist.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <cerrno>
#include <cstring>
#include <limits>
#include <new>
#include <set>
#include <utility>
#include <vector>

#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <bcrypt.h>
#elif defined(__APPLE__) || defined(__FreeBSD__)
#include <cstdlib>
#else
#include <sys/random.h>
#endif

namespace lineup::player {
namespace {
// FFmpeg's HLS parser stores at most MAX_URL_SIZE - 1 bytes of a physical
// line. A longer URI-bearing line would fetch a truncated, unvalidated name.
constexpr size_t kMaximumReferenceLineBytes = 4095;

void Wipe(std::string& value) {
  volatile char* cursor = value.data();
  for (size_t i = 0; i < value.size(); ++i) cursor[i] = 0;
  std::string().swap(value);
}
bool Starts(std::string_view text, std::string_view prefix) {
  return text.substr(0, prefix.size()) == prefix;
}
bool Digits(std::string_view text) {
  return !text.empty() && std::all_of(text.begin(), text.end(), [](char c) {
    return c >= '0' && c <= '9';
  });
}
std::optional<int64_t> Integer(std::string_view text, int64_t maximum) {
  if (!Digits(text)) return std::nullopt;
  int64_t value = 0;
  for (char c : text) {
    const int digit = c - '0';
    if (digit > maximum || value > (maximum - digit) / 10) return std::nullopt;
    value = value * 10 + digit;
  }
  return value;
}
std::optional<int64_t> Micros(std::string_view text) {
  const auto dot = text.find('.');
  auto whole = Integer(text.substr(0, dot), std::numeric_limits<int64_t>::max() / 1000000);
  if (!whole) return std::nullopt;
  int64_t fraction = 0;
  if (dot != std::string_view::npos) {
    auto part = text.substr(dot + 1);
    if (part.empty() || part.size() > 6 || !Digits(part)) return std::nullopt;
    fraction = *Integer(part, 999999);
    for (size_t i = part.size(); i < 6; ++i) fraction *= 10;
  }
  if (*whole > (std::numeric_limits<int64_t>::max() - fraction) / 1000000)
    return std::nullopt;
  return *whole * 1000000 + fraction;
}
// Decode without making another sensitive copy; reject controls, BOM and
// alternative line separators before splitting the original byte sequence.
bool Lexical(std::string_view text) {
  for (size_t i = 0; i < text.size();) {
    const auto a = static_cast<unsigned char>(text[i]);
    size_t count = a < 0x80 ? 1 : a >= 0xc2 && a <= 0xdf ? 2 :
                   a >= 0xe0 && a <= 0xef ? 3 : a >= 0xf0 && a <= 0xf4 ? 4 : 0;
    if (!count || count > text.size() - i) return false;
    uint32_t cp = a & (count == 1 ? 0x7f : count == 2 ? 0x1f : count == 3 ? 0xf : 7);
    for (size_t j = 1; j < count; ++j) {
      const auto b = static_cast<unsigned char>(text[i + j]);
      if ((b & 0xc0) != 0x80) return false;
      cp = (cp << 6) | (b & 0x3f);
    }
    if ((count == 2 && cp < 0x80) || (count == 3 && cp < 0x800) ||
        (count == 4 && cp < 0x10000) || cp > 0x10ffff ||
        (cp >= 0xd800 && cp <= 0xdfff) || (cp < 32 && cp != '\r' && cp != '\n') ||
        cp == 127 || cp == 0x85 || cp == 0x2028 || cp == 0x2029 || cp == 0xfeff)
      return false;
    i += count;
  }
  return true;
}
bool UriBytes(std::string_view text) {
  return !text.empty() && text.size() <= 4096 && std::all_of(text.begin(), text.end(), [](unsigned char c) {
    return c > 32 && c < 127 && c != '\\' && c != '%' && c != '?' && c != '#' && c != '"';
  });
}
struct HttpsUri {
  std::string origin;
  std::string_view authority;
  std::string_view path;
};
std::optional<HttpsUri> Https(std::string_view text) {
  if (!UriBytes(text) || !Starts(text, "https://")) return std::nullopt;
  const auto slash = text.find('/', 8);
  if (slash == std::string_view::npos) return std::nullopt;
  const auto authority = text.substr(8, slash - 8);
  if (authority.empty() || authority.find('@') != std::string_view::npos) return std::nullopt;
  std::string_view host, port;
  if (authority.front() == '[') {
    const auto end = authority.find(']');
    if (end == std::string_view::npos || end < 3) return std::nullopt;
    host = authority.substr(0, end + 1);
    if (!std::all_of(host.begin() + 1, host.end() - 1, [](char c) {
          return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') ||
                 (c >= 'A' && c <= 'F') || c == ':' || c == '.';
        }) || host.find(':') == std::string_view::npos) return std::nullopt;
    if (end + 1 != authority.size()) {
      if (authority[end + 1] != ':') return std::nullopt;
      port = authority.substr(end + 2);
      if (port.empty()) return std::nullopt;
    }
  } else {
    const auto colon = authority.find(':');
    host = authority.substr(0, colon);
    if (host.empty() || !std::all_of(host.begin(), host.end(), [](char c) {
          return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') ||
                 (c >= 'A' && c <= 'Z') || c == '.' || c == '-';
        })) return std::nullopt;
    if (colon != std::string_view::npos) {
      port = authority.substr(colon + 1);
      if (port.empty()) return std::nullopt;
    }
  }
  auto number = port.empty() ? std::optional<int64_t>(443) : Integer(port, 65535);
  if (!number || *number == 0) return std::nullopt;
  std::string origin(host);
  for (char& c : origin) if (c >= 'A' && c <= 'Z') c = static_cast<char>(c + ('a' - 'A'));
  origin += ':' + std::to_string(*number);
  return HttpsUri{std::move(origin), authority, text.substr(slash)};
}
bool SessionPath(std::string_view path) {
  constexpr std::string_view prefix = "/video/:/transcode/universal/session/";
  constexpr std::string_view suffix = "/base/index.m3u8";
  if (!Starts(path, prefix) || path.size() <= prefix.size() + suffix.size() ||
      path.substr(path.size() - suffix.size()) != suffix) return false;
  auto id = path.substr(prefix.size(), path.size() - prefix.size() - suffix.size());
  return id.size() <= 128 && std::all_of(id.begin(), id.end(), [](char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
           (c >= '0' && c <= '9') || c == '-' || c == '_';
  });
}
std::optional<std::string> Reference(std::string_view raw, std::string_view variant,
                                    const HttpsUri& base) {
  if (!UriBytes(raw)) return std::nullopt;
  const auto directory = base.path.substr(0, base.path.rfind('/') + 1);
  std::string resolved;
  if (Starts(raw, "https://")) resolved = raw;
  else {
    // Flat relative names only: neither an authority nor a root/path escape.
    if (raw.find_first_of("/:") != std::string_view::npos) return std::nullopt;
    resolved = std::string(variant.substr(0, variant.rfind('/') + 1)) + std::string(raw);
  }
  if (resolved.size() > kMaximumReferenceLineBytes) return std::nullopt;
  auto uri = Https(resolved);
  if (!uri || uri->origin != base.origin || !Starts(uri->path, directory)) return std::nullopt;
  auto filename = uri->path.substr(directory.size());
  if (filename.empty() || filename == "." || filename == ".." ||
      filename.find('/') != std::string_view::npos || uri->path == base.path) return std::nullopt;
  return resolved;
}
std::optional<std::string> Capability() {
  std::array<unsigned char, 16> bytes{};
#ifdef _WIN32
  if (BCryptGenRandom(nullptr, bytes.data(), static_cast<ULONG>(bytes.size()),
                      BCRYPT_USE_SYSTEM_PREFERRED_RNG) < 0) return std::nullopt;
#elif defined(__APPLE__) || defined(__FreeBSD__)
  arc4random_buf(bytes.data(), bytes.size());
#else
  size_t filled = 0;
  while (filled < bytes.size()) {
    const auto count = getrandom(bytes.data() + filled, bytes.size() - filled, 0);
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) return std::nullopt;
    filled += static_cast<size_t>(count);
  }
#endif
  constexpr char hex[] = "0123456789abcdef";
  std::string result = "lineup-session://";
  for (unsigned char b : bytes) { result += hex[b >> 4]; result += hex[b & 15]; }
  return result + ".m3u8";
}
struct Line {
  std::string_view text;
  std::string_view ending;
  bool remove = false;
  enum class Normalize { none, media, map };
  Normalize normalize = Normalize::none;
};
}  // namespace

std::shared_ptr<SessionPlaylist> SessionPlaylist::Parse(std::string_view original,
                                                       std::string_view variant,
                                                       int64_t offset) {
  if (original.empty() || original.size() > kMaximumBytes || offset < 0 || !Lexical(original)) return {};
  const auto base = Https(variant);
  if (!base || !SessionPath(base->path)) return {};
  std::vector<Line> lines;
  for (size_t cursor = 0; cursor < original.size();) {
    const auto end = original.find_first_of("\r\n", cursor);
    const auto length = (end == std::string_view::npos ? original.size() : end) - cursor;
    auto next = cursor + length;
    if (next < original.size()) { ++next; if (original[next - 1] == '\r' && next < original.size() && original[next] == '\n') ++next; }
    if (lines.size() >= 20064) return {};
    lines.push_back({original.substr(cursor, length), original.substr(cursor + length, next - cursor - length), false, Line::Normalize::none});
    cursor = next;
  }
  if (lines.empty() || lines.front().text != "#EXTM3U") return {};
  std::set<std::string_view> seen;
  std::set<std::string> refs;
  std::vector<std::pair<size_t, size_t>> pairs;
  std::vector<int64_t> durations;
  std::optional<size_t> pending;
  std::optional<std::string> init;
  std::optional<int64_t> target, sequence, start;
  size_t comments = 0;
  bool ended = false;
  constexpr std::string_view tags[] = {"EXTM3U", "EXT-X-VERSION", "EXT-X-PLAYLIST-TYPE", "EXT-X-TARGETDURATION", "EXT-X-MEDIA-SEQUENCE", "EXT-X-START", "EXT-X-MAP", "EXT-X-INDEPENDENT-SEGMENTS", "EXTINF", "EXT-X-ENDLIST"};
  for (size_t i = 1; i < lines.size(); ++i) {
    auto line = lines[i].text;
    if (line.empty()) continue;
    if (static_cast<unsigned char>(line.front()) <= 32 || static_cast<unsigned char>(line.front()) >= 128) return {};
    if (ended) return {};
    if (line.front() != '#') {
      if (!pending || !init || durations.size() > 10000) return {};
      auto uri = Reference(line, variant, *base);
      if (!uri) return {};
      const auto filename = uri->substr(uri->rfind('/') + 1);
      if (filename == init->substr(init->rfind('/') + 1) ||
          !refs.insert(filename).second) return {};
      if (*uri != line) lines[i].normalize = Line::Normalize::media;
      pairs.emplace_back(*pending, i); pending.reset();
      continue;
    }
    const auto tag = line.substr(1, line.find(':') == std::string_view::npos ? line.size() - 1 : line.find(':') - 1);
    const bool allowed = std::find(std::begin(tags), std::end(tags), tag) != std::end(tags);
    if (!allowed) {
      if (Starts(line, "#EXT") || ++comments > 16 || line.size() > 256) return {};
      continue;
    }
    if (tag != "EXTINF" && !seen.insert(tag).second) return {};
    if (tag == "EXT-X-TARGETDURATION") {
      if (!Starts(line, "#EXT-X-TARGETDURATION:")) return {};
      target = Integer(line.substr(22), 120); if (!target || *target == 0) return {};
    } else if (tag == "EXT-X-MEDIA-SEQUENCE") {
      if (!Starts(line, "#EXT-X-MEDIA-SEQUENCE:")) return {};
      sequence = Integer(line.substr(22), 0); if (!sequence) return {};
    } else if (tag == "EXT-X-VERSION") {
      if (!Starts(line, "#EXT-X-VERSION:")) return {};
      auto version = Integer(line.substr(15), 10); if (!version || *version < 1) return {};
    } else if (tag == "EXT-X-PLAYLIST-TYPE") {
      if (line != "#EXT-X-PLAYLIST-TYPE:VOD") return {};
    } else if (tag == "EXT-X-INDEPENDENT-SEGMENTS") {
      if (line != "#EXT-X-INDEPENDENT-SEGMENTS") return {};
    } else if (tag == "EXT-X-MAP") {
      constexpr std::string_view prefix = "#EXT-X-MAP:URI=\"";
      if (init || !pairs.empty() || pending || !Starts(line, prefix) ||
          line.size() <= prefix.size() || line.size() > kMaximumReferenceLineBytes ||
          line.back() != '"') return {};
      auto uri = Reference(line.substr(prefix.size(), line.size() - prefix.size() - 1), variant, *base);
      if (!uri || prefix.size() + uri->size() + 1 > kMaximumReferenceLineBytes) return {};
      init = *uri;
      if (*uri != line.substr(prefix.size(), line.size() - prefix.size() - 1)) lines[i].normalize = Line::Normalize::map;
    } else if (tag == "EXT-X-START") {
      constexpr std::string_view prefix = "#EXT-X-START:TIME-OFFSET=";
      if (!Starts(line, prefix)) return {};
      start = Micros(line.substr(prefix.size())); if (!start || *start != offset) return {};
      lines[i].remove = true;
    } else if (tag == "EXTINF") {
      if (pending) return {};
      const auto comma = line.find(',');
      if (!Starts(line, "#EXTINF:") || comma == std::string_view::npos) return {};
      const auto duration = Micros(line.substr(8, comma - 8));
      if (!duration || *duration <= 0 || *duration > 120000000) return {};
      durations.push_back(*duration); pending = i;
    } else if (tag == "EXT-X-ENDLIST") {
      if (line != "#EXT-X-ENDLIST" || pending) return {};
      ended = true;
    } else return {};
  }
  if (!ended || !init || !target || !sequence || pending || pairs.empty() ||
      pairs.size() != durations.size() || start.value_or(0) != offset) return {};
  int64_t boundary = 0;
  std::optional<size_t> containing;
  for (size_t i = 0; i < durations.size(); ++i) {
    if (boundary > std::numeric_limits<int64_t>::max() - durations[i]) return {};
    if (boundary <= offset && offset < boundary + durations[i]) containing = i;
    boundary += durations[i];
  }
  if (!containing) return {};
  for (size_t i = 0; i < *containing; ++i) { lines[pairs[i].first].remove = true; lines[pairs[i].second].remove = true; }
  std::string output;
  const auto directory = variant.substr(0, variant.rfind('/') + 1);
  for (const auto& line : lines) {
    if (line.remove) continue;
    size_t rendered_size = line.text.size();
    if (line.normalize != Line::Normalize::none) rendered_size += directory.size();
    if (rendered_size > kMaximumBytes - output.size() ||
        line.ending.size() > kMaximumBytes - output.size() - rendered_size) {
      Wipe(output); return {};
    }
    if (line.normalize == Line::Normalize::media) {
      output += directory; output += line.text;
    } else if (line.normalize == Line::Normalize::map) {
      constexpr std::string_view prefix = "#EXT-X-MAP:URI=\"";
      output += prefix; output += directory; output += line.text.substr(prefix.size());
    } else output += line.text;
    output += line.ending;
  }
  return std::shared_ptr<SessionPlaylist>(new SessionPlaylist(std::move(output)));
}
SessionPlaylist::~SessionPlaylist() { Retire(); }

size_t SessionPlaylist::byte_size() const {
  std::lock_guard lock(mutex_);
  return bytes_.size();
}

void SessionPlaylist::Retire() {
  std::lock_guard lock(mutex_);
  retired_ = true;
  Wipe(bytes_);
}

struct SessionPlaylistRegistry::Cookie {
  std::shared_ptr<SessionPlaylist> playlist;
  size_t cursor = 0;
  std::atomic<bool> cancelled{false};
};
SessionPlaylistRegistry::~SessionPlaylistRegistry() { Disable(); }
std::optional<std::string> SessionPlaylistRegistry::Activate(std::shared_ptr<SessionPlaylist> playlist) {
  Retire();
  auto uri = Capability();
  if (!uri || !playlist) {
    if (playlist) playlist->Retire();
    return std::nullopt;
  }
  std::lock_guard lock(mutex_);
  if (!enabled_) {
    playlist->Retire();
    return std::nullopt;
  }
  active_ = std::move(playlist);
  uri_ = *uri;
  return uri;
}
void SessionPlaylistRegistry::Retire() {
  std::lock_guard lock(mutex_);
  if (active_) active_->Retire();
  active_.reset();
  uri_.clear();
}
void SessionPlaylistRegistry::Disable() {
  std::lock_guard lock(mutex_);
  enabled_ = false;
  if (active_) active_->Retire();
  active_.reset();
  uri_.clear();
}
void SessionPlaylistRegistry::Enable() {
  std::lock_guard lock(mutex_);
  enabled_ = true;
}
int SessionPlaylistRegistry::Open(void* owner, char* uri, mpv_stream_cb_info* info) {
  if (!owner || !uri || !info) return MPV_ERROR_LOADING_FAILED;
  auto& self = *static_cast<SessionPlaylistRegistry*>(owner);
  std::lock_guard lock(self.mutex_);
  if (!self.active_ || self.uri_ != uri) return MPV_ERROR_LOADING_FAILED;
  auto* cookie = new (std::nothrow) Cookie{self.active_};
  if (!cookie) return MPV_ERROR_LOADING_FAILED;
  *info = {cookie, Read, Seek, Size, Close, Cancel};
  return 0;
}
int64_t SessionPlaylistRegistry::Read(void* value, char* bytes, uint64_t count) {
  auto& cookie = *static_cast<Cookie*>(value);
  auto& playlist = *cookie.playlist;
  std::lock_guard lock(playlist.mutex_);
  if (cookie.cancelled || playlist.retired_ || !bytes) return -1;
  const auto size = std::min<uint64_t>(count, playlist.bytes_.size() - cookie.cursor);
  std::memcpy(bytes, playlist.bytes_.data() + cookie.cursor, static_cast<size_t>(size));
  cookie.cursor += static_cast<size_t>(size);
  return static_cast<int64_t>(size);
}
int64_t SessionPlaylistRegistry::Seek(void* value, int64_t position) {
  auto& cookie = *static_cast<Cookie*>(value);
  auto& playlist = *cookie.playlist;
  std::lock_guard lock(playlist.mutex_);
  if (cookie.cancelled || playlist.retired_ || position < 0 || static_cast<uint64_t>(position) > playlist.bytes_.size()) return MPV_ERROR_GENERIC;
  cookie.cursor = static_cast<size_t>(position);
  return position;
}
int64_t SessionPlaylistRegistry::Size(void* value) {
  auto& cookie = *static_cast<Cookie*>(value);
  auto& playlist = *cookie.playlist;
  std::lock_guard lock(playlist.mutex_);
  return cookie.cancelled || playlist.retired_ ? MPV_ERROR_GENERIC : static_cast<int64_t>(playlist.bytes_.size());
}
void SessionPlaylistRegistry::Close(void* cookie) {
  delete static_cast<Cookie*>(cookie);
}
void SessionPlaylistRegistry::Cancel(void* cookie) {
  static_cast<Cookie*>(cookie)->cancelled = true;
}
}  // namespace lineup::player
