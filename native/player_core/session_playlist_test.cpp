#include "player_core/session_playlist.h"

#include <atomic>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <limits>
#include <string>
#include <thread>
#include <vector>

using lineup::player::SessionPlaylist;
using lineup::player::SessionPlaylistRegistry;
namespace {
void Check(bool value, const char* obligation) {
  if (!value) { std::cerr << obligation << '\n'; std::exit(1); }
}
const std::string variant = "https://fixture.invalid:443/video/:/transcode/universal/session/test-session/base/index.m3u8";
const std::string parent = variant.substr(0, variant.rfind('/') + 1);
std::string Original(bool relative = false, const std::string& start = "9") {
  const auto base = relative ? "" : parent;
  return "#EXTM3U\r\n#EXT-X-VERSION:7\r\n#EXT-X-TARGETDURATION:10\r\n"
         "#EXT-X-MEDIA-SEQUENCE:0\r\n#EXT-X-START:TIME-OFFSET=" + start +
         "\r\n#EXT-X-MAP:URI=\"" + base + "init.mp4\"\r\n" +
         "#EXTINF:4,title\r\n" + base + "0.m4s\r\n" +
         "#EXTINF:4,\r\n" + base + "1.m4s\r\n" +
         "#EXTINF:4.000001,last\r\n" + base + "2.m4s\r\n#EXT-X-ENDLIST\r\n";
}
std::string Replace(std::string text, const std::string& from, const std::string& to) {
  const auto position = text.find(from); Check(position != std::string::npos, "test replacement exists");
  text.replace(position, from.size(), to); return text;
}
std::string ReadAll(SessionPlaylistRegistry& owner, const std::string& uri) {
  mpv_stream_cb_info info{}; auto name = uri;
  Check(SessionPlaylistRegistry::Open(&owner, name.data(), &info) == 0, "issued capability opens");
  Check(info.seek_fn(info.cookie, 0) == 0, "byte seek supported without player seek");
  std::string result(static_cast<size_t>(info.size_fn(info.cookie)), '\0');
  Check(info.read_fn(info.cookie, result.data(), result.size()) == static_cast<int64_t>(result.size()), "whole view read");
  char byte; Check(info.read_fn(info.cookie, &byte, 1) == 0, "stable EOF");
  info.close_fn(info.cookie); return result;
}
void Parser() {
  auto absolute = SessionPlaylist::Parse(Original(), variant, 9000000);
  Check(!!absolute, "real-shaped absolute original accepted");
  SessionPlaylistRegistry owner;
  auto uri = owner.Activate(absolute); Check(!!uri, "cryptographic opaque id available");
  auto output = ReadAll(owner, *uri);
  Check(output.find("#EXT-X-START") == std::string::npos && output.find(parent + "0.m4s") == std::string::npos &&
        output.find(parent + "1.m4s") != std::string::npos && output.find(parent + "2.m4s") != std::string::npos,
        "retain exactly one predecessor to the containing segment");
  Check(absolute->target_duration_seconds() == 10, "validated target duration");
  auto zero = SessionPlaylist::Parse(Original(false, "0"), variant, 0);
  Check(zero && ReadAll(owner, *owner.Activate(zero)).find(parent + "0.m4s") != std::string::npos,
        "segment zero retains the full manifest");
  Check(output.find("#EXTINF:4.000001,last\r\n") != std::string::npos &&
        output.find("#EXT-X-MAP:URI=\"" + parent + "init.mp4\"\r\n") != std::string::npos &&
        output.find("#EXT-X-MEDIA-SEQUENCE:0\r\n") != std::string::npos &&
        output.substr(output.size() - 16) == "#EXT-X-ENDLIST\r\n", "retained bytes, map, sequence and ENDLIST");
  auto relative = SessionPlaylist::Parse(Original(true), variant, 9000000);
  Check(!!relative, "real PMS flat relative references accepted after original validation");
  uri = owner.Activate(relative); Check(ReadAll(owner, *uri) == output, "relative resources normalize to exact HTTPS identities");
  for (const auto& bad : std::vector<std::string>{
         "file:///private/canary", "http://fixture.invalid/a", "https://elsewhere.invalid/a",
         "//elsewhere.invalid/a", "../0.m4s", "./0.m4s", "%30.m4s", "0.m4s?X-Plex-Token=canary",
         "https://@fixture.invalid/a", parent + "../0.m4s", parent + "sub/0.m4s", "https://fixture.invalid/video/:/transcode/universal/session/test-session/base/init.mp4", "0.m4s#fragment", "lineup-session://other.m3u8"})
    Check(!SessionPlaylist::Parse(Replace(Original(), parent + "0.m4s", bad), variant, 9000000), "bad discarded reference fails whole validation");
  for (const auto& tag : {"#EXT-X-KEY:METHOD=AES-128,URI=\"file:///secret\"", "#EXT-X-PART:URI=\"https://elsewhere.invalid/a\"", "#EXT-X-DISCONTINUITY", "#EXT-X-BYTERANGE:20", "#EXT-X-STREAM-INF:BANDWIDTH=100"})
    Check(!SessionPlaylist::Parse(Replace(Original(), "#EXT-X-MAP:", std::string(tag) + "\r\n#EXT-X-MAP:"), variant, 9000000), "unsupported discarded tag rejects before trim");
  for (const auto& pair : std::vector<std::pair<std::string, std::string>>{
         {"#EXTINF:4,title", "#EXTINF:4.0000001,title"}, {"#EXTINF:4,title", "#EXTINF:0,title"},
         {"#EXTINF:4,title", "#EXTINF:121,title"}, {"#EXTINF:4,title", "#EXTINF:nan,title"},
         {"init.mp4\"", "init.mp4\",BYTERANGE=\"1@0\""},
         {"#EXT-X-MEDIA-SEQUENCE:0", "#EXT-X-MEDIA-SEQUENCE:1"},
         {"#EXT-X-TARGETDURATION:10", "#EXT-X-TARGETDURATION"},
         {"#EXT-X-TARGETDURATION:10\r\n", ""},
         {"#EXT-X-TARGETDURATION:10", "#EXT-X-TARGETDURATION:10.1"},
         {"#EXT-X-TARGETDURATION:10", "#EXT-X-TARGETDURATION:0"},
         {"#EXT-X-TARGETDURATION:10", "#EXT-X-TARGETDURATION:121"},
         {"#EXT-X-VERSION:7", "#EXT-X-VERSION"},
         {"#EXT-X-MEDIA-SEQUENCE:0", "#EXT-X-MEDIA-SEQUENCE"},
         {"#EXT-X-VERSION:7", "#EXT-X-VERSION:7\r\n#EXT-X-VERSION:7"},
         {parent + "1.m4s", parent + "0.m4s"}, {parent + "0.m4s", parent + "init.mp4"},
         {"#EXTM3U", " #EXTM3U"}, {"#EXTM3U", "\xef\xbb\xbf#EXTM3U"},
         {"#EXT-X-ENDLIST\r\n", ""}})
    Check(!SessionPlaylist::Parse(Replace(Original(), pair.first, pair.second), variant, 9000000), "closed grammar negative");
  for (const auto& bad : {std::string("\0", 1), std::string("\x01", 1), std::string("\xff", 1), std::string("\xe2\x80\xa8", 3)})
    Check(!SessionPlaylist::Parse(Replace(Original(), "title", bad), variant, 9000000), "control or invalid UTF8 rejects");
  Check(!SessionPlaylist::Parse(Original(), variant, -1) && !SessionPlaylist::Parse(Original(), variant, 8000000) &&
        !SessionPlaylist::Parse(Original(false, "99"), variant, 99000000), "offset validation");
  Check(!SessionPlaylist::Parse(std::string(SessionPlaylist::kMaximumBytes + 1, 'x'), variant, 0), "one MiB cap");
  auto exact = Original();
  exact = Replace(exact, "title", std::string(SessionPlaylist::kMaximumBytes - exact.size() + 5, 'x'));
  Check(exact.size() == SessionPlaylist::kMaximumBytes && !!SessionPlaylist::Parse(exact, variant, 9000000), "full one MiB original supported");
  const std::string long_variant = "https://" + std::string(3500, 'a') + ".invalid/video/:/transcode/universal/session/test-session/base/index.m3u8";
  std::string expansion = "#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXT-X-MEDIA-SEQUENCE:0\n#EXT-X-MAP:URI=\"init.mp4\"\n";
  for (int i = 0; i < 400; ++i) expansion += "#EXTINF:10,\n" + std::to_string(i) + ".m4s\n";
  expansion += "#EXT-X-ENDLIST\n";
  Check(!SessionPlaylist::Parse(expansion, long_variant, 0), "absolute expansion bound enforced before allocating beyond output cap");
  Check(!SessionPlaylist::Parse(std::string(SessionPlaylist::kMaximumBytes, '\n'), variant, 0), "blank line AST count bounded before allocation");
  Check(!SessionPlaylist::Parse(Original(), "memory://arbitrary", 9000000), "private input still requires verified HTTPS descriptor");
}
void ReferenceLineBounds() {
  constexpr size_t limit = 4095;
  constexpr size_t map_overhead = sizeof("#EXT-X-MAP:URI=\"\"") - 1;
  const auto absolute_name = [&](size_t length) { return parent + std::string(length - parent.size(), 'a'); };
  // The offending reference is deliberately in the discarded prefix: the
  // complete original must pass exact-resource validation before any trim.
  auto at_media_limit = Replace(Original(), parent + "0.m4s", absolute_name(limit));
  Check(!!SessionPlaylist::Parse(at_media_limit, variant, 9000000), "absolute media URI exact FFmpeg line limit accepted");
  Check(!SessionPlaylist::Parse(Replace(at_media_limit, absolute_name(limit), absolute_name(limit + 1)), variant, 9000000),
        "absolute discarded media URI one byte over limit rejected");
  auto at_map_limit = Replace(Original(), parent + "init.mp4", absolute_name(limit - map_overhead));
  Check(!!SessionPlaylist::Parse(at_map_limit, variant, 9000000), "absolute MAP rendered line exact limit accepted");
  Check(!SessionPlaylist::Parse(Replace(at_map_limit, absolute_name(limit - map_overhead), absolute_name(limit - map_overhead + 1)), variant, 9000000),
        "absolute MAP rendered line one byte over limit rejected");
  auto relative_media_limit = Replace(Original(true), "0.m4s", std::string(limit - parent.size(), 'a'));
  Check(!!SessionPlaylist::Parse(relative_media_limit, variant, 9000000), "expanded relative media exact line limit accepted");
  Check(!SessionPlaylist::Parse(Replace(relative_media_limit, std::string(limit - parent.size(), 'a'), std::string(limit - parent.size() + 1, 'a')), variant, 9000000),
        "expanded relative discarded media one byte over limit rejected");
  auto relative_map_limit = Replace(Original(true), "init.mp4", std::string(limit - map_overhead - parent.size(), 'a'));
  Check(!!SessionPlaylist::Parse(relative_map_limit, variant, 9000000), "expanded relative MAP exact line limit accepted");
  Check(!SessionPlaylist::Parse(Replace(relative_map_limit, std::string(limit - map_overhead - parent.size(), 'a'), std::string(limit - map_overhead - parent.size() + 1, 'a')), variant, 9000000),
        "expanded relative MAP one byte over limit rejected");
}

void Lifetime() {
  SessionPlaylistRegistry registry;
  auto playlist = SessionPlaylist::Parse(Original(), variant, 9000000);
  auto uri = registry.Activate(playlist); Check(!!uri, "first id");
  Check(uri->size() == std::strlen("lineup-session://") + 32 + 5 && uri->find("fixture") == std::string::npos &&
        uri->find("test-session") == std::string::npos && uri->substr(uri->size() - 5) == ".m3u8", "opaque 128bit path with HLS extension");
  mpv_stream_cb_info info{}; auto name = *uri;
  Check(SessionPlaylistRegistry::Open(&registry, name.data(), &info) == 0, "cookie opens");
  std::atomic<bool> stop{false}; std::thread reader([&] { char bytes[32]; while (!stop) { info.seek_fn(info.cookie, 0); info.read_fn(info.cookie, bytes, sizeof(bytes)); } });
  registry.Retire(); stop = true; reader.join();
  char byte; Check(playlist->byte_size() == 0 && info.read_fn(info.cookie, &byte, 1) < 0 &&
                   info.seek_fn(info.cookie, 0) < 0 && info.size_fn(info.cookie) < 0, "revocation wipes bytes and tombstones all callbacks");
  mpv_stream_cb_info refused{}; Check(SessionPlaylistRegistry::Open(&registry, name.data(), &refused) < 0, "retired id cannot reopen");
  info.close_fn(info.cookie);
  auto next = registry.Activate(SessionPlaylist::Parse(Original(), variant, 9000000)); Check(next && *next != *uri, "fresh independent random capability");
  name = *next; Check(SessionPlaylistRegistry::Open(&registry, name.data(), &info) == 0, "replacement opens");
  info.cancel_fn(info.cookie); Check(info.read_fn(info.cookie, &byte, 1) < 0, "cancel is nonblocking tombstone"); info.close_fn(info.cookie);
  registry.Disable();
  auto late = SessionPlaylist::Parse(Original(), variant, 9000000);
  Check(!registry.Activate(late) && late->byte_size() == 0, "release fence blocks late activation and wipes queued payload");
  name += "?extra"; Check(SessionPlaylistRegistry::Open(&registry, name.data(), &refused) < 0, "exact capability only");
}
}
int main() { Parser(); ReferenceLineBounds(); Lifetime(); }
