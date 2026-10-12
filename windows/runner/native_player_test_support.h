#ifndef RUNNER_NATIVE_PLAYER_TEST_SUPPORT_H_
#define RUNNER_NATIVE_PLAYER_TEST_SUPPORT_H_

#include "native_player.h"
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <chrono>
#include <cstdlib>
#include <functional>
#include <iostream>
#include <vector>

namespace native_test {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;

inline void Check(bool condition, const char* obligation) {
  if (!condition) {
    std::cerr << obligation << '\n';
    std::exit(1);
  }
}
struct Reply {
  int successes = 0;
  int errors = 0;
  std::string error;
  std::function<void()> on_success;
};

class Messenger final : public flutter::BinaryMessenger {
 public:
  void SetMessageHandler(const std::string&,
                         flutter::BinaryMessageHandler value) override {
    handler = std::move(value);
  }
  void Send(const std::string&, const uint8_t* bytes, size_t size,
            flutter::BinaryReply = nullptr) const override {
    const auto call = flutter::StandardMethodCodec::GetInstance()
                          .DecodeMethodCall(bytes, size);
    Check(call && call->method_name() == "event", "production event codec");
    const auto* map = call->arguments() ? std::get_if<Map>(call->arguments()) : nullptr;
    Check(map != nullptr, "production event map");
    events.push_back(*map);
  }
  void Call(const char* method, Reply& reply, Map arguments = {}) {
    const auto message = flutter::StandardMethodCodec::GetInstance()
        .EncodeMethodCall(flutter::MethodCall<Value>(
            method, std::make_unique<Value>(std::move(arguments))));
    Check(static_cast<bool>(handler), "live method channel");
    handler(message->data(), message->size(), [&reply](const uint8_t* bytes, size_t size) {
      Check(size > 0, "method response envelope");
      if (bytes[0] == 0) {
        ++reply.successes;
        if (reply.on_success) reply.on_success();
      } else {
        ++reply.errors;
      }
    });
  }
  flutter::BinaryMessageHandler handler;
  mutable std::vector<Map> events;
};

inline void PumpUntil(const std::function<bool()>& ready, const char* obligation) {
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(10);
  while (!ready() && std::chrono::steady_clock::now() < deadline) {
    MSG message{};
    while (::PeekMessage(&message, nullptr, 0, 0, PM_REMOVE)) {
      ::TranslateMessage(&message);
      ::DispatchMessage(&message);
    }
    ::Sleep(1);
  }
  Check(ready(), obligation);
}
inline const Value* Find(const Map& map, const char* key) {
  const auto found = map.find(Value(key));
  return found == map.end() ? nullptr : &found->second;
}
inline bool Has(const Map& map, const char* key, const Value& expected) {
  const auto* value = Find(map, key);
  return value && *value == expected;
}
}  // namespace native_test

// This friend seam does not run in the app. Transitions and platform messages
// enter production code; field inspection observes order after synchronization.
struct NativePlayerTestAccess {
  static lineup::NativePlaybackState& State(WindowsNativePlayer& player) {
    return player.playback_;
  }
  static void Event(WindowsNativePlayer& player, const mpv_event& event) {
    player.HandleMpvEvent(event, player.generation_.load());
  }
  static void Queue(WindowsNativePlayer& player, uint64_t generation,
                    native_test::Map event) {
    player.QueueEvent(generation, std::move(event));
  }
  static void Drain(WindowsNativePlayer& player) { player.DrainEvents(); }
  static uint64_t Generation(WindowsNativePlayer& player) { return player.generation_.load(); }
  static bool Disposed(WindowsNativePlayer& player) {
    return player.disposed_ && player.worker_finished_ && !player.event_thread_.joinable() &&
           !player.video_host_ && !player.mpv_ && !player.accepting_commands_ &&
           player.commands_.empty() && player.events_.empty() &&
           !player.playback_.active_load();
  }
  static bool WorkerFinished(WindowsNativePlayer& player) { return player.worker_finished_.load(); }
  static bool ShutdownStarted(WindowsNativePlayer& player) { return player.shutdown_started_; }
  static void Invoke(WindowsNativePlayer& player, const char* method,
                     native_test::Reply& reply, native_test::Map arguments = {}) {
    auto result = std::make_unique<flutter::MethodResultFunctions<native_test::Value>>(
        [&reply](const auto*) {
          ++reply.successes;
          if (reply.on_success) reply.on_success();
        },
        [&reply](const auto& code, const auto&, const auto*) {
          ++reply.errors;
          reply.error = code;
        },
        [&reply]() { ++reply.errors; reply.error = "not_implemented"; });
    player.HandleMethodCall(flutter::MethodCall<native_test::Value>(
        method, std::make_unique<native_test::Value>(std::move(arguments))), std::move(result));
  }
  static void OpenCommandClient(WindowsNativePlayer& player) {
    player.mpv_ = mpv_create();
    native_test::Check(player.mpv_ != nullptr, "command fixture client");
    native_test::Check(mpv_set_option_string(player.mpv_, "vo", "null") >= 0 &&
                       mpv_set_option_string(player.mpv_, "ao", "null") >= 0 &&
                       mpv_set_option_string(player.mpv_, "idle", "yes") >= 0 &&
                       mpv_set_option_string(player.mpv_, "config", "no") >= 0 &&
                       mpv_initialize(player.mpv_) >= 0, "command fixture initialization");
    player.accepting_commands_ = true;
  }
  static void CloseCommandClient(WindowsNativePlayer& player) {
    player.accepting_commands_ = false;
    player.commands_.clear();
    player.queued_command_bytes_ = 0;
    mpv_terminate_destroy(player.mpv_);
    player.mpv_ = nullptr;
    player.playback_.Reset();
  }
  static void RunQueued(WindowsNativePlayer& player) {
    // Only used in the fixture with no worker: real parser/queue/dispatch/mpv.
    while (!player.commands_.empty()) {
      auto command = std::move(player.commands_.front());
      player.commands_.pop_front();
      player.RunCommand(command, player.generation_.load());
    }
    player.queued_command_bytes_ = 0;
  }
};
#endif  // RUNNER_NATIVE_PLAYER_TEST_SUPPORT_H_
