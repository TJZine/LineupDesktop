#include "native_player.h"

#include <algorithm>
#include <atomic>
#include <cstring>
#include <cstdlib>
#include <iostream>

namespace {
bool reject_stop = false;

struct LoadOutcome {
  std::string uri;
  int command_status;
  std::optional<int64_t> playlist_id;
  int command_calls = 0;
  int playlist_queries = 0;
};
std::optional<LoadOutcome> controlled_load;

void RequireLoadFixture(bool condition) {
  if (!condition) {
    std::cerr << "load DLL fixture received an unexpected operation" << '\n';
    std::abort();
  }
}
int TestGetProperty(mpv_handle* client, const char* name, mpv_format format, void* data) {
  if (controlled_load && std::strcmp(name, "playlist/0/id") == 0) {
    RequireLoadFixture(controlled_load->command_calls == 1 && format == MPV_FORMAT_INT64);
    ++controlled_load->playlist_queries;
    if (!controlled_load->playlist_id) return MPV_ERROR_PROPERTY_UNAVAILABLE;
    *static_cast<int64_t*>(data) = *controlled_load->playlist_id;
    return 0;
  }
  return mpv_get_property(client, name, format, data);
}
std::atomic<int> destroyed_clients{0};
int64_t selected_track = -1;
int track_status = 0;
int TestSetProperty(mpv_handle* client, const char* name, mpv_format format, void* data) {
  const int status = mpv_set_property(client, name, format, data);
  if (std::strcmp(name, "aid") == 0 && format == MPV_FORMAT_INT64) {
    selected_track = *static_cast<int64_t*>(data);
    track_status = status;
  }
  return status;
}
int TestCommand(mpv_handle* client, const char** args) {
  if (controlled_load && std::strcmp(args[0], "loadfile") == 0) {
    RequireLoadFixture(args[1] && args[2] && !args[3] &&
                       controlled_load->uri == args[1] && std::strcmp(args[2], "replace") == 0);
    ++controlled_load->command_calls;
    return controlled_load->command_status;
  }
  if (reject_stop && std::strcmp(args[0], "stop") == 0) return MPV_ERROR_COMMAND;
  return mpv_command(client, args);
}
void TestDestroy(mpv_handle* client) {
  mpv_terminate_destroy(client);
  ++destroyed_clients;
}
}


#include "native_player_test_support.h"

namespace {
WindowsNativePlayer::MpvOperations TestOperations() {
  auto operations = lineup::player::LibmpvOperations();
  operations.get_property = TestGetProperty;
  operations.set_property = TestSetProperty;
  operations.command = TestCommand;
  operations.terminate_destroy = TestDestroy;
  return operations;
}

using native_test::Check;
using native_test::Has;
using native_test::Map;
using native_test::Reply;
using native_test::Value;

struct WindowHarness {
  HWND window = nullptr;
  WindowsNativePlayer* player = nullptr;
  static LRESULT CALLBACK Proc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
    if (message == WM_NCCREATE) {
      const auto* create = reinterpret_cast<CREATESTRUCT*>(lparam);
      ::SetWindowLongPtr(hwnd, GWLP_USERDATA,
                         reinterpret_cast<LONG_PTR>(create->lpCreateParams));
    }
    auto* harness = reinterpret_cast<WindowHarness*>(::GetWindowLongPtr(hwnd, GWLP_USERDATA));
    if (harness && harness->player && harness->player->HandleWindowMessage(message)) return 0;
    return ::DefWindowProc(hwnd, message, wparam, lparam);
  }
  WindowHarness() {
    WNDCLASSW cls{};
    cls.lpfnWndProc = Proc;
    cls.hInstance = ::GetModuleHandle(nullptr);
    cls.lpszClassName = L"LineupNativeContractTest";
    Check(::RegisterClassW(&cls) || ::GetLastError() == ERROR_CLASS_ALREADY_EXISTS,
          "test window class");
    window = ::CreateWindowW(cls.lpszClassName, L"Native contract test", WS_OVERLAPPEDWINDOW,
                             0, 0, 64, 64, nullptr, nullptr, cls.hInstance, this);
    Check(window != nullptr, "real test HWND");
  }
  ~WindowHarness() { ::DestroyWindow(window); }
};

