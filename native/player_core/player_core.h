#ifndef LINEUP_PLAYER_CORE_PLAYER_CORE_H_
#define LINEUP_PLAYER_CORE_PLAYER_CORE_H_

#include <mpv/client.h>

#include <atomic>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <deque>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <string_view>
#include <thread>
#include <utility>
#include <variant>
#include <vector>

#include "player_core/mpv_operations.h"
#include "player_core/native_playback_state.h"
#include "player_core/value.h"

namespace lineup::player {

struct CallError {
  std::string code;
  std::string message;
};

// The outcome of a method-channel call that the core owns. A success carries
// a null value unless the method returns a result map.
struct CallResult {
  std::optional<CallError> error;
  Value value;

  static CallResult Success(Value value = {}) {
    return CallResult{std::nullopt, std::move(value)};
  }
  static CallResult Failure(std::string code, std::string message) {
    return CallResult{CallError{std::move(code), std::move(message)}, {}};
  }
};

// Presentation choices the platform makes before libmpv initializes.
struct OutputConfig {
  // Applied as the `wid` option before every other option.
  std::optional<int64_t> window_id;
  // Platform options such as vo, gpu-api, and gpu-context. They are applied
  // after the core's security and input options and before hwdec.
  std::vector<std::pair<std::string, std::string>> options;
};

// Implemented by each platform adapter. The core calls the platform-thread
// methods only from its own platform-thread entry points.
class CoreHost {
 public:
  // Any thread. Asks the platform thread to call PlayerCore::ProcessWakeup.
  // Returns false when the request could not be posted; the worker retries
  // while events remain queued.
  virtual bool PostWakeup() = 0;
  // Worker thread, after mpv_terminate_destroy. Must make the platform thread
  // call ProcessWakeup so that disposal can finish; it may block until the
  // request is posted or the platform can no longer receive it.
  virtual void PostWorkerFinished() = 0;
  // Platform thread, during initialize after the core's own preconditions and
  // before libmpv is created. An error fails initialization unchanged.
  virtual std::optional<CallError> PrepareOutput(OutputConfig& output) = 0;
  // Platform thread. Undoes PrepareOutput after a later initialization step
  // failed.
  virtual void CancelOutput() = 0;
  // Platform thread. Releases presentation after the worker has been joined
  // and before queued commands and events are cleared.
  virtual void ReleaseOutput() = 0;
  // Platform thread. Called for every disposal request, before the core
  // checks whether a shutdown is already running.
  virtual void OnDisposeRequested() {}

 protected:
  ~CoreHost() = default;
};

// The platform-neutral libmpv player behind `lineup/native_player`. It owns
// the mpv client, the bounded command queue and worker, load/stop/track
// correlation, the bounded event queue, and token handling. The platform
// adapter owns the channel, codec conversion, and presentation.
//
// Threading: every method is platform-thread only unless documented
// otherwise. The worker thread runs commands and translates mpv events.
class PlayerCore {
 public:
  using Reply = std::function<void(const CallResult&)>;
  using EventSink = std::function<void(const ValueMap&)>;

  PlayerCore(MpvOperations mpv_operations, CoreHost& host);
  // Calls Shutdown(). A platform should call Shutdown() itself while the
  // state its CoreHost callbacks use is still intact.
  ~PlayerCore();

  PlayerCore(const PlayerCore&) = delete;
  PlayerCore& operator=(const PlayerCore&) = delete;

  // `initialize`: returns {clientApiVersion: int} or an error.
  CallResult Initialize();
  // `dispose`: replies on the platform thread once the worker has finished,
  // been joined, and the platform output has been released. Replies
  // immediately when already disposed or when another disposal is pending.
  void Dispose(Reply reply);
  // Starts an asynchronous disposal without a channel reply.
  void BeginDispose();
  // Validates and queues load/play/pause/seek/stop/selectTrack/setVolume.
  // Returns not_initialized for any method before initialization. Returns
  // std::nullopt for an initialized call the core does not own; the platform
  // then handles it or reports it as not implemented. `arguments` is null
  // when the call has no map argument. A `plexToken` string in `arguments`
  // is wiped before this returns, whatever the outcome.
  std::optional<CallResult> HandleCommand(std::string_view method,
                                          ValueMap* arguments);
  // Delivers queued events from the current generation in order, then
  // completes a disposal whose worker has finished.
  void ProcessWakeup(const EventSink& deliver);
  // Synchronously completes any disposal. Terminates the process if the
  // worker does not finish within five seconds. Drops a pending dispose reply
  // without answering it.
  void Shutdown();

