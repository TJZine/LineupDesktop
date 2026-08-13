#include "native_player.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <iostream>
#include <optional>
#include <utility>

#include <flutter/standard_method_codec.h>

namespace {

constexpr char kChannelName[] = "lineup/native_player";
constexpr wchar_t kCompositionMarker[] =
    L"5f77625673248ee5846fbcaf5d3e1a3878386fd7";
constexpr size_t kMaxQueuedEvents = 256;
constexpr size_t kMaxMetadataBytes = 64 * 1024;
constexpr size_t kMaxMetadataStringBytes = 4096;
constexpr int kMaxTracks = 256;

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
};

const flutter::EncodableMap* AsMap(const flutter::EncodableValue* value) {
  return value ? std::get_if<flutter::EncodableMap>(value) : nullptr;
}

const flutter::EncodableValue* Find(const flutter::EncodableMap& map,
                                    const char* key) {
  const auto found = map.find(flutter::EncodableValue(key));
  return found == map.end() ? nullptr : &found->second;
}

std::optional<double> AsNumber(const flutter::EncodableValue* value) {
  if (!value) {
    return std::nullopt;
  }
  if (const auto* number = std::get_if<double>(value)) {
    return *number;
  }
  if (const auto* number = std::get_if<int32_t>(value)) {
    return static_cast<double>(*number);
  }
  if (const auto* number = std::get_if<int64_t>(value)) {
    return static_cast<double>(*number);
  }
  return std::nullopt;
}

std::optional<int64_t> AsInt(const flutter::EncodableValue* value) {
  if (const auto* number = value ? std::get_if<int64_t>(value) : nullptr) {
    return *number;
  }
  if (const auto* number = value ? std::get_if<int32_t>(value) : nullptr) {
    return *number;
  }
  return std::nullopt;
}

const mpv_node* FindNode(const mpv_node& map, const char* key) {
  if (map.format != MPV_FORMAT_NODE_MAP || !map.u.list) {
    return nullptr;
  }
  for (int index = 0; index < map.u.list->num; ++index) {
    if (map.u.list->keys[index] &&
        std::string(map.u.list->keys[index]) == key) {
      return &map.u.list->values[index];
    }
  }
  return nullptr;
}

flutter::EncodableValue EncodeWhitelistedNode(const mpv_node* node,
                                               size_t& remaining_bytes) {
  if (!node) {
    return flutter::EncodableValue();
  }
  switch (node->format) {
    case MPV_FORMAT_STRING:
      if (node->u.string) {
        const size_t length = strnlen(node->u.string,
                                     std::min(kMaxMetadataStringBytes,
                                              remaining_bytes));
        remaining_bytes -= length;
        return flutter::EncodableValue(std::string(node->u.string, length));
      }
      return flutter::EncodableValue("");
    case MPV_FORMAT_FLAG:
      return flutter::EncodableValue(node->u.flag != 0);
    case MPV_FORMAT_INT64:
      return flutter::EncodableValue(node->u.int64);
    case MPV_FORMAT_DOUBLE:
      return flutter::EncodableValue(node->u.double_);
    default:
      return flutter::EncodableValue();
  }
}

std::string PropertyString(const mpv_event_property& property) {
  if (property.format != MPV_FORMAT_STRING || !property.data) {
    return {};
  }
  const char* value = *static_cast<char**>(property.data);
  return value ? std::string(value, strnlen(value, kMaxMetadataStringBytes))
               : "";
}

flutter::EncodableMap StateEvent(const char* state, const char* message,
                                 std::optional<int64_t> load_id = std::nullopt) {
  flutter::EncodableMap event = {
          {flutter::EncodableValue("type"), flutter::EncodableValue("state")},
          {flutter::EncodableValue("state"), flutter::EncodableValue(state)},
          {flutter::EncodableValue("message"),
           flutter::EncodableValue(message)}};
  if (load_id) {
    event[flutter::EncodableValue("loadId")] =
        flutter::EncodableValue(*load_id);
  }
  return event;
}

}  // namespace

WindowsNativePlayer::WindowsNativePlayer(
    HWND top_level_window, HWND flutter_view,
    flutter::BinaryMessenger* messenger)
    : top_level_window_(top_level_window), flutter_view_(flutter_view) {
  channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, kChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });
}

