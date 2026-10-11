// Exercise the existing method-channel boundary with the real production
// configuration and load command. Only CA and presentation are test-local.
#include "native_player.h"

#include <flutter/standard_method_codec.h>

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <iostream>

namespace {
const char* test_ca = nullptr;
const char* rejected_option = nullptr;

int SetTestOption(mpv_handle* client, const char* name, const char* value) {
  if (rejected_option && std::strcmp(name, rejected_option) == 0) {
    return MPV_ERROR_OPTION_NOT_FOUND;
  }
  return mpv_set_option_string(client, name, value);
}

mpv_handle* CreateTestClient() {
  auto* client = mpv_create();
  if (client && mpv_set_option_string(client, "tls-ca-file", test_ca) < 0) {
    mpv_terminate_destroy(client);
    return nullptr;
  }
  return client;
}

int InitializeTestClient(mpv_handle* client) {
  // These override presentation only, after all production options were set.
  for (const auto* name : {"vo", "ao"}) {
    const int status = mpv_set_option_string(client, name, "null");
    if (status < 0) return status;
  }
  return mpv_initialize(client);
}
}  // namespace

// Compile the production implementation unchanged, without exporting a private
// method, copying options, or replacing the authenticated load path. Forward
// both runtime calls to the pinned DLL, with the temporary CA and null outputs.
#define mpv_create CreateTestClient
#define mpv_initialize InitializeTestClient
#define mpv_set_option_string SetTestOption
#include "native_player.cpp"
#undef mpv_set_option_string
#undef mpv_initialize
#undef mpv_create

namespace {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;

class TestMessenger final : public flutter::BinaryMessenger {
 public:
  void SetMessageHandler(const std::string&,
                         flutter::BinaryMessageHandler value) override {
    handler = std::move(value);
  }

  void Send(const std::string&, const uint8_t* bytes, size_t size,
            flutter::BinaryReply = nullptr) const override {
    const auto call = flutter::StandardMethodCodec::GetInstance()
                          .DecodeMethodCall(bytes, size);
    if (!call || !call->arguments()) return;
    const auto* map = std::get_if<Map>(call->arguments());
    if (!map) return;
    const auto state = map->find(Value("state"));
    if (state != map->end()) {
      const auto* text = std::get_if<std::string>(&state->second);
      if (text && (*text == "stopped" || *text == "error")) {
        finished = true;
        failed = failed || (*text == "error");
      }
    }
    const auto name = map->find(Value("name"));
    const auto value = map->find(Value("value"));
    if (name != map->end() && name->second == Value("time-pos") &&
        value != map->end()) {
      const auto* seconds = std::get_if<double>(&value->second);
      if (seconds && *seconds > 0.1) progressed = true;
    }
  }

  bool Call(const char* method, Map arguments = {}) {
    const auto message = flutter::StandardMethodCodec::GetInstance()
                             .EncodeMethodCall(flutter::MethodCall<Value>(
                                 method, std::make_unique<Value>(arguments)));
    bool replied = false;
    bool success = false;
    handler(message->data(), message->size(), [&](const uint8_t* bytes,
                                                 size_t size) {
      replied = true;
      success = size > 0 && bytes[0] == 0;
    });
    return replied && success;
  }

  flutter::BinaryMessageHandler handler;
  mutable bool finished = false;
  mutable bool failed = false;
  mutable bool progressed = false;
};

void SendTestEvent(TestMessenger& messenger, Map arguments) {
  const auto message = flutter::StandardMethodCodec::GetInstance()
                           .EncodeMethodCall(flutter::MethodCall<Value>(
                               "event", std::make_unique<Value>(arguments)));
  messenger.Send("lineup/native_player", message->data(), message->size());
}

// Exercise the actual decoder and latch with checks that remain active in
// Release builds. These bounded event sequences do not simulate media output.
bool TerminalStateContractHolds() {
  TestMessenger stopped;
  SendTestEvent(stopped, {{Value("state"), Value("stopped")}});
  if (!stopped.finished || stopped.failed || stopped.progressed) return false;

  TestMessenger rejected;
  SendTestEvent(rejected, {{Value("state"), Value("error")}});
  SendTestEvent(rejected, {{Value("state"), Value("stopped")}});
  if (!rejected.finished || !rejected.failed || rejected.progressed) return false;

  TestMessenger progressed_then_rejected;
  SendTestEvent(progressed_then_rejected,
                {{Value("name"), Value("time-pos")},
                 {Value("value"), Value(1.0)}});
  SendTestEvent(progressed_then_rejected,
                {{Value("state"), Value("error")}});
  SendTestEvent(progressed_then_rejected,
                {{Value("state"), Value("stopped")}});
  return progressed_then_rejected.finished && progressed_then_rejected.failed &&
         progressed_then_rejected.progressed;
}
}  // namespace

int main(int argc, char** argv) {
  if (argc != 3 && argc != 4) return 2;
  if (!TerminalStateContractHolds()) {
    std::cout << "messenger_contract=failed\n";
    return 1;
  }
  test_ca = argv[1];
  const bool observe = argc == 4 && std::strcmp(argv[3], "observe") == 0;
  if (argc == 4 && !observe) rejected_option = argv[3];
  // Never retain raw native diagnostic output. Report fixed outcomes only.
  FILE* redirected = nullptr;
  if (freopen_s(&redirected, "NUL", "w", stderr) != 0) return 2;
  SetEnvironmentVariableW(L"LINEUP_FLUTTER_DCOMP_ACTIVE",
                          L"692136cb6582dbfc5af3fb33c2515a069f2f66d0");
  HWND window = CreateWindowExW(0, L"STATIC", L"", WS_OVERLAPPEDWINDOW,
                                0, 0, 64, 64, nullptr, nullptr,
                                GetModuleHandle(nullptr), nullptr);
  if (!window) return 2;
  TestMessenger messenger;
  bool timed_out = false;
  bool initialized = false;
  {
    WindowsNativePlayer player(window, window, &messenger);
    initialized = messenger.Call("initialize");
    if (initialized && messenger.Call("load", {
          {Value("uri"), Value(argv[2])},
          {Value("loadId"), Value(int64_t{1})},
          {Value("plexToken"), Value("lineup-synthetic-reference-test")},
        })) {
      const auto deadline = std::chrono::steady_clock::now() +
                            std::chrono::seconds(observe ? 2 : 12);
      while (!messenger.finished && std::chrono::steady_clock::now() < deadline) {
        MSG message;
        while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
          if (!player.HandleWindowMessage(message.message)) {
            TranslateMessage(&message);
            DispatchMessageW(&message);
          }
        }
        MsgWaitForMultipleObjects(0, nullptr, FALSE, 20, QS_ALLINPUT);
      }
      timed_out = !messenger.finished && !observe;
    } else {
      messenger.failed = true;
    }
    // The production destructor bounds native worker termination to 5 seconds.
  }
  DestroyWindow(window);
  std::cout << "initialized=" << initialized
            << " progressed=" << messenger.progressed
            << " rejected=" << messenger.failed
            << " timed_out=" << timed_out << '\n';
  if (rejected_option) return initialized ? 1 : 0;
  return initialized && !timed_out ? 0 : 1;
}
