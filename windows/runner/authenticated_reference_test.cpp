#include "native_player.h"

#include <flutter/standard_method_codec.h>

#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <string>
#include <thread>
#include <vector>

namespace {
const char* test_ca = nullptr;
std::string mode;
std::atomic<mpv_handle*> observed_client{nullptr};

// Each load has separate observations. Only the worker touches lifecycle
// flags; publication to the platform messenger is atomic. No target jump is progress.
struct PlaybackObservation {
  explicit PlaybackObservation(bool nonzero = false) : nonzero(nonzero) {}
  const bool nonzero;
  int files_started = 0;
  bool loaded = false;
  bool restarted = false;
  std::atomic<double> landing{-1.0};
  std::atomic<bool> advanced{false};
  std::atomic<bool> sampled{false};
  std::atomic<bool> initial_paused{false};
  std::atomic<bool> released{false};

  void Restart(double seconds, bool seeking, bool paused) {
    if (!loaded || restarted || seeking) return;
    restarted = true;
    // The alternate fixture has independently checked keyframes at 0,1,...,5.
    // Starting exactly at 3.5 or ignoring start and landing at 0 must fail.
    initial_paused.store(paused);
    if (paused && std::isfinite(seconds) && seconds >= 0 &&
        (nonzero ? std::abs(seconds - 3.0) <= 0.15 : seconds <= 0.15)) landing.store(seconds);
    sampled.store(true);
  }

