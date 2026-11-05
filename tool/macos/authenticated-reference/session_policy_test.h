#ifndef LINEUP_MACOS_FIXTURE_SESSION_POLICY_TEST_H_
#define LINEUP_MACOS_FIXTURE_SESSION_POLICY_TEST_H_

#include <mpv/client.h>

#include <cstdint>
#include <map>
#include <string>

namespace lineup::fixture {
// Test-only state capture. Never serialize these values: compare the complete
// four-option baseline in memory and publish only a checked/restored boolean.
struct SessionPolicy {
  bool valid = false;
  int references = 0;
  int64_t redirects = 0;
  std::string demuxer;
  std::map<std::string, std::string> lavf;
};

inline SessionPolicy ReadSessionPolicy(mpv_handle* client) {
  SessionPolicy result;
  if (!client || mpv_get_property(client, "options/access-references", MPV_FORMAT_FLAG, &result.references) < 0 ||
      mpv_get_property(client, "options/curl-max-redirects", MPV_FORMAT_INT64, &result.redirects) < 0) return result;
  char* demuxer = nullptr;
  if (mpv_get_property(client, "options/demuxer", MPV_FORMAT_STRING, &demuxer) < 0) return result;
  result.demuxer = demuxer ? demuxer : "";
  if (demuxer) mpv_free(demuxer);
  mpv_node options{};
  if (mpv_get_property(client, "options/demuxer-lavf-o", MPV_FORMAT_NODE, &options) < 0) return result;
  bool valid = options.format == MPV_FORMAT_NODE_MAP && options.u.list &&
      options.u.list->num >= 0 && options.u.list->num <= 64;
  if (valid) {
    const auto& list = *options.u.list;
    for (int index = 0; index < list.num; ++index) {
      if (!list.keys || !list.keys[index] || !list.values || list.values[index].format != MPV_FORMAT_STRING ||
          !list.values[index].u.string || !result.lavf.emplace(list.keys[index], list.values[index].u.string).second) {
        valid = false;
        break;
      }
    }
  }
  mpv_free_node_contents(&options);
  result.valid = valid;
  return result;
}

inline bool SameSessionPolicy(const SessionPolicy& before, const SessionPolicy& after) {
  return before.valid && after.valid && before.references == after.references &&
      before.redirects == after.redirects && before.demuxer == after.demuxer && before.lavf == after.lavf;
}
}  // namespace lineup::fixture
#endif
