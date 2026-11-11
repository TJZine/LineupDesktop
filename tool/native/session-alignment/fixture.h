#ifndef LINEUP_SESSION_ALIGNMENT_FIXTURE_H_
#define LINEUP_SESSION_ALIGNMENT_FIXTURE_H_

#include <mpv/client.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <functional>
#include <iomanip>
#include <iostream>
#include <optional>
#include <string>
#include <string_view>

#include "player_core/value.h"

namespace lineup::fixture {

// A driver of the production method codec and adapter. It consumes only the
// numeric clocks and correlation fields used by the Dart alignment policy.
class AlignmentFixture {
 public:
  using Call = std::function<bool(const char*, player::ValueMap)>;
  using Pump = std::function<void()>;
  using Clock = std::chrono::steady_clock;

  void Event(const player::ValueMap& event) {
    using namespace player;
    const auto type = FindString(&event, "type");
    if (!type) return;
    if (*type == "stopResult") {
      stopped_ = AsInt(Find(event, "stopId")) == load_ &&
                 FindBool(&event, "success") && *FindBool(&event, "success");
      return;
    }
    if (AsInt(Find(event, "loadId")) != load_) return;
    if (*type == "state") {
      const auto state = FindString(&event, "state");
      ready_ |= state && *state == "playing";
      failed_ |= state && *state == "error";
    } else if (*type == "property") {
      const auto name = FindString(&event, "name");
      const auto value = AsNumber(Find(event, "value"));
      if (!ready_ || !name || !value || !std::isfinite(*value)) return;
      if (*name == "demuxer-start-time") start_ = value;
      if (*name == "time-pos" && *value >= 0) {
        if (start_ && !initial_) initial_ = Sample{*value, *start_};
      }
    } else if (*type == "sessionSeekResult" && AsInt(Find(event, "seekId")) == load_) {
      const auto outcome = FindString(&event, "outcome");
      const auto position = AsNumber(Find(event, "positionSeconds"));
      const auto start = AsNumber(Find(event, "demuxerStartSeconds"));
      if (landed_ || !seek_sent_ || !outcome || *outcome != "landed" ||
          !position || !start || !std::isfinite(*position) || !std::isfinite(*start)) {
        failed_ = true;
      } else {
        landed_ = Sample{*position, *start};
        landing_ms_ = ElapsedMs(seek_at_);
      }
    }
  }

  // Args after --alignment: CA, variant, manifest, offset in microseconds,
  // expected per-file target duration, paused/running, optional direct file.
  int Run(int argc, char** argv, mpv_handle* client, const Call& call, const Pump& pump) {
    if ((argc != 8 && argc != 9) || !client) return 2;
    const std::string_view variant = argv[3];
    if (variant.find("https://127.0.0.1:") != 0 ||
        (argc == 9 && std::string_view(argv[8]).find("https://127.0.0.1:") != 0)) return 2;
    std::cout << "{\"mpvVersion\":\"" << Version(client, "mpv-version")
              << "\",\"ffmpegVersion\":\"" << Version(client, "ffmpeg-version") << "\"}\n";
    std::ifstream input(argv[4], std::ios::binary | std::ios::ate);
    const auto size = input.tellg();
    if (!input || size <= 0 || size > 1024 * 1024) return 2;
    std::string manifest(static_cast<size_t>(size), '\0');
    input.seekg(0);
    if (!input.read(manifest.data(), static_cast<std::streamsize>(manifest.size()))) return 2;
    const int64_t offset = std::strtoll(argv[5], nullptr, 10);
    const double target = std::strtod(argv[6], nullptr);
    const bool paused = std::string_view(argv[7]) == "paused";
    const auto baseline = DemuxerOffset(client);
    const bool session = baseline && RunSession(client, call, pump, argv[3],
                                                manifest, offset, target, paused);
    bool isolation = true;
    if (argc == 9 && session) {
      // Replace the still-loaded session directly. This exercises mpv's
      // per-file option backup across replacement on the same client.
      Reset();
      isolation = call("load", {{"uri", argv[8]}, {"loadId", load_}, {"startPaused", true}}) &&
          Wait(pump, [this] { return ready_; }, 2000) && DemuxerOffset(client) == baseline;
      std::cout << "{\"directRestored\":" << (isolation ? "true" : "false") << "}\n";
      Reset();
      isolation = isolation && RunSession(client, call, pump, argv[3], manifest,
                                          offset, target, paused);
    }
    const auto stop_at = Clock::now();
    const bool retired = call("stop", {{"stopId", load_}}) &&
        Wait(pump, [&] { return stopped_ && DemuxerOffset(client) == baseline; }, 2000, true);
    const auto restored = DemuxerOffset(client);
    std::cout << "{\"restoredOffset\":" << restored.value_or(-1)
              << ",\"baselineOffset\":" << baseline.value_or(-1)
              << ",\"stopResult\":" << (stopped_ ? "true" : "false")
              << ",\"stopMs\":" << ElapsedMs(stop_at)
              << ",\"restored\":" << (retired ? "true" : "false") << "}\n";
    return session && isolation && retired ? 0 : 1;
  }