WindowsNativePlayer::~WindowsNativePlayer() {
  channel_->SetMethodCallHandler(nullptr);
  if (!disposed_) {
    Dispose();
  }
  dispose_result_.reset();
}

void WindowsNativePlayer::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();
  if (method == "initialize") {
    std::string error;
    if (!Initialize(error)) {
      result->Error("initialize_failed", error);
      return;
    }
    flutter::EncodableMap details{
        {flutter::EncodableValue("clientApiVersion"),
         flutter::EncodableValue(
             static_cast<int64_t>(mpv_client_api_version()))}};
    result->Success(flutter::EncodableValue(details));
    return;
  }
  if (method == "dispose") {
    if (disposed_) {
      result->Success();
      return;
    }
    if (dispose_result_) {
      result->Error("dispose_in_progress", "Native player disposal is already in progress.");
      return;
    }
    dispose_result_ = std::move(result);
    BeginAsyncDispose();
    return;
  }
  if (!accepting_commands_) {
    result->Error("not_initialized", "The native player is not initialized.");
    return;
  }

  const auto* arguments = AsMap(call.arguments());
  if (method == "load") {
    const auto* uri_value = arguments ? Find(*arguments, "uri") : nullptr;
    const auto* uri = uri_value ? std::get_if<std::string>(uri_value) : nullptr;
    const auto load_id =
        arguments ? AsInt(Find(*arguments, "loadId")) : std::nullopt;
    if (!uri || uri->empty() || uri->size() > 32768) {
      result->Error("invalid_argument", "A bounded media URI is required.");
      return;
    }
    if (!load_id || *load_id < 0) {
      result->Error("invalid_argument", "A non-negative integer loadId is required.");
      return;
    }
    QueueCommand({CommandType::load, *load_id, *uri});
  } else if (method == "play") {
    QueueCommand({CommandType::play});
  } else if (method == "pause") {
    QueueCommand({CommandType::pause});
  } else if (method == "seek") {
    const auto seconds = arguments ? AsNumber(Find(*arguments, "seconds"))
                                   : std::nullopt;
    if (!seconds || !std::isfinite(*seconds) || *seconds < 0) {
      result->Error("invalid_argument", "Seek seconds must be non-negative.");
      return;
    }
    QueueCommand({CommandType::seek, 0, {}, *seconds});
  } else if (method == "stop") {
    QueueCommand({CommandType::stop});
  } else if (method == "setVideoRect") {
    if (!arguments) {
      result->Error("invalid_argument", "Video bounds are required.");
      return;
    }
    if (!SetVideoRect(*arguments)) {
      result->Error("invalid_argument", "Valid finite video bounds are required.");
      return;
    }
  } else if (method == "setFullscreen") {
    const auto* value = arguments ? Find(*arguments, "fullscreen") : nullptr;
    const auto* fullscreen = value ? std::get_if<bool>(value) : nullptr;
    if (!fullscreen) {
      result->Error("invalid_argument", "Fullscreen must be a boolean.");
      return;
    }
    std::string error;
    if (!SetFullscreen(*fullscreen, error)) {
      result->Error("window_error", error);
      return;
    }
  } else if (method == "selectTrack") {
    if (!arguments) {
      result->Error("invalid_argument", "Track selection is required.");
      return;
    }
    auto command = ParseTrack(*arguments);
    if (!command) {
      result->Error("invalid_argument", "A valid track type and id are required.");
      return;
    }
    QueueCommand(std::move(*command));
  } else if (method == "setVolume") {
    const auto volume = arguments ? AsNumber(Find(*arguments, "volume"))
                                  : std::nullopt;
    if (!volume || !std::isfinite(*volume) || *volume < 0 || *volume > 100) {
      result->Error("invalid_argument", "Volume must be between 0 and 100.");
      return;
    }
    QueueCommand({CommandType::volume, 0, {}, *volume});
  } else {
    result->NotImplemented();
    return;
  }

  result->Success();
}