void Start(WindowsNativePlayer& player, int64_t entry) {
  mpv_event_start_file data{};
  data.playlist_entry_id = entry;
  mpv_event event{};
  event.event_id = MPV_EVENT_START_FILE;
  event.data = &data;
  NativePlayerTestAccess::Event(player, event);
}
void End(WindowsNativePlayer& player, int64_t entry, int error = 0) {
  mpv_event_end_file data{};
  data.playlist_entry_id = entry;
  data.reason = error < 0 ? MPV_END_FILE_REASON_ERROR : MPV_END_FILE_REASON_STOP;
  data.error = error;
  mpv_event event{};
  event.event_id = MPV_EVENT_END_FILE;
  event.data = &data;
  NativePlayerTestAccess::Event(player, event);
}
void Property(WindowsNativePlayer& player) {
  double time = 42;
  mpv_event_property data{"time-pos", MPV_FORMAT_DOUBLE, &time};
  mpv_event event{};
  event.event_id = MPV_EVENT_PROPERTY_CHANGE;
  event.data = &data;
  NativePlayerTestAccess::Event(player, event);
}
void ErrorLog(WindowsNativePlayer& player) {
  mpv_event_log_message data{"ffmpeg", "error", "http error: 401", MPV_LOG_LEVEL_ERROR};
  mpv_event event{};
  event.event_id = MPV_EVENT_LOG_MESSAGE;
  event.data = &data;
  NativePlayerTestAccess::Event(player, event);
}

void ParsedLoad(WindowsNativePlayer& player, native_test::Messenger& messenger,
                int64_t load_id, std::optional<int64_t> playlist_id, int command_status = 0) {
  const std::string uri = "https://native-contract.invalid/load-" + std::to_string(load_id);
  controlled_load = LoadOutcome{uri, command_status, playlist_id};
  Reply queued;
  messenger.Call("load", queued, {{Value("uri"), Value(uri)},
                                  {Value("loadId"), Value(load_id)}});
  Check(queued.successes == 1 && queued.errors == 0, "parsed load accepted into command queue");
  NativePlayerTestAccess::DrainCommandsSynchronously(player);
  Check(controlled_load->command_calls == 1, "RunCommand executes parsed load URI");
  Check(controlled_load->playlist_queries == (command_status >= 0 ? 1 : 0),
        "successful load queries playlist identity; failed load does not");
  controlled_load.reset();
}

