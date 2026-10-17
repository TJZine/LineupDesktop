#ifndef RUNNER_NATIVE_PLAYER_TEST_SUPPORT_H_
#define RUNNER_NATIVE_PLAYER_TEST_SUPPORT_H_

#include "native_player.h"
#include "encodable_value_conversion.h"
#include "player_core/player_core_test_access.h"
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
}

struct NativePlayerTestAccess {
  using CoreAccess = lineup::player::PlayerCoreTestAccess;
  static lineup::player::PlayerCore& Core(WindowsNativePlayer& player) {
    return player.core_;
  }
  static lineup::player::NativePlaybackState& State(WindowsNativePlayer& player) {
    return CoreAccess::State(player.core_);
  }
  static void Event(WindowsNativePlayer& player, const mpv_event& event) {
    CoreAccess::Event(player.core_, event);
  }
  static void Queue(WindowsNativePlayer& player, uint64_t generation,
                    native_test::Map event) {
    const native_test::Value wrapped(std::move(event));
    auto converted = lineup::ToValueMap(&wrapped);
    native_test::Check(converted.has_value(), "test event map");
    CoreAccess::Queue(player.core_, generation, std::move(*converted));
  }
  static void Drain(WindowsNativePlayer& player) {
    CoreAccess::Drain(player.core_, [&player](const lineup::player::ValueMap& event) {
      player.SendEvent(event);
    });
  }
  static uint64_t Generation(WindowsNativePlayer& player) {
    return CoreAccess::Generation(player.core_);
  }
  static bool Disposed(WindowsNativePlayer& player) {
    return CoreAccess::Disposed(player.core_) && !player.video_host_;
  }
  static bool WorkerFinished(WindowsNativePlayer& player) {
    return CoreAccess::WorkerFinished(player.core_);
  }
  static bool ShutdownStarted(WindowsNativePlayer& player) {
    return CoreAccess::ShutdownStarted(player.core_);
  }
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
  static void OpenWorkerlessCommandClient(WindowsNativePlayer& player) {
    auto& core = player.core_;
    native_test::Check(CoreAccess::Workerless(core), "workerless command fixture");
    native_test::Check(CoreAccess::Client(core) == nullptr &&
                       !CoreAccess::AcceptingCommands(core),
                       "OpenWorkerlessCommandClient client state");
    mpv_handle* client = mpv_create();
    native_test::Check(client != nullptr, "command fixture client");
    native_test::Check(mpv_set_option_string(client, "vo", "null") >= 0 &&
                       mpv_set_option_string(client, "ao", "null") >= 0 &&
                       mpv_set_option_string(client, "idle", "yes") >= 0 &&
                       mpv_set_option_string(client, "config", "no") >= 0 &&
                       mpv_initialize(client) >= 0, "command fixture initialization");
    CoreAccess::OpenWorkerlessClient(core, client);
  }
  static void CloseWorkerlessCommandClient(WindowsNativePlayer& player) {
    auto& core = player.core_;
    native_test::Check(CoreAccess::Workerless(core), "workerless command fixture");
    native_test::Check(CoreAccess::Client(core) != nullptr,
                       "CloseWorkerlessCommandClient client state");
    mpv_terminate_destroy(CoreAccess::CloseWorkerlessClient(core));
  }
  static void DrainCommandsSynchronously(WindowsNativePlayer& player) {
    auto& core = player.core_;
    native_test::Check(CoreAccess::Workerless(core), "workerless command fixture");
    native_test::Check(CoreAccess::Client(core) != nullptr,
                       "DrainCommandsSynchronously client state");
    CoreAccess::RunQueuedCommands(core);
  }
};
#endif