bool WindowsNativePlayer::Initialize(std::string& error) {
  if (accepting_commands_) {
    return true;
  }
  if (event_thread_.joinable()) {
    error = "The native player has already been disposed.";
    return false;
  }

  wchar_t marker[64]{};
  if (::GetEnvironmentVariableW(L"LINEUP_FLUTTER_DCOMP_ACTIVE", marker,
                                static_cast<DWORD>(std::size(marker))) == 0 ||
      std::wstring(marker) != kCompositionMarker) {
    error = "The required Lineup DirectComposition Flutter engine is not active.";
    return false;
  }

  video_host_ = ::CreateWindowExW(
      WS_EX_NOACTIVATE, L"STATIC", L"", WS_CHILD | WS_CLIPSIBLINGS | WS_DISABLED,
      0, 0, 1, 1, flutter_view_, nullptr, ::GetModuleHandle(nullptr), nullptr);
  if (!video_host_) {
    error = "Windows could not create the native video presentation host.";
    return false;
  }

  mpv_ = mpv_create();
  if (!mpv_) {
    error = "libmpv could not create a client.";
    ::DestroyWindow(video_host_);
    video_host_ = nullptr;
    return false;
  }

  int64_t window_id = reinterpret_cast<int64_t>(video_host_);
  const int window_status =
      mpv_set_option(mpv_, "wid", MPV_FORMAT_INT64, &window_id);
  const std::pair<const char*, const char*> options[] = {
      {"config", "no"},
      {"terminal", "no"},
      {"input-default-bindings", "no"},
      {"input-vo-keyboard", "no"},
      {"input-media-keys", "no"},
      {"osc", "no"},
      {"ytdl", "no"},
      {"idle", "yes"},
      {"keep-open", "no"},
      {"vo", "gpu-next"},
      {"gpu-api", "d3d11"},
      {"gpu-context", "d3d11"},
      {"hwdec", "auto"},
  };
  int option_status = window_status;
  for (const auto& [name, value] : options) {
    if (option_status >= 0) {
      option_status = mpv_set_option_string(mpv_, name, value);
    }
  }
  const int initialize_status =
      option_status < 0 ? option_status : mpv_initialize(mpv_);
  if (initialize_status < 0) {
    error = std::string("libmpv initialization failed: ") +
            mpv_error_string(initialize_status);
    mpv_terminate_destroy(mpv_);
    mpv_ = nullptr;
    ::DestroyWindow(video_host_);
    video_host_ = nullptr;
    return false;
  }
  std::cerr << "[lineup-player] libmpv initialized client-api="
            << mpv_client_api_version() << std::endl;

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
  };
  for (const auto& observation : observations) {
    const int observe_status = mpv_observe_property(
        mpv_, observation.id, observation.name, observation.format);
    if (observe_status < 0) {
      error = std::string("libmpv property observation failed for ") +
              observation.name + ": " + mpv_error_string(observe_status);
      mpv_terminate_destroy(mpv_);
      mpv_ = nullptr;
      ::DestroyWindow(video_host_);
      video_host_ = nullptr;
      return false;
    }
  }

  const uint64_t generation = generation_.fetch_add(1) + 1;
  disposed_ = false;
  shutdown_started_ = false;
  stopping_ = false;
  accepting_commands_ = true;
  StartEventThread();
  QueueEvent(generation, StateEvent("idle", "Native libmpv player ready"));
  return true;
}

void WindowsNativePlayer::BeginAsyncDispose() {
  if (disposed_ || shutdown_started_) {
    return;
  }
  shutdown_started_ = true;
  std::cerr << "[lineup-player] native shutdown requested" << std::endl;
  generation_.fetch_add(1);
  accepting_commands_ = false;
  stopping_ = true;
  if (mpv_) {
    mpv_wakeup(mpv_);
  }
}

void WindowsNativePlayer::Dispose() {
  BeginAsyncDispose();
  StopEventThread();
  FinishDispose();
  disposed_ = true;
}

void WindowsNativePlayer::FinishDispose() {
  if (fullscreen_) {
    std::string ignored;
    SetFullscreen(false, ignored);
  }
  if (video_host_) {
    ::DestroyWindow(video_host_);
    video_host_ = nullptr;
  }
  video_rect_set_ = false;
  {
    std::lock_guard lock(command_mutex_);
    commands_.clear();
  }
  {
    std::lock_guard lock(event_mutex_);
    events_.clear();
    wakeup_posted_ = false;
  }
  active_load_id_.reset();
  event_load_id_.reset();
  playlist_load_ids_.clear();
}

