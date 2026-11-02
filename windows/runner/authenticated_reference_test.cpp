#include "native_player.h"

#include <flutter/standard_method_codec.h>

#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iostream>
#include <map>
#include <string>
#include <thread>
#include <vector>

namespace {
const char* test_ca = nullptr;
std::string mode;
std::atomic<mpv_handle*> observed_client{nullptr};
std::atomic<int> nested_forbidden_count{0};
std::atomic<int> internal_redirect_count{0};
std::atomic<int> end_file_error_count{0};
std::atomic<bool> session_structural_failure{false};
int native_event_count = 0;

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
  if (mode == "session-nested-hls" && event->event_id != MPV_EVENT_NONE) {
    if (++native_event_count > 4096) session_structural_failure = true;
    if (event->event_id == MPV_EVENT_QUEUE_OVERFLOW) session_structural_failure = true;
    if (event->event_id == MPV_EVENT_LOG_MESSAGE) {
      const auto* message = static_cast<mpv_event_log_message*>(event->data);
      if (!message || !message->text) session_structural_failure = true;
      else if (nested_forbidden_count.load() < 4096 &&
          std::strstr(message->text, "Opening this file was forbidden for security reasons"))
        ++nested_forbidden_count; // Fixed count only; never retain or print raw log text.
    }
    if (event->event_id == MPV_EVENT_END_FILE) {
      const auto* end = static_cast<mpv_event_end_file*>(event->data);
      if (!end) session_structural_failure = true;
      else if (end->reason == MPV_END_FILE_REASON_REDIRECT && internal_redirect_count.load() < 4096)
        ++internal_redirect_count;
      else if (end->reason == MPV_END_FILE_REASON_ERROR && end_file_error_count.load() < 4096)
        ++end_file_error_count;
    }
  }
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

struct SessionOptions {
  mpv_handle* client = nullptr;
  bool valid = false;
  int references = 0;
  int64_t redirects = 0;
  std::string demuxer;
  std::map<std::string, std::string> lavf;
};
SessionOptions session_baseline;

bool ReadOptionText(mpv_handle* client, const char* name, std::string& output) {
  char* text = nullptr;
  if (mpv_get_property(client, name, MPV_FORMAT_STRING, &text) < 0 || !text) return false;
  const bool valid = std::strlen(text) <= 4096;
  if (valid) output = text;
  mpv_free(text);
  return valid;
}

bool ReadLavfOptions(mpv_handle* client, std::map<std::string, std::string>& output) {
  mpv_node node{};
  if (mpv_get_property(client, "options/demuxer-lavf-o", MPV_FORMAT_NODE, &node) < 0) return false;
  bool valid = node.format == MPV_FORMAT_NODE_MAP && node.u.list &&
      node.u.list->num >= 0 && node.u.list->num <= 64;
  if (valid) {
    const auto& map = *node.u.list;
    valid = map.num == 0 || (map.keys && map.values);
    for (int i = 0; valid && i < map.num; ++i) {
      const auto& value = map.values[i];
      valid = map.keys[i] && std::strlen(map.keys[i]) <= 4096 &&
          value.format == MPV_FORMAT_STRING && value.u.string &&
          std::strlen(value.u.string) <= 4096;
      if (valid) valid = output.emplace(map.keys[i], value.u.string).second;
    }
  }
  mpv_free_node_contents(&node);
  return valid;
}

SessionOptions ReadSessionOptions() {
  SessionOptions result;
  result.client = observed_client.load();
  result.valid = result.client &&
      mpv_get_property(result.client, "options/access-references", MPV_FORMAT_FLAG, &result.references) >= 0 &&
      mpv_get_property(result.client, "options/curl-max-redirects", MPV_FORMAT_INT64, &result.redirects) >= 0 &&
      ReadOptionText(result.client, "options/demuxer", result.demuxer) &&
      ReadLavfOptions(result.client, result.lavf);
  return result;
}

struct RestoredOptions {
  bool references = false;
  bool redirects = false;
  bool demuxer = false;
  bool lavf = false;
  bool all() const { return references && redirects && demuxer && lavf; }
};

RestoredOptions OptionsRestored() {
  const auto current = ReadSessionOptions();
  if (!session_baseline.valid || !current.valid || current.client != session_baseline.client) return {};
  return {current.references == session_baseline.references,
          current.redirects == session_baseline.redirects,
          current.demuxer == session_baseline.demuxer,
          current.lavf == session_baseline.lavf};
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
    if (!call || !call->arguments()) {
      if (mode == "session-nested-hls") session_structural_failure = true;
      return;
    }
    const auto* map = std::get_if<Map>(call->arguments());
    if (!map) {
      if (mode == "session-nested-hls") session_structural_failure = true;
      return;
    }
    if (mode == "session-nested-hls" && ++event_count > 4096) session_structural_failure = true;
    const auto load_id = map->find(Value("loadId"));
    if (load_id != map->end() && !(load_id->second == Value(active_load_id))) return;
    const auto state = map->find(Value("state"));
    if (state != map->end()) {
      const auto* text = std::get_if<std::string>(&state->second);
      if (text && (*text == "ended" || *text == "stopped" || *text == "error")) {
        finished = true;
        failed = failed || (*text == "error");
        if (mode == "session-nested-hls" && *text == "error") {
          const auto code = map->find(Value("failureCode"));
          bool ordinary = false;
          for (const auto* allowed : {"mpv_error", "http_error", "network_error", "audio_decode_error",
                                     "video_decode_error", "audio_output_error", "video_output_error",
                                     "source_open_error", "container_error"})
            ordinary = ordinary || (code != map->end() && code->second == Value(allowed));
          if (!ordinary) session_structural_failure = true;
        }
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
    if (mode == "session-nested-hls" && (!replied || !success)) session_structural_failure = true;
    return replied && success;
  }

  int64_t active_load_id = 1;
  PlaybackObservation* playback_observation = nullptr;
  flutter::BinaryMessageHandler handler;
  mutable bool finished = false;
  mutable bool failed = false;
  mutable bool progressed = false;
  mutable int event_count = 0;
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
  std::string session_playlist_path;
  for (int i = 3; i < argc; ++i) {
    if (std::strncmp(argv[i], "--session-playlist=", 19) == 0) {
      if (!session_playlist_path.empty()) return 2;
      session_playlist_path = argv[i] + 19;
    } else if (std::strcmp(argv[i], "--nonzero-start") == 0) {
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
      mode != "session-control-no-references" && mode != "session-nested-hls") return 2;
  const bool session = mode.rfind("session-", 0) == 0;
  if (session != !session_playlist_path.empty() || (session && nonzero_start)) return 2;
  std::string session_playlist;
  if (session) {
    std::ifstream file(session_playlist_path, std::ios::binary | std::ios::ate);
    if (!file) return 2;
    const auto length = file.tellg();
    if (length <= 0 || length > 1024 * 1024) return 2;
    session_playlist.resize(static_cast<size_t>(length));
    file.seekg(0);
    if (!file.read(session_playlist.data(), static_cast<std::streamsize>(session_playlist.size()))) return 2;
  }
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
  RestoredOptions restored_before;
  RestoredOptions restored_after;
  {
    WindowsNativePlayer player(window, window, &messenger, TestOperations());
    initialized = messenger.Call("initialize");
    if (session && initialized) session_baseline = ReadSessionOptions();
    Map load = {
        {Value("uri"), Value(argv[2])},
        {Value("loadId"), Value(int64_t{1})},
        {Value("plexToken"), Value("lineup-synthetic-reference-test")},
        {Value("startPaused"), Value(true)},
    };
    if (session) {
      load.erase(Value("plexToken"));
      load.emplace(Value("kind"), Value("plexSession"));
      load.emplace(Value("sessionPlaylist"), Value(Map{
          {Value("text"), Value(session_playlist)},
          {Value("offsetMicroseconds"), Value(int64_t{0})},
      }));
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
      if (session_rejected && !timed_out) restored_after = OptionsRestored();
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
          restored_before = OptionsRestored();
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
          restored_after = OptionsRestored();
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
            << " nested_forbidden_count=" << nested_forbidden_count.load()
            << " internal_redirect_count=" << internal_redirect_count.load()
            << " end_file_error_count=" << end_file_error_count.load()
            << " session_structural_failure=" << session_structural_failure.load()
            << " session_load_started=" << (playback.files_started == 1)
            << " session_progressed=" << session_progressed
            << " session_rejected=" << session_rejected
            << " session_override_removed=" << ignored_references
            << " restoration_attempted=" << restoration_attempted
            << " restoration_rejected=" << restoration_rejected
            << " restoration_progressed=" << restoration_progressed
            << " session_options_captured=" << session_baseline.valid
            << " references_restored_before=" << restored_before.references
            << " references_restored_after=" << restored_after.references
            << " redirects_restored_before=" << restored_before.redirects
            << " redirects_restored_after=" << restored_after.redirects
            << " demuxer_restored_before=" << restored_before.demuxer
            << " demuxer_restored_after=" << restored_after.demuxer
            << " lavf_options_restored_before=" << restored_before.lavf
            << " lavf_options_restored_after=" << restored_after.lavf
            << " session_options_restored_before=" << restored_before.all()
            << " session_options_restored_after=" << restored_after.all()
            << " timed_out=" << timed_out << '\n';
  if (mode == "access-references" || mode == "autoload-files") return initialized ? 1 : 0;
  return initialized && !timed_out ? 0 : 1;
}