  void Position(double seconds, bool seeking, bool paused) {
    const double baseline = landing.load();
    if (loaded && released.load() && !paused && !seeking && baseline >= 0 && std::isfinite(seconds) &&
        seconds >= baseline + 0.2) advanced.store(true);
  }
};
std::atomic<PlaybackObservation*> observation{nullptr};
bool delay_exercised = false;
bool ignored_start = false;
bool ignored_references = false;

// Sensitivity controls remove only their named per-file option. All other
// authentication, redirect and seek policy remains in the original node map.
int CommandTestNode(mpv_handle* client, mpv_node* command, mpv_node* result) {
  if (mode != "control-ignore-start-delayed" && mode != "session-control-no-references")
    return mpv_command_node(client, command, result);
  if (command->format != MPV_FORMAT_NODE_ARRAY || command->u.list->num != 5)
    return MPV_ERROR_INVALID_PARAMETER;
  const auto& options = command->u.list->values[4];
  if (options.format != MPV_FORMAT_NODE_MAP) return MPV_ERROR_INVALID_PARAMETER;
  std::vector<mpv_node> values;
  std::vector<char*> keys;
  for (int i = 0; i < options.u.list->num; ++i) {
    if (mode == "session-control-no-references" &&
        std::strcmp(options.u.list->keys[i], "access-references") == 0) {
      ignored_references = true;
      continue;
    }
    if (mode == "control-ignore-start-delayed" &&
        std::strcmp(options.u.list->keys[i], "start") == 0) {
      ignored_start = true;
      continue;
    }
    values.push_back(options.u.list->values[i]);
    keys.push_back(options.u.list->keys[i]);
  }
  mpv_node_list option_list{static_cast<int>(values.size()), values.data(), keys.data()};
  mpv_node arguments[5];
  for (int i = 0; i < 5; ++i) arguments[i] = command->u.list->values[i];
  arguments[4].u.list = &option_list;
  mpv_node_list argument_list{5, arguments, nullptr};
  mpv_node altered{};
  altered.format = MPV_FORMAT_NODE_ARRAY;
  altered.u.list = &argument_list;
  return mpv_command_node(client, &altered, result);
}

mpv_event* WaitTestEvent(mpv_handle* client, double timeout) {
  auto* event = mpv_wait_event(client, timeout);
  auto* current_observation = observation.load();
  if (!current_observation || !event) return event;
  if (event->event_id == MPV_EVENT_START_FILE) {
    ++current_observation->files_started;
    current_observation->loaded = false;
  }
  if (event->event_id == MPV_EVENT_FILE_LOADED && current_observation->files_started == 1)
    current_observation->loaded = true;
  if (event->event_id == MPV_EVENT_END_FILE) current_observation->loaded = false;
  if (event->event_id == MPV_EVENT_PLAYBACK_RESTART && current_observation->loaded &&
      !delay_exercised && (mode == "control-delayed-start" || mode == "control-ignore-start-delayed")) {
    delay_exercised = true;
    std::this_thread::sleep_for(std::chrono::seconds(3));
  }
  if (event->event_id == MPV_EVENT_PLAYBACK_RESTART ||
      event->event_id == MPV_EVENT_PROPERTY_CHANGE) {
    const auto* property = event->event_id == MPV_EVENT_PROPERTY_CHANGE
        ? static_cast<mpv_event_property*>(event->data) : nullptr;
    if (event->event_id == MPV_EVENT_PLAYBACK_RESTART ||
        (property && std::strcmp(property->name, "time-pos") == 0)) {
      double seconds = 0;
      int seeking = 1;
      int paused = 0;
      if (mpv_get_property(client, "seeking", MPV_FORMAT_FLAG, &seeking) >= 0 &&
          mpv_get_property(client, "pause", MPV_FORMAT_FLAG, &paused) >= 0 &&
          mpv_get_property(client, "time-pos", MPV_FORMAT_DOUBLE, &seconds) >= 0) {
        if (event->event_id == MPV_EVENT_PLAYBACK_RESTART)
          current_observation->Restart(seconds, seeking != 0, paused != 0);
        else
          current_observation->Position(seconds, seeking != 0, paused != 0);
      }
    }
  }
  return event;
}

int SetTestOption(mpv_handle* client, const char* name, const char* value) {
  if (mode == name) {
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
  observed_client = client;
  return client;
}

bool ReferencesRestored() {
  auto* client = observed_client.load();
  int enabled = 1;
  return client && mpv_get_property(client, "options/access-references",
                                    MPV_FORMAT_FLAG, &enabled) >= 0 && !enabled;
}

int InitializeTestClient(mpv_handle* client) {
  for (const auto* name : {"vo", "ao"}) {
    const int status = mpv_set_option_string(client, name, "null");
    if (status < 0) return status;
  }
  return mpv_initialize(client);
}
}


namespace {
WindowsNativePlayer::MpvOperations TestOperations() {
  auto operations = lineup::player::LibmpvOperations();
  operations.create = CreateTestClient;
  operations.initialize = InitializeTestClient;
  operations.set_option_string = SetTestOption;
  operations.wait_event = WaitTestEvent;
  operations.command_node = CommandTestNode;
  return operations;
}

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
    const auto load_id = map->find(Value("loadId"));
    if (load_id != map->end() && load_id->second != Value(active_load_id)) return;
    const auto state = map->find(Value("state"));
    if (state != map->end()) {
      const auto* text = std::get_if<std::string>(&state->second);
      if (text && (*text == "ended" || *text == "stopped" || *text == "error")) {
        finished = true;
        failed = failed || (*text == "error");
      }
    }
    const auto name = map->find(Value("name"));
    const auto value = map->find(Value("value"));
    if (name != map->end() && name->second == Value("time-pos") &&
        value != map->end()) {
      const auto* seconds = std::get_if<double>(&value->second);
      if (seconds && std::isfinite(*seconds) && playback_observation &&
          playback_observation->advanced.load()) progressed = true;
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

  int64_t active_load_id = 1;
  PlaybackObservation* playback_observation = nullptr;
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

bool TerminalStateContractHolds() {
  PlaybackObservation baseline;
  baseline.files_started = 1;
  baseline.loaded = true;
  baseline.Restart(0, false, true);
  baseline.released.store(true);
  baseline.Position(1, false, false);
  TestMessenger ended;
  SendTestEvent(ended, {{Value("state"), Value("ended")}});
  if (!ended.finished || ended.failed || ended.progressed) return false;

  TestMessenger progressed_then_ended;
  progressed_then_ended.playback_observation = &baseline;
  SendTestEvent(progressed_then_ended,
                {{Value("name"), Value("time-pos")},
                 {Value("value"), Value(1.0)}});
  if (progressed_then_ended.finished || progressed_then_ended.failed ||
      !progressed_then_ended.progressed) return false;
  SendTestEvent(progressed_then_ended,
                {{Value("state"), Value("ended")}});
  if (!progressed_then_ended.finished || progressed_then_ended.failed ||
      !progressed_then_ended.progressed) return false;
  SendTestEvent(progressed_then_ended,
                {{Value("state"), Value("error")}});
  if (!progressed_then_ended.failed) return false;

  TestMessenger rejected_then_ended;
  SendTestEvent(rejected_then_ended, {{Value("state"), Value("error")}});
  SendTestEvent(rejected_then_ended, {{Value("state"), Value("ended")}});
  if (!rejected_then_ended.finished || !rejected_then_ended.failed ||
      rejected_then_ended.progressed) return false;

  TestMessenger stopped;
  SendTestEvent(stopped, {{Value("state"), Value("stopped")}});
  if (!stopped.finished || stopped.failed || stopped.progressed) return false;

  TestMessenger rejected;
  SendTestEvent(rejected, {{Value("state"), Value("error")}});
  SendTestEvent(rejected, {{Value("state"), Value("stopped")}});
  if (!rejected.finished || !rejected.failed || rejected.progressed) return false;

  TestMessenger progressed_then_rejected;
  progressed_then_rejected.playback_observation = &baseline;
  SendTestEvent(progressed_then_rejected,
                {{Value("name"), Value("time-pos")},
                 {Value("value"), Value(1.0)}});
  SendTestEvent(progressed_then_rejected,
                {{Value("state"), Value("error")}});
  SendTestEvent(progressed_then_rejected,
                {{Value("state"), Value("stopped")}});
  if (!progressed_then_rejected.finished || !progressed_then_rejected.failed ||
      !progressed_then_rejected.progressed) return false;

  PlaybackObservation alternate(true);
  TestMessenger messenger;
  messenger.playback_observation = &alternate;
  alternate.Restart(3.0, false, true);
  if (alternate.landing.load() >= 0) return false;
  alternate.files_started = 1;
  alternate.loaded = true;
  alternate.Restart(3.0, true, true);
  if (alternate.landing.load() >= 0) return false;
  alternate.Restart(3.0, false, true);
  for (double seconds : {3.0, 3.0, 2.9}) {
    alternate.Position(seconds, false, true);
    SendTestEvent(messenger, {{Value("name"), Value("time-pos")},
                              {Value("value"), Value(seconds)}});
    if (messenger.progressed) return false;
  }
  alternate.Position(3.5, true, true);
  if (alternate.advanced.load()) return false;
  alternate.Position(3.25, false, true);
  if (alternate.advanced.load()) return false;
  alternate.released.store(true);
  alternate.Position(3.25, false, false);
  SendTestEvent(messenger, {{Value("name"), Value("time-pos")},
                            {Value("value"), Value(3.25)}});
  for (double wrong : {0.0, 3.5}) {
    PlaybackObservation ignored(true);
    ignored.files_started = 1;
    ignored.loaded = true;
    ignored.Restart(wrong, false, true);
    ignored.released.store(true);
    ignored.Position(4.0, false, false);
    if (ignored.advanced.load()) return false;
  }
  PlaybackObservation moving(true);
  moving.loaded = true;
  moving.Restart(3.0, false, false);
  moving.released.store(true);
  moving.Position(3.3, false, false);
  if (moving.landing.load() >= 0 || moving.advanced.load()) return false;
  return messenger.progressed;
}
}

int main(int argc, char** argv) {
  if (argc < 3 || argc > 5) return 2;
  if (!TerminalStateContractHolds()) {
    std::cout << "messenger_contract=failed\n";
    return 1;
  }
  test_ca = argv[1];
  bool nonzero_start = false;
  for (int i = 3; i < argc; ++i) {
    if (std::strcmp(argv[i], "--nonzero-start") == 0) {
      if (nonzero_start) return 2;
      nonzero_start = true;
    } else {
      if (!mode.empty()) return 2;
      mode = argv[i];
    }
  }
  if (!mode.empty() && mode != "observe" && mode != "access-references" &&
      mode != "autoload-files" && mode != "control-delayed-start" &&
      mode != "control-ignore-start-delayed" && mode != "session-complete" &&
      mode != "session-stop" && mode != "session-replace" &&
      mode != "session-redirect" && mode != "session-off-origin" &&
      mode != "session-control-no-references") return 2;
  const bool session = mode.rfind("session-", 0) == 0;
  if (session && nonzero_start) return 2;
  if (!nonzero_start && (mode == "control-delayed-start" || mode == "control-ignore-start-delayed")) return 2;
  const bool observe = mode == "observe";
  FILE* redirected = nullptr;
  if (freopen_s(&redirected, "NUL", "w", stderr) != 0) return 2;
  SetEnvironmentVariableW(L"LINEUP_FLUTTER_DCOMP_ACTIVE",
                          L"deb287481e3ce9468f3434937ced4240a70539ca");
  HWND window = CreateWindowExW(0, L"STATIC", L"", WS_OVERLAPPEDWINDOW,
                                0, 0, 64, 64, nullptr, nullptr,
                                GetModuleHandle(nullptr), nullptr);
  if (!window) return 2;
  PlaybackObservation playback(nonzero_start);
  PlaybackObservation restored;
  observation = &playback;
  TestMessenger messenger;
  messenger.playback_observation = &playback;
  bool timed_out = false;
  bool initialized = false;
  bool session_progressed = false;
  bool session_rejected = false;
  bool restoration_attempted = false;
  bool restoration_rejected = false;
  bool restoration_progressed = false;
  bool references_restored_before = false;
  bool references_restored_after = false;
  {
    WindowsNativePlayer player(window, window, &messenger, TestOperations());
    initialized = messenger.Call("initialize");
    Map load = {
        {Value("uri"), Value(argv[2])},
        {Value("loadId"), Value(int64_t{1})},
        {Value("plexToken"), Value("lineup-synthetic-reference-test")},
        {Value("startPaused"), Value(true)},
    };
    if (session) {
      load.erase(Value("plexToken"));
      load.emplace(Value("kind"), Value("plexSession"));
    }
    if (nonzero_start) load.emplace(Value("startSeconds"), Value(3.5));
    if (initialized && messenger.Call("load", load)) {
      const auto deadline = std::chrono::steady_clock::now() +
                            std::chrono::seconds(observe ? 2 : 12);
      while (!messenger.finished && std::chrono::steady_clock::now() < deadline) {
        // Test-only stationary measurement, followed by actual playback.
        if (playback.sampled.load() && playback.initial_paused.load() && !playback.released.load()) {
          if (!messenger.Call("play")) { messenger.failed = true; break; }
          playback.released.store(true);
        }
        if (session && messenger.progressed &&
            (mode == "session-stop" || mode == "session-replace")) break;
        MSG message;
        while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
          if (!player.HandleWindowMessage(message.message)) {
            TranslateMessage(&message);
            DispatchMessageW(&message);
          }
        }
        MsgWaitForMultipleObjects(0, nullptr, FALSE, 20, QS_ALLINPUT);
      }
      timed_out = !messenger.finished && !observe &&
          !(session && messenger.progressed &&
            (mode == "session-stop" || mode == "session-replace"));
    } else {
      messenger.failed = true;
    }
    if (session) {
      session_progressed = messenger.progressed;
      session_rejected = messenger.failed;
      if (!timed_out && session_progressed && !session_rejected &&
          (mode == "session-complete" || mode == "session-stop" || mode == "session-replace")) {
        if (mode == "session-stop") {
          messenger.finished = false;
          if (!messenger.Call("stop", {{Value("stopId"), Value(int64_t{1})}})) {
            timed_out = true;
          }
          const auto stop_deadline = std::chrono::steady_clock::now() + std::chrono::seconds(3);
          while (!messenger.finished && !timed_out && std::chrono::steady_clock::now() < stop_deadline) {
            MSG message;
            while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
              if (!player.HandleWindowMessage(message.message)) {
                TranslateMessage(&message);
                DispatchMessageW(&message);
              }
            }
            MsgWaitForMultipleObjects(0, nullptr, FALSE, 20, QS_ALLINPUT);
          }
          timed_out = timed_out || !messenger.finished;
          session_rejected = session_rejected || messenger.failed;
        }
        if (!timed_out && !session_rejected) {
          references_restored_before = ReferencesRestored();
          // The same initialized client now makes an authenticated Direct Play
          // load. Its nested reference must be refused after every exit path.
          const std::string first_uri(argv[2]);
          const auto path = first_uri.find('/', 8);
          if (path == std::string::npos) return 2;
          const auto restore_uri = first_uri.substr(0, path) + "/restore.m3u8";
          observation = &restored;
          messenger.playback_observation = &restored;
          messenger.active_load_id = 2;
          messenger.finished = false;
          messenger.failed = false;
          messenger.progressed = false;
          restoration_attempted = true;
          if (!messenger.Call("load", {{Value("uri"), Value(restore_uri)},
                                      {Value("loadId"), Value(int64_t{2})},
                                      {Value("plexToken"), Value("lineup-synthetic-reference-test")},
                                      {Value("startPaused"), Value(true)}})) {
            messenger.failed = true;
          } else {
            const auto restore_deadline = std::chrono::steady_clock::now() + std::chrono::seconds(12);
            while (!messenger.finished && std::chrono::steady_clock::now() < restore_deadline) {
              if (restored.sampled.load() && restored.initial_paused.load() && !restored.released.load()) {
                if (!messenger.Call("play")) { messenger.failed = true; break; }
                restored.released.store(true);
              }
              MSG message;
              while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
                if (!player.HandleWindowMessage(message.message)) {
                  TranslateMessage(&message);
                  DispatchMessageW(&message);
                }
              }
              MsgWaitForMultipleObjects(0, nullptr, FALSE, 20, QS_ALLINPUT);
            }
            timed_out = !messenger.finished;
          }
          references_restored_after = ReferencesRestored();
          restoration_rejected = messenger.failed;
          restoration_progressed = messenger.progressed;
          observation = nullptr;
          messenger.playback_observation = nullptr;
        }
      }
    }
  }
  observation = nullptr;
  DestroyWindow(window);
  std::cout << "initialized=" << initialized
            << " start_configured=" << nonzero_start
            << " initial_paused=" << playback.initial_paused.load()
            << " play_released=" << playback.released.load()
            << " delay_exercised=" << delay_exercised
            << " ignored_start=" << ignored_start
            << " landing_confirmed=" << (playback.landing.load() >= 0)
            << " progressed=" << messenger.progressed
            << " rejected=" << messenger.failed
            << " session_progressed=" << session_progressed
            << " session_rejected=" << session_rejected
            << " session_override_removed=" << ignored_references
            << " restoration_attempted=" << restoration_attempted
            << " restoration_rejected=" << restoration_rejected
            << " restoration_progressed=" << restoration_progressed
            << " references_restored_before=" << references_restored_before
            << " references_restored_after=" << references_restored_after
            << " timed_out=" << timed_out << '\n';
  if (mode == "access-references" || mode == "autoload-files") return initialized ? 1 : 0;
  return initialized && !timed_out ? 0 : 1;
}