bool WindowsNativePlayer::SetVideoRect(
    const flutter::EncodableMap& arguments) {
  const auto left = AsNumber(Find(arguments, "left"));
  const auto top = AsNumber(Find(arguments, "top"));
  const auto width = AsNumber(Find(arguments, "width"));
  const auto height = AsNumber(Find(arguments, "height"));
  const auto scale = AsNumber(Find(arguments, "scale"));
  if (!left || !top || !width || !height || !scale ||
      !std::isfinite(*left) || !std::isfinite(*top) ||
      !std::isfinite(*width) || !std::isfinite(*height) ||
      !std::isfinite(*scale) || *width < 0 || *height < 0 || *scale <= 0) {
    return false;
  }
  video_rect_ = {
      static_cast<LONG>(std::lround(*left * *scale)),
      static_cast<LONG>(std::lround(*top * *scale)),
      static_cast<LONG>(std::lround((*left + std::max(0.0, *width)) * *scale)),
      static_cast<LONG>(std::lround((*top + std::max(0.0, *height)) * *scale)),
  };
  video_rect_set_ = true;
  if (!video_host_) {
    return false;
  }
  if (!::SetWindowPos(video_host_, HWND_BOTTOM, video_rect_.left,
                      video_rect_.top, video_rect_.right - video_rect_.left,
                      video_rect_.bottom - video_rect_.top,
                      SWP_NOACTIVATE | SWP_NOOWNERZORDER)) {
    return false;
  }
  ::ShowWindow(video_host_, parent_minimized_ ? SW_HIDE : SW_SHOWNOACTIVATE);
  return true;
}

bool WindowsNativePlayer::SetFullscreen(bool fullscreen, std::string& error) {
  if (fullscreen == fullscreen_ || !top_level_window_) {
    return true;
  }
  if (fullscreen) {
    ::SetLastError(ERROR_SUCCESS);
    window_style_ = ::GetWindowLongPtr(top_level_window_, GWL_STYLE);
    if (window_style_ == 0 && ::GetLastError() != ERROR_SUCCESS) {
      error = "Windows could not read the window style.";
      return false;
    }
    window_placement_.length = sizeof(WINDOWPLACEMENT);
    MONITORINFO monitor{sizeof(MONITORINFO)};
    if (!::GetWindowPlacement(top_level_window_, &window_placement_) ||
        !::GetMonitorInfo(
            ::MonitorFromWindow(top_level_window_, MONITOR_DEFAULTTONEAREST),
            &monitor)) {
      error = "Windows could not read the current window placement.";
      return false;
    }
    ::SetLastError(ERROR_SUCCESS);
    if (::SetWindowLongPtr(top_level_window_, GWL_STYLE,
                           window_style_ & ~WS_OVERLAPPEDWINDOW) == 0 &&
        ::GetLastError() != ERROR_SUCCESS) {
      error = "Windows could not enter fullscreen.";
      return false;
    }
    if (!::SetWindowPos(top_level_window_, HWND_TOP, monitor.rcMonitor.left,
                        monitor.rcMonitor.top,
                        monitor.rcMonitor.right - monitor.rcMonitor.left,
                        monitor.rcMonitor.bottom - monitor.rcMonitor.top,
                        SWP_FRAMECHANGED | SWP_NOOWNERZORDER)) {
      ::SetLastError(ERROR_SUCCESS);
      const bool style_restored =
          ::SetWindowLongPtr(top_level_window_, GWL_STYLE, window_style_) != 0 ||
          ::GetLastError() == ERROR_SUCCESS;
      const bool placement_restored =
          style_restored &&
          ::SetWindowPlacement(top_level_window_, &window_placement_);
      error = placement_restored
                  ? "Windows could not size the fullscreen window."
                  : "Windows could not size or roll back the fullscreen window.";
      return false;
    }
    fullscreen_ = true;
  } else {
    ::SetLastError(ERROR_SUCCESS);
    const bool style_set =
        ::SetWindowLongPtr(top_level_window_, GWL_STYLE, window_style_) != 0 ||
        ::GetLastError() == ERROR_SUCCESS;
    const bool placement_set =
        style_set && ::SetWindowPlacement(top_level_window_, &window_placement_);
    const bool frame_set =
        placement_set &&
        ::SetWindowPos(top_level_window_, nullptr, 0, 0, 0, 0,
                       SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE |
                           SWP_NOZORDER | SWP_NOOWNERZORDER);
    if (!frame_set) {
      error = "Windows could not restore the window after fullscreen.";
      return false;
    }
    fullscreen_ = false;
  }
  return true;
}

