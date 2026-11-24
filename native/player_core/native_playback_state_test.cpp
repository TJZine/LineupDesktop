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
  Check(old && old->wire_id == 11, "old END_FILE must retain old load id");
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
  Check(!state.EndFile(401), "an evicted redirect child cannot end the current load");
  state.RetireLoad(state.EndFile(402));
  Check(state.active_load() == 32 && state.event_load() == 32,
        "redirect retirement cannot clear replacement stream");
  state.StartFile(402);
  Check(!state.event_load(), "retirement removes all redirected entries");
  const auto current = state.active_owner();
  Check(!state.Redirect(current, -1, 1), "negative redirect id");
  Check(!state.Redirect(current, 1, -1), "negative redirect count");
  Check(!state.Redirect(current, std::numeric_limits<int64_t>::max(), 2),
        "redirect addition cannot overflow");
  Check(!state.Redirect(std::nullopt, 1, 1), "uncorrelated redirect");
  Check(!state.Redirect(current, 1, 1025), "oversized redirect");
  Check(state.Redirect(current, std::numeric_limits<int64_t>::max(), 1),
        "maximum valid id");
  state.StartFile(std::numeric_limits<int64_t>::max());
  Check(state.event_load() == 32, "maximum id correlation");
}

void EarlyEndsAndLateRedirects() {
  lineup::player::NativePlaybackState state;
  state.AcceptLoad(7, 90);
  const auto early = state.EndFile(90);
  Check(early && early->wire_id == 7 && state.Redirect(early, 91, 2),
        "a keyed redirect before START_FILE keeps its owner");
  state.AcceptLoad(2, 10);
  state.StartFile(92);
  state.StartFile(91);
  Check(state.event_load() == 7, "older redirect siblings remain viable until replacement starts");
  state.StartFile(10);
  Check(state.EndFile(std::nullopt) == state.active_owner(), "payload-less end uses observed load");
  const auto late = state.EndFile(91);
  Check(late == early && state.Redirect(late, 95, 2), "late redirect retains its started owner");
  Check(!state.EndFile(95) && !state.EndFile(96), "late redirect must not recreate obsolete slots");
  Check(state.EndFile(92) == early, "a started sibling still owns its late end");
}

void SkippedFallback(int64_t first, int64_t second, int64_t third) {
  lineup::player::NativePlaybackState state;
  state.AcceptLoad(first, std::nullopt);
  state.AcceptLoad(second, 20);
  state.StartFile(20);
  state.RetireLoad(state.EndFile(20));
  state.AcceptLoad(third, std::nullopt);
  state.StartFile(30);
  Check(state.event_load() == third, "a keyed start retires superseded fallback loads");
}

void SkippedRedirect() {
  lineup::player::NativePlaybackState state;
  state.AcceptLoad(1, 10);
  state.StartFile(10);
  Check(state.Redirect(state.EndFile(10), 15, 1), "register redirect child");
  state.AcceptLoad(2, 20);
  state.StartFile(20);
  for (size_t i = 1; i < state.kMaxPlaylistEntries; ++i) {
    const auto id = static_cast<int64_t>(i) + 30;
    Check(state.AcceptLoad(id, id), "a replaced redirect child must release its slot before stop");
  }
  Check(!state.AcceptLoad(2000, 2000), "the live started replacement still occupies one slot");
}

void CapacityAndReset() {
  lineup::player::NativePlaybackState state;
  for (int64_t i = 0; i < 1024; ++i) Check(state.AcceptLoad(i + 1, i), "map capacity");
  Check(!state.AcceptLoad(2000, 1024), "map bound");
  Check(state.active_load() == 2000, "capacity failure retains accepted load");
  Check(state.AcceptLoad(2001, 0), "existing id update at capacity");
  Check(!state.Redirect(state.active_owner(), 0, 1025), "redirect bound at capacity");
  Check(!state.Redirect(state.active_owner(), 1023, 2), "partial redirect cannot exceed capacity");
  Check(state.Redirect(state.active_owner(), 0, 1024), "existing redirect ids cost no capacity");
  Check(state.AcceptLoad(2002, std::nullopt), "pending load at full map");
  Check(state.StartFile(9000).within_capacity && state.event_load() == 2002,
        "fallback start reclaims a full table of obsolete unstarted entries before admission");

  state.Reset();
  for (int64_t i = 0; i < 1024; ++i) {
    Check(state.AcceptLoad(i + 1, i) && state.StartFile(i).within_capacity,
          "fill map with started entries awaiting END_FILE");
  }
  Check(state.AcceptLoad(2002, std::nullopt), "accept fallback behind all started entries");
  const auto rejected_start = state.StartFile(9000);
  Check(!rejected_start.within_capacity && rejected_start.rejected_load == 2002 &&
        !state.event_load(), "capacity error preserves attempted load but clears event identity");
  state.Reset();
  Check(state.AcceptLoad(1, std::nullopt), "first FIFO load");
  const auto first = state.active_owner();
  for (int64_t i = 1; i < 1024; ++i) Check(state.AcceptLoad(i + 1, std::nullopt), "FIFO capacity");
  Check(!state.AcceptLoad(2000, std::nullopt), "FIFO bound");
  state.RetireLoad(first);
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
  EarlyEndsAndLateRedirects();
  SkippedFallback(1, 2, 3);
  SkippedFallback(9, 2, 1);
  SkippedFallback(1, 1, 3);
  SkippedRedirect();
  CapacityAndReset();
  StopObservation();
  return 0;
}
