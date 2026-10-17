#ifndef LINEUP_PLAYER_CORE_PLAYER_CORE_TEST_ACCESS_H_
#define LINEUP_PLAYER_CORE_PLAYER_CORE_TEST_ACCESS_H_

// Test-only access to PlayerCore internals. Shared by the portable core
// contract test and the platform adapter tests.

#include "player_core/player_core.h"

#include <utility>

namespace lineup::player {

struct PlayerCoreTestAccess {
  static NativePlaybackState& State(PlayerCore& core) { return core.playback_; }
  static void Event(PlayerCore& core, const mpv_event& event) {
    core.HandleMpvEvent(event, core.generation_.load());
  }
  static void Queue(PlayerCore& core, uint64_t generation, ValueMap event) {
    core.QueueEvent(generation, std::move(event));
  }
  // Delivers queued events without completing a pending disposal.
  static void Drain(PlayerCore& core, const PlayerCore::EventSink& deliver) {
    core.DrainEvents(deliver);
  }
  static uint64_t Generation(PlayerCore& core) { return core.generation_.load(); }
  static bool Disposed(PlayerCore& core) {
    return core.disposed_ && core.worker_finished_ && !core.event_thread_.joinable() &&
           !core.mpv_ && !core.accepting_commands_ && core.commands_.empty() &&
           core.events_.empty() && !core.playback_.active_load();
  }
  static bool WorkerFinished(PlayerCore& core) { return core.worker_finished_.load(); }
  static bool ShutdownStarted(PlayerCore& core) { return core.shutdown_started_; }
  static bool Workerless(PlayerCore& core) {
    return !core.event_thread_.joinable() && core.worker_finished_.load();
  }
  static mpv_handle* Client(PlayerCore& core) { return core.mpv_; }
  static bool AcceptingCommands(PlayerCore& core) { return core.accepting_commands_; }

  // Installs a client and accepts commands without starting the worker, so a
  // test can run queued commands synchronously.
  static void OpenWorkerlessClient(PlayerCore& core, mpv_handle* client) {
    core.mpv_ = client;
    core.accepting_commands_ = true;
  }
  // Returns the client for the caller to destroy.
  static mpv_handle* CloseWorkerlessClient(PlayerCore& core) {
    core.accepting_commands_ = false;
    core.commands_.clear();
    core.queued_command_bytes_ = 0;
    mpv_handle* client = core.mpv_;
    core.mpv_ = nullptr;
    core.playback_.Reset();
    return client;
  }
  static void RunQueuedCommands(PlayerCore& core) {
    while (!core.commands_.empty()) {
      auto command = std::move(core.commands_.front());
      core.commands_.pop_front();
      core.RunCommand(command, core.generation_.load());
    }
    core.queued_command_bytes_ = 0;
  }
};

}  // namespace lineup::player

#endif
