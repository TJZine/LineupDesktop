#include "player_core/player_core.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>
#include <cstdlib>
#include <exception>
#include <iostream>
#include <iomanip>
#include <sstream>
#include <limits>
#include <type_traits>

#include "player_core/track_list_encoder.h"

namespace lineup::player {

namespace {

constexpr size_t kMaxQueuedEvents = 256;
constexpr size_t kMaxQueuedCommands = 64;
constexpr size_t kMaxQueuedCommandBytes = 128 * 1024;
constexpr size_t kMaxPlexTokenBytes = 8 * 1024;
constexpr size_t kMaxMetadataStringBytes = 4096;

enum PropertyId : uint64_t {
  kPause = 1,
  kTimePosition,
  kDuration,
  kTrackList,
  kVideoFormat,
  kVideoCodec,
  kCurrentVideoOutput,
  kHardwareDecoder,
  kVideoParameters,
  kVideoTargetParameters,
};

CallResult QueueFullError() {
  return CallResult::Failure("command_queue_full",
                             "The native command queue is full.");
}

// Volatile stores keep the compiler from removing a wipe of memory that is
// about to be freed.
void SecureWipe(char* data, size_t size) noexcept {
  volatile char* cursor = data;
  while (size-- > 0) {
    *cursor++ = 0;
  }
}

std::string UriScheme(std::string_view uri) {
  const size_t separator = uri.find(':');
  if (separator == std::string_view::npos || separator == 0) {
    return {};
  }
  return AsciiLower(std::string(uri.substr(0, separator)));
}

bool IsHttpsUri(std::string_view uri) {
  const size_t separator = uri.find(':');
  if (UriScheme(uri) != "https" || separator == std::string_view::npos ||
      uri.substr(separator, 3) != "://") {
    return false;
  }
  const size_t authority_start = separator + 3;
  const size_t authority_end = uri.find_first_of("/?#", authority_start);
  return authority_start < uri.size() && authority_end != authority_start;
}

bool IsValidPlexToken(std::string_view value) {
  if (value.empty() || value.size() > kMaxPlexTokenBytes) {
    return false;
  }
  for (const unsigned char byte : value) {
    if (byte < 0x21 || byte > 0x7e) {
      return false;
    }
  }
  return true;
}

constexpr bool EscapeMpvStringListByte(char value) {
  return value == '\\' || value == ',';
}

static_assert(!EscapeMpvStringListByte('a'));
static_assert(EscapeMpvStringListByte(','));
static_assert(EscapeMpvStringListByte('\\'));

constexpr bool IsHttpStatusSeparator(char value) {
  return value == ' ' || value == '\t' || value == '\r' || value == '\n' ||
         value == ':' || value == '=' || value == '-';
}

constexpr bool IsAsciiDigit(char value) {
  return value >= '0' && value <= '9';
}

constexpr std::optional<int64_t> ParseHttpErrorStatus(std::string_view text) {
  constexpr std::string_view marker = "http error";
  const size_t start = text.find(marker);
  if (start == std::string_view::npos) {
    return std::nullopt;
  }
  size_t cursor = start + marker.size();
  while (cursor < text.size() && IsHttpStatusSeparator(text[cursor])) {
    ++cursor;
  }
  const size_t digit_start = cursor;
  while (cursor < text.size() && IsAsciiDigit(text[cursor])) {
    ++cursor;
  }
  if (cursor - digit_start != 3 ||
      (text[digit_start] != '4' && text[digit_start] != '5')) {
    return std::nullopt;
  }
  return (text[digit_start] - '0') * 100 +
         (text[digit_start + 1] - '0') * 10 +
         (text[digit_start + 2] - '0');
}

static_assert(ParseHttpErrorStatus("http error: 404") == 404);
static_assert(ParseHttpErrorStatus("http error = 503") == 503);
static_assert(!ParseHttpErrorStatus("http error: 4040"));
static_assert(!ParseHttpErrorStatus("http error while opening; retry 503"));

// `osc` and `ytdl` only disable mpv's bundled Lua scripts, so a libmpv built
// without Lua (the macOS runtime) does not define them. A feature that is not
// compiled in is already disabled, so the core's "no" request for exactly
// these two options is satisfied when the option does not exist. Every other
// option failure, including any other value for these two, still fails
// initialization.
int DisablingOptionStatus(std::string_view name, std::string_view value,
                          int status) {
  if (status == MPV_ERROR_OPTION_NOT_FOUND && value == "no" &&
      (name == "osc" || name == "ytdl")) {
    return 0;
  }
  return status;
}

std::string PropertyString(const mpv_event_property& property) {
  if (property.format != MPV_FORMAT_STRING || !property.data) {
    return {};
  }
  const char* value = *static_cast<char**>(property.data);
  return BoundedUtf8(value, kMaxMetadataStringBytes);
}

ValueMap StateEvent(const char* state, const char* message,
                    std::optional<int64_t> load_id = std::nullopt) {
  ValueMap event = {
      {"type", Value("state")},
      {"state", Value(state)},
      {"message", Value(message)}};
  if (load_id) {
    event["loadId"] = Value(*load_id);
  }
  return event;
}

ValueMap FailureStateEvent(const std::string& code,
                           std::optional<int64_t> http_status,
                           std::optional<int64_t> load_id,
                           const char* message) {
  auto event = StateEvent("error", message, load_id);
  event["failureCode"] = Value(code);
  if (http_status) {
    event["httpStatus"] = Value(*http_status);
  }
  return event;
}

struct ClassifiedFailure {
  std::string code;
  std::optional<int64_t> http_status;
};

std::optional<ClassifiedFailure> ClassifyMpvFailure(
    const mpv_event_log_message& message) {
  const std::string prefix =
      AsciiLower(BoundedUtf8(message.prefix, kMaxMetadataStringBytes));
  const std::string text =
      AsciiLower(BoundedUtf8(message.text, kMaxMetadataStringBytes));
  const auto contains = [&](const char* value) {
    return text.find(value) != std::string::npos;
  };
  if (const size_t start = text.find("http error");
      start != std::string::npos) {
    if (const auto status = ParseHttpErrorStatus(text)) {
      return ClassifiedFailure{"http_error", status};
    }
    return ClassifiedFailure{"http_error", std::nullopt};
  }
  if (contains("connection refused") || contains("connection timed out") ||
      contains("network is unreachable") || contains("failed to resolve") ||
      contains("tls") || contains("certificate")) {
    return ClassifiedFailure{"network_error", std::nullopt};
  }
  if (contains("audio") &&
      (contains("decode") || contains("decoder") || contains("codec"))) {
    return ClassifiedFailure{"audio_decode_error", std::nullopt};
  }
  if (contains("video") &&
      (contains("decode") || contains("decoder") || contains("codec"))) {
    return ClassifiedFailure{"video_decode_error", std::nullopt};
  }
  if (prefix.rfind("ao/", 0) == 0 || contains("audio output")) {
    return ClassifiedFailure{"audio_output_error", std::nullopt};
  }
  if (prefix.rfind("vo/", 0) == 0 || contains("video output")) {
    return ClassifiedFailure{"video_output_error", std::nullopt};
  }
  if (contains("failed to open") || contains("cannot open") ||
      contains("could not open")) {
    return ClassifiedFailure{"source_open_error", std::nullopt};
  }
  if (prefix.find("demux") != std::string::npos ||
      contains("demuxer") || contains("invalid data found")) {
    return ClassifiedFailure{"container_error", std::nullopt};
  }
  return std::nullopt;
}

// This probe has no string-valued output interface. Raw mpv messages only
// select finite enums; URI/header/path-bearing text can never reach the sink.
enum class ProbeModule { core, curl, ffmpeg, demux, stream, audio_output, video_output, unknown };
enum class ProbeCause {
  accepted, opening, ready, end_error, end_error_unknown, end_stopped,
  end_eof, end_other, playlist_redirect, stop_accepted,
  dns, connect, tls, redirect_limit, range, container, http, timeout, unknown,
};

const char* ProbeName(ProbeModule module) {
  switch (module) {
    case ProbeModule::core: return "core";
    case ProbeModule::curl: return "curl";
    case ProbeModule::ffmpeg: return "ffmpeg";
    case ProbeModule::demux: return "demux";
    case ProbeModule::stream: return "stream";
    case ProbeModule::audio_output: return "audio_output";
    case ProbeModule::video_output: return "video_output";
    case ProbeModule::unknown: return "unknown";
  }
  return "unknown";
}

const char* ProbeName(ProbeCause cause) {
  switch (cause) {
    case ProbeCause::accepted: return "accepted";
    case ProbeCause::opening: return "opening";
    case ProbeCause::ready: return "ready";
    case ProbeCause::end_error: return "end_error";
    case ProbeCause::end_error_unknown: return "end_error_unknown";
    case ProbeCause::end_stopped: return "end_stopped";
    case ProbeCause::end_eof: return "end_eof";
    case ProbeCause::end_other: return "end_other";
    case ProbeCause::playlist_redirect: return "playlist_redirect";
    case ProbeCause::stop_accepted: return "stop_accepted";
    case ProbeCause::dns: return "dns";
    case ProbeCause::connect: return "connect";
    case ProbeCause::tls: return "tls";
    case ProbeCause::redirect_limit: return "redirect_limit";
    case ProbeCause::range: return "range";
    case ProbeCause::container: return "container";
    case ProbeCause::http: return "http";
    case ProbeCause::timeout: return "timeout";
    case ProbeCause::unknown: return "unknown";
  }
  return "unknown";
}

ProbeModule ProbeModuleFor(std::string_view prefix) {
  if (prefix == "curl" || prefix == "stream/curl") return ProbeModule::curl;
  if (prefix == "ffmpeg" || prefix == "ffmpeg/demuxer" ||
      prefix == "ffmpeg/video" || prefix == "ffmpeg/audio") return ProbeModule::ffmpeg;
  if (prefix == "demux" || prefix == "demuxer") return ProbeModule::demux;
  if (prefix == "stream") return ProbeModule::stream;
  if (prefix == "ao/coreaudio" || prefix == "ao") return ProbeModule::audio_output;
  if (prefix == "vo/gpu-next" || prefix == "vo") return ProbeModule::video_output;
  return ProbeModule::unknown;
}

ProbeCause ProbeCauseFor(const std::string& text) {
  const auto has = [&](const char* phrase) { return text.find(phrase) != std::string::npos; };
  if (ParseHttpErrorStatus(text)) return ProbeCause::http;
  if (has("could not resolve") || has("couldn't resolve") || has("failed to resolve") ||
      has("name or service not known")) return ProbeCause::dns;
  if (has("could not connect") || has("failed to connect") || has("connection refused") ||
      has("network is unreachable")) return ProbeCause::connect;
  if (has("tls error") || has("tls handshake") || has("certificate verification") ||
      has("certificate verify") || has("ssl connect error") || has("ssl handshake")) return ProbeCause::tls;
  if (has("too many redirects") || has("maximum redirects") ||
      has("number of redirects hit") || has("redirect limit")) return ProbeCause::redirect_limit;
  if (has("range request") || has("requested range") || has("range not satisfiable") ||
      has("unexpected reply with offset")) return ProbeCause::range;
  if (has("demuxer") || has("invalid data found") ||
      has("failed to recognize file format")) return ProbeCause::container;
  if (has("timed out") || has("timeout")) return ProbeCause::timeout;
  return ProbeCause::unknown;
}

bool ProbeErrorInRange(int error) { return error >= -128 && error <= 0; }

void WriteFirstOpenProbe(ProbeModule module, ProbeCause cause,
                         std::optional<int> error = std::nullopt,
                         std::optional<int64_t> http = std::nullopt) {
  std::ostringstream line;
  line << "[lineup-first-open] module=" << ProbeName(module) << " cause=" << ProbeName(cause);
  if (error && ProbeErrorInRange(*error)) line << " mpv_error=" << *error;
  if (http && *http >= 100 && *http <= 599) line << " http_status=" << *http;
  line << '\n';
  std::cerr << line.str();
}

bool FirstOpenProbeEnabled() {
#ifdef _WIN32
  char* value = nullptr;
  size_t size = 0;
  if (_dupenv_s(&value, &size, "LINEUP_FIRST_OPEN_DIAGNOSTICS") != 0) return false;
  const bool enabled = value && std::strcmp(value, "1") == 0;
  std::free(value);
  return enabled;
#else
  const auto* value = std::getenv("LINEUP_FIRST_OPEN_DIAGNOSTICS");
  return value && std::strcmp(value, "1") == 0;
#endif
}

// Wipes a converted token argument when the call returns, on every path. The
// platform codec's own decoded copy is outside the core's control.
class TokenArgumentScrubber {
 public:
  explicit TokenArgumentScrubber(ValueMap* arguments) : arguments_(arguments) {}
  ~TokenArgumentScrubber() {
    if (!arguments_) {
      return;
    }
    const auto token = arguments_->find("plexToken");
    if (token == arguments_->end()) {
      return;
    }
    if (auto* text = std::get_if<std::string>(&token->second)) {
      SecureWipe(text->data(), text->size());
    }
  }

