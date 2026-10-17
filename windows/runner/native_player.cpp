#include "native_player.h"
#include "display_guardian.h"

#include "encodable_value_conversion.h"
#include "player_core/platform_arguments.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <iterator>
#include <memory>
#include <string>
#include <utility>

#include <flutter/standard_method_codec.h>

namespace {

using lineup::player::CallError;
using lineup::player::CallResult;
using lineup::player::Value;
using lineup::player::ValueMap;

constexpr char kChannelName[] = "lineup/native_player";
constexpr wchar_t kCompositionMarker[] =
    L"deb287481e3ce9468f3434937ced4240a70539ca";

void SendResult(flutter::MethodResult<flutter::EncodableValue>& result,
                const CallResult& outcome) {
  if (outcome.error) {
    result.Error(outcome.error->code, outcome.error->message);
  } else if (std::holds_alternative<std::monostate>(outcome.value)) {
    result.Success();
  } else {
    result.Success(lineup::ToEncodableValue(outcome.value));
  }
}

bool RestoreWindowState(HWND window, LONG_PTR style,
                        const WINDOWPLACEMENT& placement) {
  ::SetLastError(ERROR_SUCCESS);
  const bool style_set =
      ::SetWindowLongPtr(window, GWL_STYLE, style) != 0 ||
      ::GetLastError() == ERROR_SUCCESS;
  return style_set && ::SetWindowPlacement(window, &placement) &&
         ::SetWindowPos(window, nullptr, 0, 0, 0, 0,
                        SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE |
                            SWP_NOZORDER | SWP_NOOWNERZORDER);
}

}

WindowsNativePlayer::WindowsNativePlayer(
    HWND top_level_window, HWND flutter_view,
    flutter::BinaryMessenger* messenger)
    : WindowsNativePlayer(top_level_window, flutter_view, messenger,
                          lineup::player::LibmpvOperations()) {}

WindowsNativePlayer::WindowsNativePlayer(
    HWND top_level_window, HWND flutter_view,
    flutter::BinaryMessenger* messenger, MpvOperations mpv_operations)
    : top_level_window_(top_level_window),
      flutter_view_(flutter_view),
      core_(mpv_operations, *this) {
  channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, kChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });
  display_ = std::make_unique<lineup::DisplayDynamicRange>(
      top_level_window_, lineup::MakeDisplayConfigApi(),
      lineup::MakeDisplayGuardianFactory(),
      [this](const auto& report) { QueueDisplayReport(report); },
      [this] { core_.RequestWakeup(); });
}

WindowsNativePlayer::~WindowsNativePlayer() {
  display_.reset();
  ::KillTimer(top_level_window_, kPlatformEventMessage);
  channel_->SetMethodCallHandler(nullptr);
  // Joins the worker and releases the video host while this object's window
  // state is intact. A pending dispose result is dropped without a reply.
  core_.Shutdown();
}

void WindowsNativePlayer::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();
  if (method == "initialize") {
    display_->ResetRevision();
    core_.DiscardQueuedEvents("display");
    SendResult(*result, core_.Initialize());
    return;
  }
  if (method == "dispose") {
    std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>> pending(
        std::move(result));
    core_.Dispose([pending](const CallResult& outcome) {
      SendResult(*pending, outcome);
    });
    return;
  }

  auto arguments = lineup::ToValueMap(call.arguments());
  ValueMap* argument_map = arguments ? &*arguments : nullptr;
  if (const auto outcome = core_.HandleCommand(method, argument_map)) {
    SendResult(*result, *outcome);
    return;
  }

  // The core has checked initialization and does not own this method.
  if (method == "setDisplayMatching") {
    std::string error;
    if (!SetDisplayMatching(argument_map, error)) {
      result->Error("invalid_argument", error);
      return;
    }
  } else if (method == "setVideoRect") {
    if (!argument_map) {
      result->Error("invalid_argument", "Video bounds are required.");
      return;
    }
    if (!SetVideoRect(*argument_map)) {
      result->Error("invalid_argument", lineup::player::kInvalidVideoRectMessage);
      return;
    }
  } else if (method == "setFullscreen") {
    const auto* fullscreen = lineup::player::FindBool(argument_map, "fullscreen");
    if (!fullscreen) {
      result->Error("invalid_argument", "Fullscreen must be a boolean.");
      return;
    }
    std::string error;
    if (!SetFullscreen(*fullscreen, error)) {
      result->Error("window_error", error);
      return;
    }
  } else {
    result->NotImplemented();
    return;
  }

  result->Success();
}

