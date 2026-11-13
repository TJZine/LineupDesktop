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
      const auto success = FindBool(&event, "success");
      if (!stop_sent_ || AsInt(Find(event, "stopId")) != load_ ||
          stopped_ || !success || !*success) {
        failed_ = true;
      } else {
        stopped_ = true;
      }
      return;
    }
    const auto id = AsInt(Find(event, "loadId"));
    if (*type == "state") {
      const auto state = FindString(&event, "state");
      if (state && *state == "error") failed_ = true;
      if (id != load_ || !state) return;
      if (*state == "playing") {
        ready_ = true;
        CheckPause(FindBool(&event, "paused"));
      } else if (*state == "stopped" && stop_sent_ && !file_stopped_) {
        file_stopped_ = true;
      } else if (*state == "stopped" || *state == "ended") {
        failed_ = true;
      }
    } else if (*type == "sessionSeekResult") {
      const auto outcome = FindString(&event, "outcome");
      const auto position = AsNumber(Find(event, "positionSeconds"));
      const auto start = AsNumber(Find(event, "demuxerStartSeconds"));
      if (id != load_ || AsInt(Find(event, "seekId")) != load_ ||
          landed_ || !seek_sent_ || file_stopped_ || stopped_ ||
          !outcome || *outcome != "landed" ||
          !position || !start || !std::isfinite(*position) || *position < 0 ||
          *position > 10000000 || !std::isfinite(*start) || std::abs(*start) > 1000000) {
        failed_ = true;
      } else {
        landed_ = Sample{*position, *start};
        landing_ms_ = ElapsedMs(seek_at_);
      }
    } else if (*type == "property" && id == load_ && ready_) {
      const auto name = FindString(&event, "name");
      if (!name) return;
      if (*name == "pause") {
        CheckPause(FindBool(&event, "value"));
      }
      const auto value = AsNumber(Find(event, "value"));
      if (!value || !std::isfinite(*value)) return;
      if (*name == "demuxer-start-time" && std::abs(*value) <= 1000000) start_ = value;
      if (*name == "time-pos" && *value >= 0 && *value <= 10000000) {
        if (start_ && !initial_) initial_ = Sample{*value, *start_};
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
      expected_paused_ = true;
      isolation = call("load", {{"uri", argv[8]}, {"loadId", load_}, {"startPaused", true}}) &&
          Wait(pump, [this] { return ready_; }, 2000) && DemuxerOffset(client) == baseline &&
          ReadPause(client) == expected_paused_;
      std::cout << "{\"directRestored\":" << (isolation ? "true" : "false") << "}\n";
      Reset();
      isolation = isolation && RunSession(client, call, pump, argv[3], manifest,
                                          offset, target, paused);
    }
    const auto stop_at = Clock::now();
    stop_sent_ = true;
    const bool retired = call("stop", {{"stopId", load_}}) &&
        Wait(pump, [&] {
          return stopped_ && file_stopped_ && DemuxerOffset(client) == baseline;
        }, 2000, true);
    // Drain a final adapter turn and confirm the real pause property after stop.
    pump();
    const auto paused_after_stop = ReadPause(client);
    const bool valid_through_stop = !failed_ && !pause_changed_ &&
                                    paused_after_stop == expected_paused_;
    const auto restored = DemuxerOffset(client);
    std::cout << "{\"restoredOffset\":" << restored.value_or(-1)
              << ",\"baselineOffset\":" << baseline.value_or(-1)
              << ",\"stopResult\":" << (stopped_ ? "true" : "false")
              << ",\"stopMs\":" << ElapsedMs(stop_at)
              << ",\"fileStopped\":" << (file_stopped_ ? "true" : "false")
              << ",\"lateOrInvalidEvent\":" << (failed_ ? "true" : "false")
              << ",\"pauseChanged\":" << (pause_changed_ ? "true" : "false")
              << ",\"pausedAfterStop\":" << (paused_after_stop ? (*paused_after_stop ? "true" : "false") : "null")
              << ",\"validThroughStop\":" << (valid_through_stop ? "true" : "false")
              << ",\"restored\":" << (retired ? "true" : "false") << "}\n";
    return session && isolation && retired && valid_through_stop ? 0 : 1;
  }

 private:
  static int64_t Microseconds(double seconds) {
    return std::llround(seconds * 1000000);
  }

  struct Sample {
    double position;
    double start;
    int64_t mapped_microseconds() const {
      return Microseconds(position) + Microseconds(start) - 10000000;
    }
  };

  void CheckPause(const bool* paused) {
    if (!paused || *paused != expected_paused_) pause_changed_ = true;
  }

  static std::optional<bool> ReadPause(mpv_handle* client) {
    int flag = 0;
    if (mpv_get_property(client, "pause", MPV_FORMAT_FLAG, &flag) < 0) return std::nullopt;
    return flag != 0;
  }

  bool RunSession(mpv_handle* client, const Call& call, const Pump& pump,
                  const char* variant, const std::string& manifest,
                  int64_t offset, double target_duration, bool paused) {
    using player::ValueMap;
    expected_paused_ = paused;
    const auto opened_at = Clock::now();
    const double requested = static_cast<double>(offset) / 1000000.0;
    const bool clock_ready = call("load", {
        {"uri", variant}, {"loadId", load_}, {"kind", "plexSession"},
        {"startPaused", paused}, {"sessionPlaylist", ValueMap{
            {"text", manifest}, {"offsetMicroseconds", offset}}}}) &&
        Wait(pump, [this] { return ready_; }, 15000) &&
        Wait(pump, [this] { return initial_.has_value(); }, 2000);
    const auto effective = DemuxerOffset(client);
    const auto native_pause = ReadPause(client);
    const double clock_ms = ElapsedMs(opened_at);
    bool arrived = false;
    if (clock_ready) {
      if (std::abs(offset - initial_->mapped_microseconds()) > 500000) {
        const int64_t target = offset + 10000000 - Microseconds(initial_->start);
        target_ms_ = std::max(int64_t{0}, target) / 1000;
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
    const auto error = landed_ ? landed_->mapped_microseconds() - offset : 0;
    const char* outcome = "noLanding";
    if (arrived) {
      outcome = !seek_sent_ ? "noneNeeded" :
                std::abs(error) > 500000 ? "imprecise" : "landed";
    }
    const bool valid = arrived && effective == target_duration && native_pause == paused &&
                       ReadPause(client) == paused && !failed_ && !pause_changed_;
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
              << ",\"errorSeconds\":" << static_cast<double>(error) / 1000000
              << ",\"effectiveOffset\":" << effective.value_or(-1)
              << ",\"paused\":" << (native_pause ? (*native_pause ? "true" : "false") : "null")
              << ",\"outcome\":\"" << outcome
              << "\",\"valid\":" << (valid ? "true" : "false") << "}\n";
    return valid;
  }

  void Reset() {
    ++load_;
    ready_ = stopped_ = file_stopped_ = seek_sent_ = false;
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
  bool stop_sent_ = false;
  bool file_stopped_ = false;
  bool expected_paused_ = false;
  bool pause_changed_ = false;
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
