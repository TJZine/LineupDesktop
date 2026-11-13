#ifndef LINEUP_PLAYER_CORE_SESSION_PLAYLIST_H_
#define LINEUP_PLAYER_CORE_SESSION_PLAYLIST_H_

#include <mpv/stream_cb.h>

#include <cstddef>
#include <cstdint>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <string_view>
#include <utility>

namespace lineup::player {

// Owns only a completely validated, finite session view. Revocation wipes its
// bytes even when libmpv still holds a stream cookie. No callback calls libmpv.
class SessionPlaylist {
 public:
  static constexpr size_t kMaximumBytes = 1024 * 1024;
  static std::shared_ptr<SessionPlaylist> Parse(std::string_view original,
                                               std::string_view variant,
                                               int64_t offset_microseconds);
  ~SessionPlaylist();
  size_t byte_size() const;
  int64_t target_duration_seconds() const { return target_duration_seconds_; }
  void Retire();

 private:
  friend class SessionPlaylistRegistry;
  SessionPlaylist(std::string bytes, int64_t target_duration_seconds)
      : bytes_(std::move(bytes)), target_duration_seconds_(target_duration_seconds) {}
  mutable std::mutex mutex_;
  std::string bytes_;
  const int64_t target_duration_seconds_;
  bool retired_ = false;
};

// One registration per mpv instance; the API has no unregister operation.
// Keep this owner alive until terminate_destroy returns. Per-load capabilities
// are revoked on replacement/stop, and contain no source identity or URL.
class SessionPlaylistRegistry {
 public:
  static constexpr const char* kProtocol = "lineup-session";
  // Custom streams have mpv's UNSAFE origin, not its NET sandbox. The
  // closed manifest grammar, absolute same-origin HTTPS references and these
  // per-file lavf selection and FFmpeg lists jointly constrain delivery. New URI-bearing tags,
  // formats or protocols require a new containment review. Lavf-only
  // selection prevents mpv's generic M3U fallback from reopening children
  // with global options; HLS child demuxers deny further nested I/O and MOV
  // external data references remain disabled by default in the pinned runtime.
  // Key/value option values use mpv's %BYTECOUNT% quoting, so the commas
  // remain inside the two FFmpeg lists rather than creating new options.
  static constexpr const char* kLavfOptions =
      "format_whitelist=%7%hls,mov,protocol_whitelist=%13%https,tls,tcp";
  ~SessionPlaylistRegistry();
  std::optional<std::string> Activate(std::shared_ptr<SessionPlaylist> playlist);
  void Retire();
  void Disable();
  void Enable();
  static int Open(void* owner, char* uri, mpv_stream_cb_info* info);

 private:
  struct Cookie;
  static int64_t Read(void* cookie, char* bytes, uint64_t count);
  static int64_t Seek(void* cookie, int64_t position);
  static int64_t Size(void* cookie);
  static void Close(void* cookie);
  static void Cancel(void* cookie);
  std::mutex mutex_;
  std::shared_ptr<SessionPlaylist> active_;
  std::string uri_;
  bool enabled_ = true;
};

}  // namespace lineup::player
#endif