  TokenArgumentScrubber(const TokenArgumentScrubber&) = delete;
  TokenArgumentScrubber& operator=(const TokenArgumentScrubber&) = delete;

 private:
  ValueMap* arguments_;
};

}  // namespace

PlayerCore::PlexHeader::PlexHeader(std::string_view token) {
  constexpr std::string_view prefix = "X-Plex-Token: ";
  const size_t escapes = static_cast<size_t>(
      std::count_if(token.begin(), token.end(), EscapeMpvStringListByte));
  size_ = prefix.size() + token.size() + escapes;
  data_ = std::make_unique<char[]>(size_ + 1);
  char* output = data_.get();
  std::memcpy(output, prefix.data(), prefix.size());
  output += prefix.size();
  for (const char byte : token) {
    if (EscapeMpvStringListByte(byte)) {
      *output++ = '\\';
    }
    *output++ = byte;
  }
  *output = '\0';
}

PlayerCore::PlexHeader::~PlexHeader() {
  Clear();
}

PlayerCore::PlexHeader::PlexHeader(PlexHeader&& other) noexcept
    : data_(std::move(other.data_)), size_(std::exchange(other.size_, 0)) {}

PlayerCore::PlexHeader& PlayerCore::PlexHeader::operator=(
    PlexHeader&& other) noexcept {
  if (this != &other) {
    Clear();
    data_ = std::move(other.data_);
    size_ = std::exchange(other.size_, 0);
  }
  return *this;
}

void PlayerCore::PlexHeader::Clear() noexcept {
  if (data_) {
    SecureWipe(data_.get(), size_);
    data_.reset();
    size_ = 0;
  }
}

PlayerCore::PlayerCore(MpvOperations mpv_operations, CoreHost& host)
    : mpv_operations_(mpv_operations), host_(host),
      first_open_diagnostics_(FirstOpenProbeEnabled()) {}

PlayerCore::~PlayerCore() {
  Shutdown();
}

CallResult PlayerCore::Initialize() {
  const auto initialized = [this] {
    ValueMap details{
        {"clientApiVersion",
         Value(static_cast<int64_t>(mpv_operations_.client_api_version()))}};
    return CallResult::Success(Value(std::move(details)));
  };
  if (accepting_commands_) {
    return initialized();
  }
  if (event_thread_.joinable()) {
    return CallResult::Failure("initialize_failed",
                               "The native player has already been disposed.");
  }

  OutputConfig output;
  if (auto error = host_.PrepareOutput(output)) {
    return CallResult{std::move(error), {}};
  }

  mpv_ = mpv_operations_.create();
  if (!mpv_) {
    host_.CancelOutput();
    return CallResult::Failure("initialize_failed",
                               "libmpv could not create a client.");
  }

  int option_status = 0;
  if (output.window_id) {
    int64_t window_id = *output.window_id;
    option_status = mpv_operations_.set_option(mpv_, "wid", MPV_FORMAT_INT64,
                                               &window_id);
  }
  const std::pair<const char*, const char*> core_options[] = {
      {"config", "no"},
      {"terminal", "no"},
      {"input-default-bindings", "no"},
      {"input-vo-keyboard", "no"},
      {"input-media-keys", "no"},
      {"osc", "no"},
      {"ytdl", "no"},
      {"tls-verify", "yes"},
      {"access-references", "no"},
      {"autoload-files", "no"},
      {"idle", "yes"},
      {"keep-open", "no"},
  };
  for (const auto& [name, value] : core_options) {
    if (option_status >= 0) {
      option_status = DisablingOptionStatus(
          name, value, mpv_operations_.set_option_string(mpv_, name, value));
    }
  }
  for (const auto& [name, value] : output.options) {
    if (option_status >= 0) {
      option_status =
          mpv_operations_.set_option_string(mpv_, name.c_str(), value.c_str());
    }
  }
  if (option_status >= 0) {
    option_status = mpv_operations_.set_option_string(mpv_, "hwdec", "auto");
  }
  const int initialize_status =
      option_status < 0 ? option_status : mpv_operations_.initialize(mpv_);
  if (initialize_status < 0) {
    std::string error = std::string("libmpv initialization failed: ") +
                        mpv_operations_.error_string(initialize_status);
    mpv_operations_.terminate_destroy(mpv_);
    mpv_ = nullptr;
    host_.CancelOutput();
    return CallResult::Failure("initialize_failed", std::move(error));
  }
  std::cerr << "[lineup-player] libmpv initialized client-api="
            << mpv_operations_.client_api_version() << std::endl;
  mpv_operations_.request_log_messages(mpv_, "error");

  struct Observation {
    uint64_t id;
    const char* name;
    mpv_format format;
  };
  const Observation observations[] = {
      {kPause, "pause", MPV_FORMAT_FLAG},
      {kTimePosition, "time-pos", MPV_FORMAT_DOUBLE},
      {kDuration, "duration", MPV_FORMAT_DOUBLE},
      {kTrackList, "track-list", MPV_FORMAT_NODE},
      {kVideoFormat, "video-format", MPV_FORMAT_STRING},
      {kVideoCodec, "video-codec", MPV_FORMAT_STRING},
      {kCurrentVideoOutput, "current-vo", MPV_FORMAT_STRING},
      {kHardwareDecoder, "hwdec-current", MPV_FORMAT_STRING},
      {kVideoParameters, "video-params", MPV_FORMAT_NODE},
      {kVideoTargetParameters, "video-target-params", MPV_FORMAT_NODE},
  };
  for (const auto& observation : observations) {
    const int observe_status = mpv_operations_.observe_property(
        mpv_, observation.id, observation.name, observation.format);
    if (observe_status < 0) {
      std::string error = std::string("libmpv property observation failed for ") +
                          observation.name + ": " +
                          mpv_operations_.error_string(observe_status);
      mpv_operations_.terminate_destroy(mpv_);
      mpv_ = nullptr;
      host_.CancelOutput();
      return CallResult::Failure("initialize_failed", std::move(error));
    }
  }

  const uint64_t generation = generation_.fetch_add(1) + 1;
  disposed_ = false;
  shutdown_started_ = false;
  stopping_ = false;
  worker_finished_ = false;
  accepting_commands_ = true;
  StartEventThread();
  QueueEvent(generation, StateEvent("idle", "Native libmpv player ready"));
  return initialized();
}

void PlayerCore::Dispose(Reply reply) {
  if (disposed_) {
    reply(CallResult::Success());
    return;
  }
  if (dispose_reply_) {
    reply(CallResult::Failure("dispose_in_progress",
                              "Native player disposal is already in progress."));
    return;
  }
  dispose_reply_ = std::move(reply);
  BeginDispose();
}

void PlayerCore::BeginDispose() {
  host_.OnDisposeRequested();
  if (disposed_ || shutdown_started_) {
    return;
  }
  shutdown_started_ = true;
  std::cerr << "[lineup-player] native shutdown requested" << std::endl;
  generation_.fetch_add(1);
  accepting_commands_ = false;
  stopping_ = true;
}

void PlayerCore::ProcessWakeup(const EventSink& deliver) {
  DrainEvents(deliver);
  if (dispose_ready_.exchange(false)) {
    std::cerr << "[lineup-player] finishing native shutdown" << std::endl;
    if (event_thread_.joinable()) {
      event_thread_.join();
    }
    FinishDispose();
    disposed_ = true;
    shutdown_started_ = false;
    if (dispose_reply_) {
      dispose_reply_(CallResult::Success());
      dispose_reply_ = nullptr;
    }
  }
}

void PlayerCore::Shutdown() {
  if (!disposed_) {
    BeginDispose();
    const auto deadline = std::chrono::steady_clock::now() +
                          std::chrono::seconds(5);
    while (!worker_finished_ && std::chrono::steady_clock::now() < deadline) {
      std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    if (!worker_finished_) {
      std::terminate();
    }
    StopEventThread();
    FinishDispose();
    disposed_ = true;
    shutdown_started_ = false;
    // The worker set this before posting its finished wakeup. Disposal is
    // complete here, so that wakeup, delivered later, must not finish it
    // again or join a worker started by a later Initialize.
    dispose_ready_ = false;
  }
  dispose_reply_ = nullptr;
}

void PlayerCore::FinishDispose() {
  host_.ReleaseOutput();
  {
    std::lock_guard lock(command_mutex_);
    commands_.clear();
    queued_command_bytes_ = 0;
  }
  {
    std::lock_guard lock(event_mutex_);
    events_.clear();
    wakeup_posted_ = false;
  }
  playback_.Reset();
  first_open_probe_ = {};
  ResetSeekObservation();
}

std::optional<CallResult> PlayerCore::HandleCommand(std::string_view method,
                                                    ValueMap* arguments) {
  // Established before any return so that no rejection path, including
  // not_initialized, leaves the converted token behind.
  const TokenArgumentScrubber scrubber(arguments);
  if (!accepting_commands_) {
    return CallResult::Failure("not_initialized",
                               "The native player is not initialized.");
  }
  if (method == "load") {
    return HandleLoad(arguments);
  }
  if (method == "play") {
    if (!QueueCommand(PlayCommand{})) {
      return QueueFullError();
    }
    return CallResult::Success();
  }
  if (method == "pause") {
    if (!QueueCommand(PauseCommand{})) {
      return QueueFullError();
    }
    return CallResult::Success();
  }
  if (method == "seek") {
    const auto seconds = arguments ? AsNumber(Find(*arguments, "seconds"))
                                   : std::nullopt;
    if (!seconds || !std::isfinite(*seconds) || *seconds < 0) {
      return CallResult::Failure("invalid_argument",
                                 "Seek seconds must be non-negative.");
    }
    const auto* mode_value = Find(*arguments, "mode");
    const auto* mode = mode_value ? std::get_if<std::string>(mode_value) : nullptr;
    if (mode_value && (!mode || (*mode != "exact" && *mode != "keyframes"))) {
      return CallResult::Failure("invalid_argument", "Seek mode must be exact or keyframes.");
    }
    const SeekMode seek_mode = mode && *mode == "keyframes"
                                   ? SeekMode::keyframes : SeekMode::exact;
    if (!QueueCommand(SeekCommand{*seconds, seek_mode})) {
      return QueueFullError();
    }
    return CallResult::Success();
  }
  if (method == "stop") {
    const auto stop_id = arguments ? AsInt(Find(*arguments, "stopId"))
                                   : std::nullopt;
    if (!stop_id || *stop_id <= 0) {
      return CallResult::Failure("invalid_argument",
                                 "A positive integer stopId is required.");
    }
    if (!QueueCommand(StopCommand{*stop_id})) {
      return QueueFullError();
    }
    return CallResult::Success();
  }
  if (method == "selectTrack") {
    if (!arguments) {
      return CallResult::Failure("invalid_argument",
                                 "Track selection is required.");
    }
    auto command = ParseTrack(*arguments);
    if (!command) {
      return CallResult::Failure(
          "invalid_argument",
          "A valid track, loadId, and requestId are required.");
    }
    if (!QueueCommand(std::move(*command))) {
      return QueueFullError();
    }
    return CallResult::Success();
  }
  if (method == "setVolume") {
    const auto volume = arguments ? AsNumber(Find(*arguments, "volume"))
                                  : std::nullopt;
    if (!volume || !std::isfinite(*volume) || *volume < 0 || *volume > 100) {
      return CallResult::Failure("invalid_argument",
                                 "Volume must be between 0 and 100.");
    }
    if (!QueueCommand(VolumeCommand{*volume})) {
      return QueueFullError();
    }
    return CallResult::Success();
  }
  return std::nullopt;
}

CallResult PlayerCore::HandleLoad(ValueMap* arguments) {
  const auto* uri = FindString(arguments, "uri");
  const auto load_id =
      arguments ? AsInt(Find(*arguments, "loadId")) : std::nullopt;
  if (!uri || uri->empty() || uri->size() > 32768) {
    return CallResult::Failure("invalid_argument",
                               "A bounded media URI is required.");
  }
  if (!load_id || *load_id < 0) {
    return CallResult::Failure("invalid_argument",
                               "A non-negative integer loadId is required.");
  }
  const auto* token_value = Find(*arguments, "plexToken");
  const bool token_supplied =
      token_value && !std::holds_alternative<std::monostate>(*token_value);
  const auto* plex_token = FindString(arguments, "plexToken");
  if (token_supplied &&
      (!plex_token || !IsValidPlexToken(*plex_token))) {
    return CallResult::Failure("invalid_argument", "The Plex token is invalid.");
  }
  if (plex_token && !IsHttpsUri(*uri)) {
    return CallResult::Failure(
        "insecure_media_uri",
        "Plex authentication requires an HTTPS media URI.");
  }
  LoadCommand command{*load_id, *uri, {}};
  if (Find(*arguments, "startPaused")) {
    const auto* paused = FindBool(arguments, "startPaused");
    if (!paused) {
      return CallResult::Failure("invalid_argument",
                                 "startPaused must be a boolean.");
    }
    command.start_paused = *paused;
  }
  if (const auto* start = Find(*arguments, "startSeconds")) {
    const auto seconds = AsNumber(start);
    if (!seconds || !std::isfinite(*seconds) || *seconds < 0) {
      return CallResult::Failure("invalid_argument",
                                 "startSeconds must be finite and non-negative.");
    }
    command.start_seconds = *seconds;
  }
  if (plex_token) {
    command.plex_header = PlexHeader(*plex_token);
  }
  if (!QueueCommand(std::move(command))) {
    return QueueFullError();
  }
  return CallResult::Success();
}

std::optional<PlayerCore::TrackCommand> PlayerCore::ParseTrack(
    const ValueMap& arguments) {
  const auto* type = FindString(&arguments, "type");
  if (!type) {
    return std::nullopt;
  }
  const char* property =
      *type == "video" ? "vid" : *type == "audio" ? "aid" :
      *type == "subtitle" ? "sid" : nullptr;
  if (!property) {
    return std::nullopt;
  }
  const auto load_id = AsInt(Find(arguments, "loadId"));
  const auto request_id = AsInt(Find(arguments, "requestId"));
  if (!load_id || *load_id <= 0 || !request_id || *request_id <= 0) {
    return std::nullopt;
  }
  const auto* id_value = Find(arguments, "id");
  if (!id_value || std::holds_alternative<std::monostate>(*id_value)) {
    return TrackCommand{*load_id, *request_id, property, std::nullopt};
  }
  const auto* id = std::get_if<int64_t>(id_value);
  if (!id || *id <= 0) {
    return std::nullopt;
  }
  return TrackCommand{*load_id, *request_id, property, *id};
}

void PlayerCore::StartEventThread() {
  const uint64_t generation = generation_.load();
  event_thread_ = std::thread([this, generation] { EventLoop(generation); });
}

bool PlayerCore::QueueCommand(QueuedCommand command) {
  std::lock_guard lock(command_mutex_);
  const size_t command_bytes = std::visit([](const auto& payload) -> size_t {
    using Payload = std::decay_t<decltype(payload)>;
    if constexpr (std::is_same_v<Payload, LoadCommand>) {
      if (payload.uri.size() > kMaxQueuedCommandBytes ||
          payload.plex_header.size() > kMaxQueuedCommandBytes - payload.uri.size()) {
        return kMaxQueuedCommandBytes + 1;
      }
      return payload.uri.size() + payload.plex_header.size();
    } else if constexpr (std::is_same_v<Payload, TrackCommand>) {
      return payload.property.size();
    } else {
      return 0;
    }
  }, command);
  if (!accepting_commands_ || commands_.size() >= kMaxQueuedCommands ||
      queued_command_bytes_ > kMaxQueuedCommandBytes ||
      command_bytes > kMaxQueuedCommandBytes - queued_command_bytes_) {
    return false;
  }
  queued_command_bytes_ += command_bytes;
  commands_.push_back(std::move(command));
  return true;
}

void PlayerCore::RunCommand(QueuedCommand& command, uint64_t generation) {
  int status = 0;
  std::visit([&](auto& payload) {
    using Payload = std::decay_t<decltype(payload)>;
    if constexpr (std::is_same_v<Payload, LoadCommand>) {
      if (first_open_diagnostics_) first_open_probe_ = {};
      ResetSeekObservation();
      int paused = payload.start_paused ? 1 : 0;
      status =
          mpv_operations_.set_property(mpv_, "pause", MPV_FORMAT_FLAG, &paused);
      if (status >= 0) {
        if (payload.plex_header.empty() && !payload.start_seconds) {
          const char* value[] = {"loadfile", payload.uri.c_str(), "replace",
                                 nullptr};
          status = mpv_operations_.command(mpv_, value);
        } else {
          char* command_name = const_cast<char*>("loadfile");
          char* uri = const_cast<char*>(payload.uri.c_str());
          char* flags = const_cast<char*>("replace");
          mpv_node values[5]{};
          values[0].format = MPV_FORMAT_STRING;
          values[0].u.string = command_name;
          values[1].format = MPV_FORMAT_STRING;
          values[1].u.string = uri;
          values[2].format = MPV_FORMAT_STRING;
          values[2].u.string = flags;
          values[3].format = MPV_FORMAT_INT64;
          values[3].u.int64 = -1;
          values[4].format = MPV_FORMAT_NODE_MAP;
          // String per-file options share one map. Never append options or
          // authentication material to the media URI.
          mpv_node option_values[4]{};
          char* option_keys[4]{};
          int option_count = 0;
          auto option = [&](const char* key, char* value) {
            option_keys[option_count] = const_cast<char*>(key);
            option_values[option_count].format = MPV_FORMAT_STRING;
            option_values[option_count++].u.string = value;
          };
          if (!payload.plex_header.empty()) {
            // mpv reuses custom headers on redirects; authenticated loads
            // must remain on their original HTTPS request.
            option("http-header-fields", payload.plex_header.data());
            option("curl-max-redirects", const_cast<char*>("0"));
          }
          std::string start;
          if (payload.start_seconds) {
            std::ostringstream seconds;
            seconds << std::setprecision(std::numeric_limits<double>::max_digits10)
                    << *payload.start_seconds;
            start = seconds.str();
            option("start", start.data());
            // mpv's initial absolute seek uses default precision. Explicit
            // absolute+exact commands still override this per-file setting.
            option("hr-seek", const_cast<char*>("no"));
          }
          mpv_node_list option_list{option_count, option_values, option_keys};
          values[4].u.list = &option_list;
          mpv_node_list command_list{5, values, nullptr};
          mpv_node command_node{};
          command_node.format = MPV_FORMAT_NODE_ARRAY;
          command_node.u.list = &command_list;
          status = mpv_operations_.command_node(mpv_, &command_node, nullptr);
        }
        if (status >= 0) {
          int64_t playlist_entry_id = 0;
          const bool has_playlist_id =
              mpv_operations_.get_property(mpv_, "playlist/0/id", MPV_FORMAT_INT64,
                                           &playlist_entry_id) >= 0;
          if (!playback_.AcceptLoad(payload.load_id,
                  has_playlist_id ? std::optional<int64_t>(playlist_entry_id)
                                  : std::nullopt)) {
            QueueEvent(generation,
                FailureStateEvent("correlation_error", std::nullopt,
                                  payload.load_id,
                                  "Playback correlation exceeded native limits"));
          } else {
            if (first_open_diagnostics_) {
              first_open_probe_ = FirstOpenProbe{payload.load_id};
              WriteFirstOpenProbe(ProbeModule::core, ProbeCause::accepted);
            }
            if (payload.start_seconds) {
              seek_observation_ = SeekObservation{
                  payload.load_id, *payload.start_seconds, SeekMode::keyframes,
                  SeekObservationPhase::load_start,
                  std::chrono::steady_clock::now() + std::chrono::seconds(10)};
            }
          }
        }
      }
    } else if constexpr (std::is_same_v<Payload, PlayCommand>) {
      int paused = 0;
      status =
          mpv_operations_.set_property(mpv_, "pause", MPV_FORMAT_FLAG, &paused);
    } else if constexpr (std::is_same_v<Payload, PauseCommand>) {
      int paused = 1;
      status =
          mpv_operations_.set_property(mpv_, "pause", MPV_FORMAT_FLAG, &paused);
    } else if constexpr (std::is_same_v<Payload, SeekCommand>) {
      std::ostringstream seconds_stream;
      seconds_stream << std::setprecision(std::numeric_limits<double>::max_digits10)
                     << payload.seconds;
      const std::string seconds = seconds_stream.str();
      const char* flags = payload.mode == SeekMode::keyframes
                              ? "absolute+keyframes" : "absolute+exact";
      const char* value[] = {"seek", seconds.c_str(), flags, nullptr};
      status = mpv_operations_.command(mpv_, value);
      // Passive observation only. Overlapping commands have no libmpv request
      // IDs, so suppress their landing samples for this load instead of
      // attributing an older restart to the newest target.
      if (seek_observation_) {
        seek_observation_.reset();
        seek_observation_ambiguous_ = true;
      }
      const auto load = playback_.active_load();
      if (status >= 0 && !seek_observation_ambiguous_ && load &&
          playback_.event_load() == load) {
        seek_observation_ = SeekObservation{
            *load, payload.seconds, payload.mode, SeekObservationPhase::seek_start,
            std::chrono::steady_clock::now() + std::chrono::seconds(10)};
      }
    } else if constexpr (std::is_same_v<Payload, StopCommand>) {
      ResetSeekObservation();
      const char* value[] = {"stop", nullptr};
      status = mpv_operations_.command(mpv_, value);
      if (status < 0) {
        QueueStopResult(generation, payload.stop_id, false);
      } else {
        playback_.AcceptStop(payload.stop_id);
        if (first_open_diagnostics_ && first_open_probe_.load_id &&
            (first_open_probe_.load_id == playback_.active_load() ||
             (first_open_probe_.ended && !playback_.active_load())) &&
            !first_open_probe_.stop_reported) {
          first_open_probe_.stop_reported = true;
          WriteFirstOpenProbe(ProbeModule::core, ProbeCause::stop_accepted);
        }
      }
      return;
    } else if constexpr (std::is_same_v<Payload, TrackCommand>) {
      if (!playback_.TrackTargetsActiveLoad(payload.load_id)) {
        QueueTrackResult(generation, payload.load_id,
                         payload.request_id, false);
        return;
      }
      if (!payload.selection_id) {
        status = mpv_operations_.set_property_string(
            mpv_, payload.property.c_str(), "no");
      } else {
        int64_t id = *payload.selection_id;
        status = mpv_operations_.set_property(
            mpv_, payload.property.c_str(), MPV_FORMAT_INT64, &id);
      }
      QueueTrackResult(generation, payload.load_id, payload.request_id,
                       status >= 0);
      return;
    } else if constexpr (std::is_same_v<Payload, VolumeCommand>) {
      double volume = payload.volume;
      status =
          mpv_operations_.set_property(mpv_, "volume", MPV_FORMAT_DOUBLE, &volume);
    }
  }, command);
  if (std::holds_alternative<StopCommand>(command) ||
      std::holds_alternative<TrackCommand>(command)) return;
  if (status < 0) {
    const auto* load = std::get_if<LoadCommand>(&command);
    const std::optional<int64_t> error_load_id =
        load ? std::optional<int64_t>(load->load_id) : playback_.active_load();
    // This error need not populate playback_.failure(). A later restart
    // cannot be attributed safely after the published command failure.
    seek_observation_.reset();
    seek_observation_ambiguous_ = true;
    QueueEvent(generation,
               FailureStateEvent("command_error", std::nullopt,
                                 error_load_id,
                                 mpv_operations_.error_string(status)));
  }
}

void PlayerCore::StopEventThread() {
  stopping_ = true;
  if (event_thread_.joinable()) {
    event_thread_.join();
  }
}

void PlayerCore::EventLoop(uint64_t generation) {
  while (!stopping_) {
    if (!wakeup_posted_) {
      bool has_events = false;
      {
        std::lock_guard lock(event_mutex_);
        has_events = !events_.empty();
      }
      if (has_events) {
        RequestWakeup();
      }
    }
    std::deque<QueuedCommand> commands;
    {
      std::lock_guard lock(command_mutex_);
      std::swap(commands, commands_);
      queued_command_bytes_ = 0;
    }
    for (auto& command : commands) {
      RunCommand(command, generation);
      if (auto* load = std::get_if<LoadCommand>(&command)) {
        load->plex_header.Clear();
      }
    }
    if (playback_.pending_stop()) {
      int idle = 0;
      int64_t playlist_count = -1;
      if (mpv_operations_.get_property(mpv_, "idle-active", MPV_FORMAT_FLAG,
                                       &idle) >= 0 &&
          mpv_operations_.get_property(mpv_, "playlist-count", MPV_FORMAT_INT64,
                                       &playlist_count) >= 0) {
        if (const auto stop = playback_.ObserveIdle(idle != 0, playlist_count)) {
          QueueStopResult(generation, *stop, true);
        }
      }
    }
    const mpv_event* event = mpv_operations_.wait_event(mpv_, 0.05);
    if (stopping_) {
      break;
    }
    if (event && event->event_id != MPV_EVENT_NONE) {
      HandleMpvEvent(*event, generation);
    }
  }
  mpv_operations_.terminate_destroy(mpv_);
  mpv_ = nullptr;
  std::cerr << "[lineup-player] libmpv shutdown complete" << std::endl;
  dispose_ready_ = true;
  host_.PostWorkerFinished();
  worker_finished_ = true;
}

void PlayerCore::ResetSeekObservation() {
  seek_observation_.reset();
  seek_observation_ambiguous_ = false;
}

void PlayerCore::ObserveSeekLanding(mpv_event_id event) {
  if (!seek_observation_) return;
  auto& sample = *seek_observation_;
  if (std::chrono::steady_clock::now() > sample.deadline ||
      playback_.active_load() != sample.load_id) {
    seek_observation_.reset();
    seek_observation_ambiguous_ = true;
    return;
  }
  // A new load can have older events queued ahead of its START_FILE. Neither
  // those events nor a pre-FILE_LOADED restart open its observation window.
  if (sample.phase == SeekObservationPhase::load_start) return;
  if (playback_.event_load() != sample.load_id) {
    seek_observation_.reset();
    seek_observation_ambiguous_ = true;
    return;
  }
  if (event == MPV_EVENT_FILE_LOADED) {
    if (sample.phase == SeekObservationPhase::file_loaded) {
      sample.phase = SeekObservationPhase::initial_restart;
    }
    return;
  }
  if (sample.phase == SeekObservationPhase::file_loaded) return;
  if (event == MPV_EVENT_SEEK) {
    if (sample.phase == SeekObservationPhase::seek_restart) {
      seek_observation_.reset();
      seek_observation_ambiguous_ = true;
    } else {
      sample.phase = SeekObservationPhase::seek_restart;
    }
    return;
  }
  if (sample.phase == SeekObservationPhase::seek_start) return;
  double position = 0;
  int seeking = 1;
  if (mpv_operations_.get_property(mpv_, "seeking", MPV_FORMAT_FLAG, &seeking) >= 0 &&
      !seeking &&
      mpv_operations_.get_property(mpv_, "time-pos", MPV_FORMAT_DOUBLE, &position) >= 0 &&
      std::isfinite(position) && position >= 0) {
    std::ostringstream line;
    line << std::fixed << std::setprecision(6)
         << "[lineup-player] seek landing loadId=" << sample.load_id
         << " mode=" << (sample.mode == SeekMode::keyframes ? "keyframes" : "exact")
         << " target=" << sample.target << " observed=" << position
         << " offset=" << position - sample.target << '\n';
    std::cerr << line.str();
  }
  seek_observation_.reset();
}

void PlayerCore::HandleMpvEvent(const mpv_event& event, uint64_t generation) {
  switch (event.event_id) {
    case MPV_EVENT_START_FILE: {
      const auto* start = static_cast<mpv_event_start_file*>(event.data);
      const auto transition = playback_.StartFile(
          start ? std::optional<int64_t>(start->playlist_entry_id) : std::nullopt);
      if (first_open_diagnostics_ && first_open_probe_.load_id &&
          first_open_probe_.load_id == playback_.event_load() &&
          first_open_probe_.load_id == playback_.active_load() &&
          !first_open_probe_.opening && !first_open_probe_.ended) {
        first_open_probe_.opening = true;
        WriteFirstOpenProbe(ProbeModule::core, ProbeCause::opening);
      }
      if (seek_observation_) {
        if (seek_observation_->phase == SeekObservationPhase::load_start) {
          if (playback_.event_load() == seek_observation_->load_id &&
              playback_.active_load() == seek_observation_->load_id) {
            seek_observation_->phase = SeekObservationPhase::file_loaded;
          }
        } else {
          seek_observation_.reset();
          seek_observation_ambiguous_ = true;
        }
      }
      if (!transition.within_capacity) {
        QueueEvent(generation,
            FailureStateEvent("correlation_error", std::nullopt,
                              transition.rejected_load,
                              "Playback correlation exceeded native limits"));
      }
      QueueEvent(generation,
                 StateEvent("loading", "Loading media", playback_.event_load()));
      break;
    }
    case MPV_EVENT_FILE_LOADED: {
      if (first_open_diagnostics_ && first_open_probe_.load_id &&
          first_open_probe_.load_id == playback_.event_load() &&
          first_open_probe_.load_id == playback_.active_load() &&
          !first_open_probe_.ready && !first_open_probe_.ended) {
        first_open_probe_.ready = true;
        WriteFirstOpenProbe(ProbeModule::core, ProbeCause::ready);
      }
      int observed_pause = -1;
      if (mpv_operations_.get_property(mpv_, "pause", MPV_FORMAT_FLAG,
                                       &observed_pause) < 0) {
        observed_pause = -1;
      }
      ObserveSeekLanding(event.event_id);
      auto ready = StateEvent("playing", "Playing", playback_.event_load());
      // A load hold can pause and resume before mpv emits another observed
      // property change. Publish the current flag atomically with readiness,
      // rather than leaving Dart to infer it from the requested load intent.
      if (observed_pause >= 0) ready["paused"] = Value(observed_pause != 0);
      QueueEvent(generation, std::move(ready));
      break;
    }
    case MPV_EVENT_END_FILE: {
      const auto* end = static_cast<mpv_event_end_file*>(event.data);
      const auto load_id = playback_.EndFile(
          end ? std::optional<int64_t>(end->playlist_entry_id) : std::nullopt);
      if (first_open_diagnostics_ && end && first_open_probe_.load_id &&
          first_open_probe_.load_id == load_id &&
          load_id == playback_.active_load() &&
          !first_open_probe_.ended) {
        if (end->reason == MPV_END_FILE_REASON_REDIRECT) {
          if (!first_open_probe_.redirect_reported) {
            first_open_probe_.redirect_reported = true;
            WriteFirstOpenProbe(ProbeModule::core, ProbeCause::playlist_redirect);
          }
        } else {
          first_open_probe_.ended = true;
          auto cause = ProbeCause::end_other;
          if (end->reason == MPV_END_FILE_REASON_STOP) {
            cause = ProbeCause::end_stopped;
          } else if (end->reason == MPV_END_FILE_REASON_EOF) {
            cause = ProbeCause::end_eof;
          }
          if (end->reason == MPV_END_FILE_REASON_ERROR) {
            cause = ProbeErrorInRange(end->error)
                        ? ProbeCause::end_error
                        : ProbeCause::end_error_unknown;
          }
          const auto& failure = playback_.failure();
          WriteFirstOpenProbe(
              ProbeModule::core, cause, end->error,
              failure && failure->load_id == *load_id ? failure->http_status
                                                     : std::nullopt);
        }
      }
      if (seek_observation_ && seek_observation_->load_id == load_id) {
        seek_observation_.reset();
        seek_observation_ambiguous_ = true;
      }
      if (end && end->reason == MPV_END_FILE_REASON_REDIRECT) {
        if (!playback_.Redirect(load_id, end->playlist_insert_id,
                                end->playlist_insert_num_entries)) {
          QueueEvent(generation,
              FailureStateEvent("correlation_error", std::nullopt, load_id,
                                "Redirect correlation exceeded native limits"));
        }
        break;
      }
      if (end && end->error < 0) {
        const auto& failure = playback_.failure();
        const bool has_detail = load_id && failure &&
                                failure->load_id == *load_id &&
                                !failure->code.empty();
        QueueEvent(
            generation,
            FailureStateEvent(has_detail ? failure->code : "mpv_error",
                              has_detail ? failure->http_status
                                         : std::nullopt,
                              load_id,
                              has_detail ? "Media playback failed"
                                         : mpv_operations_.error_string(end->error)));
      } else if (end && end->reason == MPV_END_FILE_REASON_EOF) {
        QueueEvent(generation,
                   StateEvent("ended", "Playback ended", load_id));
      } else {
        QueueEvent(generation,
                   StateEvent("stopped", "Playback stopped", load_id));
      }
      playback_.RetireLoad(load_id);
      break;
    }
    case MPV_EVENT_SEEK:
    case MPV_EVENT_PLAYBACK_RESTART:
      ObserveSeekLanding(event.event_id);
      break;
    case MPV_EVENT_LOG_MESSAGE:
      if (const auto* message =
              static_cast<mpv_event_log_message*>(event.data)) {
        if (message->log_level != MPV_LOG_LEVEL_ERROR &&
            message->log_level != MPV_LOG_LEVEL_FATAL) {
          break;
        }
        if (first_open_diagnostics_ && first_open_probe_.load_id &&
            first_open_probe_.load_id == playback_.event_load() &&
            first_open_probe_.load_id == playback_.active_load() &&
            !first_open_probe_.ended && !first_open_probe_.ready &&
            !first_open_probe_.stop_reported && first_open_probe_.log_count < 4) {
          ++first_open_probe_.log_count;
          const auto prefix = AsciiLower(BoundedUtf8(message->prefix, kMaxMetadataStringBytes));
          const auto text = AsciiLower(BoundedUtf8(message->text, kMaxMetadataStringBytes));
          WriteFirstOpenProbe(ProbeModuleFor(prefix), ProbeCauseFor(text), std::nullopt,
                              ParseHttpErrorStatus(text));
        }
        if (const auto detail = ClassifyMpvFailure(*message)) {
          playback_.RecordFailure(detail->code, detail->http_status);
        }
      }
      break;
    case MPV_EVENT_QUEUE_OVERFLOW:
      seek_observation_.reset();
      seek_observation_ambiguous_ = true;
      QueueEvent(generation,
                 FailureStateEvent("event_queue_overflow", std::nullopt,
                                   playback_.event_load(),
                                   "The libmpv event queue overflowed"));
      break;
    case MPV_EVENT_PROPERTY_CHANGE: {
      const auto* property = static_cast<mpv_event_property*>(event.data);
      if (!property || !property->name) {
        break;
      }
      Value value;
      if (property->data) {
        switch (property->format) {
          case MPV_FORMAT_FLAG:
            value = Value(*static_cast<int*>(property->data) != 0);
            break;
          case MPV_FORMAT_DOUBLE:
            value = Value(*static_cast<double*>(property->data));
            break;
          case MPV_FORMAT_STRING:
            value = Value(PropertyString(*property));
            break;
          case MPV_FORMAT_NODE: {
            const auto& node = *static_cast<mpv_node*>(property->data);
            value = event.reply_userdata == kTrackList
                        ? EncodeTrackList(node)
                        : event.reply_userdata == kVideoTargetParameters
                              ? EncodeVideoTargetParameters(node)
                              : EncodeVideoParameters(node);
            break;
          }
          default:
            break;
        }
      }
      if (event.reply_userdata == kCurrentVideoOutput ||
          event.reply_userdata == kHardwareDecoder) {
        const std::string fact = PropertyString(*property);
        if (!fact.empty()) {
          std::cerr << "[lineup-player] " << property->name << '=' << fact
                    << std::endl;
        }
      }
      ValueMap property_event = {
          {"type", Value("property")},
          {"name", Value(property->name)},
          {"value", std::move(value)}};
      if (playback_.event_load()) {
        property_event["loadId"] = Value(*playback_.event_load());
      }
      QueueEvent(generation, std::move(property_event));
      break;
    }
    default:
      break;
  }
}

void PlayerCore::QueueStopResult(uint64_t generation, int64_t stop_id,
                                 bool success) {
  QueueEvent(generation, {
      {"type", Value("stopResult")},
      {"stopId", Value(stop_id)},
      {"success", Value(success)},
  });
}

void PlayerCore::QueueTrackResult(uint64_t generation, int64_t load_id,
                                  int64_t request_id, bool success) {
  QueueEvent(generation, {
      {"type", Value("trackResult")},
      {"loadId", Value(load_id)},
      {"requestId", Value(request_id)},
      {"success", Value(success)},
  });
}

void PlayerCore::QueuePlatformEvent(ValueMap event) {
  QueueEvent(generation_.load(), std::move(event));
}

void PlayerCore::DiscardQueuedEvents(std::string_view type) {
  std::lock_guard lock(event_mutex_);
  events_.erase(std::remove_if(events_.begin(), events_.end(), [type](const auto& event) {
    const auto* text = FindString(&event.value, "type");
    return text && *text == type;
  }), events_.end());
}

void PlayerCore::QueueEvent(uint64_t generation, ValueMap value) {
  {
    std::lock_guard lock(event_mutex_);
    // At capacity, evict the oldest property event; otherwise drop an
    // incoming property, or evict the oldest event to admit a non-property.
    // This protects state, stop, track, and display completions from
    // property telemetry pressure.
    if (events_.size() >= kMaxQueuedEvents) {
      const auto* incoming_type_value = FindString(&value, "type");
      const auto property = std::find_if(
          events_.begin(), events_.end(), [](const QueuedEvent& event) {
            const auto* type = FindString(&event.value, "type");
            return type && *type == "property";
          });
      if (property != events_.end()) {
        events_.erase(property);
      } else if (incoming_type_value && *incoming_type_value == "property") {
        return;
      } else {
        events_.pop_front();
      }
    }
    events_.push_back({generation, std::move(value)});
    if (wakeup_posted_.exchange(true)) {
      return;
    }
  }
  RequestWakeup();
}

void PlayerCore::RequestWakeup() {
  wakeup_posted_ = true;
  if (!host_.PostWakeup()) {
    std::lock_guard lock(event_mutex_);
    wakeup_posted_ = false;
  }
}

void PlayerCore::DrainEvents(const EventSink& deliver) {
  std::deque<QueuedEvent> pending;
  {
    std::lock_guard lock(event_mutex_);
    std::swap(pending, events_);
    wakeup_posted_ = false;
  }
  const uint64_t current_generation = generation_.load();
  while (!pending.empty()) {
    QueuedEvent event = std::move(pending.front());
    pending.pop_front();
    if (event.generation != current_generation) {
      continue;
    }
    deliver(event.value);
  }
}

}  // namespace lineup::player
