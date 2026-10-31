// Portable contract test for PlayerCore. Every libmpv entry point is a test
// fake, so this target needs mpv headers but not libmpv itself.

#include "player_core/platform_arguments.h"
#include "player_core/player_core.h"
#include "player_core/player_core_test_access.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstddef>
#include <cstdlib>
#include <cstring>
#include <new>
#include <deque>
#include <functional>
#include <iostream>
#include <limits>
#include <mutex>
#include <optional>
#include <string>
#include <sstream>
#include <thread>
#include <vector>

// Observes the authenticated header buffer at deallocation without reading
// freed memory: the replaced array delete inspects the watched buffer just
// before releasing it. PlexHeader allocates with new char[].
namespace {
std::atomic<const char*> watched_header{nullptr};
std::atomic<size_t> watched_size{0};
std::atomic<bool> watched_freed{false};
std::atomic<bool> watched_wiped{false};
std::atomic<bool> header_live_at_wait{false};

void WatchHeader(const char* header) {
  watched_size = std::strlen(header);
  watched_freed = false;
  watched_wiped = false;
  header_live_at_wait = false;
  watched_header = header;
}

void ResetHeaderWatch() {
  watched_header = nullptr;
  watched_freed = false;
  watched_wiped = false;
  header_live_at_wait = false;
}

void ObserveArrayDelete(void* pointer) noexcept {
  const char* expected = static_cast<const char*>(pointer);
  if (!pointer || !watched_header.compare_exchange_strong(expected, nullptr)) {
    return;
  }
  const auto* bytes = static_cast<const char*>(pointer);
  watched_wiped = std::all_of(bytes, bytes + watched_size.load(),
                              [](char byte) { return byte == 0; });
  watched_freed = true;
}
}  // namespace

void* operator new[](std::size_t size) {
  if (void* pointer = std::malloc(size == 0 ? 1 : size)) return pointer;
  std::abort();
}
void operator delete[](void* pointer) noexcept {
  ObserveArrayDelete(pointer);
  std::free(pointer);
}
void operator delete[](void* pointer, std::size_t) noexcept {
  ObserveArrayDelete(pointer);
  std::free(pointer);
}

namespace lineup::player {
struct SubtitleCoreTestAccess {
  static void Run(PlayerCore& core) { core.RunPendingCommands(core.generation_.load()); }
  static bool EmptySlot(PlayerCore& core) { return !core.pending_subtitle_presentation_; }
  static void Dispose(PlayerCore& core) { core.FinishDispose(); }
};
}  // namespace lineup::player

namespace {

using lineup::player::CallError;
using lineup::player::CallResult;
using lineup::player::CoreHost;
using lineup::player::MpvOperations;
using lineup::player::OutputConfig;
using lineup::player::PlayerCore;
using lineup::player::PlayerCoreTestAccess;
using lineup::player::Value;
using lineup::player::ValueMap;
using lineup::player::ValueList;

void Check(bool condition, const char* obligation) {
  if (!condition) {
    std::cerr << obligation << '\n';
    std::exit(1);
  }
}

bool Has(const ValueMap& map, const char* key, const Value& expected) {
  const auto* value = lineup::player::Find(map, key);
  return value && *value == expected;
}

struct LoadOutcome {
  std::string uri;
  int command_status;
  std::optional<int64_t> playlist_id;
  int command_calls = 0;
  int playlist_queries = 0;
};

// State behind the fake libmpv functions. Worker-visible fields are atomic or
// guarded by `mutex`.
struct FakeMpv {
  std::mutex mutex;
  std::vector<std::string> options;
  std::vector<std::string> observations;
  std::vector<std::string> commands;
  std::vector<std::pair<std::string, double>> subtitle_properties;
  std::vector<std::string> execution_order;
  std::string rejected_subtitle_property;
  std::vector<std::string> seek_flags;
  std::vector<std::string> seek_targets;
  std::atomic<double> seek_position{0};
  std::atomic<bool> seeking{false};
  std::atomic<bool> paused{false};
  std::atomic<bool> reject_volume{false};
  std::string log_level;
  std::string authenticated_header;
  std::string authenticated_redirects;
  std::string authenticated_uri;
  std::map<std::string, std::string> load_options;
  int node_load_status = 0;
  std::string rejected_option;
  int rejected_option_status = MPV_ERROR_OPTION_NOT_FOUND;
  std::string rejected_observation;
  std::optional<LoadOutcome> controlled_load;
  std::optional<int64_t> playlist_id;
  bool reject_stop = false;
  bool fail_create = false;
  int64_t selected_track = -1;
  int track_status = 0;
  std::atomic<int> created{0};
  std::atomic<int> destroyed{0};
  std::atomic<bool> idle{true};
  std::deque<mpv_event> injected;
  mpv_event current{};
};

FakeMpv* fake = nullptr;
int fake_client_storage = 0;

mpv_handle* FakeClient() {
  return reinterpret_cast<mpv_handle*>(&fake_client_storage);
}

void RequireLoadFixture(bool condition) {
  if (!condition) {
    std::cerr << "load fixture received an unexpected operation" << '\n';
    std::abort();
  }
}

mpv_handle* FakeCreate() {
  if (fake->fail_create) return nullptr;
  ++fake->created;
  return FakeClient();
}

int FakeInitialize(mpv_handle*) { return 0; }

int FakeSetOption(mpv_handle*, const char* name, mpv_format format, void* data) {
  std::lock_guard lock(fake->mutex);
  if (format == MPV_FORMAT_INT64) {
    fake->options.push_back(std::string(name) + "=" +
                            std::to_string(*static_cast<int64_t*>(data)));
  }
  return 0;
}

int FakeSetOptionString(mpv_handle*, const char* name, const char* value) {
  std::lock_guard lock(fake->mutex);
  fake->options.push_back(std::string(name) + "=" + value);
  return fake->rejected_option == name ? fake->rejected_option_status : 0;
}

int FakeRequestLogMessages(mpv_handle*, const char* level) {
  std::lock_guard lock(fake->mutex);
  fake->log_level = level;
  return 0;
}

int FakeObserveProperty(mpv_handle*, uint64_t, const char* name, mpv_format) {
  std::lock_guard lock(fake->mutex);
  fake->observations.push_back(name);
  return fake->rejected_observation == name ? MPV_ERROR_PROPERTY_NOT_FOUND : 0;
}

int FakeGetProperty(mpv_handle*, const char* name, mpv_format format, void* data) {
  if (std::strcmp(name, "playlist/0/id") == 0) {
    if (fake->controlled_load) {
      RequireLoadFixture(fake->controlled_load->command_calls == 1 &&
                         format == MPV_FORMAT_INT64);
      ++fake->controlled_load->playlist_queries;
      if (!fake->controlled_load->playlist_id) return MPV_ERROR_PROPERTY_UNAVAILABLE;
      *static_cast<int64_t*>(data) = *fake->controlled_load->playlist_id;
      return 0;
    }
    std::lock_guard lock(fake->mutex);
    if (!fake->playlist_id) return MPV_ERROR_PROPERTY_UNAVAILABLE;
    *static_cast<int64_t*>(data) = *fake->playlist_id;
    return 0;
  }
  if (std::strcmp(name, "pause") == 0 && format == MPV_FORMAT_FLAG) {
    *static_cast<int*>(data) = fake->paused ? 1 : 0;
    return 0;
  }
  if (std::strcmp(name, "time-pos") == 0 && format == MPV_FORMAT_DOUBLE) {
    *static_cast<double*>(data) = fake->seek_position;
    return 0;
  }
  if (std::strcmp(name, "seeking") == 0 && format == MPV_FORMAT_FLAG) {
    *static_cast<int*>(data) = fake->seeking ? 1 : 0;
    return 0;
  }
  if (std::strcmp(name, "idle-active") == 0 && format == MPV_FORMAT_FLAG) {
    *static_cast<int*>(data) = fake->idle ? 1 : 0;
    return 0;
  }
  if (std::strcmp(name, "playlist-count") == 0 && format == MPV_FORMAT_INT64) {
    *static_cast<int64_t*>(data) = fake->idle ? 0 : 1;
    return 0;
  }
  return MPV_ERROR_PROPERTY_UNAVAILABLE;
}

int FakeSetProperty(mpv_handle*, const char* name, mpv_format format, void* data) {
  if (std::string_view(name).substr(0, 4) == "sub-") {
    std::lock_guard lock(fake->mutex);
    const double value = format == MPV_FORMAT_FLAG ? *static_cast<int*>(data) : *static_cast<double*>(data);
    fake->subtitle_properties.emplace_back(name, value);
    fake->execution_order.push_back(name);
    return fake->rejected_subtitle_property == name ? MPV_ERROR_PROPERTY_ERROR : 0;
  }
  if (std::strcmp(name, "pause") == 0 && format == MPV_FORMAT_FLAG) {
    fake->paused = *static_cast<int*>(data) != 0;
    return 0;
  }
  if (std::strcmp(name, "volume") == 0 && format == MPV_FORMAT_DOUBLE &&
      fake->reject_volume) return MPV_ERROR_COMMAND;
  if (std::strcmp(name, "aid") == 0 && format == MPV_FORMAT_INT64) {
    fake->selected_track = *static_cast<int64_t*>(data);
    return fake->track_status;
  }
  return 0;
}

int FakeSetPropertyString(mpv_handle*, const char*, const char*) { return 0; }

int FakeCommand(mpv_handle*, const char** args) {
  if (fake->controlled_load && std::strcmp(args[0], "loadfile") == 0) {
    RequireLoadFixture(args[1] && args[2] && !args[3] &&
                       fake->controlled_load->uri == args[1] &&
                       std::strcmp(args[2], "replace") == 0);
    ++fake->controlled_load->command_calls;
    return fake->controlled_load->command_status;
  }
  std::lock_guard lock(fake->mutex);
  fake->commands.push_back(args[0]);
  fake->execution_order.push_back(args[0]);
  if (std::strcmp(args[0], "seek") == 0) {
    fake->seek_flags.push_back(args[2]);
    fake->seek_targets.push_back(args[1]);
  }
  if (std::strcmp(args[0], "stop") == 0 && fake->reject_stop) {
    return MPV_ERROR_COMMAND;
  }
  return 0;
}

int FakeCommandNode(mpv_handle*, mpv_node* node, mpv_node* result) {
  std::lock_guard lock(fake->mutex);
  fake->commands.push_back("loadfile-node");
  const bool shape =
      result == nullptr && node->format == MPV_FORMAT_NODE_ARRAY &&
      node->u.list->num == 5 &&
      std::strcmp(node->u.list->values[0].u.string, "loadfile") == 0 &&
      std::strcmp(node->u.list->values[2].u.string, "replace") == 0 &&
      node->u.list->values[3].format == MPV_FORMAT_INT64 &&
      node->u.list->values[3].u.int64 == -1 &&
      node->u.list->values[4].format == MPV_FORMAT_NODE_MAP &&
      node->u.list->values[4].u.list->num >= 2;
  if (!shape) return MPV_ERROR_INVALID_PARAMETER;
  const auto& options = *node->u.list->values[4].u.list;
  fake->authenticated_uri = node->u.list->values[1].u.string;
  fake->load_options.clear();
  for (int index = 0; index < options.num; ++index) {
    RequireLoadFixture(options.values[index].format == MPV_FORMAT_STRING);
    fake->load_options[options.keys[index]] = options.values[index].u.string;
    if (std::strcmp(options.keys[index], "http-header-fields") == 0) {
      fake->authenticated_header = options.values[index].u.string;
      WatchHeader(options.values[index].u.string);
    } else if (std::strcmp(options.keys[index], "curl-max-redirects") == 0) {
      fake->authenticated_redirects = options.values[index].u.string;
    }
  }
  return fake->node_load_status;
}

mpv_event* FakeWaitEvent(mpv_handle*, double) {
  // The worker must clear an executed load's header before it waits again.
  if (watched_header.load() && !watched_freed.load()) {
    header_live_at_wait = true;
  }
  std::this_thread::sleep_for(std::chrono::milliseconds(1));
  std::lock_guard lock(fake->mutex);
  fake->current = mpv_event{};
  if (!fake->injected.empty()) {
    fake->current = fake->injected.front();
    fake->injected.pop_front();
  }
  return &fake->current;
}

void FakeTerminateDestroy(mpv_handle*) { ++fake->destroyed; }

const char* FakeErrorString(int) { return "fake mpv error"; }

unsigned long FakeClientApiVersion() { return MPV_CLIENT_API_VERSION; }

MpvOperations FakeOperations() {
  MpvOperations operations;
  operations.create = FakeCreate;
  operations.initialize = FakeInitialize;
  operations.set_option = FakeSetOption;
  operations.set_option_string = FakeSetOptionString;
  operations.request_log_messages = FakeRequestLogMessages;
  operations.observe_property = FakeObserveProperty;
  operations.get_property = FakeGetProperty;
  operations.set_property = FakeSetProperty;
  operations.set_property_string = FakeSetPropertyString;
  operations.command = FakeCommand;
  operations.command_node = FakeCommandNode;
  operations.wait_event = FakeWaitEvent;
  operations.terminate_destroy = FakeTerminateDestroy;
  operations.error_string = FakeErrorString;
  operations.client_api_version = FakeClientApiVersion;
  return operations;
}

class FakeHost final : public CoreHost {
 public:
  bool PostWakeup() override {
    ++wakeups;
    return post_succeeds.load();
  }
  void PostWorkerFinished() override { ++worker_finished_posts; }
  std::optional<CallError> PrepareOutput(OutputConfig& output) override {
    ++prepared;
    if (prepare_error) return prepare_error;
    output.window_id = 4242;
    output.options = {{"vo", "gpu-next"}, {"gpu-api", "d3d11"},
                      {"gpu-context", "d3d11"}};
    return std::nullopt;
  }
  void CancelOutput() override { ++cancelled; }
  void ReleaseOutput() override { ++released; }
  void OnDisposeRequested() override { ++dispose_requests; }