void CorrelationAndPressure(WindowsNativePlayer& player, native_test::Messenger& messenger) {
  NativePlayerTestAccess::OpenWorkerlessCommandClient(player);
  const auto& state = NativePlayerTestAccess::State(player);
  ParsedLoad(player, messenger, 11, 101);
  Start(player, 101);
  ParsedLoad(player, messenger, 12, 102);
  Property(player);
  ErrorLog(player);
  Check(!state.failure(), "old log cannot mark replacement failed");
  Start(player, 102);
  Property(player);
  End(player, 101, MPV_ERROR_LOADING_FAILED);
  Check(state.active_load() == 12 && state.event_load() == 12,
        "stale actual END_FILE cannot retire new load");
  Property(player);
  NativePlayerTestAccess::Drain(player);
  Check(messenger.events.size() == 6, "actual event projection sequence");
  Check(Has(messenger.events[0], "loadId", Value(int64_t{11})) &&
        Has(messenger.events[0], "state", Value("loading")) &&
        Has(messenger.events[1], "loadId", Value(int64_t{11})) &&
        Has(messenger.events[2], "loadId", Value(int64_t{12})) &&
        Has(messenger.events[2], "state", Value("loading")) &&
        Has(messenger.events[3], "loadId", Value(int64_t{12})) &&
        Has(messenger.events[4], "loadId", Value(int64_t{11})) &&
        Has(messenger.events[4], "state", Value("error")) &&
        Has(messenger.events[5], "loadId", Value(int64_t{12})),
        "state/property/error retain observed identity");
  messenger.events.clear();
  ParsedLoad(player, messenger, 13, 103);
  Start(player, 103);
  Start(player, 102);
  Property(player);
  ErrorLog(player);
  Check(state.active_load() == 13 && state.event_load() == 12 && !state.failure(),
        "late old START_FILE does not change accepted replacement or failure attribution");
  NativePlayerTestAccess::Drain(player);
  Check(messenger.events.size() == 3 &&
        Has(messenger.events[0], "loadId", Value(int64_t{13})) &&
        Has(messenger.events[1], "loadId", Value(int64_t{12})) &&
        Has(messenger.events[2], "loadId", Value(int64_t{12})),
        "late old START/property retain old identity for Dart rejection");
  NativePlayerTestAccess::CloseWorkerlessCommandClient(player);
  NativePlayerTestAccess::OpenWorkerlessCommandClient(player);
  messenger.events.clear();
  ParsedLoad(player, messenger, 21, std::nullopt);
  ParsedLoad(player, messenger, 22, std::nullopt);
  Start(player, 201);
  mpv_event_end_file redirect{};
  redirect.playlist_entry_id = 201;
  redirect.reason = MPV_END_FILE_REASON_REDIRECT;
  redirect.playlist_insert_id = 301;
  redirect.playlist_insert_num_entries = 2;
  mpv_event redirect_event{};
  redirect_event.event_id = MPV_EVENT_END_FILE;
  redirect_event.data = &redirect;
  NativePlayerTestAccess::Event(player, redirect_event);
  Start(player, 302);
  Property(player);
  Start(player, 202);
  Property(player);
  NativePlayerTestAccess::Drain(player);
  Check(messenger.events.size() == 5 &&
        Has(messenger.events[0], "loadId", Value(int64_t{21})) &&
        Has(messenger.events[1], "loadId", Value(int64_t{21})) &&
        Has(messenger.events[2], "loadId", Value(int64_t{21})) &&
        Has(messenger.events[3], "loadId", Value(int64_t{22})) &&
        Has(messenger.events[4], "loadId", Value(int64_t{22})),
        "actual redirect and pending FIFO property projection");
  messenger.events.clear();
  redirect.playlist_entry_id = 202;
  redirect.playlist_insert_id = std::numeric_limits<int64_t>::max();
  redirect.playlist_insert_num_entries = 2;
  NativePlayerTestAccess::Event(player, redirect_event);
  NativePlayerTestAccess::Drain(player);
  Check(messenger.events.size() == 1 &&
        Has(messenger.events[0], "failureCode", Value("correlation_error")) &&
        Has(messenger.events[0], "loadId", Value(int64_t{22})),
        "actual redirect overflow produces correlated failure");
  NativePlayerTestAccess::CloseWorkerlessCommandClient(player);
  NativePlayerTestAccess::OpenWorkerlessCommandClient(player);
  messenger.events.clear();
  ParsedLoad(player, messenger, 41, 401);
  Start(player, 401);
  NativePlayerTestAccess::Drain(player);
  messenger.events.clear();
  ParsedLoad(player, messenger, 42, 402, MPV_ERROR_LOADING_FAILED);
  NativePlayerTestAccess::Drain(player);
  Check(messenger.events.size() == 1 &&
        Has(messenger.events[0], "loadId", Value(int64_t{42})) &&
        Has(messenger.events[0], "failureCode", Value("command_error")) &&
        state.active_load() == 41 && state.event_load() == 41,
        "failed parsed replacement reports requested load without accepting or retiring it");
  messenger.events.clear();
  Property(player);
  ErrorLog(player);
  End(player, 401, MPV_ERROR_LOADING_FAILED);
  NativePlayerTestAccess::Drain(player);
  Check(messenger.events.size() == 2 &&
        Has(messenger.events[0], "loadId", Value(int64_t{41})) &&
        Has(messenger.events[1], "loadId", Value(int64_t{41})) &&
        Has(messenger.events[1], "failureCode", Value("http_error")) &&
        Has(messenger.events[1], "httpStatus", Value(int64_t{401})),
        "failed replacement preserves observed predecessor property and detailed END failure");
  NativePlayerTestAccess::CloseWorkerlessCommandClient(player);
  messenger.events.clear();
  const auto generation = NativePlayerTestAccess::Generation(player);
  NativePlayerTestAccess::Queue(player, generation + 1, {{Value("type"), Value("state")}});
  NativePlayerTestAccess::Queue(player, generation, {{Value("type"), Value("trackResult")}});
  NativePlayerTestAccess::Drain(player);
  Check(messenger.events.size() == 1 && Has(messenger.events[0], "type", Value("trackResult")),
        "drain discards obsolete generation");
  messenger.events.clear();
  for (int i = 0; i < 256; ++i) {
    NativePlayerTestAccess::Queue(player, generation, {{Value("type"), Value("property")}});
  }
  NativePlayerTestAccess::Queue(player, generation, {{Value("type"), Value("stopResult")}});
  for (int i = 0; i < 300; ++i) {
    NativePlayerTestAccess::Queue(player, generation, {{Value("type"), Value("property")}});
  }
  NativePlayerTestAccess::Drain(player);
  Check(messenger.events.size() == 256, "property pressure stays bounded");
  Check(std::count_if(messenger.events.begin(), messenger.events.end(), [](const Map& event) {
    return Has(event, "type", Value("stopResult"));
  }) == 1, "property pressure preserves critical acknowledgment");
  messenger.events.clear();
  NativePlayerTestAccess::Queue(player, generation, {{Value("type"), Value("trackResult")}});
  for (int i = 0; i < 255; ++i) {
    NativePlayerTestAccess::Queue(player, generation, {{Value("type"), Value("state")}});
  }
  NativePlayerTestAccess::Queue(player, generation, {{Value("type"), Value("property")}});
  NativePlayerTestAccess::Drain(player);
  Check(messenger.events.size() == 256 && Has(messenger.events[0], "type", Value("trackResult")),
        "incoming property cannot evict non-property acknowledgment");
  messenger.events.clear();
  NativePlayerTestAccess::Queue(player, generation, {{Value("type"), Value("trackResult")}});
  for (int i = 0; i < 256; ++i) {
    NativePlayerTestAccess::Queue(player, generation, {{Value("type"), Value("state")}});
  }
  NativePlayerTestAccess::Drain(player);
  Check(messenger.events.size() == 256 &&
        std::none_of(messenger.events.begin(), messenger.events.end(), [](const Map& event) {
          return Has(event, "type", Value("trackResult"));
        }), "non-property saturation evicts oldest ack; caller timeout/retry is required");
  messenger.events.clear();
}

