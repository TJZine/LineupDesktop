#ifndef RUNNER_NATIVE_PLAYBACK_STATE_H_
#define RUNNER_NATIVE_PLAYBACK_STATE_H_

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <deque>
#include <limits>
#include <optional>
#include <string>
#include <unordered_map>
#include <utility>

namespace lineup {

class NativePlaybackState {
 public:
  static constexpr size_t kMaxPlaylistEntries = 1024;
  struct StartResult {
    bool within_capacity;
    std::optional<int64_t> rejected_load;
  };
  struct Failure {
    int64_t load_id;
    std::string code;
    std::optional<int64_t> http_status;
  };

  std::optional<int64_t> active_load() const { return active_load_; }
  std::optional<int64_t> event_load() const { return event_load_; }
  std::optional<int64_t> pending_stop() const { return pending_stop_; }
  const std::optional<Failure>& failure() const { return failure_; }
  bool TrackTargetsActiveLoad(int64_t load_id) const {
    return active_load_ == load_id;
  }

  // A missing playlist id uses the pending START_FILE FIFO. Capacity failure
  // leaves command acceptance intact, but cannot manufacture an event identity.
  bool AcceptLoad(int64_t load_id, std::optional<int64_t> playlist_id) {
    active_load_ = load_id;
    if (playlist_id) {
      if (playlist_loads_.find(*playlist_id) == playlist_loads_.end() &&
          playlist_loads_.size() >= kMaxPlaylistEntries) {
        return false;
      }
      playlist_loads_[*playlist_id] = load_id;
    } else {
      if (pending_loads_.size() >= kMaxPlaylistEntries) {
        return false;
      }
      pending_loads_.push_back(load_id);
    }
    return true;
  }

  StartResult StartFile(std::optional<int64_t> playlist_id) {
    if (!playlist_id) {
      ClearFailureFor(event_load_);
      return {true, std::nullopt};
    }
    const auto load = playlist_loads_.find(*playlist_id);
    StartResult result{true, std::nullopt};
    if (load != playlist_loads_.end()) {
      event_load_ = load->second;
    } else if (!pending_loads_.empty()) {
      event_load_ = pending_loads_.front();
      pending_loads_.pop_front();
      if (playlist_loads_.size() >= kMaxPlaylistEntries) {
        result = {false, event_load_};
        event_load_.reset();
      } else {
        playlist_loads_[*playlist_id] = *event_load_;
      }
    } else {
      event_load_.reset();
    }
    ClearFailureFor(event_load_);
    return result;
  }

  std::optional<int64_t> EndFile(std::optional<int64_t> playlist_id) {
    auto load_id = event_load_;
    if (playlist_id) {
      const auto load = playlist_loads_.find(*playlist_id);
      if (load != playlist_loads_.end()) {
        load_id = load->second;
        playlist_loads_.erase(load);
      }
    }
    return load_id;
  }

  bool Redirect(std::optional<int64_t> load_id, int64_t first, int64_t count) {
    if (!load_id || first < 0 || count < 0 ||
        count > static_cast<int64_t>(kMaxPlaylistEntries) ||
        (count != 0 && first > std::numeric_limits<int64_t>::max() - (count - 1))) {
      return false;
    }
    size_t new_entries = 0;
    for (int64_t offset = 0; offset < count; ++offset) {
      if (playlist_loads_.find(first + offset) == playlist_loads_.end()) {
        ++new_entries;
      }
    }
    if (new_entries > kMaxPlaylistEntries - playlist_loads_.size()) {
      return false;
    }
    for (int64_t offset = 0; offset < count; ++offset) {
      playlist_loads_[first + offset] = *load_id;
    }
    return true;
  }

  void RetireLoad(std::optional<int64_t> load_id) {
    if (load_id) {
      for (auto entry = playlist_loads_.begin(); entry != playlist_loads_.end();) {
        if (entry->second == *load_id) {
          entry = playlist_loads_.erase(entry);
        } else {
          ++entry;
        }
      }
      pending_loads_.erase(std::remove(pending_loads_.begin(), pending_loads_.end(),
                                      *load_id), pending_loads_.end());
    }
    ClearFailureFor(load_id);
    if (active_load_ == load_id) {
      active_load_.reset();
    }
    if (event_load_ == load_id) {
      event_load_.reset();
    }
  }

  void RecordFailure(std::string code, std::optional<int64_t> http_status) {
    if (!event_load_ || event_load_ != active_load_) {
      return;
    }
    if (!failure_ || failure_->load_id != *event_load_ || http_status) {
      failure_ = Failure{*event_load_, std::move(code), http_status};
    }
  }

  void AcceptStop(int64_t stop_id) { pending_stop_ = stop_id; }
  std::optional<int64_t> ObserveIdle(bool idle, int64_t playlist_count) {
    if (!pending_stop_ || !idle || playlist_count != 0) {
      return std::nullopt;
    }
    const auto completed = pending_stop_;
    pending_stop_.reset();
    return completed;
  }

  void Reset() { *this = NativePlaybackState{}; }

 private:
  void ClearFailureFor(std::optional<int64_t> load_id) {
    if (load_id && failure_ && failure_->load_id == *load_id) {
      failure_.reset();
    }
  }
  std::optional<int64_t> active_load_;
  std::optional<int64_t> event_load_;
  std::optional<int64_t> pending_stop_;
  std::deque<int64_t> pending_loads_;
  std::unordered_map<int64_t, int64_t> playlist_loads_;
  std::optional<Failure> failure_;
};

}
#endif
