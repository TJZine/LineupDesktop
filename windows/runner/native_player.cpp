#include "native_player.h"

#include <algorithm>
#include <cmath>
#include <iostream>
#include <optional>
#include <utility>
#include <vector>

#include <flutter/standard_method_codec.h>

namespace {

constexpr char kChannelName[] = "lineup/native_player";
constexpr wchar_t kCompositionMarker[] =
    L"5f77625673248ee5846fbcaf5d3e1a3878386fd7";
constexpr size_t kMaxQueuedEvents = 256;
constexpr int kMaxTracks = 256;

enum PropertyId : uint64_t {
  kPause = 1,
  kIdleActive,
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

flutter::EncodableValue EncodeWhitelistedNode(const mpv_node* node) {
  if (!node) {
    return flutter::EncodableValue();
  }
  switch (node->format) {
    case MPV_FORMAT_STRING:
      return flutter::EncodableValue(node->u.string ? node->u.string : "");
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
  return value ? value : "";
}

flutter::EncodableMap StateEvent(const char* state, const char* message) {
  return {{flutter::EncodableValue("type"), flutter::EncodableValue("state")},
          {flutter::EncodableValue("state"), flutter::EncodableValue(state)},
          {flutter::EncodableValue("message"),
           flutter::EncodableValue(message)}};
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
  Dispose();
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
    Dispose();
    result->Success();
    return;
  }
  if (!mpv_) {
    result->Error("not_initialized", "The native player is not initialized.");
    return;
  }

  int status = 0;
  const auto* arguments = AsMap(call.arguments());
  if (method == "load") {
    const auto* uri_value = arguments ? Find(*arguments, "uri") : nullptr;
    const auto* uri = uri_value ? std::get_if<std::string>(uri_value) : nullptr;
    if (!uri || uri->empty() || uri->size() > 32768) {
      result->Error("invalid_argument", "A bounded media URI is required.");
      return;
    }
    const char* command[] = {"loadfile", uri->c_str(), "replace", nullptr};
    status = mpv_command(mpv_, command);
  } else if (method == "play") {
    int paused = 0;
    status = mpv_set_property(mpv_, "pause", MPV_FORMAT_FLAG, &paused);
  } else if (method == "pause") {
    int paused = 1;
    status = mpv_set_property(mpv_, "pause", MPV_FORMAT_FLAG, &paused);
  } else if (method == "seek") {
    const auto seconds = arguments ? AsNumber(Find(*arguments, "seconds"))
                                   : std::nullopt;
    if (!seconds || !std::isfinite(*seconds) || *seconds < 0) {
      result->Error("invalid_argument", "Seek seconds must be non-negative.");
      return;
    }
    const std::string value = std::to_string(*seconds);
    const char* command[] = {"seek", value.c_str(), "absolute+exact", nullptr};
    status = mpv_command(mpv_, command);
  } else if (method == "stop") {
    status = Command({"stop"});
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
    SetFullscreen(*fullscreen);
  } else if (method == "selectTrack") {
    if (!arguments) {
      result->Error("invalid_argument", "Track selection is required.");
      return;
    }
    const auto track_status = SetTrack(*arguments);
    if (!track_status) {
      result->Error("invalid_argument", "A valid track type and id are required.");
      return;
    }
    status = *track_status;
  } else if (method == "setVolume") {
    const auto volume = arguments ? AsNumber(Find(*arguments, "volume"))
                                  : std::nullopt;
    if (!volume || !std::isfinite(*volume) || *volume < 0 || *volume > 100) {
      result->Error("invalid_argument", "Volume must be between 0 and 100.");
      return;
    }
    double value = *volume;
    status = mpv_set_property(mpv_, "volume", MPV_FORMAT_DOUBLE, &value);
  } else {
    result->NotImplemented();
    return;
  }

  if (status < 0) {
    result->Error("mpv_error", mpv_error_string(status));
  } else {
    result->Success();
  }
}

bool WindowsNativePlayer::Initialize(std::string& error) {
  if (mpv_) {
    return true;
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
      option_status = SetOption(name, value);
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
      {kIdleActive, "idle-active", MPV_FORMAT_FLAG},
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
      Dispose();
      return false;
    }
  }