  std::atomic<int> wakeups{0};
  std::atomic<bool> post_succeeds{true};
  std::atomic<int> worker_finished_posts{0};
  std::optional<CallError> prepare_error;
  int prepared = 0;
  int cancelled = 0;
  int released = 0;
  int dispose_requests = 0;
};

struct Reply {
  int successes = 0;
  int errors = 0;
  std::string error;
  Value value;
  std::function<void()> on_success;
};

void Record(Reply& reply, const CallResult& result) {
  if (result.error) {
    ++reply.errors;
    reply.error = result.error->code;
  } else {
    ++reply.successes;
    reply.value = result.value;
    if (reply.on_success) reply.on_success();
  }
}

// Simulates the platform channel: the adapter handles initialize and dispose
// itself and treats an unclaimed command as not implemented.
void Call(PlayerCore& core, const char* method, Reply& reply, ValueMap arguments = {}) {
  if (std::strcmp(method, "initialize") == 0) {
    Record(reply, core.Initialize());
    return;
  }
  if (std::strcmp(method, "dispose") == 0) {
    core.Dispose([&reply](const CallResult& result) { Record(reply, result); });
    return;
  }
  if (const auto result = core.HandleCommand(method, &arguments)) {
    Record(reply, *result);
  } else {
    ++reply.errors;
    reply.error = "not_implemented";
  }
}

struct Events {
  std::vector<ValueMap> received;
  PlayerCore::EventSink Sink() {
    return [this](const ValueMap& event) { received.push_back(event); };
  }
};

void PumpUntil(PlayerCore& core, Events& events, const std::function<bool()>& ready,
               const char* obligation) {
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(10);
  while (!ready() && std::chrono::steady_clock::now() < deadline) {
    core.ProcessWakeup(events.Sink());
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
  Check(ready(), obligation);
}

void Drain(PlayerCore& core, Events& events) {
  PlayerCoreTestAccess::Drain(core, events.Sink());
}

// A load rejected before initialization, during disposal, or after disposal
// keeps the not_initialized result and still wipes the converted token.
bool RejectedLoadWipesToken(PlayerCore& core) {
  ValueMap arguments{{"uri", Value("https://media.invalid/a")},
                     {"loadId", Value(int64_t{1})},
                     {"plexToken", Value("rejected-token")}};
  const auto result = core.HandleCommand("load", &arguments);
  const auto& token = std::get<std::string>(arguments["plexToken"]);
  return result && result->error && result->error->code == "not_initialized" &&
         result->error->message == "The native player is not initialized." &&
         token.size() == 14 &&
         std::all_of(token.begin(), token.end(), [](char byte) { return byte == 0; });
}

void OpenWorkerless(PlayerCore& core) {
  Check(PlayerCoreTestAccess::Workerless(core), "workerless command fixture");
  Check(!PlayerCoreTestAccess::Client(core) && !PlayerCoreTestAccess::AcceptingCommands(core),
        "OpenWorkerless client state");
  PlayerCoreTestAccess::OpenWorkerlessClient(core, FakeCreate());
}

void CloseWorkerless(PlayerCore& core) {
  Check(PlayerCoreTestAccess::Workerless(core), "workerless command fixture");
  Check(PlayerCoreTestAccess::Client(core) != nullptr, "CloseWorkerless client state");
  FakeTerminateDestroy(PlayerCoreTestAccess::CloseWorkerlessClient(core));
}

void Start(PlayerCore& core, int64_t entry) {
  mpv_event_start_file data{};
  data.playlist_entry_id = entry;
  mpv_event event{};
  event.event_id = MPV_EVENT_START_FILE;
  event.data = &data;
  PlayerCoreTestAccess::Event(core, event);
}

void End(PlayerCore& core, int64_t entry, int error = 0) {
  mpv_event_end_file data{};
  data.playlist_entry_id = entry;
  data.reason = error < 0 ? MPV_END_FILE_REASON_ERROR : MPV_END_FILE_REASON_STOP;
  data.error = error;
  mpv_event event{};
  event.event_id = MPV_EVENT_END_FILE;
  event.data = &data;
  PlayerCoreTestAccess::Event(core, event);
}

void Property(PlayerCore& core) {
  double time = 42;
  mpv_event_property data{"time-pos", MPV_FORMAT_DOUBLE, &time};
  mpv_event event{};
  event.event_id = MPV_EVENT_PROPERTY_CHANGE;
  event.data = &data;
  PlayerCoreTestAccess::Event(core, event);
}

void ErrorLog(PlayerCore& core) {
  mpv_event_log_message data{"ffmpeg", "error", "http error: 401", MPV_LOG_LEVEL_ERROR};
  mpv_event event{};
  event.event_id = MPV_EVENT_LOG_MESSAGE;
  event.data = &data;
  PlayerCoreTestAccess::Event(core, event);
}

void AudioOutputProbeError(PlayerCore& core) {
  mpv_event_log_message data{
      "ao/coreaudio", "error",
      "unable to set the input channel layout on the audio unit",
      MPV_LOG_LEVEL_ERROR};
  mpv_event event{};
  event.event_id = MPV_EVENT_LOG_MESSAGE;
  event.data = &data;
  PlayerCoreTestAccess::Event(core, event);
}

void ParsedLoad(PlayerCore& core, int64_t load_id, std::optional<int64_t> playlist_id,
                int command_status = 0) {
  const std::string uri = "https://native-contract.invalid/load-" + std::to_string(load_id);
  fake->controlled_load = LoadOutcome{uri, command_status, playlist_id};
  Reply queued;
  Call(core, "load", queued, {{"uri", Value(uri)}, {"loadId", Value(load_id)}});
  Check(queued.successes == 1 && queued.errors == 0, "parsed load accepted into command queue");
  PlayerCoreTestAccess::RunQueuedCommands(core);
  Check(fake->controlled_load->command_calls == 1, "RunCommand executes parsed load URI");
  Check(fake->controlled_load->playlist_queries == (command_status >= 0 ? 1 : 0),
        "successful load queries playlist identity; failed load does not");
  fake->controlled_load.reset();
}

// Capture the actual core stderr boundary. Only this one explicit developer
// variable is varied; no application state or real media/credentials are used.
class FirstOpenEnvironment {
 public:
  explicit FirstOpenEnvironment(const char* value) {
#ifdef _WIN32
    char* previous = nullptr;
    size_t size = 0;
    if (_dupenv_s(&previous, &size, "LINEUP_FIRST_OPEN_DIAGNOSTICS") == 0 && previous) previous_ = previous;
    std::free(previous);
#else
    if (const auto* previous = std::getenv("LINEUP_FIRST_OPEN_DIAGNOSTICS")) previous_ = previous;
#endif
    Set(value);
  }
  ~FirstOpenEnvironment() { Set(previous_ ? previous_->c_str() : nullptr); }
 private:
  static void Set(const char* value) {
#ifdef _WIN32
    _putenv_s("LINEUP_FIRST_OPEN_DIAGNOSTICS", value ? value : "");
#else
    if (value) setenv("LINEUP_FIRST_OPEN_DIAGNOSTICS", value, 1);
    else unsetenv("LINEUP_FIRST_OPEN_DIAGNOSTICS");
#endif
  }
  std::optional<std::string> previous_;
};

void ProbeMessage(PlayerCore& core, const char* module, const char* text,
                  mpv_log_level level = MPV_LOG_LEVEL_ERROR) {
  mpv_event_log_message data{module, "error", text, level};
  mpv_event event{};
  event.event_id = MPV_EVENT_LOG_MESSAGE;
  event.data = &data;
  PlayerCoreTestAccess::Event(core, event);
}

bool SafeProbeOutput(const std::string& output) {
  const std::vector<std::string> modules = {
      "core", "curl", "ffmpeg", "demux", "stream", "audio_output", "video_output", "unknown"};
  const std::vector<std::string> causes = {
      "accepted", "opening", "ready", "end_error", "end_error_unknown", "end_stopped",
      "end_eof", "end_other", "playlist_redirect", "stop_accepted", "dns", "connect",
      "tls", "redirect_limit", "range", "container", "http", "timeout", "unknown"};
  std::istringstream lines(output);
  std::string line;
  while (std::getline(lines, line)) {
    std::istringstream fields(line);
    std::string tag, module, cause;
    if (!(fields >> tag >> module >> cause) || tag != "[lineup-first-open]" ||
        module.rfind("module=", 0) != 0 || cause.rfind("cause=", 0) != 0 ||
        std::find(modules.begin(), modules.end(), module.substr(7)) == modules.end() ||
        std::find(causes.begin(), causes.end(), cause.substr(6)) == causes.end()) return false;
    bool saw_error = false, saw_http = false;
    std::string field;
    while (fields >> field) {
      const auto equal = field.find('=');
      if (equal == std::string::npos) return false;
      std::istringstream number(field.substr(equal + 1));
      int64_t value = 0;
      char extra = 0;
      if (!(number >> value) || (number >> extra)) return false;
      const auto key = field.substr(0, equal);
      if (key == "mpv_error" && !saw_error && !saw_http && value >= -128 && value <= 0) saw_error = true;
      else if (key == "http_status" && !saw_http && value >= 100 && value <= 599) saw_http = true;
      else return false;
    }
  }
  return true;
}

void FirstOpenProbeContract() {
  FakeMpv local;
  auto* previous = fake;
  fake = &local;
  const auto exercise = [&](const char* enabled) {
    FirstOpenEnvironment environment(enabled);
    FakeHost host;
    PlayerCore core(FakeOperations(), host);
    OpenWorkerless(core);
    std::ostringstream log;
    auto* original = std::cerr.rdbuf(log.rdbuf());
    ParsedLoad(core, 7001, 8001);
    Start(core, 8001);
    ProbeMessage(core, "stream/curl", "Could not resolve host: https://private.invalid/secret X-Plex-Token: SENTINEL");
    End(core, 8001, MPV_ERROR_LOADING_FAILED);
    Reply stop;
    Call(core, "stop", stop, {{"stopId", Value(int64_t{1})}});
    PlayerCoreTestAccess::RunQueuedCommands(core);
    Events events;
    Drain(core, events);
    std::cerr.rdbuf(original);
    CloseWorkerless(core);
    return std::make_pair(log.str(), events.received);
  };
  const auto off = exercise(nullptr);
  const auto invalid = exercise("1-SENTINEL");
  const auto on = exercise("1");
  Check(off.first.empty() && invalid.first.empty(), "first-open probe is silent unless exact opt-in is enabled");
  Check(on.first.find("module=curl cause=dns") != std::string::npos &&
        on.first.find("cause=end_error mpv_error=-13") != std::string::npos &&
        on.first.find("cause=stop_accepted") != std::string::npos &&
        on.first.find("cause=stop_accepted") > on.first.find("cause=end_error"),
        "first-open preserves original native failure before later stop");
  Check(SafeProbeOutput(on.first), "probe output contains only contract enums and bounded integers");
  Check(off.second == on.second && off.second == invalid.second,
        "probe does not alter playback events/status/correlation");
  Check(on.first.find("private") == std::string::npos && on.first.find("SENTINEL") == std::string::npos &&
        on.first.find("X-Plex") == std::string::npos, "probe never forwards synthetic private log text");
  {
    FirstOpenEnvironment environment("1");
    FakeHost host;
    PlayerCore core(FakeOperations(), host);
    OpenWorkerless(core);
    std::ostringstream log;
    auto* original = std::cerr.rdbuf(log.rdbuf());
    const auto check = [&](bool condition, const char* obligation) {
      if (!condition) std::cerr.rdbuf(original);
      Check(condition, obligation);
    };
    struct Case { const char* module; const char* text; const char* expected; };
    const Case cases[] = {
      {"stream/curl", "Failed to connect to host", "module=curl cause=connect"},
      {"curl", "TLS certificate verification failed", "module=curl cause=tls"},
      {"stream/curl", "Number of redirects hit maximum amount", "module=curl cause=redirect_limit"},
      {"stream/curl", "Server sent back unexpected reply with offset", "module=curl cause=range"},
      {"ffmpeg/demuxer", "Invalid data found", "module=ffmpeg cause=container"},
      {"stream/curl", "HTTP error: 403", "module=curl cause=http http_status=403"},
      {"curl https://private.invalid/SENTINEL", "Unknown /private/SENTINEL X-Plex-Token: SENTINEL", "module=unknown cause=unknown"},
      {"unknown", "HTTP error: 4030 SENTINEL", "module=unknown cause=unknown"},
      {nullptr, nullptr, "module=unknown cause=unknown"},
    };
    int64_t id = 9000;
    for (const auto& item : cases) {
      log.str(""); log.clear();
      ++id;
      ParsedLoad(core, id, id + 1000);
      Start(core, id + 1000);
      ProbeMessage(core, item.module, item.text);
      check(SafeProbeOutput(log.str()), "every category record obeys the strict privacy grammar");
      check(log.str().find(item.expected) != std::string::npos, "known probe categories use finite allowlisted values");
      check(log.str().find("SENTINEL") == std::string::npos && log.str().find("private") == std::string::npos,
            "unknown/malicious module and text cannot leak");
      if (std::strstr(item.expected, "http_status=403")) {
        End(core, id + 1000, MPV_ERROR_LOADING_FAILED);
        check(log.str().find("mpv_error=-13 http_status=403") != std::string::npos,
              "terminal probe retains safely observed HTTP status and original mpv integer");
      }
    }
    log.str(""); log.clear();
    ParsedLoad(core, 10001, 11001);
    Start(core, 11001);
    for (int i = 0; i < 100; ++i) ProbeMessage(core, "curl", "Could not resolve hostname SENTINEL");
    const auto bounded = log.str();
    check(std::count(bounded.begin(), bounded.end(), '\n') == 6, "probe bounds per-load log spam to four error records plus lifecycle markers");
    End(core, 11001, std::numeric_limits<int>::min());
    End(core, 11001, MPV_ERROR_LOADING_FAILED);
    check(log.str().find("cause=end_error_unknown") != std::string::npos &&
          log.str().find("-2147483648") == std::string::npos,
          "out-of-range END_FILE integers are omitted, not copied or clamped");
    const auto ended = log.str();
    ProbeMessage(core, "curl", "TLS error SENTINEL");
    check(log.str() == ended, "post-terminal logs are suppressed");
    ParsedLoad(core, 10002, 11002);
    const auto accepted = log.str();
    ProbeMessage(core, "curl", "TLS error SENTINEL");
    End(core, 11001, MPV_ERROR_LOADING_FAILED);
    check(log.str() == accepted, "late retired-load error and end do not pollute replacement probe");
    Start(core, 11002);
    ProbeMessage(core, "curl", "TLS error SENTINEL");
    check(log.str().find("module=curl cause=tls") != std::string::npos, "new accepted load resets probe budget");
    mpv_event loaded{}; loaded.event_id = MPV_EVENT_FILE_LOADED;
    PlayerCoreTestAccess::Event(core, loaded);
    const auto ready = log.str();
    ProbeMessage(core, "curl", "Could not resolve host SENTINEL");
    check(log.str() == ready && ready.find("cause=ready") != std::string::npos,
          "first-open probe stops reading error categories after readiness");
    ParsedLoad(core, 10003, 11003);
    Start(core, 11003);
    Reply stop;
    Call(core, "stop", stop, {{"stopId", Value(int64_t{2})}});
    PlayerCoreTestAccess::RunQueuedCommands(core);
    const auto stopped = log.str();
    ProbeMessage(core, "curl", "TLS error SENTINEL");
    check(log.str() == stopped, "accepted cancellation suppresses later opening log records");
    End(core, 11003);
    const auto final = log.str();
    check(final.find("cause=end_stopped mpv_error=0") != std::string::npos && SafeProbeOutput(final),
          "stop-driven end is distinguished from initial native error within the safe grammar");
    log.str(""); log.clear();
    ParsedLoad(core, 20001, 21001);
    Start(core, 21001);
    Start(core, 21001);
    for (int i = 0; i < 10; ++i) ProbeMessage(core, "curl", "Could not resolve hostname SENTINEL");
    mpv_event_end_file redirect{};
    redirect.playlist_entry_id = 21001;
    redirect.reason = MPV_END_FILE_REASON_REDIRECT;
    mpv_event redirect_event{};
    redirect_event.event_id = MPV_EVENT_END_FILE;
    redirect_event.data = &redirect;
    PlayerCoreTestAccess::Event(core, redirect_event);
    PlayerCoreTestAccess::Event(core, redirect_event);
    PlayerCoreTestAccess::Event(core, loaded);
    PlayerCoreTestAccess::Event(core, loaded);
    End(core, 21001, MPV_ERROR_LOADING_FAILED);
    End(core, 21001, MPV_ERROR_LOADING_FAILED);
    Reply cleanup, duplicate_cleanup;
    Call(core, "stop", cleanup, {{"stopId", Value(int64_t{3})}});
    Call(core, "stop", duplicate_cleanup, {{"stopId", Value(int64_t{4})}});
    PlayerCoreTestAccess::RunQueuedCommands(core);
    const auto maximum = log.str();
    check(SafeProbeOutput(maximum) && std::count(maximum.begin(), maximum.end(), '\n') == 10,
          "all repeated lifecycle/log events remain within ten lines per accepted load");
    std::cerr.rdbuf(original);
    CloseWorkerless(core);
  }
  fake = previous;
}

void CorrelationAndPressure(PlayerCore& core) {
  Events events;
  OpenWorkerless(core);
  const auto& state = PlayerCoreTestAccess::State(core);
  ParsedLoad(core, 11, 101);
  Start(core, 101);
  ParsedLoad(core, 12, 102);
  Property(core);
  ErrorLog(core);
  Check(!state.failure(), "old log cannot mark replacement failed");
  Start(core, 102);
  Property(core);
  End(core, 101, MPV_ERROR_LOADING_FAILED);
  Check(state.active_load() == 12 && state.event_load() == 12,
        "stale actual END_FILE cannot retire new load");
  Property(core);
  Drain(core, events);
  auto& received = events.received;
  Check(received.size() == 6, "actual event projection sequence");
  Check(Has(received[0], "loadId", Value(int64_t{11})) &&
        Has(received[0], "state", Value("loading")) &&
        Has(received[1], "loadId", Value(int64_t{11})) &&
        Has(received[2], "loadId", Value(int64_t{12})) &&
        Has(received[2], "state", Value("loading")) &&
        Has(received[3], "loadId", Value(int64_t{12})) &&
        Has(received[4], "loadId", Value(int64_t{11})) &&
        Has(received[4], "state", Value("error")) &&
        Has(received[5], "loadId", Value(int64_t{12})),
        "state/property/error retain observed identity");
  received.clear();
  ParsedLoad(core, 13, 103);
  Start(core, 103);
  Start(core, 102);
  Property(core);
  ErrorLog(core);
  Check(state.active_load() == 13 && state.event_load() == 12 && !state.failure(),
        "late old START_FILE does not change accepted replacement or failure attribution");
  Drain(core, events);
  Check(received.size() == 3 &&
        Has(received[0], "loadId", Value(int64_t{13})) &&
        Has(received[1], "loadId", Value(int64_t{12})) &&
        Has(received[2], "loadId", Value(int64_t{12})),
        "late old START/property retain old identity for Dart rejection");
  CloseWorkerless(core);
  OpenWorkerless(core);
  received.clear();
  ParsedLoad(core, 21, std::nullopt);
  ParsedLoad(core, 22, std::nullopt);
  Start(core, 201);
  mpv_event_end_file redirect{};
  redirect.playlist_entry_id = 201;
  redirect.reason = MPV_END_FILE_REASON_REDIRECT;
  redirect.playlist_insert_id = 301;
  redirect.playlist_insert_num_entries = 2;
  mpv_event redirect_event{};
  redirect_event.event_id = MPV_EVENT_END_FILE;
  redirect_event.data = &redirect;
  PlayerCoreTestAccess::Event(core, redirect_event);
  Start(core, 302);
  Property(core);
  Start(core, 202);
  Property(core);
  Drain(core, events);
  Check(received.size() == 5 &&
        Has(received[0], "loadId", Value(int64_t{21})) &&
        Has(received[1], "loadId", Value(int64_t{21})) &&
        Has(received[2], "loadId", Value(int64_t{21})) &&
        Has(received[3], "loadId", Value(int64_t{22})) &&
        Has(received[4], "loadId", Value(int64_t{22})),
        "actual redirect and pending FIFO property projection");
  received.clear();
  redirect.playlist_entry_id = 202;
  redirect.playlist_insert_id = std::numeric_limits<int64_t>::max();
  redirect.playlist_insert_num_entries = 2;
  PlayerCoreTestAccess::Event(core, redirect_event);
  Drain(core, events);
  Check(received.size() == 1 &&
        Has(received[0], "failureCode", Value("correlation_error")) &&
        Has(received[0], "loadId", Value(int64_t{22})),
        "actual redirect overflow produces correlated failure");
  CloseWorkerless(core);
  OpenWorkerless(core);
  received.clear();
  ParsedLoad(core, 41, 401);
  Start(core, 401);
  Drain(core, events);
  received.clear();
  ParsedLoad(core, 42, 402, MPV_ERROR_LOADING_FAILED);
  Drain(core, events);
  Check(received.size() == 1 &&
        Has(received[0], "loadId", Value(int64_t{42})) &&
        Has(received[0], "failureCode", Value("command_error")) &&
        Has(received[0], "message", Value("fake mpv error")) &&
        state.active_load() == 41 && state.event_load() == 41,
        "failed parsed replacement reports requested load without accepting or retiring it");
  received.clear();
  Property(core);
  ErrorLog(core);
  End(core, 401, MPV_ERROR_LOADING_FAILED);
  Drain(core, events);
  Check(received.size() == 2 &&
        Has(received[0], "loadId", Value(int64_t{41})) &&
        Has(received[1], "loadId", Value(int64_t{41})) &&
        Has(received[1], "failureCode", Value("http_error")) &&
        Has(received[1], "httpStatus", Value(int64_t{401})) &&
        Has(received[1], "message", Value("Media playback failed")),
        "failed replacement preserves observed predecessor property and detailed END failure");
  CloseWorkerless(core);
  received.clear();
  const auto generation = PlayerCoreTestAccess::Generation(core);
  PlayerCoreTestAccess::Queue(core, generation + 1, {{"type", Value("state")}});
  PlayerCoreTestAccess::Queue(core, generation, {{"type", Value("trackResult")}});
  Drain(core, events);
  Check(received.size() == 1 && Has(received[0], "type", Value("trackResult")),
        "drain discards obsolete generation");
  received.clear();
  for (int i = 0; i < 256; ++i) {
    PlayerCoreTestAccess::Queue(core, generation, {{"type", Value("property")}});
  }
  PlayerCoreTestAccess::Queue(core, generation, {{"type", Value("stopResult")}});
  for (int i = 0; i < 300; ++i) {
    PlayerCoreTestAccess::Queue(core, generation, {{"type", Value("property")}});
  }
  Drain(core, events);
  Check(received.size() == 255, "property pressure stays bounded");
  Check(std::count_if(received.begin(), received.end(), [](const ValueMap& event) {
    return Has(event, "type", Value("stopResult"));
  }) == 1, "property pressure preserves critical acknowledgment");
  received.clear();
  PlayerCoreTestAccess::Queue(core, generation, {{"type", Value("trackResult")}});
  for (int i = 0; i < 254; ++i) {
    PlayerCoreTestAccess::Queue(core, generation, {{"type", Value("state")}});
  }
  PlayerCoreTestAccess::Queue(core, generation, {{"type", Value("property")}});
  Drain(core, events);
  Check(received.size() == 255 && Has(received[0], "type", Value("trackResult")),
        "incoming property cannot evict non-property acknowledgment");
  received.clear();
  PlayerCoreTestAccess::Queue(core, generation, {{"type", Value("trackResult")}});
  for (int i = 0; i < 255; ++i) {
    PlayerCoreTestAccess::Queue(core, generation, {{"type", Value("state")}});
  }
  Drain(core, events);
  Check(received.size() == 255 &&
        std::none_of(received.begin(), received.end(), [](const ValueMap& event) {
          return Has(event, "type", Value("trackResult"));
        }), "non-property saturation evicts oldest ack; caller timeout/retry is required");
  received.clear();
  PlayerCoreTestAccess::Queue(core, generation, {{"type", Value("trackResult")}});
  for (int i = 0; i < 254; ++i) {
    PlayerCoreTestAccess::Queue(core, generation,
                                {{"type", Value("property")}, {"value", Value(int64_t{i})}});
  }
  PlayerCoreTestAccess::Queue(core, generation, {{"type", Value("stopResult")}});
  PlayerCoreTestAccess::Queue(core, generation,
                              {{"type", Value("property")}, {"value", Value(int64_t{999})}});
  Drain(core, events);
  Check(received.size() == 255 && Has(received[0], "type", Value("trackResult")) &&
        Has(received[1], "value", Value(int64_t{2})) &&
        Has(received[253], "type", Value("stopResult")) &&
        Has(received[254], "value", Value(int64_t{999})),
        "full queue evicts the oldest property, not an older acknowledgment");
  received.clear();
  PlayerCoreTestAccess::Queue(core, generation, {{"type", Value("display")}});
  PlayerCoreTestAccess::Queue(core, generation, {{"type", Value("state")}});
  core.QueuePlatformEvent({{"type", Value("display")}});
  core.DiscardQueuedEvents("display");
  Drain(core, events);
  Check(received.size() == 1 && Has(received[0], "type", Value("state")),
        "platform event purge removes only its type");
  received.clear();
}

void Commands(PlayerCore& core) {
  Events events;
  auto& received = events.received;
  OpenWorkerless(core);
  Reply queued;
  for (int i = 0; i < 64; ++i) Call(core, "pause", queued);
  Check(queued.successes == 64, "command count capacity");
  Reply full;
  Call(core, "play", full);
  Check(full.errors == 1 && full.error == "command_queue_full", "command count bound rejects overflow");
  PlayerCoreTestAccess::RunQueuedCommands(core);
  Reply bytes;
  const ValueMap load{{"uri", Value(std::string(32768, 'x'))},
                      {"loadId", Value(int64_t{3})}};
  for (int i = 0; i < 4; ++i) Call(core, "load", bytes, load);
  Reply byte_full;
  Call(core, "load", byte_full, load);
  Check(bytes.successes == 4 && byte_full.errors == 1 &&
        byte_full.error == "command_queue_full", "command byte bound");
  CloseWorkerless(core);
  OpenWorkerless(core);
  PlayerCoreTestAccess::State(core).AcceptLoad(11, 101);
  const ValueMap track{{"type", Value("audio")}, {"loadId", Value(int64_t{11})},
                       {"requestId", Value(int64_t{701})}};
  Reply accepted;
  Call(core, "selectTrack", accepted, track);
  Check(accepted.successes == 1, "track command queue acceptance");
  PlayerCoreTestAccess::RunQueuedCommands(core);
  Drain(core, events);
  Check(received.size() == 1 && Has(received[0], "success", Value(true)) &&
        Has(received[0], "loadId", Value(int64_t{11})) &&
        Has(received[0], "requestId", Value(int64_t{701})),
        "track command result uses load and request ids, not selection id");
  received.clear();
  ValueMap numbered_track = track;
  numbered_track["id"] = Value(int64_t{7});
  numbered_track["requestId"] = Value(int64_t{702});
  fake->track_status = MPV_ERROR_PROPERTY_UNAVAILABLE;
  Reply numbered;
  Call(core, "selectTrack", numbered, numbered_track);
  PlayerCoreTestAccess::RunQueuedCommands(core);
  Drain(core, events);
  Check(numbered.successes == 1 && fake->selected_track == 7 && received.size() == 1 &&
        Has(received[0], "loadId", Value(int64_t{11})) &&
        Has(received[0], "requestId", Value(int64_t{702})) &&
        Has(received[0], "success", Value(false)),
        "selection id sent to mpv remains separate from result load/request ids");
  fake->track_status = 0;
  received.clear();
  Reply invalid;
  numbered_track["requestId"] = Value(int64_t{0});
  Call(core, "selectTrack", invalid, numbered_track);
  Check(invalid.errors == 1 && invalid.error == "invalid_argument",
        "invalid request id cannot construct queued track payload");
  Reply late;
  Call(core, "selectTrack", late, track);
  PlayerCoreTestAccess::State(core).RetireLoad(11);
  PlayerCoreTestAccess::RunQueuedCommands(core);
  Drain(core, events);
  Check(received.size() == 1 && Has(received[0], "success", Value(false)) &&
        Has(received[0], "requestId", Value(int64_t{701})),
        "queued track across retirement fails with original correlation");
  received.clear();
  fake->reject_stop = true;
  Reply stop;
  Call(core, "stop", stop, {{"stopId", Value(int64_t{801})}});
  Check(stop.successes == 1, "stop acceptance separate from execution");
  PlayerCoreTestAccess::RunQueuedCommands(core);
  Drain(core, events);
  Check(received.size() == 1 && Has(received[0], "stopId", Value(int64_t{801})) &&
        Has(received[0], "success", Value(false)), "stop rejection belongs to stop id");
  received.clear();
  fake->reject_stop = false;
  Reply retry;
  Call(core, "stop", retry, {{"stopId", Value(int64_t{802})}});
  PlayerCoreTestAccess::RunQueuedCommands(core);
  Drain(core, events);
  Check(received.empty() && PlayerCoreTestAccess::State(core).pending_stop() == 802,
        "successful stop dispatch awaits idle observation");
  CloseWorkerless(core);
}

void SeekPolicyAndObservation(PlayerCore& core) {
  OpenWorkerless(core);
  std::ostringstream log;
  auto* original = std::cerr.rdbuf(log.rdbuf());
  const auto check = [&](bool condition, const char* obligation) {
    if (!condition) std::cerr.rdbuf(original);
    Check(condition, obligation);
  };
  auto begin = [&](int64_t load) {
    fake->playlist_id = load + 1000;
    Reply reply;
    Call(core, "load", reply, {{"uri", Value("file:///seek-test.mkv")},
                                {"loadId", Value(load)}});
    PlayerCoreTestAccess::RunQueuedCommands(core);
    Start(core, load + 1000);
  };
  auto event = [&](mpv_event_id id) {
    mpv_event value{};
    value.event_id = id;
    PlayerCoreTestAccess::Event(core, value);
  };
  auto seek = [&](double target, const char* mode = nullptr) {
    ValueMap arguments{{"seconds", Value(target)}};
    if (mode) arguments["mode"] = Value(mode);
    Reply reply;
    Call(core, "seek", reply, arguments);
    check(reply.successes == 1, "seek mode accepted");
    PlayerCoreTestAccess::RunQueuedCommands(core);
  };
  begin(77);
  seek(18.25, "keyframes");
  check(fake->seek_flags.back() == "absolute+keyframes", "join uses absolute keyframes, never relative/nearest flags");
  Property(core);
  event(MPV_EVENT_PLAYBACK_RESTART);
  check(log.str().empty(), "acceptance, telemetry, and initial restart cannot invent a landing");
  fake->seek_position = 16;
  event(MPV_EVENT_SEEK);
  event(MPV_EVENT_PLAYBACK_RESTART);
  check(log.str().find("loadId=77 mode=keyframes target=18.250000 observed=16.000000 offset=-2.250000") != std::string::npos,
        "landing logs actual native position and negative offset");
  const auto first = log.str();
  event(MPV_EVENT_PLAYBACK_RESTART);
  check(log.str() == first, "one sample per observed seek");
  log.str("");
  seek(20.25);
  check(fake->seek_flags.back() == "absolute+exact", "omitted mode remains absolute exact");
  fake->seek_position = 20.5;
  event(MPV_EVENT_SEEK);
  event(MPV_EVENT_PLAYBACK_RESTART);
  check(log.str().find("mode=exact target=20.250000 observed=20.500000 offset=0.250000") != std::string::npos,
        "positive landing offset remains truthful");
  log.str("");
  seek(30);
  seek(31);
  event(MPV_EVENT_SEEK);
  event(MPV_EVENT_PLAYBACK_RESTART);
  seek(32);
  event(MPV_EVENT_SEEK);
  event(MPV_EVENT_PLAYBACK_RESTART);
  check(log.str().empty(), "overlapping/coalesced seeks suppress ambiguous samples for the load");
  begin(78);
  seek(40);
  event(MPV_EVENT_SEEK);
  PlayerCoreTestAccess::State(core).AcceptLoad(79, 1079);
  event(MPV_EVENT_PLAYBACK_RESTART);
  check(log.str().empty(), "a replacement invalidates the old load sample");
  begin(79);
  seek(40);
  event(MPV_EVENT_PLAYBACK_RESTART);
  check(log.str().empty(), "same-position/no-SEEK restart is not confirmation");
  PlayerCoreTestAccess::ExpireSeekObservation(core);
  event(MPV_EVENT_SEEK);
  event(MPV_EVENT_PLAYBACK_RESTART);
  check(log.str().empty(), "late restart cannot revive an expired sample");
  begin(80);
  seek(50);
  event(MPV_EVENT_SEEK);
  fake->seek_position = std::numeric_limits<double>::quiet_NaN();
  event(MPV_EVENT_PLAYBACK_RESTART);
  check(log.str().empty(), "invalid native position is not a landing");
  fake->seek_position = 49;
  seek(50);
  event(MPV_EVENT_SEEK);
  End(core, 1080, MPV_ERROR_GENERIC);
  event(MPV_EVENT_PLAYBACK_RESTART);
  check(log.str().empty(), "terminal load error invalidates landing sample");
  begin(81);
  seek(50);
  event(MPV_EVENT_SEEK);
  Reply stop;
  Call(core, "stop", stop, {{"stopId", Value(int64_t{901})}});
  PlayerCoreTestAccess::RunQueuedCommands(core);
  event(MPV_EVENT_PLAYBACK_RESTART);
  check(log.str().empty(), "stop invalidates landing sample");
  begin(82);
  const double boundary = 1.0000009;
  seek(boundary, "keyframes");
  check(std::stod(fake->seek_targets.back()) == boundary,
        "seek target round-trips without rounding forward to a boundary");
  begin(82);
  seek(0, "keyframes");
  fake->seek_position = 0;
  event(MPV_EVENT_SEEK);
  event(MPV_EVENT_PLAYBACK_RESTART);
  check(log.str().find("target=0.000000 observed=0.000000 offset=0.000000") != std::string::npos,
        "zero-boundary keyframe join remains absolute and observable");
  log.str("");
  begin(83);
  seek(1, "keyframes");
  event(MPV_EVENT_SEEK);
  event(MPV_EVENT_SEEK);
  event(MPV_EVENT_PLAYBACK_RESTART);
  check(log.str().empty(), "duplicate seek notifications cannot be misattributed");
  begin(84);
  seek(1, "keyframes");
  event(MPV_EVENT_SEEK);
  fake->seeking = true;
  event(MPV_EVENT_PLAYBACK_RESTART);
  check(log.str().empty(), "a still-seeking native snapshot cannot confirm landing");
  fake->seeking = false;
  begin(85);
  seek(1, "keyframes");
  event(MPV_EVENT_SEEK);
  AudioOutputProbeError(core);
  fake->seek_position = 0.75;
  event(MPV_EVENT_PLAYBACK_RESTART);
  check(log.str().find("loadId=85 mode=keyframes target=1.000000 observed=0.750000 offset=-0.250000") != std::string::npos,
        "a matched explicit seek remains observable after a recovered backend probe error");
  const auto recovered_seek = log.str();
  event(MPV_EVENT_PLAYBACK_RESTART);
  check(log.str() == recovered_seek, "recovered explicit seek logs at most once");
  const auto& seek_detail = PlayerCoreTestAccess::State(core).failure();
  check(seek_detail && seek_detail->load_id == 85 && seek_detail->code == "audio_output_error",
        "explicit landing retains the classified log detail for a later terminal error");
  log.str("");
  seek(2, "keyframes");
  event(MPV_EVENT_SEEK);
  Events terminal_error;
  Drain(core, terminal_error);
  terminal_error.received.clear();
  End(core, 1085, MPV_ERROR_GENERIC);
  event(MPV_EVENT_PLAYBACK_RESTART);
  check(log.str().empty(), "actual terminal error still retires a pending explicit seek");
  Drain(core, terminal_error);
  check(terminal_error.received.size() == 1 &&
        Has(terminal_error.received[0], "loadId", Value(int64_t{85})) &&
        Has(terminal_error.received[0], "state", Value("error")) &&
        Has(terminal_error.received[0], "failureCode", Value("audio_output_error")),
        "later terminal error preserves the original classified audio detail");
  begin(86);
  Events command_errors;
  Drain(core, command_errors);
  command_errors.received.clear();
  seek(10, "keyframes");
  fake->seek_position = 9;
  fake->reject_volume = true;
  Reply volume;
  Call(core, "setVolume", volume, {{"volume", Value(50.0)}});
  check(volume.successes == 1, "volume failure occurs after command admission");
  PlayerCoreTestAccess::RunQueuedCommands(core);
  fake->reject_volume = false;
  Drain(core, command_errors);
  check(command_errors.received.size() == 1 &&
        Has(command_errors.received[0], "loadId", Value(int64_t{86})) &&
        Has(command_errors.received[0], "state", Value("error")) &&
        Has(command_errors.received[0], "failureCode", Value("command_error")),
        "actual command-error producer retains its current-load wire result");
  check(!PlayerCoreTestAccess::State(core).failure(),
        "command-error regression does not rely on the failure detail cache");
  event(MPV_EVENT_SEEK);
  event(MPV_EVENT_PLAYBACK_RESTART);
  check(log.str().empty(), "published command failure discards the earlier seek sample");
  seek(11, "keyframes");
  event(MPV_EVENT_SEEK);
  event(MPV_EVENT_PLAYBACK_RESTART);
  check(log.str().empty(), "command failure keeps the load ambiguous for later restarts");
  std::cerr.rdbuf(original);
  CloseWorkerless(core);
}

void ReadinessPauseSnapshot(PlayerCore& core) {
  OpenWorkerless(core);
  for (const bool resume : {true, false}) {
    const int64_t id = resume ? 301 : 302;
    fake->playlist_id = id + 1000;
    Reply load;
    Call(core, "load", load, {{"uri", Value("file:///fixture.mp4")},
                              {"loadId", Value(id)}, {"startPaused", Value(true)},
                              {"startSeconds", Value(18.25)}});
    Check(load.successes == 1, "held initial join admitted");
    PlayerCoreTestAccess::RunQueuedCommands(core);
    if (resume) {
      Reply play;
      Call(core, "play", play);
      PlayerCoreTestAccess::RunQueuedCommands(core);
    }
    // No property-change notification: mpv may coalesce pause true/false.
    Start(core, id + 1000);
    mpv_event loaded{};
    loaded.event_id = MPV_EVENT_FILE_LOADED;
    PlayerCoreTestAccess::Event(core, loaded);
    Events events;
    Drain(core, events);
    const auto ready = std::find_if(events.received.begin(), events.received.end(),
        [id](const ValueMap& event) { return Has(event, "state", Value("playing")) &&
                                         Has(event, "loadId", Value(id)); });
    Check(ready != events.received.end() &&
          Has(*ready, "loadId", Value(id)) &&
          Has(*ready, "paused", Value(!resume)),
          "readiness carries actual pause independently of requested startPaused");
  }
  CloseWorkerless(core);
}

void InitialJoinObservation(PlayerCore& core) {
  OpenWorkerless(core);
  std::ostringstream log;
  auto* original = std::cerr.rdbuf(log.rdbuf());
  const auto check = [&](bool condition, const char* obligation) {
    if (!condition) std::cerr.rdbuf(original);
    Check(condition, obligation);
  };
  auto event = [&](mpv_event_id id) {
    mpv_event value{};
    value.event_id = id;
    PlayerCoreTestAccess::Event(core, value);
  };
  auto load = [&](int64_t id, double target = 18.25) {
    log.str("");
    fake->playlist_id = id + 1000;
    Reply reply;
    Call(core, "load", reply, {{"uri", Value("https://media.invalid/a%20b?quality=original")},
                                {"loadId", Value(id)}, {"startSeconds", Value(target)}});
    check(reply.successes == 1, "initial join admitted");
    PlayerCoreTestAccess::RunQueuedCommands(core);
  };
  auto ready = [&](int64_t id) {
    Start(core, id + 1000);
    event(MPV_EVENT_FILE_LOADED);
  };
  fake->seek_position = 16;
  fake->seeking = false;
  load(201);
  check(fake->load_options.size() == 2 && fake->load_options["hr-seek"] == "no" &&
        fake->load_options["start"] == "18.25" &&
        fake->authenticated_uri == "https://media.invalid/a%20b?quality=original",
        "unauthenticated start is a string node map with unchanged URI");
  event(MPV_EVENT_FILE_LOADED);
  event(MPV_EVENT_PLAYBACK_RESTART);
  Start(core, 1201);
  event(MPV_EVENT_PLAYBACK_RESTART);
  check(log.str().empty(), "pre-START and pre-FILE_LOADED restart cannot confirm initial landing");
  event(MPV_EVENT_FILE_LOADED);
  event(MPV_EVENT_SEEK);
  event(MPV_EVENT_PLAYBACK_RESTART);
  check(log.str().find("loadId=201 mode=keyframes target=18.250000 observed=16.000000 offset=-2.250000") != std::string::npos,
        "matched initial restart logs a truthful keyframe offset");
  const auto first = log.str();
  event(MPV_EVENT_PLAYBACK_RESTART);
  check(log.str() == first, "initial landing logs at most once");

  load(202, 0);
  End(core, 1201);
  event(MPV_EVENT_PLAYBACK_RESTART);
  ready(202);
  fake->seek_position = 0;
  event(MPV_EVENT_PLAYBACK_RESTART);
  check(log.str().find("loadId=202 mode=keyframes target=0.000000 observed=0.000000") != std::string::npos,
        "previous end cannot retire the new initial sample; zero start remains observable");

  load(203);
  load(204);
  ready(203);
  event(MPV_EVENT_PLAYBACK_RESTART);
  check(log.str().empty(), "superseded load restart cannot satisfy the new initial window");
  ready(204);
  event(MPV_EVENT_PLAYBACK_RESTART);
  check(log.str().find("loadId=204") != std::string::npos,
        "only the matching replacement START/FILE_LOADED opens its window");

  load(205);
  ready(205);
  AudioOutputProbeError(core);
  fake->seek_position = 16;
  event(MPV_EVENT_PLAYBACK_RESTART);
  check(log.str().find("loadId=205 mode=keyframes target=18.250000 observed=16.000000 offset=-2.250000") != std::string::npos,
        "a matched initial restart remains observable after a recovered backend probe error");
  const auto recovered_initial = log.str();
  event(MPV_EVENT_PLAYBACK_RESTART);
  check(log.str() == recovered_initial, "recovered initial join logs at most once");
  const auto& initial_detail = PlayerCoreTestAccess::State(core).failure();
  check(initial_detail && initial_detail->load_id == 205 && initial_detail->code == "audio_output_error",
        "initial landing retains the classified log detail for a later terminal error");

  for (int failure = 0; failure < 8; ++failure) {
    const int64_t id = 210 + failure;
    load(id);
    ready(id);
    if (failure == 0) {
      Reply reply;
      Call(core, "seek", reply, {{"seconds", Value(10.0)}, {"mode", Value("exact")}});
      PlayerCoreTestAccess::RunQueuedCommands(core);
      event(MPV_EVENT_SEEK);
      check(fake->seek_flags.back() == "absolute+exact", "explicit exact overrides per-file hr-seek=no");
    } else if (failure == 1) {
      fake->seeking = true;
    } else if (failure == 2) {
      fake->seek_position = std::numeric_limits<double>::quiet_NaN();
    } else if (failure == 3) {
      End(core, id + 1000);
    } else if (failure == 4) {
      PlayerCoreTestAccess::ExpireSeekObservation(core);
    } else if (failure == 5) {
      fake->reject_volume = true;
      Reply reply;
      Call(core, "setVolume", reply, {{"volume", Value(50.0)}});
      PlayerCoreTestAccess::RunQueuedCommands(core);
      fake->reject_volume = false;
    } else if (failure == 6) {
      AudioOutputProbeError(core);
      Events terminal_error;
      Drain(core, terminal_error);
      terminal_error.received.clear();
      End(core, id + 1000, MPV_ERROR_GENERIC);
      Drain(core, terminal_error);
      check(terminal_error.received.size() == 1 &&
            Has(terminal_error.received[0], "loadId", Value(id)) &&
            Has(terminal_error.received[0], "state", Value("error")) &&
            Has(terminal_error.received[0], "failureCode", Value("audio_output_error")),
            "failed initial load publishes its retained classified error detail");
    } else {
      event(MPV_EVENT_SEEK);
      event(MPV_EVENT_SEEK);
    }
    event(MPV_EVENT_PLAYBACK_RESTART);
    check(log.str().empty(), "ambiguous, seeking, invalid, ended, expired or failed initial sample is suppressed");
    fake->seeking = false;
    fake->seek_position = 16;
    End(core, id + 1000);
  }
  fake->node_load_status = MPV_ERROR_COMMAND;
  load(220);
  fake->node_load_status = 0;
  ready(220);
  event(MPV_EVENT_PLAYBACK_RESTART);
  check(log.str().empty(), "rejected load cannot create an initial landing sample");
  std::cerr.rdbuf(original);
  CloseWorkerless(core);
  fake->playlist_id.reset();
}

void Validation(PlayerCore& core) {
  Reply early;
  Call(core, "play", early);
  Check(early.errors == 1 && early.error == "not_initialized", "commands require initialization");
  Check(RejectedLoadWipesToken(core), "pre-initialize load wipes the converted token");
  Check(core.HandleCommand("setVideoRect", nullptr)->error->code == "not_initialized",
        "platform methods also require initialization");
  OpenWorkerless(core);
  Check(!core.HandleCommand("setVideoRect", nullptr), "platform methods are not claimed");
  const auto rejects = [&](const char* method, ValueMap arguments, const char* code) {
    Reply reply;
    Call(core, method, reply, std::move(arguments));
    return reply.errors == 1 && reply.error == code;
  };
  const auto accepts = [&](const char* method, ValueMap arguments) {
    Reply reply;
    Call(core, method, reply, std::move(arguments));
    return reply.successes == 1;
  };
  const Value https("https://media.invalid/file.mkv");
  Check(rejects("load", {{"uri", Value("")}, {"loadId", Value(int64_t{1})}}, "invalid_argument") &&
        rejects("load", {{"uri", Value(std::string(32769, 'x'))}, {"loadId", Value(int64_t{1})}},
                "invalid_argument") &&
        rejects("load", {{"uri", https}, {"loadId", Value(int64_t{-1})}}, "invalid_argument") &&
        rejects("load", {{"uri", https}, {"loadId", Value(1.0)}}, "invalid_argument") &&
        accepts("load", {{"uri", Value(std::string(32768, 'x'))}, {"loadId", Value(int64_t{0})}}),
        "load uri and loadId bounds");
  Check(rejects("load", {{"uri", https}, {"loadId", Value(int64_t{1})}, {"plexToken", Value("a b")}},
                "invalid_argument") &&
        rejects("load", {{"uri", https}, {"loadId", Value(int64_t{1})}, {"plexToken", Value("")}},
                "invalid_argument") &&
        rejects("load", {{"uri", https}, {"loadId", Value(int64_t{1})},
                         {"plexToken", Value(std::string(8193, 'a'))}}, "invalid_argument") &&
        rejects("load", {{"uri", https}, {"loadId", Value(int64_t{1})},
                         {"plexToken", Value(lineup::player::ValueList{})}}, "invalid_argument") &&
        rejects("load", {{"uri", Value("http://media.invalid/a")}, {"loadId", Value(int64_t{1})},
                         {"plexToken", Value("token")}}, "insecure_media_uri") &&
        rejects("load", {{"uri", Value("https:///a")}, {"loadId", Value(int64_t{1})},
                         {"plexToken", Value("token")}}, "insecure_media_uri") &&
        rejects("load", {{"uri", https}, {"loadId", Value(int64_t{1})}, {"startPaused", Value()}},
                "invalid_argument") &&
        accepts("load", {{"uri", Value("HTTPS://media.invalid")}, {"loadId", Value(int64_t{1})},
                         {"plexToken", Value(std::string(8192, '~'))}}) &&
        accepts("load", {{"uri", Value("http://media.invalid/a")}, {"loadId", Value(int64_t{1})},
                         {"plexToken", Value()}, {"startPaused", Value(true)}}),
        "token, HTTPS, and startPaused validation");
  for (const Value& invalid : {Value(), Value("3"), Value(true), Value(-1.0),
                              Value(std::numeric_limits<double>::infinity()),
                              Value(std::numeric_limits<double>::quiet_NaN())}) {
    Check(rejects("load", {{"uri", https}, {"loadId", Value(int64_t{1})},
                           {"startSeconds", invalid}}, "invalid_argument"),
          "initial start requires a finite non-negative number");
  }
  Check(rejects("seek", {{"seconds", Value(-0.5)}}, "invalid_argument") &&
        rejects("seek", {{"seconds", Value(std::numeric_limits<double>::infinity())}},
                "invalid_argument") &&
        accepts("seek", {{"seconds", Value(int64_t{3})}}) &&
        accepts("seek", {{"seconds", Value(0.0)}, {"mode", Value("keyframes")}}) &&
        accepts("seek", {{"seconds", Value(3.0)}, {"mode", Value("exact")}}) &&
        rejects("seek", {{"seconds", Value(3.0)}, {"mode", Value("nearest")}}, "invalid_argument") &&
        rejects("seek", {{"seconds", Value(3.0)}, {"mode", Value()}}, "invalid_argument") &&
        rejects("seek", {{"seconds", Value(3.0)}, {"mode", Value(true)}}, "invalid_argument") &&
        rejects("stop", {{"stopId", Value(int64_t{0})}}, "invalid_argument") &&
        rejects("setVolume", {{"volume", Value(100.5)}}, "invalid_argument") &&
        rejects("setVolume", {{"volume", Value(std::numeric_limits<double>::quiet_NaN())}},
                "invalid_argument") &&
        accepts("setVolume", {{"volume", Value(int64_t{100})}}) &&
        rejects("selectTrack", {{"type", Value("sub")}, {"loadId", Value(int64_t{1})},
                                {"requestId", Value(int64_t{1})}}, "invalid_argument") &&
        rejects("selectTrack", {{"type", Value("video")}, {"loadId", Value(int64_t{1})},
                                {"requestId", Value(int64_t{1})}, {"id", Value(int64_t{0})}},
                "invalid_argument") &&
        accepts("selectTrack", {{"type", Value("subtitle")}, {"loadId", Value(int64_t{1})},
                                {"requestId", Value(int64_t{1})}, {"id", Value()}}),
        "seek, stop, volume, and track validation");
  Check(core.HandleCommand("selectTrack", nullptr)->error->message == "Track selection is required.",
        "missing track map keeps its message");
  CloseWorkerless(core);

  OpenWorkerless(core);
  ResetHeaderWatch();
  ValueMap authenticated{{"uri", https}, {"loadId", Value(int64_t{5})},
                         {"plexToken", Value("tok,en\\x")}, {"startSeconds", Value(18.2500001)}};
  Reply reply;
  Record(reply, *core.HandleCommand("load", &authenticated));
  const auto& scrubbed = std::get<std::string>(authenticated["plexToken"]);
  Check(reply.successes == 1 &&
        std::all_of(scrubbed.begin(), scrubbed.end(), [](char byte) { return byte == 0; }),
        "converted token argument is wiped after the call");
  PlayerCoreTestAccess::RunQueuedCommands(core);
  Check(fake->authenticated_header == "X-Plex-Token: tok\\,en\\\\x" &&
        fake->authenticated_redirects == "0" &&
        fake->authenticated_uri == "https://media.invalid/file.mkv",
        "authenticated load scopes the escaped header and forbids redirects");
  Check(fake->load_options.size() == 4 &&
        fake->load_options["hr-seek"] == "no" &&
        std::stod(fake->load_options["start"]) == 18.2500001,
        "string start and hr-seek compose with authenticated options without rounding");
  Check(watched_freed && watched_wiped, "header buffer is wiped before deallocation");
  CloseWorkerless(core);
}

void InitializeFailures() {
  fake->created = 0;
  fake->destroyed = 0;
  {
    FakeHost host;
    host.prepare_error = CallError{"required_engine_unavailable", "engine"};
    PlayerCore core(FakeOperations(), host);
    Reply reply;
    Call(core, "initialize", reply);
    Check(reply.error == "required_engine_unavailable" && fake->created == 0 &&
          host.cancelled == 0, "platform precondition fails before libmpv");
  }
  {
    FakeHost host;
    fake->fail_create = true;
    PlayerCore core(FakeOperations(), host);
    Reply reply;
    Call(core, "initialize", reply);
    fake->fail_create = false;
    Check(reply.error == "initialize_failed" && host.cancelled == 1,
          "client creation failure releases platform output");
  }
  {
    FakeHost host;
    fake->rejected_option = "tls-verify";
    fake->options.clear();
    PlayerCore core(FakeOperations(), host);
    const CallResult result = core.Initialize();
    fake->rejected_option.clear();
    Check(result.error && result.error->code == "initialize_failed" &&
          result.error->message == "libmpv initialization failed: fake mpv error" &&
          host.cancelled == 1 && fake->destroyed == 1 &&
          fake->options.back() == "tls-verify=yes" && !core.initialized(),
          "security option failure stops initialization");
  }
  for (const char* absent : {"osc", "ytdl"}) {
    FakeHost host;
    fake->rejected_option = absent;
    fake->options.clear();
    PlayerCore core(FakeOperations(), host);
    Reply reply;
    Call(core, "initialize", reply);
    fake->rejected_option.clear();
    const bool continued =
        std::find(fake->options.begin(), fake->options.end(), "hwdec=auto") !=
        fake->options.end();
    Check(reply.successes == 1 && core.initialized() && host.cancelled == 0 &&
          continued, "a runtime without the osc or ytdl option still initializes");
    core.Shutdown();
  }
  {
    // Other mandatory options remain fatal even though the fake reports
    // the same option-not-found status as optional osc/ytdl disabling.
    FakeHost host;
    fake->rejected_option = "input-media-keys";
    PlayerCore core(FakeOperations(), host);
    const CallResult result = core.Initialize();
    fake->rejected_option.clear();
    Check(result.error && result.error->code == "initialize_failed" &&
          result.error->message == "libmpv initialization failed: fake mpv error" &&
          host.cancelled == 1 && !core.initialized(),
          "only the absent disabling options are accepted");
  }
  {
    const int destroyed_before = fake->destroyed.load();
    FakeHost host;
    fake->rejected_observation = "track-list";
    PlayerCore core(FakeOperations(), host);
    Reply reply;
    Call(core, "initialize", reply);
    fake->rejected_observation.clear();
    Check(reply.error == "initialize_failed" && host.cancelled == 1 &&
          fake->destroyed == destroyed_before + 1 && !core.initialized(),
          "observation failure stops initialization");
  }
  const std::pair<const char*, const char*> subtitle_options[] = {
      {"sub-color", "#00FFFFFF"},
      {"sub-outline-size", "0"},
      {"sub-shadow-offset", "0"},
      {"sub-back-color", "#00000000"},
      {"sub-border-style", "outline-and-shadow"},
      {"sub-ass-override", "scale"},
  };
  for (const auto& [rejected, ignored_value] : subtitle_options) {
    (void)ignored_value;
    for (const int status : {MPV_ERROR_OPTION_NOT_FOUND, MPV_ERROR_OPTION_ERROR}) {
      FakeHost host;
      fake->rejected_option = rejected;
      fake->rejected_option_status = status;
      fake->options.clear();
      fake->commands.clear();
      fake->playlist_id = 77;
      PlayerCore core(FakeOperations(), host);
      std::ostringstream diagnostics;
      auto* original_stderr = std::cerr.rdbuf(diagnostics.rdbuf());
      const CallResult result = core.Initialize();
      std::cerr.rdbuf(original_stderr);
      fake->rejected_option.clear();
      fake->rejected_option_status = MPV_ERROR_OPTION_NOT_FOUND;
      Check(!result.error && core.initialized() && host.cancelled == 0,
            "each rejected subtitle init option leaves playback initialized");
      const std::string rejection =
          std::string("[lineup-player] subtitle option ") + rejected + " rejected\n";
      Check(diagnostics.str().find(rejection) == 0 &&
            diagnostics.str().find(rejection, rejection.size()) == std::string::npos,
            "subtitle init rejection emits one fixed non-content diagnostic");
      for (const auto& [name, value] : subtitle_options) {
        Check(std::count(fake->options.begin(), fake->options.end(),
                         std::string(name) + "=" + value) == 1,
              "all subtitle defaults attempted despite an earlier rejection");
      }
      Check(std::find(fake->options.begin(), fake->options.end(), "vo=gpu-next") != fake->options.end() &&
            fake->options.back() == "hwdec=auto",
            "subtitle rejection does not skip mandatory output/hwdec options");
      Events events;
      Reply load;
      Call(core, "load", load, {{"uri", Value("https://fixture.invalid/subtitle-option")},
                                 {"loadId", Value(41)}});
      Check(load.successes == 1, "load accepted after subtitle option rejection");
      PumpUntil(core, events, [&] {
        std::lock_guard lock(fake->mutex);
        return std::find(fake->commands.begin(), fake->commands.end(), "loadfile") != fake->commands.end();
      }, "worker executes load after subtitle option rejection");
      mpv_event_start_file start_data{};
      start_data.playlist_entry_id = 77;
      mpv_event start{};
      start.event_id = MPV_EVENT_START_FILE;
      start.data = &start_data;
      mpv_event ready{};
      ready.event_id = MPV_EVENT_FILE_LOADED;
      {
        std::lock_guard lock(fake->mutex);
        fake->injected.push_back(start);
        fake->injected.push_back(ready);
      }
      PumpUntil(core, events, [&] {
        return std::any_of(events.received.begin(), events.received.end(), [](const auto& event) {
          return Has(event, "state", Value("playing")) && Has(event, "loadId", Value(41));
        });
      }, "later load reaches correlated playing state after subtitle option rejection");
      Check(std::none_of(events.received.begin(), events.received.end(), [](const auto& event) {
        return Has(event, "state", Value("error"));
      }), "subtitle init rejection never publishes a playback failure");
      core.Shutdown();
      fake->playlist_id.reset();
    }
  }
  fake->created = 0;
  fake->destroyed = 0;
}

void Lifecycle() {
  FakeHost host;
  PlayerCore core(FakeOperations(), host);
  Events events;
  auto& received = events.received;
  fake->options.clear();
  fake->observations.clear();
  fake->commands.clear();
  Reply init;
  Call(core, "initialize", init);
  Check(init.successes == 1 &&
        Has(std::get<ValueMap>(init.value), "clientApiVersion",
            Value(static_cast<int64_t>(MPV_CLIENT_API_VERSION))),
        "initialization reports the client API version");
  const std::vector<std::string> expected_options{
      "wid=4242", "config=no", "terminal=no", "input-default-bindings=no",
      "input-vo-keyboard=no", "input-media-keys=no", "osc=no", "ytdl=no",
      "tls-verify=yes", "access-references=no", "autoload-files=no", "idle=yes",
      "keep-open=no", "sub-color=#00FFFFFF", "sub-outline-size=0", "sub-shadow-offset=0",
      "sub-back-color=#00000000", "sub-border-style=outline-and-shadow", "sub-ass-override=scale", "vo=gpu-next", "gpu-api=d3d11", "gpu-context=d3d11",
      "hwdec=auto"};
  const std::vector<std::string> expected_observations{
      "pause", "time-pos", "duration", "track-list", "video-format", "video-codec",
      "current-vo", "hwdec-current", "video-params", "video-target-params",
      "current-tracks/sub/codec", "sub-text/ass"};
  {
    std::lock_guard lock(fake->mutex);
    Check(fake->options == expected_options, "option order and platform placement");
    Check(fake->observations == expected_observations, "property observations");
    Check(fake->log_level == "error", "error log subscription");
  }
  PumpUntil(core, events, [&] { return !received.empty(); }, "ready event delivered");
  Check(Has(received[0], "state", Value("idle")) &&
        Has(received[0], "message", Value("Native libmpv player ready")) &&
        !lineup::player::Find(received[0], "loadId"),
        "ready event has no load identity");
  received.clear();
  Reply again;
  Call(core, "initialize", again);
  Check(again.successes == 1 && fake->created == 1, "repeated initialize is idempotent");

  {
    std::lock_guard lock(fake->mutex);
    fake->playlist_id = 77;
  }
  Reply load;
  Call(core, "load", load, {{"uri", Value("https://media.invalid/a")}, {"loadId", Value(int64_t{5})}});
  Check(load.successes == 1, "worker load acceptance");
  PumpUntil(core, events, [&] {
    std::lock_guard lock(fake->mutex);
    return std::find(fake->commands.begin(), fake->commands.end(), "loadfile") !=
           fake->commands.end();
  }, "worker runs queued load");
  static mpv_event_start_file start{};
  start.playlist_entry_id = 77;
  static mpv_event_end_file end{};
  end.playlist_entry_id = 77;
  end.reason = MPV_END_FILE_REASON_EOF;
  {
    std::lock_guard lock(fake->mutex);
    mpv_event start_event{};
    start_event.event_id = MPV_EVENT_START_FILE;
    start_event.data = &start;
    mpv_event end_event{};
    end_event.event_id = MPV_EVENT_END_FILE;
    end_event.data = &end;
    fake->injected.push_back(start_event);
    fake->injected.push_back(end_event);
  }
  PumpUntil(core, events, [&] { return received.size() >= 2; }, "worker translates mpv events");
  Check(Has(received[0], "state", Value("loading")) && Has(received[0], "loadId", Value(int64_t{5})) &&
        Has(received[1], "state", Value("ended")) && Has(received[1], "loadId", Value(int64_t{5})),
        "worker events keep load identity");
  received.clear();

  ResetHeaderWatch();
  Reply authenticated;
  Call(core, "load", authenticated, {{"uri", Value("https://media.invalid/b")},
                                     {"loadId", Value(int64_t{6})},
                                     {"plexToken", Value("worker-token")}});
  Check(authenticated.successes == 1, "worker authenticated load acceptance");
  PumpUntil(core, events, [&] { return watched_freed.load(); },
            "worker releases the executed header");
  {
    std::lock_guard lock(fake->mutex);
    Check(fake->authenticated_header == "X-Plex-Token: worker-token",
          "worker executed the authenticated load");
  }
  Check(watched_wiped && !header_live_at_wait,
        "worker wipes the header before deallocation and before waiting again");
  received.clear();

  fake->idle = false;
  Reply stop;
  Call(core, "stop", stop, {{"stopId", Value(int64_t{901})}});
  Check(stop.successes == 1, "worker stop acceptance");
  std::this_thread::sleep_for(std::chrono::milliseconds(20));
  core.ProcessWakeup(events.Sink());
  Check(std::none_of(received.begin(), received.end(), [](const ValueMap& event) {
    return Has(event, "stopId", Value(int64_t{901}));
  }), "stop result waits for idle observation");
  fake->idle = true;
  PumpUntil(core, events, [&] {
    return std::any_of(received.begin(), received.end(), [](const ValueMap& event) {
      return Has(event, "stopId", Value(int64_t{901})) && Has(event, "success", Value(true));
    });
  }, "worker observes idle before stop result");

  const int before = fake->destroyed.load();
  Reply disposed;
  disposed.on_success = [&]() {
    Check(fake->destroyed.load() == before + 1, "libmpv teardown precedes result");
    Check(PlayerCoreTestAccess::Disposed(core), "join and FinishDispose precede result");
    Check(host.released == 1, "platform output released before result");
  };
  Call(core, "dispose", disposed);
  Check(disposed.successes == 0, "normal dispose is asynchronous");
  Check(host.dispose_requests == 1, "dispose notifies the platform");
  Reply during;
  Call(core, "initialize", during);
  Check(during.errors == 1 && during.error == "initialize_failed",
        "reinitialize before join is rejected");
  Reply duplicate;
  Call(core, "dispose", duplicate);
  Check(duplicate.errors == 1 && duplicate.error == "dispose_in_progress",
        "concurrent dispose is rejected");
  Check(host.dispose_requests == 1, "rejected dispose does not restart shutdown");
  Reply command;
  Call(core, "play", command);
  Check(command.error == "not_initialized", "commands stop with disposal");
  Check(RejectedLoadWipesToken(core), "load during disposal wipes the converted token");
  core.QueuePlatformEvent({{"type", Value("display")}});
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(10);
  while (!PlayerCoreTestAccess::WorkerFinished(core) &&
         std::chrono::steady_clock::now() < deadline) {
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
  Check(PlayerCoreTestAccess::WorkerFinished(core) && host.worker_finished_posts == 1,
        "worker terminates and notifies the platform");
  Check(disposed.successes == 0, "worker cannot reply before platform processing");
  received.clear();
  PumpUntil(core, events, [&] { return disposed.successes == 1; }, "platform dispose completion");
  Check(disposed.errors == 0 && received.size() == 1 &&
        Has(received[0], "type", Value("display")),
        "dispose delivers current-generation platform events once");
  Reply already;
  Call(core, "dispose", already);
  Check(already.successes == 1, "repeated disposal is successful");
  Check(RejectedLoadWipesToken(core), "post-dispose load wipes the converted token");

  received.clear();
  Reply recreate;
  Call(core, "initialize", recreate);
  Check(recreate.successes == 1, "same owner reinitializes after normal dispose");
  PumpUntil(core, events, [&] { return !received.empty(); }, "second ready event");
  Reply pending;
  Call(core, "dispose", pending);
  core.Shutdown();
  Check(PlayerCoreTestAccess::Disposed(core) && host.released == 2 && pending.successes == 0 &&
        pending.errors == 0, "shutdown completes synchronously and drops the pending reply");
}

void WakeupRetry() {
  FakeHost host;
  PlayerCore core(FakeOperations(), host);
  host.post_succeeds = false;
  Reply init;
  Call(core, "initialize", init);
  Check(init.successes == 1, "initialize with a failing wakeup post");
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(10);
  while (host.wakeups < 3 && std::chrono::steady_clock::now() < deadline) {
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
  Check(host.wakeups >= 3, "worker retries a failed wakeup while events remain");
  host.post_succeeds = true;
  Events events;
  PumpUntil(core, events, [&] { return !events.received.empty(); }, "retried wakeup delivers");
  core.Shutdown();
}

void PlatformArguments() {
  using lineup::player::DisplayDesire;
  using lineup::player::ParseDisplayMatchingArguments;
  using lineup::player::ParseVideoRectArguments;
  const auto display = [](Value revision, Value session, Value desired) {
    return ValueMap{{"revision", std::move(revision)},
                    {"session", std::move(session)},
                    {"desired", std::move(desired)}};
  };
  {
    const ValueMap valid = display(Value(int64_t{0}), Value(true), Value("hdr"));
    const auto parsed = ParseDisplayMatchingArguments(&valid);
    Check(parsed && parsed->revision == 0 && parsed->session &&
          parsed->desired == DisplayDesire::hdr, "valid display request parses");
    const ValueMap sdr = display(Value(int64_t{7}), Value(false), Value("sdr"));
    const ValueMap unknown = display(Value(int64_t{8}), Value(false), Value("unknown"));
    Check(ParseDisplayMatchingArguments(&sdr)->desired == DisplayDesire::sdr &&
          ParseDisplayMatchingArguments(&unknown)->desired == DisplayDesire::unknown,
          "every desired state parses");
  }
  const ValueMap invalid_display[] = {
      display(Value(int64_t{-1}), Value(true), Value("hdr")),
      display(Value(1.0), Value(true), Value("hdr")),
      display(Value(int64_t{1}), Value(int64_t{1}), Value("hdr")),
      display(Value(int64_t{1}), Value(true), Value("HDR")),
      display(Value(int64_t{1}), Value(true), Value()),
      ValueMap{{"revision", Value(int64_t{1})}, {"desired", Value("sdr")}},
  };
  for (const auto& arguments : invalid_display) {
    Check(!ParseDisplayMatchingArguments(&arguments), "invalid display request is rejected");
  }
  Check(!ParseDisplayMatchingArguments(nullptr), "missing display arguments are rejected");

  lineup::player::DisplayRevisionOrder order;
  Check(order.Admit(0) && !order.Admit(0) && order.Admit(3) && !order.Admit(2) &&
        !order.Admit(3) && order.Admit(4), "display revisions strictly increase");
  order.Reset();
  Check(order.Admit(0), "initialize resets the display revision");

  const auto rect = [](Value left, Value top, Value width, Value height, Value scale) {
    return ValueMap{{"left", std::move(left)},   {"top", std::move(top)},
                    {"width", std::move(width)}, {"height", std::move(height)},
                    {"scale", std::move(scale)}};
  };
  {
    const auto parsed = ParseVideoRectArguments(
        rect(Value(int64_t{10}), Value(-5.5), Value(640.0), Value(int64_t{360}), Value(2.0)));
    Check(parsed && parsed->left == 10 && parsed->top == -5.5 && parsed->width == 640 &&
          parsed->height == 360 && parsed->scale == 2, "integer and double bounds parse");
    Check(ParseVideoRectArguments(
              rect(Value(0.0), Value(0.0), Value(0.0), Value(0.0), Value(1.0))).has_value(),
          "an empty rectangle is valid");
  }
  const double nan = std::numeric_limits<double>::quiet_NaN();
  const double inf = std::numeric_limits<double>::infinity();
  const ValueMap invalid_rects[] = {
      rect(Value(nan), Value(0.0), Value(1.0), Value(1.0), Value(1.0)),
      rect(Value(0.0), Value(inf), Value(1.0), Value(1.0), Value(1.0)),
      rect(Value(0.0), Value(0.0), Value(-inf), Value(1.0), Value(1.0)),
      rect(Value(0.0), Value(0.0), Value(1.0), Value(nan), Value(1.0)),
      rect(Value(0.0), Value(0.0), Value(1.0), Value(1.0), Value(inf)),
      rect(Value(0.0), Value(0.0), Value(-1.0), Value(1.0), Value(1.0)),
      rect(Value(0.0), Value(0.0), Value(1.0), Value(-0.5), Value(1.0)),
      rect(Value(0.0), Value(0.0), Value(1.0), Value(1.0), Value(0.0)),
      rect(Value(0.0), Value(0.0), Value(1.0), Value(1.0), Value(-2.0)),
      rect(Value("0"), Value(0.0), Value(1.0), Value(1.0), Value(1.0)),
      rect(Value(0.0), Value(0.0), Value(true), Value(1.0), Value(1.0)),
      rect(Value(0.0), Value(0.0), Value(1.0), Value(), Value(1.0)),
      ValueMap{{"left", Value(0.0)}, {"top", Value(0.0)}, {"width", Value(1.0)},
               {"height", Value(1.0)}},
  };
  for (const auto& arguments : invalid_rects) {
    Check(!ParseVideoRectArguments(arguments), "invalid video bounds are rejected");
  }
}

// Runs `step`, failing the suite instead of hanging if it does not return.
void WithinDeadline(const char* obligation, const std::function<void()>& step) {
  std::atomic<bool> done{false};
  std::thread watchdog([&done, obligation] {
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
    while (!done && std::chrono::steady_clock::now() < deadline) {
      std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }
    if (!done) {
      std::cerr << "FAILED (hang): " << obligation << '\n';
      std::_Exit(1);
    }
  });
  step();
  done = true;
  watchdog.join();
}

// A platform may call Shutdown while it keeps running (macOS does on window
// close). The worker's finished wakeup was posted during Shutdown and is
// delivered afterwards; it must not finish disposal a second time, and after
// a new Initialize it must not join the new worker.
void StaleWakeupAfterShutdown() {
  {
    FakeHost host;
    PlayerCore core(FakeOperations(), host);
    Events events;
    Reply init;
    Call(core, "initialize", init);
    core.Shutdown();
    Check(host.released == 1 && host.worker_finished_posts == 1,
          "shutdown completes once and posts the finished wakeup");
    WithinDeadline("stale wakeup after shutdown returns", [&] {
      core.ProcessWakeup(events.Sink());
    });
    Check(host.released == 1 && PlayerCoreTestAccess::Disposed(core),
          "a stale finished wakeup does not release output again");
  }
  {
    FakeHost host;
    PlayerCore core(FakeOperations(), host);
    Events events;
    Reply first;
    Call(core, "initialize", first);
    core.Shutdown();
    Reply second;
    Call(core, "initialize", second);
    Check(second.successes == 1 && core.initialized(),
          "the core reinitializes after a synchronous shutdown");
    WithinDeadline("stale wakeup after reinitialize returns", [&] {
      core.ProcessWakeup(events.Sink());
    });
    Check(core.initialized() && !core.disposed() && host.released == 1,
          "a stale finished wakeup leaves the new session running");
    Reply play;
    Call(core, "play", play);
    Check(play.successes == 1, "the new session still accepts commands");
    core.Shutdown();
    Check(host.released == 2, "the new session shuts down normally");
  }
}

void CueSlotReservation() {
  FakeHost host;
  PlayerCore core(FakeOperations(), host);
  Events events;
  const auto generation = PlayerCoreTestAccess::Generation(core);
  const auto ordinary = [&](int id, bool telemetry = false) {
    const char* types[] = {"state", "stopResult", "trackResult", "display"};
    PlayerCoreTestAccess::Queue(core, generation,
        {{"type", Value(telemetry ? "property" : types[id % 4])},
         {"name", Value(telemetry ? "time-pos" : "completion")}, {"testId", Value(id)}});
  };
  const auto cue = [&](bool clear) {
    PlayerCoreTestAccess::Queue(core, generation,
        {{"type", Value("property")}, {"name", Value("subtitle-cues")},
         {"loadId", Value(77)},
         {"value", Value(clear ? ValueList{} : lineup::player::ParseSubtitleCues("fixture", false))}});
  };
  const auto check_ids = [&](size_t cue_position) {
    Check(events.received.size() == 256, "255 completions plus reserved cue stay within total256");
    int id = 0;
    for (size_t i = 0; i < events.received.size(); ++i) {
      if (i == cue_position) {
        Check(Has(events.received[i], "name", Value("subtitle-cues")) &&
              std::get<ValueList>(events.received[i].at("value")).empty(),
              "clear replacement retains the exact cue FIFO position");
      } else {
        Check(Has(events.received[i], "testId", Value(id++)),
              "first cue/clear preserves every admitted completion identity in FIFO order");
      }
    }
    Check(id == 255, "all255 uniquely identified completions survive cue admission");
  };

  // Reservation exists before any cue. Genuine ordinary overflow still evicts
  // the oldest completion; an otherwise unused cue slot cannot hide overflow.
  for (int i = 0; i < 256; ++i) ordinary(i);
  Drain(core, events);
  Check(events.received.size() == 255,
        "ordinary events reserve one of256 slots even before the first cue");
  for (size_t i = 0; i < events.received.size(); ++i) {
    Check(Has(events.received[i], "testId", Value(static_cast<int>(i) + 1)),
          "genuine completion overflow retains existing oldest-first eviction policy");
  }
  events.received.clear();

  for (int i = 0; i < 255; ++i) ordinary(i);
  cue(false);
  cue(true);
  Drain(core, events);
  check_ids(255);
  events.received.clear();

  for (int i = 0; i < 127; ++i) ordinary(i);
  cue(false);
  for (int i = 127; i < 255; ++i) ordinary(i);
  cue(true);
  ordinary(999, true);  // Telemetry cannot displace a completion or the clear.
  Drain(core, events);
  check_ids(127);
  events.received.clear();

  cue(true);
  for (int i = 0; i < 255; ++i) ordinary(i, true);
  for (int i = 0; i < 600; ++i) ordinary(1000 + i, i % 2 == 0);
  Drain(core, events);
  Check(events.received.size() == 256 &&
        Has(events.received.front(), "name", Value("subtitle-cues")) &&
        std::get<ValueList>(events.received.front().at("value")).empty() &&
        Has(events.received.back(), "testId", Value(1599)),
        "mixed telemetry/completion pressure retains clear and newest completion within256");
  int previous_id = -1;
  for (size_t i = 1; i < events.received.size(); ++i) {
    const auto id = std::get<int64_t>(events.received[i].at("testId"));
    Check(id > previous_id, "ordinary FIFO survives mixed pressure without a duplicate cue");
    previous_id = static_cast<int>(id);
  }
}

void SubtitleContract() {
  FakeMpv state;
  fake = &state;
  FakeHost host;
  PlayerCore core(FakeOperations(), host);
  Events events;
  const auto presentation = [](double scale, double raise = .15, bool styled = false) {
    return ValueMap{{"scale", Value(scale)}, {"imageRaise", Value(raise)}, {"lineupDrawsStyled", Value(styled)}};
  };
  Reply cold;
  Call(core, "setSubtitlePresentation", cold, presentation(1));
  Check(cold.error == "not_initialized", "subtitle command requires initialization");
  PlayerCoreTestAccess::OpenWorkerlessClient(core, FakeClient());
  for (auto args : {ValueMap{}, ValueMap{{"scale", Value(1)}}, presentation(.24), presentation(4.01),
                    presentation(1, -.01), presentation(1, .251), presentation(std::numeric_limits<double>::infinity()),
                    presentation(1, std::numeric_limits<double>::quiet_NaN()),
                    ValueMap{{"scale", Value(true)}, {"imageRaise", Value(0)}, {"lineupDrawsStyled", Value(false)}}}) {
    Reply invalid;
    Call(core, "setSubtitlePresentation", invalid, args);
    Check(invalid.error == "invalid_argument", "malformed subtitle presentation rejected");
  }
  for (int i = 0; i < 10; ++i) {
    Reply reply;
    Call(core, "setSubtitlePresentation", reply, presentation(1 + i * .1));
    Check(reply.successes == 1, "latest value accepts rapid changes");
  }
  Reply invalid_latest;
  Call(core, "setSubtitlePresentation", invalid_latest, presentation(9));
  Check(invalid_latest.error == "invalid_argument", "invalid call leaves pending value intact");
  Reply load;
  Call(core, "load", load, {{"uri", Value("https://fixture.invalid/video")}, {"loadId", Value(1)}});
  lineup::player::SubtitleCoreTestAccess::Run(core);
  Check(state.subtitle_properties.front().first == "sub-scale" && std::abs(state.subtitle_properties.front().second - 1.9) < 1e-9, "only final scale applied");
  Check(std::count_if(state.subtitle_properties.begin(), state.subtitle_properties.end(), [](auto& property) { return property.first == "sub-scale"; }) == 1, "one latest-value application");
  Check(std::find(state.execution_order.begin(), state.execution_order.end(), "sub-scale") <
        std::find(state.execution_order.begin(), state.execution_order.end(), "loadfile"), "style precedes load in one batch");
  auto& playback = PlayerCoreTestAccess::State(core);
  playback.StartFile(1);
  const auto property = [&](const char* name, const char* text) {
    char* data = const_cast<char*>(text);
    mpv_event_property p{name, text ? MPV_FORMAT_STRING : MPV_FORMAT_NONE, text ? &data : nullptr};
    mpv_event event{}; event.event_id = MPV_EVENT_PROPERTY_CHANGE; event.data = &p;
    PlayerCoreTestAccess::Event(core, event);
  };
  const auto last_cues = [&]() -> ValueList {
    events.received.clear(); Drain(core, events);
    ValueList cues;
    for (const auto& event : events.received) {
      const auto* name = lineup::player::FindString(&event, "name");
      Check(!name || (*name != "sub-text/ass" && *name != "current-tracks/sub/codec"), "raw cue/codec properties intercepted");
      if (name && *name == "subtitle-cues") cues = std::get<ValueList>(event.at("value"));
    }
    return cues;
  };
  property("sub-text/ass", "Fixture text before codec");
  Check(last_cues().empty(), "unknown codec cannot publish text");
  property("current-tracks/sub/codec", "subrip");
  Check(last_cues().size() == 1, "codec reclassifies cached text");
  Check(state.subtitle_properties.back() == std::make_pair(std::string("sub-visibility"), 0.0), "text suppressed");
  property("current-tracks/sub/codec", "hdmv_pgs_subtitle");
  Check(last_cues().empty(), "PGS clears Flutter cues");
  Check(std::find(state.subtitle_properties.begin(), state.subtitle_properties.end(), std::make_pair(std::string("sub-pos"), 85.0)) != state.subtitle_properties.end(), "image raise applies");
  property("current-tracks/sub/codec", "ass");
  Check(last_cues().empty(), "native ASS remains engine drawn");
  const auto last_position = std::find_if(state.subtitle_properties.rbegin(), state.subtitle_properties.rend(), [](auto& property_value) { return property_value.first == "sub-pos"; });
  Check(last_position != state.subtitle_properties.rend() && last_position->second == 100, "ASS position reset");
  property("sub-text/ass", "{\\pos(1,2)}Fixture sign\nFixture dialogue");
  Reply styled;
  Call(core, "setSubtitlePresentation", styled, presentation(2, .1, true));
  lineup::player::SubtitleCoreTestAccess::Run(core);
  Check(last_cues().size() == 1, "styled opt-in reuses cached dialogue and excludes signs");
  state.rejected_subtitle_property = "sub-scale";
  Reply failing;
  Call(core, "setSubtitlePresentation", failing, presentation(3, .2, false));
  lineup::player::SubtitleCoreTestAccess::Run(core);
  last_cues();
  Check(std::none_of(events.received.begin(), events.received.end(), [](auto& event) { return Has(event, "failureCode", Value("command_error")); }), "subtitle failure never fails playback");
  Check(state.subtitle_properties.back() == std::make_pair(std::string("sub-visibility"), 1.0), "later properties apply after scale rejection");
  const size_t applied_before_repeat = state.subtitle_properties.size();
  Reply repeated;
  Call(core, "setSubtitlePresentation", repeated, presentation(3, .2, false));
  lineup::player::SubtitleCoreTestAccess::Run(core);
  Check(state.subtitle_properties.size() == applied_before_repeat, "rejected unchanged properties are not retried per cue/value");
  property("current-tracks/sub/codec", "ssa");
  property("sub-text/ass", "Fixture lavf SSA");
  Check(last_cues().size() == 1, "lavf SSA is converted text");
  property("current-tracks/sub/codec", nullptr);
  Check(last_cues().empty(), "no selection clears");
  property("current-tracks/sub/codec", "subrip");
  Check(last_cues().empty(), "track deselection forgets cached text");
  property("sub-text/ass", "Fixture before selection");
  Reply selected;
  Call(core, "selectTrack", selected, {{"loadId", Value(1)}, {"requestId", Value(9)}, {"type", Value("subtitle")}, {"id", Value(2)}});
  lineup::player::SubtitleCoreTestAccess::Run(core);
  Check(last_cues().empty(), "track selection clears old text");
  property("sub-text/ass", "Fixture same codec new track");
  Check(last_cues().size() == 1, "same-codec track switch needs no repeated codec notification");
  property("sub-text/ass", "Fixture before stop");
  Reply stop;
  Call(core, "stop", stop, {{"stopId", Value(1)}});
  lineup::player::SubtitleCoreTestAccess::Run(core);
  Check(last_cues().empty(), "stop clears cues");
  property("sub-text/ass", "Fixture stale stop cue");
  Check(last_cues().empty(), "pending stop blocks late cue");
  playback.ObserveIdle(true, 0);
  Reply next;
  Call(core, "load", next, {{"uri", Value("https://fixture.invalid/next")}, {"loadId", Value(2)}});
  lineup::player::SubtitleCoreTestAccess::Run(core);
  Check(last_cues().empty(), "new load clears cues");
  property("current-tracks/sub/codec", "subrip");
  property("sub-text/ass", "Fixture obsolete load");
  Check(last_cues().empty(), "obsolete load observation blocked");
  playback.StartFile(2);
  property("sub-text/ass", "Fixture same codec new load");
  Check(last_cues().size() == 1, "same-codec load needs no repeated codec notification");
  End(core, 2, 0);
  Check(last_cues().empty(), "end clears visible text");
  property("sub-text/ass", "Fixture late terminal text");
  Check(last_cues().empty(), "terminal load cannot republish cues");
  // Queue clear cannot be evicted by either telemetry or completion pressure.
  const auto generation = PlayerCoreTestAccess::Generation(core);
  auto cue = [](bool nonempty) { return ValueMap{{"type", Value("property")}, {"name", Value("subtitle-cues")}, {"loadId", Value(2)}, {"value", Value(nonempty ? ValueList{Value("fixture")} : ValueList{})}}; };
  PlayerCoreTestAccess::Queue(core, generation, {{"type", Value("state")}, {"state", Value("marker")}});
  PlayerCoreTestAccess::Queue(core, generation, cue(true));
  PlayerCoreTestAccess::Queue(core, generation, {{"type", Value("state")}, {"state", Value("after")}});
  PlayerCoreTestAccess::Queue(core, generation, cue(false));
  events.received.clear(); Drain(core, events);
  Check(events.received.size() == 3 && Has(events.received[1], "name", Value("subtitle-cues")), "replace cue in place without duplicate");
  PlayerCoreTestAccess::Queue(core, generation, cue(true));
  for (int i = 0; i < 600; ++i) PlayerCoreTestAccess::Queue(core, generation, {{"type", Value("property")}, {"name", Value("time-pos")}});
  PlayerCoreTestAccess::Queue(core, generation, cue(false));
  for (int i = 0; i < 600; ++i) PlayerCoreTestAccess::Queue(core, generation, {{"type", Value("trackResult")}});
  events.received.clear(); Drain(core, events);
  Check(events.received.size() == 256 && std::count_if(events.received.begin(), events.received.end(), [](auto& event) { return Has(event, "name", Value("subtitle-cues")) && std::get<ValueList>(event.at("value")).empty(); }) == 1, "clear retained at capacity under mixed pressure");
  for (int i = 0; i < 64; ++i) {
    Reply play;
    Call(core, "play", play);
    Check(play.successes == 1, "fill generic command queue");
  }
  Reply full;
  Call(core, "play", full);
  Check(full.error == "command_queue_full", "generic queue really is saturated");
  Reply independent;
  Call(core, "setSubtitlePresentation", independent, {{"scale", Value(4)}, {"imageRaise", Value(0)}, {"lineupDrawsStyled", Value(false)}, {"future", Value(true)}});
  Check(independent.successes == 1, "presentation accepts integers and extra keys at queue capacity");
  lineup::player::SubtitleCoreTestAccess::Run(core);
  Reply load_after_failure;
  Call(core, "load", load_after_failure, {{"uri", Value("https://fixture.invalid/recovery")}, {"loadId", Value(3)}});
  lineup::player::SubtitleCoreTestAccess::Run(core);
  Start(core, 3);
  mpv_event ready{};
  ready.event_id = MPV_EVENT_FILE_LOADED;
  PlayerCoreTestAccess::Event(core, ready);
  events.received.clear(); Drain(core, events);
  Check(std::any_of(events.received.begin(), events.received.end(), [](auto& event) { return Has(event, "state", Value("playing")); }), "load still plays after subtitle property rejection");
  Reply pending;
  Call(core, "setSubtitlePresentation", pending, presentation(4));
  lineup::player::SubtitleCoreTestAccess::Dispose(core);
  Check(lineup::player::SubtitleCoreTestAccess::EmptySlot(core), "dispose clears pending slot");
  PlayerCoreTestAccess::CloseWorkerlessClient(core);
  fake = nullptr;
}

}  // namespace

int main() {
  FirstOpenEnvironment diagnostic_defaults(nullptr);
  FirstOpenProbeContract();
  SubtitleContract();
  CueSlotReservation();
  FakeMpv state;
  fake = &state;
  {
    FakeHost host;
    PlayerCore core(FakeOperations(), host);
    CorrelationAndPressure(core);
    Commands(core);
    SeekPolicyAndObservation(core);
    InitialJoinObservation(core);
    ReadinessPauseSnapshot(core);
    Validation(core);
  }
  InitializeFailures();
  Lifecycle();
  WakeupRetry();
  StaleWakeupAfterShutdown();
  PlatformArguments();
  fake = nullptr;
  return 0;
}