void Commands(WindowsNativePlayer& player, native_test::Messenger& messenger) {
  NativePlayerTestAccess::OpenWorkerlessCommandClient(player);
  Reply queued;
  for (int i = 0; i < 64; ++i) messenger.Call("pause", queued);
  Check(queued.successes == 64, "command count capacity");
  Reply full;
  messenger.Call("play", full);
  Check(full.errors == 1, "command count bound rejects overflow");
  NativePlayerTestAccess::DrainCommandsSynchronously(player);
  Reply bytes;
  const Map load{{Value("uri"), Value(std::string(32768, 'x'))},
                 {Value("loadId"), Value(int64_t{3})}};
  for (int i = 0; i < 4; ++i) messenger.Call("load", bytes, load);
  Reply byte_full;
  messenger.Call("load", byte_full, load);
  Check(bytes.successes == 4 && byte_full.errors == 1, "command byte bound");
  NativePlayerTestAccess::CloseWorkerlessCommandClient(player);
  NativePlayerTestAccess::OpenWorkerlessCommandClient(player);
  NativePlayerTestAccess::State(player).AcceptLoad(11, 101);
  const Map track{{Value("type"), Value("audio")}, {Value("loadId"), Value(int64_t{11})},
                  {Value("requestId"), Value(int64_t{701})}};
  Reply accepted;
  messenger.Call("selectTrack", accepted, track);
  Check(accepted.successes == 1, "track command queue acceptance");
  NativePlayerTestAccess::DrainCommandsSynchronously(player);
  NativePlayerTestAccess::Drain(player);
  Check(messenger.events.size() == 1 && Has(messenger.events[0], "success", Value(true)) &&
        Has(messenger.events[0], "loadId", Value(int64_t{11})) &&
        Has(messenger.events[0], "requestId", Value(int64_t{701})),
        "real track command result uses load and request ids, not selection id");
  messenger.events.clear();
  Map numbered_track = track;
  numbered_track[Value("id")] = Value(int64_t{7});
  numbered_track[Value("requestId")] = Value(int64_t{702});
  Reply numbered;
  messenger.Call("selectTrack", numbered, numbered_track);
  NativePlayerTestAccess::DrainCommandsSynchronously(player);
  NativePlayerTestAccess::Drain(player);
  Check(numbered.successes == 1 && selected_track == 7 && messenger.events.size() == 1 &&
        Has(messenger.events[0], "loadId", Value(int64_t{11})) &&
        Has(messenger.events[0], "requestId", Value(int64_t{702})) &&
        Has(messenger.events[0], "success", Value(track_status >= 0)),
        "selection id sent to DLL remains separate from result load/request ids");
  messenger.events.clear();
  Reply invalid;
  numbered_track[Value("requestId")] = Value(int64_t{0});
  messenger.Call("selectTrack", invalid, numbered_track);
  Check(invalid.errors == 1, "invalid request id cannot construct queued track payload");
  Reply late;
  messenger.Call("selectTrack", late, track);
  NativePlayerTestAccess::State(player).RetireLoad(11);
  NativePlayerTestAccess::DrainCommandsSynchronously(player);
  NativePlayerTestAccess::Drain(player);
  Check(messenger.events.size() == 1 && Has(messenger.events[0], "success", Value(false)) &&
        Has(messenger.events[0], "requestId", Value(int64_t{701})),
        "queued track across retirement fails with original correlation");
  messenger.events.clear();
  reject_stop = true;
  Reply stop;
  messenger.Call("stop", stop, {{Value("stopId"), Value(int64_t{801})}});
  Check(stop.successes == 1, "stop acceptance separate from execution");
  NativePlayerTestAccess::DrainCommandsSynchronously(player);
  NativePlayerTestAccess::Drain(player);
  Check(messenger.events.size() == 1 && Has(messenger.events[0], "stopId", Value(int64_t{801})) &&
        Has(messenger.events[0], "success", Value(false)), "real stop rejection belongs to stop id");
  messenger.events.clear();
  reject_stop = false;
  Reply retry;
  messenger.Call("stop", retry, {{Value("stopId"), Value(int64_t{802})}});
  NativePlayerTestAccess::DrainCommandsSynchronously(player);
  NativePlayerTestAccess::Drain(player);
  Check(messenger.events.empty() && NativePlayerTestAccess::State(player).pending_stop() == 802,
        "successful stop dispatch awaits idle observation");
  NativePlayerTestAccess::CloseWorkerlessCommandClient(player);
}