std::optional<WindowsNativePlayer::QueuedCommand> WindowsNativePlayer::ParseTrack(
    const flutter::EncodableMap& arguments) {
  const auto* type_value = Find(arguments, "type");
  const auto* type =
      type_value ? std::get_if<std::string>(type_value) : nullptr;
  if (!type) {
    return std::nullopt;
  }
  const char* property =
      *type == "video" ? "vid" : *type == "audio" ? "aid" :
      *type == "subtitle" ? "sid" : nullptr;
  if (!property) {
    return std::nullopt;
  }
  const auto* id_value = Find(arguments, "id");
  if (!id_value || std::holds_alternative<std::monostate>(*id_value)) {
    return QueuedCommand{CommandType::track, 0, property};
  }
  int64_t id = 0;
  if (const auto* int64_value = std::get_if<int64_t>(id_value)) {
    id = *int64_value;
  } else if (const auto* int32_value = std::get_if<int32_t>(id_value)) {
    id = *int32_value;
  } else {
    return std::nullopt;
  }
  if (id <= 0) {
    return std::nullopt;
  }
  return QueuedCommand{CommandType::track, id, property};
}

void WindowsNativePlayer::StartEventThread() {
  const uint64_t generation = generation_.load();
  event_thread_ = std::thread([this, generation] { EventLoop(generation); });
}

void WindowsNativePlayer::QueueCommand(QueuedCommand command) {
  {
    std::lock_guard lock(command_mutex_);
    commands_.push_back(std::move(command));
  }
  mpv_wakeup(mpv_);
}

void WindowsNativePlayer::RunCommand(const QueuedCommand& command,
                                     uint64_t generation) {
  int status = 0;
  switch (command.type) {
    case CommandType::load: {
      active_load_id_ = command.load_id;
      const char* value[] = {"loadfile", command.text.c_str(), "replace",
                             nullptr};
      status = mpv_command(mpv_, value);
      int64_t playlist_entry_id = 0;
      if (status >= 0 &&
          mpv_get_property(mpv_, "playlist/0/id", MPV_FORMAT_INT64,
                           &playlist_entry_id) >= 0) {
        playlist_load_ids_[playlist_entry_id] = command.load_id;
      }
      break;
    }
    case CommandType::play: {
      int paused = 0;
      status = mpv_set_property(mpv_, "pause", MPV_FORMAT_FLAG, &paused);
      break;
    }
    case CommandType::pause: {
      int paused = 1;
      status = mpv_set_property(mpv_, "pause", MPV_FORMAT_FLAG, &paused);
      break;
    }
    case CommandType::seek: {
      const std::string seconds = std::to_string(command.number);
      const char* value[] = {"seek", seconds.c_str(), "absolute+exact",
                             nullptr};
      status = mpv_command(mpv_, value);
      break;
    }
    case CommandType::stop: {
      const char* value[] = {"stop", nullptr};
      status = mpv_command(mpv_, value);
      break;
    }
    case CommandType::track:
      if (command.load_id == 0) {
        status = mpv_set_property_string(mpv_, command.text.c_str(), "no");
      } else {
        int64_t id = command.load_id;
        status = mpv_set_property(mpv_, command.text.c_str(), MPV_FORMAT_INT64,
                                  &id);
      }
      break;
    case CommandType::volume: {
      double volume = command.number;
      status = mpv_set_property(mpv_, "volume", MPV_FORMAT_DOUBLE, &volume);
      break;
    }
  }
  if (status < 0) {
    const std::optional<int64_t> error_load_id =
        command.type == CommandType::load
            ? std::optional<int64_t>(command.load_id)
            : active_load_id_;
    QueueEvent(generation,
               StateEvent("error", mpv_error_string(status), error_load_id));
  }
}