void WindowsNativePlayer::SendEvent(const ValueMap& event) {
  channel_->InvokeMethod(
      "event", std::make_unique<flutter::EncodableValue>(
                   lineup::ToEncodableMap(event)));
}

bool WindowsNativePlayer::SetDisplayMatching(const ValueMap* arguments,
                                             std::string& error) {
  using lineup::player::DisplayDesire;
  const auto request = lineup::player::ParseDisplayMatchingArguments(arguments);
  if (!request) {
    error = lineup::player::kInvalidDisplayMatchingMessage;
    return false;
  }
  const auto state = request->desired == DisplayDesire::hdr ? lineup::DisplayState::hdr :
      request->desired == DisplayDesire::sdr ? lineup::DisplayState::sdr :
                                               lineup::DisplayState::unknown;
  // The display controller orders revisions inside its own request state.
  if (!display_->Submit({request->revision, request->session, state})) {
    error = lineup::player::kStaleDisplayRevisionMessage;
    return false;
  }
  return true;
}

bool WindowsNativePlayer::PostWakeup() {
  return ::PostMessage(top_level_window_, kPlatformEventMessage, 0, 0) != FALSE;
}

void WindowsNativePlayer::PostWorkerFinished() {
  // Retry until the platform can drain the disposal or the window is gone.
  while (::IsWindow(top_level_window_) &&
         !::PostMessage(top_level_window_, kPlatformEventMessage, 0, 0)) {
    ::Sleep(10);
  }
}

std::optional<CallError> WindowsNativePlayer::PrepareOutput(
    lineup::player::OutputConfig& output) {
  wchar_t marker[64]{};
  if (::GetEnvironmentVariableW(L"LINEUP_FLUTTER_DCOMP_ACTIVE", marker,
                                static_cast<DWORD>(std::size(marker))) == 0 ||
      std::wstring(marker) != kCompositionMarker) {
    return CallError{
        "required_engine_unavailable",
        "The required Lineup DirectComposition Flutter engine is not active."};
  }

  video_host_ = ::CreateWindowExW(
      WS_EX_NOACTIVATE, L"STATIC", L"", WS_CHILD | WS_CLIPSIBLINGS | WS_DISABLED,
      0, 0, 1, 1, flutter_view_, nullptr, ::GetModuleHandle(nullptr), nullptr);
  if (!video_host_) {
    return CallError{
        "initialize_failed",
        "Windows could not create the native video presentation host."};
  }

  output.window_id = reinterpret_cast<int64_t>(video_host_);
  output.options = {
      {"vo", "gpu-next"},
      {"gpu-api", "d3d11"},
      {"gpu-context", "d3d11"},
  };
  return std::nullopt;
}

void WindowsNativePlayer::CancelOutput() {
  ::DestroyWindow(video_host_);
  video_host_ = nullptr;
}

void WindowsNativePlayer::ReleaseOutput() {
  if (fullscreen_) {
    std::string ignored;
    SetFullscreen(false, ignored);
  }
  if (video_host_) {
    ::DestroyWindow(video_host_);
    video_host_ = nullptr;
  }
  video_rect_set_ = false;
}

void WindowsNativePlayer::OnDisposeRequested() {
  if (display_) display_->EndSession();
}