 private:
  struct Sample {
    double position;
    double start;
    double mapped() const { return position + start - 10; }
  };

  bool RunSession(mpv_handle* client, const Call& call, const Pump& pump,
                  const char* variant, const std::string& manifest,
                  int64_t offset, double target_duration, bool paused) {
    using player::ValueMap;
    const auto opened_at = Clock::now();
    const double requested = static_cast<double>(offset) / 1000000.0;
    const bool clock_ready = call("load", {
        {"uri", variant}, {"loadId", load_}, {"kind", "plexSession"},
        {"startPaused", paused}, {"sessionPlaylist", ValueMap{
            {"text", manifest}, {"offsetMicroseconds", offset}}}}) &&
        Wait(pump, [this] { return ready_; }, 15000) &&
        Wait(pump, [this] { return initial_.has_value(); }, 2000);
    const auto effective = DemuxerOffset(client);
    int native_pause = -1;
    const bool pause_matches =
        mpv_get_property(client, "pause", MPV_FORMAT_FLAG, &native_pause) >= 0 &&
        native_pause == (paused ? 1 : 0);
    const double clock_ms = ElapsedMs(opened_at);
    bool arrived = false;
    if (clock_ready) {
      if (requested - initial_->mapped() > 0.5) {
        const double target = std::max(0.0, requested + 10 - initial_->start);
        target_ms_ = static_cast<int64_t>(target * 1000);
        seek_at_ = Clock::now();
        seek_sent_ = true;
        arrived = call("alignSession", {{"loadId", load_}, {"seekId", load_},
                                        {"positionMs", target_ms_}}) &&
                  Wait(pump, [this] { return landed_.has_value(); }, 5000);
      } else {
        landed_ = initial_;
        arrived = true;
      }
    }
    const auto error = landed_ ? landed_->mapped() - requested : 0;
    const bool passed = arrived && effective == target_duration && pause_matches &&
                        std::abs(error) <= 0.5;
    std::cout << std::setprecision(12)
              << "{\"loadId\":" << load_ << ",\"clockReady\":" << (clock_ready ? "true" : "false")
              << ",\"requested\":" << requested
              << ",\"initialP\":" << (initial_ ? initial_->position : -1)
              << ",\"initialD\":" << (initial_ ? initial_->start : -1)
              << ",\"clockMs\":" << clock_ms
              << ",\"targetMs\":" << target_ms_
              << ",\"landedP\":" << (landed_ ? landed_->position : -1)
              << ",\"landedD\":" << (landed_ ? landed_->start : -1)
              << ",\"landingMs\":" << landing_ms_
              << ",\"errorSeconds\":" << error
              << ",\"effectiveOffset\":" << effective.value_or(-1)
              << ",\"paused\":" << (native_pause == 1 ? "true" : "false")
              << ",\"outcome\":\"" << (arrived ? seek_sent_ ? "landed" : "noneNeeded" : "noLanding")
              << "\",\"pass\":" << (passed ? "true" : "false") << "}\n";
    return passed;
  }

  void Reset() {
    ++load_;
    ready_ = failed_ = stopped_ = seek_sent_ = false;
    start_.reset();
    initial_.reset();
    landed_.reset();
    target_ms_ = -1;
    landing_ms_ = -1;
  }

  template <typename Predicate>
  bool Wait(const Pump& pump, Predicate done, int timeout_ms, bool cleanup = false) const {
    const auto started = Clock::now();
    while (!done() && (!failed_ || cleanup) && ElapsedMs(started) < timeout_ms) pump();
    return done() && (!failed_ || cleanup) && ElapsedMs(started) < timeout_ms;
  }

  static std::string Version(mpv_handle* client, const char* property) {
    char* raw = mpv_get_property_string(client, property);
    if (!raw) return {};
    const std::string version(raw);
    mpv_free(raw);
    if (version.size() > 96 || version.find_first_not_of(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .-_+") != std::string::npos) return {};
    return version;
  }

  static std::optional<double> DemuxerOffset(mpv_handle* client) {
    double result = 0;
    return mpv_get_property(client, "options/hr-seek-demuxer-offset",
                            MPV_FORMAT_DOUBLE, &result) >= 0
        ? std::optional<double>(result) : std::nullopt;
  }

  static double ElapsedMs(Clock::time_point since) {
    return std::chrono::duration<double, std::milli>(Clock::now() - since).count();
  }

  int64_t load_ = 1;
  bool ready_ = false;
  bool failed_ = false;
  bool stopped_ = false;
  bool seek_sent_ = false;
  int64_t target_ms_ = -1;
  double landing_ms_ = -1;
  Clock::time_point seek_at_;
  std::optional<double> start_;
  std::optional<Sample> initial_;
  std::optional<Sample> landed_;
};

}  // namespace lineup::fixture

#endif