void Lifecycle(WindowHarness& window, WindowsNativePlayer& player,
               native_test::Messenger& messenger) {
  ::SetEnvironmentVariableW(L"LINEUP_FLUTTER_DCOMP_ACTIVE",
                            L"deb287481e3ce9468f3434937ced4240a70539ca");
  Reply init;
  messenger.Call("initialize", init);
  Check(init.successes == 1, "real production mpv initialization");
  const auto observed_fullscreen = [&](bool value) {
    return std::any_of(messenger.events.begin(), messenger.events.end(), [&](const Map& event) {
      return Has(event, "type", Value("fullscreen")) &&
             Has(event, "fullscreen", Value(value)) && event.size() == 2;
    });
  };
  native_test::PumpUntil([&]() { return observed_fullscreen(false); },
                        "initial fullscreen snapshot is player-scoped and typed");
  for (const bool fullscreen : {true, false}) {
    messenger.events.clear();
    Reply changed;
    messenger.Call("setFullscreen", changed, {{Value("fullscreen"), Value(fullscreen)}});
    Check(changed.successes == 1 && changed.errors == 0,
          "actual adapter fullscreen transition succeeds");
    native_test::PumpUntil([&]() { return observed_fullscreen(fullscreen); },
                          "completed fullscreen uses production platform-event codec");
  }
  messenger.events.clear();
  Reply invalid_fullscreen;
  messenger.Call("setFullscreen", invalid_fullscreen, {{Value("fullscreen"), Value(1)}});
  Check(invalid_fullscreen.errors == 1, "fullscreen bool validation retained");
  NativePlayerTestAccess::Drain(player);
  Check(!observed_fullscreen(true) && !observed_fullscreen(false),
        "invalid fullscreen command cannot invent an observation");
  Reply stop;
  messenger.Call("stop", stop, {{Value("stopId"), Value(int64_t{901})}});
  Check(stop.successes == 1, "worker stop acceptance");
  native_test::PumpUntil([&]() {
    return std::any_of(messenger.events.begin(), messenger.events.end(), [](const Map& event) {
      return Has(event, "stopId", Value(int64_t{901})) && Has(event, "success", Value(true));
    });
  }, "worker observes actual mpv idle before stop result");
  const int before = destroyed_clients.load();
  Reply disposed;
  disposed.on_success = [&]() {
    Check(destroyed_clients.load() == before + 1, "DLL teardown precedes result");
    Check(NativePlayerTestAccess::Disposed(player), "join and FinishDispose precede result");
    Check(::IsWindow(window.window) && static_cast<bool>(messenger.handler),
          "HWND and messenger remain live during result");
  };
  messenger.Call("dispose", disposed);
  Check(disposed.successes == 0, "normal dispose is asynchronous");
  Reply during;
  messenger.Call("initialize", during);
  Check(during.errors == 1, "reinitialize before join is rejected");
  Reply duplicate;
  messenger.Call("dispose", duplicate);
  Check(duplicate.errors == 1, "concurrent dispose is rejected");
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(10);
  while (!NativePlayerTestAccess::WorkerFinished(player) && std::chrono::steady_clock::now() < deadline) {
    ::Sleep(1);
  }
  Check(NativePlayerTestAccess::WorkerFinished(player), "real worker terminates");
  Check(disposed.successes == 0, "worker cannot reply before platform pumping");
  native_test::PumpUntil([&]() { return disposed.successes == 1; }, "platform dispose completion");
  Check(disposed.errors == 0, "dispose successful once");
  Reply recreate;
  messenger.Call("initialize", recreate);
  Check(recreate.successes == 1, "same owner reinitializes after normal dispose");
  Check(!player.BeginWindowClose() && !player.TakeWindowCloseReady(),
        "close readiness waits for real worker and platform completion");
  native_test::PumpUntil([&]() { return NativePlayerTestAccess::Disposed(player); }, "window close shutdown");
  Check(player.TakeWindowCloseReady() && !player.TakeWindowCloseReady(), "close readiness consumed once");
  Check(player.BeginWindowClose(), "disposed owner permits immediate close");
}
}

int main() {
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  {
    WindowHarness window;
    native_test::Messenger messenger;
    WindowsNativePlayer player(window.window, window.window, &messenger,
                               TestOperations());
    window.player = &player;
    CorrelationAndPressure(player, messenger);
    Commands(player, messenger);
    Lifecycle(window, player, messenger);
    window.player = nullptr;
  }
  ::CoUninitialize();
  return 0;
}
