#ifndef LINEUP_PLAYER_CORE_NATIVE_PLAYBACK_STATE_H_
#define LINEUP_PLAYER_CORE_NATIVE_PLAYBACK_STATE_H_

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <deque>
#include <limits>
#include <optional>
#include <string>
#include <unordered_map>
#include <utility>

namespace lineup::player {

class NativePlaybackState {
 public:
  static constexpr size_t kMaxPlaylistEntries = 1024;
  struct Load {
    int64_t wire_id;
    uint64_t sequence;
    bool operator==(const Load& other) const { return sequence == other.sequence; }
    bool operator!=(const Load& other) const { return !(*this == other); }
  };
  struct StartResult {
    bool within_capacity;
    std::optional<int64_t> rejected_load;
  };
  // Deferred log detail for a later failed END_FILE, not a live failure state.
  // Backend probing can log an error and then recover with another backend.
  struct Failure {
    Load owner;
    std::string code;
    std::optional<int64_t> http_status;
  };

  std::optional<Load> active_owner() const {
    return active_ ? std::optional<Load>(latest_) : std::nullopt;
  }
  std::optional<int64_t> active_load() const {
    return active_ ? std::optional<int64_t>(latest_.wire_id) : std::nullopt;
  }
  std::optional<int64_t> PublicId(std::optional<Load> owner) const {
    if (!owner || (*owner != latest_ && owner->wire_id == latest_.wire_id)) {
      return std::nullopt;
    }
    return owner->wire_id;
  }
  std::optional<int64_t> event_load() const { return PublicId(event_); }
  std::optional<int64_t> pending_stop() const { return pending_stop_; }
  const std::optional<Failure>& failure() const { return failure_; }
  bool TrackTargetsActiveLoad(int64_t load_id) const {
    return active_load() == load_id;
  }

  bool AcceptLoad(int64_t load_id, std::optional<int64_t> playlist_id) {
    latest_ = Load{load_id, latest_.sequence + 1};
    active_ = true;
    if (playlist_id) {
      if (playlist_loads_.find(*playlist_id) == playlist_loads_.end() &&
          playlist_loads_.size() >= kMaxPlaylistEntries) {
        return false;
      }
      playlist_loads_.insert_or_assign(*playlist_id, PlaylistLoad{latest_, false});
    } else {
      if (pending_loads_.size() >= kMaxPlaylistEntries) return false;
      pending_loads_.push_back(latest_);
    }
    return true;
  }

  StartResult StartFile(std::optional<int64_t> playlist_id) {
    if (!playlist_id) {
      ClearFailureFor(event_);
      return {true, std::nullopt};
    }
    const auto entry = playlist_loads_.find(*playlist_id);
    if (entry != playlist_loads_.end()) {
      event_ = entry->second.owner;
      entry->second.started = true;
    } else if (!pending_loads_.empty()) {
      event_ = pending_loads_.front();
      pending_loads_.pop_front();
    } else {
      event_.reset();
      return {true, std::nullopt};
    }

    ReclaimBefore(event_->sequence);
    if (entry == playlist_loads_.end()) {
      if (playlist_loads_.size() >= kMaxPlaylistEntries) {
        const auto rejected = PublicId(event_);
        event_.reset();
        return {false, rejected};
      }
      playlist_loads_.emplace(*playlist_id, PlaylistLoad{*event_, true});
    }
    ClearFailureFor(event_);
    return {true, std::nullopt};
  }

  std::optional<Load> EndFile(std::optional<int64_t> playlist_id) {
    if (!playlist_id) return event_;
    const auto entry = playlist_loads_.find(*playlist_id);
    if (entry == playlist_loads_.end()) return std::nullopt;
    const auto owner = entry->second.owner;
    playlist_loads_.erase(entry);
    return owner;
  }

  bool Redirect(std::optional<Load> owner, int64_t first, int64_t count) {
    if (!owner || first < 0 || count < 0 ||
        count > static_cast<int64_t>(kMaxPlaylistEntries) ||
        (count != 0 && first > std::numeric_limits<int64_t>::max() - (count - 1))) {
      return false;
    }
    if (owner->sequence < latest_start_) return true;
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
      playlist_loads_.try_emplace(first + offset, PlaylistLoad{*owner, false});
    }
    return true;
  }

  void RetireLoad(std::optional<Load> owner) {
    if (!owner) return;
    EraseEntries([&](const PlaylistLoad& entry) { return entry.owner == *owner; });
    pending_loads_.erase(std::remove(pending_loads_.begin(), pending_loads_.end(),
                                    *owner), pending_loads_.end());
    ClearFailureFor(owner);
    if (latest_ == *owner) active_ = false;
    if (event_ == owner) event_.reset();
  }

  void RecordFailure(std::string code, std::optional<int64_t> http_status) {
    if (!event_ || event_ != active_owner()) return;
    if (!failure_ || failure_->owner != *event_ || http_status) {
      failure_ = Failure{*event_, std::move(code), http_status};
    }
  }

  void AcceptStop(int64_t stop_id) { pending_stop_ = stop_id; }
  std::optional<int64_t> ObserveIdle(bool idle, int64_t playlist_count) {
    if (!pending_stop_ || !idle || playlist_count != 0) {
      return std::nullopt;
    }
    // The caller must drain queued lifecycle events before confirming empty
    // idle. Even START_FILE/END_FILE pairs may still be queued after stop.
    EraseEntries([](const PlaylistLoad& entry) { return !entry.started; });
    pending_loads_.clear();
    const auto completed = pending_stop_;
    pending_stop_.reset();
    return completed;
  }

  void Reset() { *this = NativePlaybackState{}; }

 private:
  void ReclaimBefore(uint64_t sequence) {
    if (sequence <= latest_start_) return;
    latest_start_ = sequence;
    while (!pending_loads_.empty() && pending_loads_.front().sequence < sequence) {
      pending_loads_.pop_front();
    }
    EraseEntries([&](const PlaylistLoad& entry) {
      return !entry.started && entry.owner.sequence < sequence;
    });
  }

  template <typename Predicate>
  void EraseEntries(Predicate remove) {
    for (auto entry = playlist_loads_.begin(); entry != playlist_loads_.end();) {
      if (remove(entry->second)) {
        entry = playlist_loads_.erase(entry);
      } else {
        ++entry;
      }
    }
  }

  void ClearFailureFor(std::optional<Load> owner) {
    if (owner && failure_ && failure_->owner == *owner) failure_.reset();
  }
  Load latest_{0, 0};
  uint64_t latest_start_ = 0;
  bool active_ = false;
  std::optional<Load> event_;
  std::optional<int64_t> pending_stop_;
  std::deque<Load> pending_loads_;
  struct PlaylistLoad {
    Load owner;
    bool started;
  };
  std::unordered_map<int64_t, PlaylistLoad> playlist_loads_;
  std::optional<Failure> failure_;
};

}  // namespace lineup::player

#endif