bool WindowsNativePlayer::SetVideoRect(const ValueMap& arguments) {
  const auto rect = lineup::player::ParseVideoRectArguments(arguments);
  if (!rect) {
    return false;
  }
  video_rect_ = {
      static_cast<LONG>(std::lround(rect->left * rect->scale)),
      static_cast<LONG>(std::lround(rect->top * rect->scale)),
      static_cast<LONG>(
          std::lround((rect->left + std::max(0.0, rect->width)) * rect->scale)),
      static_cast<LONG>(
          std::lround((rect->top + std::max(0.0, rect->height)) * rect->scale)),
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
      const bool restored =
          RestoreWindowState(top_level_window_, window_style_, window_placement_);
      error = restored
                  ? "Windows could not size the fullscreen window."
                  : "Windows could not size or roll back the fullscreen window.";
      return false;
    }
    fullscreen_ = true;
  } else {
    ::SetLastError(ERROR_SUCCESS);
    const LONG_PTR fullscreen_style =
        ::GetWindowLongPtr(top_level_window_, GWL_STYLE);
    WINDOWPLACEMENT fullscreen_placement{sizeof(WINDOWPLACEMENT)};
    if ((fullscreen_style == 0 && ::GetLastError() != ERROR_SUCCESS) ||
        !::GetWindowPlacement(top_level_window_, &fullscreen_placement)) {
      error = "Windows could not snapshot the fullscreen window.";
      return false;
    }
    if (!RestoreWindowState(top_level_window_, window_style_,
                            window_placement_)) {
      const bool rolled_back = RestoreWindowState(
          top_level_window_, fullscreen_style, fullscreen_placement);
      error = rolled_back
                  ? "Windows could not restore the window after fullscreen."
                  : "Windows could not restore or roll back the fullscreen window.";
      return false;
    }
    fullscreen_ = false;
  }
  return true;
}

bool WindowsNativePlayer::HandleWindowMessage(UINT message, WPARAM wparam) {
  if (message == WM_DISPLAYCHANGE || message == WM_MOVE ||
      message == WM_WINDOWPOSCHANGED || message == WM_SETTINGCHANGE) {
    display_->Notify(message != WM_SETTINGCHANGE,
                     message == WM_DISPLAYCHANGE ||
                         message == WM_SETTINGCHANGE);
    return false;
  }
  const bool close_timer = message == WM_TIMER && wparam == kPlatformEventMessage;
  if (close_timer) {
    display_close_timeout_ = true;
    ::KillTimer(top_level_window_, kPlatformEventMessage);
  }
  if (message != kPlatformEventMessage && !close_timer) {
    return false;
  }
  core_.ProcessWakeup([this](const ValueMap& event) { SendEvent(event); });
  if (window_close_requested_ && core_.disposed() &&
      (display_->ReleaseComplete() || display_close_timeout_)) {
    window_close_ready_ = true;
    ::KillTimer(top_level_window_, kPlatformEventMessage);
  }
  return true;
}

bool WindowsNativePlayer::BeginWindowClose() {
  display_->EndSession();
  if (core_.disposed() && display_->ReleaseComplete()) {
    return true;
  }
  window_close_requested_ = true;
  display_close_timeout_ = false;
  ::SetTimer(top_level_window_, kPlatformEventMessage, 3000, nullptr);
  if (core_.disposed()) core_.RequestWakeup();
  core_.BeginDispose();
  return false;
}

void WindowsNativePlayer::EndWindowsSession() {
  display_->EndSessionAndWait(std::chrono::seconds(2));
}

void WindowsNativePlayer::QueueDisplayReport(const lineup::DisplayReport& report) {
  core_.QueuePlatformEvent({
      {"type", Value("display")},
      {"revision", Value(report.revision)},
      {"session", Value(report.session)},
      {"observed", Value(lineup::DisplayStateName(report.observed))},
      {"outcome", Value(report.outcome)},
      {"wrote", Value(report.wrote)},
      {"owned", Value(report.owned)},
      {"reason", report.reason ? Value(report.reason) : Value()},
      {"route", Value(lineup::DisplayRouteName(report.route))},
      {"activeColorMode", Value(report.active_color_mode)},
  });
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
