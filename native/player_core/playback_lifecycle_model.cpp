#include "player_core/native_playback_state.h"

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdlib>
#include <deque>
#include <iostream>
#include <optional>
#include <string>
#include <type_traits>
#include <utility>
#include <vector>

namespace {

constexpr int kLoads = 3;
enum class Lifecycle { absent, may_start, owes_end };

struct Schedule {
  lineup::player::NativePlaybackState playback;
  std::array<Lifecycle, kLoads> loads{};
  int accepted = 0;
  int stops = 0;
  bool awaiting_idle = false;
  std::optional<int64_t> active;
  std::vector<std::string> steps;

  Schedule Next(const std::string& step) const {
    auto next = *this;
    next.steps.push_back(step);
    return next;
  }

  void Require(bool holds, const char* property) const {
    if (holds) return;
    std::cerr << property << '\n';
    for (const auto& step : steps) std::cerr << "  " << step << '\n';
    std::exit(EXIT_FAILURE);
  }

  void CheckCapacity() const {
    auto probe = playback;
    const auto live = std::count_if(loads.begin(), loads.end(), [](Lifecycle entry) {
      return entry != Lifecycle::absent;
    });
    const auto capacity = static_cast<int64_t>(probe.kMaxPlaylistEntries);
    for (int64_t i = 0; i < capacity - live; ++i) {
      Require(probe.AcceptLoad(1000 + i, 2000 + i),
              "Release skipped playlist entries so remaining capacity is available.");
    }
  }
};

int64_t LoadId(int slot) { return 100 + slot; }
int64_t PlaylistId(int slot) { return 200 + slot; }
int64_t StopId(int attempt) { return 300 + attempt; }

template <typename Owner>
int64_t WireId(const Owner& owner) {
  if constexpr (std::is_same_v<Owner, int64_t>) {
    return owner;
  } else {
    return owner.wire_id;
  }
}

void Expand(const Schedule& state, std::deque<Schedule>& queue) {
  state.Require(state.playback.active_load() == state.active,
                "A late lifecycle event must preserve the accepted replacement.");

  if (state.accepted < kLoads && !state.awaiting_idle) {
    const auto slot = state.accepted;
    auto next = state.Next("accept load " + std::to_string(slot));
    next.Require(next.playback.AcceptLoad(LoadId(slot), PlaylistId(slot)),
                 "Accept each load while capacity is available.");
    next.active = LoadId(slot);
    next.loads[slot] = Lifecycle::may_start;
    ++next.accepted;
    queue.push_back(std::move(next));
  }

  for (int slot = 0; slot < state.accepted; ++slot) {
    if (state.loads[slot] == Lifecycle::may_start) {
      auto next = state.Next("start load " + std::to_string(slot));
      const auto start = next.playback.StartFile(PlaylistId(slot));
      next.Require(start.within_capacity && next.playback.event_load() == LoadId(slot),
                   "START_FILE must publish the load that owns its playlist entry.");
      next.loads[slot] = Lifecycle::owes_end;
      std::replace(next.loads.begin(), next.loads.begin() + slot,
                   Lifecycle::may_start, Lifecycle::absent);
      next.CheckCapacity();
      queue.push_back(std::move(next));
    } else if (state.loads[slot] == Lifecycle::owes_end) {
      auto next = state.Next("end load " + std::to_string(slot));
      const auto ended = next.playback.EndFile(PlaylistId(slot));
      next.Require(ended && WireId(*ended) == LoadId(slot),
                   "Keep a started predecessor's identity until its own END_FILE.");
      next.playback.RetireLoad(ended);
      next.loads[slot] = Lifecycle::absent;
      if (next.active == LoadId(slot)) next.active.reset();
      queue.push_back(std::move(next));
    }
  }

  if (state.stops == 0 || (state.awaiting_idle && state.stops == 1)) {
    auto next = state.Next(state.stops == 0 ? "accept stop" : "retry stop");
    ++next.stops;
    next.playback.AcceptStop(StopId(next.stops));
    next.awaiting_idle = true;
    queue.push_back(std::move(next));
  }

  if (state.awaiting_idle) {
    auto next = state.Next("drain events and observe empty idle");
    next.Require(!next.playback.ObserveIdle(false, 0) &&
                 !next.playback.ObserveIdle(true, 1) &&
                 !next.playback.ObserveIdle(true, -1),
                 "Wait for both idle and a confirmed empty playlist.");
    next.Require(next.playback.ObserveIdle(true, 0) == StopId(state.stops),
                 "Complete the latest stop attempt exactly once.");
    next.awaiting_idle = false;
    std::replace(next.loads.begin(), next.loads.end(),
                 Lifecycle::may_start, Lifecycle::absent);
    next.CheckCapacity();
    queue.push_back(std::move(next));
  } else {
    auto probe = state.playback;
    state.Require(!probe.ObserveIdle(true, 0),
                  "An empty idle observation without a pending stop cannot publish a result.");
  }
}

}  // namespace

int main() {
  std::deque<Schedule> queue(1);
  size_t prefixes = 0;
  while (!queue.empty()) {
    auto state = std::move(queue.front());
    queue.pop_front();
    Expand(state, queue);
    ++prefixes;
  }
  std::cout << "Verified " << prefixes << " playback lifecycle prefixes.\n";
}