  const uint64_t generation = generation_.fetch_add(1) + 1;
  stopping_ = false;
  StartEventThread();
  QueueEvent(generation, StateEvent("idle", "Native libmpv player ready"));
  return true;
}

void WindowsNativePlayer::Dispose() {
  generation_.fetch_add(1);
  StopEventThread();
  if (mpv_) {
    mpv_terminate_destroy(mpv_);
    mpv_ = nullptr;
  }
  if (fullscreen_) {
    SetFullscreen(false);
  }
  if (video_host_) {
    ::DestroyWindow(video_host_);
    video_host_ = nullptr;
  }
  video_rect_set_ = false;
  std::lock_guard lock(event_mutex_);
  while (!events_.empty()) {
    events_.pop();
  }
}

int WindowsNativePlayer::Command(
    std::initializer_list<const char*> arguments) {
  std::vector<const char*> command(arguments);
  command.push_back(nullptr);
  return mpv_command(mpv_, command.data());
}

int WindowsNativePlayer::SetOption(const char* name, const char* value) {
  return mpv_set_option_string(mpv_, name, value);
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

void WindowsNativePlayer::SetFullscreen(bool fullscreen) {
  if (fullscreen == fullscreen_ || !top_level_window_) {
    return;
  }
  if (fullscreen) {
    window_style_ = ::GetWindowLongPtr(top_level_window_, GWL_STYLE);
    window_placement_.length = sizeof(WINDOWPLACEMENT);
    MONITORINFO monitor{sizeof(MONITORINFO)};
    if (!::GetWindowPlacement(top_level_window_, &window_placement_) ||
        !::GetMonitorInfo(
            ::MonitorFromWindow(top_level_window_, MONITOR_DEFAULTTONEAREST),
            &monitor)) {
      return;
    }
    ::SetWindowLongPtr(top_level_window_, GWL_STYLE,
                       window_style_ & ~WS_OVERLAPPEDWINDOW);
    ::SetWindowPos(top_level_window_, HWND_TOP, monitor.rcMonitor.left,
                   monitor.rcMonitor.top,
                   monitor.rcMonitor.right - monitor.rcMonitor.left,
                   monitor.rcMonitor.bottom - monitor.rcMonitor.top,
                   SWP_FRAMECHANGED | SWP_NOOWNERZORDER);
    fullscreen_ = true;
  } else {
    ::SetWindowLongPtr(top_level_window_, GWL_STYLE, window_style_);
    ::SetWindowPlacement(top_level_window_, &window_placement_);
    ::SetWindowPos(top_level_window_, nullptr, 0, 0, 0, 0,
                   SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE |
                       SWP_NOZORDER | SWP_NOOWNERZORDER);
    fullscreen_ = false;
  }
}

std::optional<int> WindowsNativePlayer::SetTrack(
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
    return mpv_set_property_string(mpv_, property, "no");
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
  return mpv_set_property(mpv_, property, MPV_FORMAT_INT64, &id);
}

void WindowsNativePlayer::StartEventThread() {
  const uint64_t generation = generation_.load();
  event_thread_ = std::thread([this, generation] { EventLoop(generation); });
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
    const mpv_event* event = mpv_wait_event(mpv_, -1);
    if (stopping_) {
      break;
    }
    if (event && event->event_id != MPV_EVENT_NONE) {
      HandleMpvEvent(*event, generation);
    }
  }
}

void WindowsNativePlayer::HandleMpvEvent(const mpv_event& event,
                                         uint64_t generation) {
  switch (event.event_id) {
    case MPV_EVENT_START_FILE:
      QueueEvent(generation, StateEvent("loading", "Loading media"));
      break;
    case MPV_EVENT_FILE_LOADED:
      QueueEvent(generation, StateEvent("playing", "Playing"));
      break;
    case MPV_EVENT_END_FILE: {
      const auto* end = static_cast<mpv_event_end_file*>(event.data);
      if (end && end->error < 0) {
        QueueEvent(generation,
                   StateEvent("error", mpv_error_string(end->error)));
      } else {
        QueueEvent(generation, StateEvent("stopped", "Playback stopped"));
      }
      break;
    }
    case MPV_EVENT_QUEUE_OVERFLOW:
      QueueEvent(generation,
                 StateEvent("error", "The libmpv event queue overflowed"));
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
        LogPlaybackFact(property->name, PropertyString(*property));
      }
      QueueEvent(
          generation,
          {{flutter::EncodableValue("type"),
            flutter::EncodableValue("property")},
           {flutter::EncodableValue("name"),
            flutter::EncodableValue(property->name)},
           {flutter::EncodableValue("value"), std::move(value)}});
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
      events_.pop();
    }
    events_.push({generation, std::move(value)});
  }
  ::PostMessage(top_level_window_, kPlatformEventMessage, 0, 0);
}

void WindowsNativePlayer::DrainEvents() {
  std::queue<QueuedEvent> pending;
  {
    std::lock_guard lock(event_mutex_);
    std::swap(pending, events_);
  }
  const uint64_t current_generation = generation_.load();
  while (!pending.empty()) {
    QueuedEvent event = std::move(pending.front());
    pending.pop();
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
  return true;
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
          EncodeWhitelistedNode(FindNode(track, key));
    }
    tracks.emplace_back(value);
  }
  return flutter::EncodableValue(tracks);
}

flutter::EncodableValue WindowsNativePlayer::EncodeVideoParameters(
    const mpv_node& node) const {
  flutter::EncodableMap parameters;
  for (const char* key : {"w", "h", "pixelformat", "hw-pixelformat",
                          "primaries", "gamma", "colormatrix", "sig-peak"}) {
    parameters[flutter::EncodableValue(key)] =
        EncodeWhitelistedNode(FindNode(node, key));
  }
  return flutter::EncodableValue(parameters);
}

void WindowsNativePlayer::LogPlaybackFact(const std::string& name,
                                          const std::string& value) const {
  if (value.empty()) {
    return;
  }
  std::cerr << "[lineup-player] " << name << '=' << value << std::endl;
}
