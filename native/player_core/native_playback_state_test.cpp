#include "player_core/native_playback_state.h"

#include <cstdlib>
#include <iostream>
#include <limits>

namespace {
void Check(bool condition, const char* obligation) {
  if (!condition) {
    std::cerr << obligation << '\n';
    std::exit(1);
  }
}

void ReplacementAndRetirement() {
  lineup::player::NativePlaybackState state;
  Check(state.AcceptLoad(11, 100), "first accepted load");
  Check(state.StartFile(100).within_capacity, "first observed start");
  state.RecordFailure("network_error", std::nullopt);
  Check(state.AcceptLoad(12, 200), "replacement accepted");
  Check(state.active_load() == 12 && state.event_load() == 11,
        "acceptance must not relabel old properties");
  state.RecordFailure("http_error", 401);
  Check(state.failure()->code == "network_error",
        "retired event stream cannot overwrite failure detail");
  Check(!state.TrackTargetsActiveLoad(11) && state.TrackTargetsActiveLoad(12),
        "track targets accepted load, not observed predecessor");
  const auto old = state.EndFile(100);
  Check(old == 11, "old END_FILE must retain old load id");
  state.RetireLoad(old);
  Check(state.active_load() == 12 && !state.event_load() && !state.failure(),
        "old end cannot retire replacement");
  Check(state.StartFile(200).within_capacity && state.event_load() == 12, "replacement start");
  state.RecordFailure("source_open_error", std::nullopt);
  state.RecordFailure("container_error", std::nullopt);
  Check(state.failure()->code == "source_open_error", "keep first detail");
  state.RecordFailure("http_error", 503);
  Check(state.failure()->http_status == 503, "HTTP detail takes precedence");
  state.RetireLoad(state.EndFile(200));
  Check(!state.TrackTargetsActiveLoad(12) && !state.failure(), "retirement");
  state.StartFile(999);
  Check(!state.event_load(), "unknown start must not inherit latest command");
}

void FifoAndRedirects() {
  lineup::player::NativePlaybackState state;
  state.AcceptLoad(31, std::nullopt);
  state.AcceptLoad(32, std::nullopt);
  state.StartFile(301);
  Check(state.event_load() == 31 && state.active_load() == 32, "FIFO first");
  const auto redirected = state.EndFile(301);
  Check(state.Redirect(redirected, 401, 2), "bounded redirect");
  state.StartFile(402);
  Check(state.event_load() == 31, "redirect inherits original load");
  state.StartFile(302);
  Check(state.event_load() == 32, "FIFO second");
  state.RetireLoad(state.EndFile(401));
  Check(state.active_load() == 32 && state.event_load() == 32,
        "redirect retirement cannot clear replacement stream");
  state.StartFile(402);
  Check(!state.event_load(), "retirement removes all redirected entries");
  Check(!state.Redirect(32, -1, 1), "negative redirect id");
  Check(!state.Redirect(32, 1, -1), "negative redirect count");
  Check(!state.Redirect(32, std::numeric_limits<int64_t>::max(), 2),
        "redirect addition cannot overflow");
  Check(!state.Redirect(std::nullopt, 1, 1), "uncorrelated redirect");
  Check(!state.Redirect(32, 1, 1025), "oversized redirect");
  Check(state.Redirect(32, std::numeric_limits<int64_t>::max(), 1),
        "maximum valid id");
  state.StartFile(std::numeric_limits<int64_t>::max());
  Check(state.event_load() == 32, "maximum id correlation");
}

void CapacityAndReset() {
  lineup::player::NativePlaybackState state;
  for (int64_t i = 0; i < 1024; ++i) Check(state.AcceptLoad(i + 1, i), "map capacity");
  Check(!state.AcceptLoad(2000, 1024), "map bound");
  Check(state.active_load() == 2000, "capacity failure retains accepted load");
  Check(state.AcceptLoad(2001, 0), "existing id update at capacity");
  Check(!state.Redirect(2001, 0, 1025), "redirect bound at capacity");
  Check(!state.Redirect(2001, 1023, 2), "partial redirect cannot exceed capacity");
  Check(state.Redirect(2001, 0, 1024), "existing redirect ids cost no capacity");
  Check(state.AcceptLoad(2002, std::nullopt), "pending load at full map");
  const auto rejected_start = state.StartFile(9000);
  Check(!rejected_start.within_capacity && rejected_start.rejected_load == 2002 &&
        !state.event_load(), "capacity error preserves attempted load but clears event identity");
  state.Reset();
  for (int64_t i = 0; i < 1024; ++i) Check(state.AcceptLoad(i + 1, std::nullopt), "FIFO capacity");
  Check(!state.AcceptLoad(2000, std::nullopt), "FIFO bound");
  state.RetireLoad(1);
  state.StartFile(90);
  Check(state.event_load() == 2, "retirement removes pending FIFO entry");
  state.AcceptStop(71);
  state.Reset();
  Check(!state.active_load() && !state.event_load() && !state.pending_stop() &&
        !state.failure(), "dispose reset clears identities");
  state.StartFile(90);
  Check(!state.event_load(), "reset clears playlist map");
}

void StopObservation() {
  lineup::player::NativePlaybackState state;
  state.AcceptLoad(5, 9);
  state.AcceptStop(81);
  Check(!state.ObserveIdle(false, 0), "stop acceptance is not idle completion");
  Check(!state.ObserveIdle(true, 1), "idle with playlist is not completion");
  Check(!state.ObserveIdle(true, -1), "failed playlist observation is not completion");
  state.AcceptStop(82);
  Check(state.ObserveIdle(true, 0) == 82, "retry completes distinct latest stop id");
  Check(!state.ObserveIdle(true, 0), "stop completion emitted once");
  Check(state.active_load() == 5, "stop observation is separate from END_FILE");
}
}

int main() {
  ReplacementAndRetirement();
  FifoAndRedirects();
  CapacityAndReset();
  StopObservation();
  return 0;
}