  // Any thread. Queues a platform-scoped event (for example a display report)
  // in the current generation through the bounded event queue.
  void QueuePlatformEvent(ValueMap event);
  // Removes queued events whose `type` equals `type`.
  void DiscardQueuedEvents(std::string_view type);
  // Any thread. Asks the platform to call ProcessWakeup.
  void RequestWakeup();

  bool initialized() const { return accepting_commands_; }
  bool disposed() const { return disposed_; }

 private:
  struct QueuedEvent {
    uint64_t generation;
    ValueMap value;
  };

  // Owns the escaped `X-Plex-Token` header. The token lives only in this
  // buffer while queued and is wiped after the load command runs.
  class PlexHeader {
   public:
    PlexHeader() = default;
    explicit PlexHeader(std::string_view token);
    ~PlexHeader();

    PlexHeader(const PlexHeader&) = delete;
    PlexHeader& operator=(const PlexHeader&) = delete;
    PlexHeader(PlexHeader&& other) noexcept;
    PlexHeader& operator=(PlexHeader&& other) noexcept;

    char* data() { return data_.get(); }
    size_t size() const { return size_; }
    bool empty() const { return data_ == nullptr; }
    void Clear() noexcept;

   private:
    std::unique_ptr<char[]> data_;
    size_t size_ = 0;
  };

  struct LoadCommand {
    int64_t load_id;
    std::string uri;
    PlexHeader plex_header;
    bool start_paused = false;
    std::optional<double> start_seconds = std::nullopt;
  };
  struct PlayCommand {};
  struct PauseCommand {};
  enum class SeekMode { exact, keyframes };
  struct SeekCommand {
    double seconds;
    SeekMode mode;
  };
  enum class SeekObservationPhase {
    load_start, file_loaded, initial_restart, seek_start, seek_restart,
  };
  struct SeekObservation {
    int64_t load_id;
    double target;
    SeekMode mode;
    SeekObservationPhase phase;
    std::chrono::steady_clock::time_point deadline;
  };
  struct StopCommand {
    int64_t stop_id;
  };
  struct TrackCommand {
    int64_t load_id;
    int64_t request_id;
    std::string property;
    std::optional<int64_t> selection_id;
  };
  struct VolumeCommand {
    double volume;
  };
  using QueuedCommand = std::variant<LoadCommand, PlayCommand, PauseCommand,
                                     SeekCommand, StopCommand, TrackCommand,
                                     VolumeCommand>;

  friend struct PlayerCoreTestAccess;

  CallResult HandleLoad(ValueMap* arguments);
  std::optional<TrackCommand> ParseTrack(const ValueMap& arguments);
  void FinishDispose();
  bool QueueCommand(QueuedCommand command);
  void RunCommand(QueuedCommand& command, uint64_t generation);
  void StartEventThread();
  void StopEventThread();
  void EventLoop(uint64_t generation);
  void HandleMpvEvent(const mpv_event& event, uint64_t generation);
  void ObserveSeekLanding(mpv_event_id event);
  void ResetSeekObservation();
  void QueueEvent(uint64_t generation, ValueMap value);
  void QueueStopResult(uint64_t generation, int64_t stop_id, bool success);
  void QueueTrackResult(uint64_t generation, int64_t load_id,
                        int64_t request_id, bool success);
  void DrainEvents(const EventSink& deliver);

  const MpvOperations mpv_operations_;
  CoreHost& host_;
  mpv_handle* mpv_ = nullptr;
  std::thread event_thread_;
  std::atomic<bool> accepting_commands_{false};
  std::atomic<bool> stopping_{false};
  std::atomic<uint64_t> generation_{0};
  std::atomic<bool> wakeup_posted_{false};
  std::mutex command_mutex_;
  std::deque<QueuedCommand> commands_;
  size_t queued_command_bytes_ = 0;
  std::mutex event_mutex_;
  std::deque<QueuedEvent> events_;
  NativePlaybackState playback_;
  std::optional<SeekObservation> seek_observation_;
  bool seek_observation_ambiguous_ = false;
  Reply dispose_reply_;
  std::atomic<bool> dispose_ready_{false};
  std::atomic<bool> worker_finished_{true};
  bool shutdown_started_ = false;
  bool disposed_ = true;
};

}  // namespace lineup::player

#endif