void WindowsNativePlayer::StopEventThread() {
  stopping_ = true;
  if (mpv_) {
    mpv_wakeup(mpv_);
  }
  if (event_thread_.joinable()) {
    event_thread_.join();
  }
}

void WindowsNativePlayer::EventLoop(uint64_t generation) {
  while (!stopping_) {
    if (!wakeup_posted_) {
      bool has_events = false;
      {
        std::lock_guard lock(event_mutex_);
        has_events = !events_.empty();
      }
      if (has_events) {
        PostPlatformWakeup();
      }
    }
    std::deque<QueuedCommand> commands;
    {
      std::lock_guard lock(command_mutex_);
      std::swap(commands, commands_);
    }
    for (const auto& command : commands) {
      RunCommand(command, generation);
    }
    const mpv_event* event = mpv_wait_event(mpv_, 0.05);
    if (stopping_) {
      break;
    }
    if (event && event->event_id != MPV_EVENT_NONE) {
      HandleMpvEvent(*event, generation);
    }
  }
  mpv_terminate_destroy(mpv_);
  mpv_ = nullptr;
  std::cerr << "[lineup-player] libmpv shutdown complete" << std::endl;
  dispose_ready_ = true;
  while (::IsWindow(top_level_window_) &&
         !::PostMessage(top_level_window_, kPlatformEventMessage, 0, 0)) {
    ::Sleep(10);
  }
}

void WindowsNativePlayer::HandleMpvEvent(const mpv_event& event,
                                         uint64_t generation) {
  switch (event.event_id) {
    case MPV_EVENT_START_FILE:
      if (const auto* start = static_cast<mpv_event_start_file*>(event.data)) {
        const auto load = playlist_load_ids_.find(start->playlist_entry_id);
        event_load_id_ = load == playlist_load_ids_.end()
                             ? std::nullopt
                             : std::optional<int64_t>(load->second);
      }
      QueueEvent(generation,
                 StateEvent("loading", "Loading media", event_load_id_));
      break;
    case MPV_EVENT_FILE_LOADED:
      QueueEvent(generation, StateEvent("playing", "Playing", event_load_id_));
      break;
    case MPV_EVENT_END_FILE: {
      const auto* end = static_cast<mpv_event_end_file*>(event.data);
      std::optional<int64_t> load_id;
      if (end) {
        const auto load = playlist_load_ids_.find(end->playlist_entry_id);
        if (load != playlist_load_ids_.end()) {
          load_id = load->second;
          playlist_load_ids_.erase(load);
        }
      }
      if (end && end->error < 0) {
        QueueEvent(generation,
                   StateEvent("error", mpv_error_string(end->error),
                              load_id));
      } else {
        QueueEvent(generation,
                   StateEvent("stopped", "Playback stopped", load_id));
      }
      break;
    }
    case MPV_EVENT_QUEUE_OVERFLOW:
      QueueEvent(generation,
                 StateEvent("error", "The libmpv event queue overflowed",
                            event_load_id_));
      break;
    case MPV_EVENT_PROPERTY_CHANGE: {
      const auto* property = static_cast<mpv_event_property*>(event.data);
      if (!property || !property->name) {
        break;
      }
      flutter::EncodableValue value;
      if (property->data) {
        switch (property->format) {
          case MPV_FORMAT_FLAG:
            value = flutter::EncodableValue(
                *static_cast<int*>(property->data) != 0);
            break;
          case MPV_FORMAT_DOUBLE:
            value = flutter::EncodableValue(
                *static_cast<double*>(property->data));
            break;
          case MPV_FORMAT_STRING:
            value = flutter::EncodableValue(PropertyString(*property));
            break;
          case MPV_FORMAT_NODE: {
            const auto& node = *static_cast<mpv_node*>(property->data);
            value = event.reply_userdata == kTrackList
                        ? EncodeTrackList(node)
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
      flutter::EncodableMap property_event = {
          {flutter::EncodableValue("type"),
           flutter::EncodableValue("property")},
           {flutter::EncodableValue("name"),
            flutter::EncodableValue(property->name)},
           {flutter::EncodableValue("value"), std::move(value)}};
      if (event_load_id_) {
        property_event[flutter::EncodableValue("loadId")] =
            flutter::EncodableValue(*event_load_id_);
      }
      QueueEvent(generation, std::move(property_event));
      break;
    }
    default:
      break;
  }
}

void WindowsNativePlayer::QueueEvent(uint64_t generation,
                                     flutter::EncodableMap value) {
  {
    std::lock_guard lock(event_mutex_);
    if (events_.size() >= kMaxQueuedEvents) {
      const auto* incoming_type = Find(value, "type");
      const auto* incoming_type_value =
          incoming_type ? std::get_if<std::string>(incoming_type) : nullptr;
      const auto property = std::find_if(
          events_.begin(), events_.end(), [](const QueuedEvent& event) {
            const auto* type = Find(event.value, "type");
            const auto* value = type ? std::get_if<std::string>(type) : nullptr;
            return value && *value == "property";
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
  PostPlatformWakeup();
}

void WindowsNativePlayer::PostPlatformWakeup() {
  wakeup_posted_ = true;
  if (!::PostMessage(top_level_window_, kPlatformEventMessage, 0, 0)) {
    std::lock_guard lock(event_mutex_);
    wakeup_posted_ = false;
  }
}

void WindowsNativePlayer::DrainEvents() {
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
    channel_->InvokeMethod(
        "event", std::make_unique<flutter::EncodableValue>(event.value));
  }
}

bool WindowsNativePlayer::HandleWindowMessage(UINT message) {
  if (message != kPlatformEventMessage) {
    return false;
  }
  DrainEvents();
  if (dispose_ready_.exchange(false)) {
    std::cerr << "[lineup-player] finishing native shutdown" << std::endl;
    if (event_thread_.joinable()) {
      event_thread_.join();
    }
    FinishDispose();
    disposed_ = true;
    shutdown_started_ = false;
    if (dispose_result_) {
      dispose_result_->Success();
      dispose_result_.reset();
    }
    if (window_close_requested_) {
      window_close_ready_ = true;
    }
  }
  return true;
}

bool WindowsNativePlayer::BeginWindowClose() {
  if (disposed_) {
    return true;
  }
  window_close_requested_ = true;
  BeginAsyncDispose();
  return false;
}

bool WindowsNativePlayer::TakeWindowCloseReady() {
  const bool ready = window_close_ready_;
  window_close_ready_ = false;
  return ready;
}

void WindowsNativePlayer::SetParentMinimized(bool minimized) {
  parent_minimized_ = minimized;
  if (!video_host_ || !video_rect_set_) {
    return;
  }
  ::ShowWindow(video_host_, minimized ? SW_HIDE : SW_SHOWNOACTIVATE);
}

flutter::EncodableValue WindowsNativePlayer::EncodeTrackList(
    const mpv_node& node) const {
  flutter::EncodableList tracks;
  size_t remaining_bytes = kMaxMetadataBytes;
  if (node.format != MPV_FORMAT_NODE_ARRAY || !node.u.list) {
    return flutter::EncodableValue(tracks);
  }
  const int count = std::min(node.u.list->num, kMaxTracks);
  for (int index = 0; index < count; ++index) {
    const mpv_node& track = node.u.list->values[index];
    if (track.format != MPV_FORMAT_NODE_MAP) {
      continue;
    }
    flutter::EncodableMap value;
    for (const char* key : {"id", "type", "title", "lang", "codec",
                            "selected"}) {
      value[flutter::EncodableValue(key)] =
          EncodeWhitelistedNode(FindNode(track, key), remaining_bytes);
    }
    tracks.emplace_back(value);
  }
  return flutter::EncodableValue(tracks);
}

flutter::EncodableValue WindowsNativePlayer::EncodeVideoParameters(
    const mpv_node& node) const {
  flutter::EncodableMap parameters;
  size_t remaining_bytes = kMaxMetadataBytes;
  for (const char* key : {"w", "h", "pixelformat", "hw-pixelformat",
                          "primaries", "gamma", "colormatrix", "sig-peak"}) {
    parameters[flutter::EncodableValue(key)] =
        EncodeWhitelistedNode(FindNode(node, key), remaining_bytes);
  }
  return flutter::EncodableValue(parameters);
}
